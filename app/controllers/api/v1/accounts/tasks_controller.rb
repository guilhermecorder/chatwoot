class Api::V1::Accounts::TasksController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  include TaskAttachments
  include Crm::ClinicalAccessGate

  before_action :task, only: [:update, :destroy]
  # 🔐 achados #18/#130/#315 + #147: quem pode mexer e a troca de tipo são
  # conferidas ANTES de qualquer ação de editar/apagar
  before_action :authorize_task_change, only: [:update, :destroy]

  def index
    # cards arquivados (coluna oculta do item 95) ficam fora do board.
    # Privacidade: agente comum só vê as próprias tarefas e o que é da clínica
    # toda (Task.visible_to — achado #131: consulta/cirurgia sem unidade e as
    # tarefas ⚠️ da IA também aparecem). Admin vê tudo.
    tasks = visible_tasks.where(archived_at: nil)
    # 🐢 Rodada 7 "Fôlego" (achados #149/#301/#316): a lista vem por PERÍODO
    # (from/to ou days; sem nada = janela larga), com canceladas opcionais e
    # um modo leve (light=1) para quem só faz contas (Meu Painel)
    tasks = filter_index(tasks)
    tasks = tasks.includes(:creator, :assignee)
    # item 237: :contact evita N+1; a versão leve não usa contato, quem
    # cancelou nem anexos — não carrega
    tasks = tasks.includes(:contact, :canceled_by, files_attachments: :blob) unless light_list?

    tasks = tasks.order(Arel.sql('priority DESC, due_at ASC NULLS LAST, created_at DESC')).to_a
    # 💰 valor das cirurgias (só admin) em UMA consulta para a lista toda
    preload_surgery_cards(tasks) unless light_list?
    render json: tasks.map { |t| task_json(t, light: light_list?) }
  end

  # 🔔 Rodada 7 (#301): o número dourado de Tarefas na barra lateral — só a
  # contagem (a mesma regra que a tela fazia: cards do quadro com você como
  # responsável, a fazer, atrasados ou vencendo nas próximas 24 h)
  def alert_count
    scope = visible_tasks.board_cards.where(archived_at: nil).where(mine_or_team_sql, uid: Current.user.id, ret: Crm::TaskOwner::RETORNO)
    count = scope.where('tasks.status = :todo OR (tasks.status <> :done AND tasks.due_at IS NOT NULL AND tasks.due_at <= :soon)',
                        todo: Task.statuses[:todo], done: Task.statuses[:done], soon: 24.hours.from_now).count
    render json: { count: count }
  end

  # item 95: RENOVAR o ambiente — as tarefas CONCLUÍDAS visíveis pra mim
  # vão pra coluna oculta (a tela nasce limpa pro próximo ciclo)
  def archive_done
    # consultas/cirurgias (Agenda) NUNCA entram aqui — só cards do board
    scope = Current.account.tasks.board_cards.where(status: :done, archived_at: nil)
    unless Current.account_user.administrator?
      uid = Current.user.id
      scope = scope.where('assignee_id = :uid OR creator_id = :uid', uid: uid)
    end
    count = scope.update_all(archived_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    render json: { archived: count }
  end

  # Lista do dia da Agenda (item 76): etiquetas do paciente + a resposta de
  # formulário mais recente — o médico LÊ as respostas antes da consulta
  def agenda_details # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    ids = params[:ids].to_s.split(',').map(&:to_i).first(80)
    # 🔐 achado #307: a lista do dia obedece à mesma visibilidade do index
    day_tasks = visible_tasks.where(id: ids).where.not(contact_id: nil)
    contacts = Current.account.contacts.where(id: day_tasks.map(&:contact_id)).index_by(&:id)
    responses = Crm::FormResponse.where(account_id: Current.account.id, contact_id: contacts.keys)
                                 .where.not(completed_at: nil)
                                 .includes(:form).order(:completed_at)
                                 .group_by(&:contact_id)

    render json: day_tasks.map { |t|
      contact = contacts[t.contact_id]
      # 🔐 achado #118: a resposta CONFIRMADA mais recente ganha; a do link
      # limpo (não confirmada) só aparece quando não há nenhuma confirmada —
      # assim uma resposta de terceiro nunca esconde a do paciente
      lista = responses[t.contact_id] || []
      resp = lista.reverse.find(&:verified?) || lista.last
      nao_confirmadas = lista.count { |r| !r.verified? }
      {
        task_id: t.id,
        contact_id: t.contact_id,
        labels: contact ? contact.label_list.map(&:to_s).first(4) : [],
        # o selo vai no nome do formulário (a tela da Agenda mostra esse texto
        # no cabeçalho) e em `verified`
        form_response: resp && {
          form: agenda_form_title(resp, nao_confirmadas),
          verified: resp.verified?,
          unverified_count: nao_confirmadas,
          answered_at: resp.completed_at,
          # 🔐 achado #307: as respostas são dado de saúde (LGPD) — só com o
          # acesso clínico (médicos, admin ou equipe com team_view ligado)
          restricted: !clinical_access_view?,
          answers: clinical_access_view? ? resp.answer_items.reject { |a| a['type'] == 'message' } : []
        }
      }
    }
  end

  # título que a Agenda mostra no cabeçalho das respostas do formulário
  def agenda_form_title(resp, nao_confirmadas)
    name = resp.form&.name
    # 🔐 achado #307: sem acesso clínico a Agenda mostra só o nome do formulário
    return "#{name} · 🔒 respostas só para quem tem acesso clínico" unless clinical_access_view?
    return "#{name} · ⚠️ resposta NÃO confirmada (identificação só por nome + WhatsApp)" unless resp.verified?
    return name if nao_confirmadas.zero?

    "#{name} · ⚠️ há #{nao_confirmadas} resposta(s) não confirmada(s) pelo link limpo (não exibida)"
  end

  def create # rubocop:disable Metrics/AbcSize
    return render_unit_denied if params[:unit].present? && !cevico_access.unit_allowed?(params[:unit])

    # 🔁 item 343: RETORNO não fica no nome de quem marcou — com a equipe dos
    # retornos configurada, o Task nasce sem dono (Crm::TaskOwner.apply_retorno_team!)
    new_task = Current.account.tasks.new(
      task_params.merge(
        creator: Current.user,
        assignee_id: params[:assignee_id].presence || Current.user.id
      )
    )
    new_task.assign_charges(charges_param, Current.user) if params.key?(:charges) # 💰 item 324
    new_task.save!
    # item 300: origem escolhida → contato criado, etiqueta e card no funil certo
    Crm::AppointmentOrigin.apply(account: Current.account, task: new_task)
    stamp_channel(new_task) # 🧭 item 362: como chegou
    new_task.reload
    render json: task_json(new_task), status: :created
  end

  def update
    # (quem pode mexer e a troca de tipo já foram conferidos em authorize_task_change)
    return render_unit_denied unless cevico_access.unit_allowed?(task.unit) && cevico_access.unit_allowed?(params[:unit])

    # consulta com dia/horário alterado = reagendamento (indicador do painel)
    if task.task_type == 'consulta' && params[:due_at].present? && task.due_at.present? &&
       Time.zone.parse(params[:due_at].to_s) != task.due_at
      task.rescheduled_count += 1
    end
    # cancelar/reativar consulta — item 304: com quem e por quê (Lixeira)
    apply_cancel_params if params.key?(:canceled)
    # ✅ item 300: a equipe marca/desmarca "confirmou" à mão (paciente confirmou por telefone)
    apply_manual_confirmation if params.key?(:confirmed)

    # conferência do dia: compareceu = consulta concluída
    params[:status] = 'done' if params[:attendance] == 'attended' && params[:status].blank?

    task.assign_charges(charges_param, Current.user) if params.key?(:charges) # 💰 item 324
    task.update!(task_params)

    # comparecimento/indicação refletem no CRM (move o card + automações)
    reflect_attendance_in_crm if task.saved_change_to_attendance? || task.saved_change_to_surgery_indication?
    reflect_confirmation_in_crm if task.saved_change_to_confirmed_at? && task.confirmed_at.present?
    Crm::AppointmentOrigin.apply(account: Current.account, task: task) if task.saved_change_to_origin?
    # item 319: telefone corrigido num agendamento sem paciente → acha ou cria o cadastro
    if task.saved_change_to_phone? && task.contact_id.blank? && %w[consulta cirurgia].include?(task.task_type)
      Crm::AppointmentOrigin.ensure_contact(account: Current.account, task: task)
    end
    stamp_channel(task) # 🧭 item 362

    render json: task_json(task)
  end

  # 🧭 item 362: "como chegou" informado pela equipe → carimbo canal_origem no
  # contato (primeiro toque; não sobrescreve). Sem contato, acha/cria pelo telefone.
  def stamp_channel(record)
    key = params[:channel].to_s
    return if key.blank? || !Crm::LeadChannel.valid?(key)

    contact = record.contact || Crm::AppointmentOrigin.ensure_contact(account: Current.account, task: record)
    Crm::LeadChannel.stamp!(contact, key, user: Current.user) if contact
  rescue StandardError => e
    Rails.logger.error "[tasks#stamp_channel] #{record&.id}: #{e.class}: #{e.message}"
  end

  # 🗑️ item 304 (30/09): "Excluir" um AGENDAMENTO manda para a Lixeira (fica no
  # banco, some da grade, guarda quem apagou) — em 30/09 a equipe apagou os
  # "duplicados" do Tatuapé e os retornos sumiram sem rastro. Apagar de vez só
  # o admin, e só pela Lixeira (force=1). Card de tarefa comum continua apagando
  # — mas só nas mãos de quem criou, do responsável ou do admin (achado #315).
  # O tipo que decide a Lixeira é o ORIGINAL: a troca card↔agendamento é
  # barrada no update para quem não é admin (achado #147). A regra do que vai
  # para a Lixeira é a MESMA que a Agenda usa para desenhar (Task#agenda_entry?:
  # consulta/cirurgia ou agendamento antigo só com unidade e data) e vale
  # também para a tarefa ⚠️ do robô — ela é o rastro de quem escapou da IA.
  def destroy
    if task.keeps_trace_on_delete? && !force_delete?
      trash_with_trace!
      return render json: task_json(task)
    end
    if task.keeps_trace_on_delete? && !Current.account_user.administrator?
      return render json: { error: 'Só o administrador apaga de vez. Use a Lixeira.' }, status: :forbidden
    end

    task.destroy!
    head :no_content
  end

  # POST /tasks/:id/comment — solicitação/ajuda entre quem criou e quem executa
  def comment # rubocop:disable Metrics/AbcSize
    return render json: { error: 'Sem acesso a esta tarefa.' }, status: :forbidden unless can_collaborate?

    text = params[:text].to_s.strip
    return render json: { error: 'Escreva a mensagem.' }, status: :unprocessable_entity if text.blank?

    entry = {
      'user_id' => Current.user.id,
      'name' => Current.user.name,
      'text' => text.first(600),
      'at' => Time.current.iso8601
    }
    # trava a linha e relê antes de somar: um carimbo de remarcação gravado ao
    # mesmo tempo (IA ou Agenda) não some (auditoria 10/2026, #2/#133)
    task.with_lock { task.update!(comments: Array(task.comments) + [entry]) }
    render json: task_json(task)
  end

  private

  # 🔐 rodada 334: a mesma API serve Tarefas e a Agenda — consulta/cirurgia
  # cobram o nó 'agenda' (ou 'agenda.cirurgias'); o resto cobra 'tarefas'.
  # Ler a lista é livre para quem VÊ qualquer um dos dois.
  def cevico_access_requirement # rubocop:disable Metrics/CyclomaticComplexity
    case action_name
    when 'index', 'agenda_details', 'alert_count'
      return nil if cevico_access.view?('agenda') || cevico_access.view?('tarefas')

      %w[tarefas view]
    when 'create'
      [agenda_node_for(params[:task_type]) || 'tarefas', 'edit']
    when 'update', 'destroy', 'comment'
      [agenda_node_for(task_for_access&.task_type) || 'tarefas', 'edit']
    when 'archive_done'
      nil
    else
      %w[tarefas edit]
    end
  end

  def render_unit_denied
    render json: { error: 'Essa unidade não está liberada para você. Peça a um administrador.' }, status: :forbidden
  end

  def render_task_denied
    render json: { error: 'Sem acesso a esta tarefa.' }, status: :forbidden
  end

  def render_type_switch_denied
    render json: { error: 'Só o administrador muda o tipo entre tarefa e agendamento.' }, status: :forbidden
  end

  # 🔐 a lista que ESTA pessoa pode ver (index e agenda_details usam a mesma):
  # admin vê tudo; o resto vê o próprio + o que é da clínica toda
  # (Task.visible_to); quem está preso a UNIDADES (rodada 334) só vê as
  # consultas dessas unidades (tarefas sem unidade continuam aparecendo)
  def visible_tasks
    scope = Current.account.tasks
    unless Current.account_user.administrator?
      all = scope
      scope = scope.visible_to(Current.user)
      # 🔁 item 343: a equipe dos retornos vê TODOS os cards carimbados de retorno
      scope = scope.or(all.where(modality: Crm::TaskOwner::RETORNO)) if retorno_member?
    end
    allowed_units = cevico_access.units
    scope = scope.where(unit: allowed_units + [nil]) if allowed_units.any?
    scope
  end

  # 🔐 achado #147: mudar task_type entre CARD e AGENDAMENTO troca a porta de
  # acesso (tarefas × agenda) e a regra da Lixeira — só o administrador.
  # Entre agendas (consulta ↔ cirurgia) vale a porta de edição do destino.
  def task_type_switch_denied?
    return false if Current.account_user.administrator? || !params.key?(:task_type)

    new_type = params[:task_type].to_s
    old_type = task.task_type.to_s
    return false if new_type == old_type
    return true if Task::APPOINTMENT_TYPES.include?(new_type) != Task::APPOINTMENT_TYPES.include?(old_type)

    node = agenda_node_for(new_type)
    node.present? && node != agenda_node_for(old_type) && !cevico_access.edit?(node)
  end

  def agenda_node_for(type)
    return nil unless Task::APPOINTMENT_TYPES.include?(type.to_s)

    type.to_s == 'cirurgia' ? 'agenda.cirurgias' : 'agenda'
  end

  def task_for_access
    @task_for_access ||= Current.account.tasks.find_by(id: params[:id])
  end

  def task
    @task ||= Current.account.tasks.find(params[:id])
  end

  def force_delete?
    ActiveModel::Type::Boolean.new.cast(params[:force]) == true
  end

  # agendamento → Lixeira da Agenda; card ⚠️ do robô → Lixeira + fora do quadro
  # (archived_at), porque o quadro de Tarefas não desenha a Lixeira
  def trash_with_trace!
    if task.agenda_entry?
      task.to_trash!(by: Current.user, reason: 'excluida_agenda')
    else
      task.to_trash!(by: Current.user, reason: 'excluida_tarefas')
      task.update!(archived_at: Time.current)
    end
  end

  # 🔐 porta de editar/apagar (achados #18/#130/#315): admin, quem criou, o
  # responsável — e, no que é da clínica toda (agendamento, tarefa ⚠️ do
  # robô), qualquer pessoa da equipe com a porta da Agenda/Tarefas
  # (Task#shared_with_team?). Depois, a troca de tipo (achado #147).
  def authorize_task_change
    return render_task_denied unless can_edit_task?

    render_type_switch_denied if action_name == 'update' && task_type_switch_denied?
  end

  def can_edit_task?
    can_collaborate? || task.shared_with_team?
  end

  # item 304: cancelar guarda quem e por quê; reativar limpa o rastro
  def apply_cancel_params
    if params[:canceled]
      task.canceled_at ||= Time.current
      task.canceled_by ||= Current.user
      task.cancel_reason ||= 'cancelada_equipe'
    else
      task.canceled_at = nil
      task.canceled_by = nil
      task.cancel_reason = nil
    end
  end

  # "confirmou" à mão: a outra consulta do mesmo dia (#462/#472, registrada
  # duas vezes) vai junto, e o card anda para "Consulta Confirmada"
  def reflect_confirmation_in_crm
    Crm::AppointmentConfirmation.confirm_twins!(task, task.contact)
    Crm::ConfirmationReflector.call(account: Current.account, task: task)
  end

  def apply_manual_confirmation
    confirmed = ActiveModel::Type::Boolean.new.cast(params[:confirmed])
    if confirmed
      task.confirmed_at ||= Time.current
      task.declined_at = nil
    else
      task.confirmed_at = nil
    end
  end

  # quem pode comentar e anexar/remover arquivos: admin, quem criou e o
  # responsável — como sempre foi. (Decisão pendente com o Guilherme: abrir
  # comentário/anexo de agendamento para a equipe toda; até lá fica o lado
  # mais fechado.) Editar/apagar usa can_edit_task?, que soma o que é da
  # clínica toda.
  def can_collaborate?
    Current.account_user.administrator? ||
      [task.creator_id, task.assignee_id].include?(Current.user.id) ||
      (task.modality == Crm::TaskOwner::RETORNO && retorno_member?) # 🔁 343: quem pegar primeiro assume
  end

  # 🔁 item 343: quem está na "Equipe dos retornos" (Agenda → Conferência do dia)
  def retorno_member?
    return @retorno_member if defined?(@retorno_member)

    @retorno_member = Crm::TaskOwner.retorno_team_member?(Current.account, Current.user)
  end

  # o número dourado: os meus + (para a equipe dos retornos) os retornos ainda sem dono
  def mine_or_team_sql
    return 'tasks.assignee_id = :uid' unless retorno_member?

    'tasks.assignee_id = :uid OR (tasks.assignee_id IS NULL AND tasks.modality = :ret)'
  end

  def task_params
    attrs = params.permit(:title, :description, :task_type, :priority, :status, :due_at, :assignee_id, :unit,
                          :phone, :procedure, :doctor, :modality, :attendance, :surgery_indication, :indicated_procedure,
                          :contact_id, :booking_kind, :color, :origin, :particular)
    # item 300: origem vazia = não mexe (agendamento antigo segue sem origem)
    attrs.delete(:origin) if attrs.key?(:origin) && attrs[:origin].blank?
    # item 217: vazio = agendamento (padrão); só 'registro' muda a contagem
    attrs[:booking_kind] = nil if attrs.key?(:booking_kind) && attrs[:booking_kind].blank?
    # item 290: cor vazia = volta à cor padrão do tipo; maiúsculas como na lista
    attrs[:color] = attrs[:color].presence&.upcase if attrs.key?(:color)
    attrs
  end

  # 💰 item 324: valores lançados à mão no card — [{ label, amount }]
  def charges_param
    Array(params[:charges]).map { |row| row.respond_to?(:permit) ? row.permit(:label, :amount).to_h : {} }
  end

  def price_config
    @price_config ||= Crm::AppointmentPrice.config(Current.account)
  end

  # Conferência do dia → CRM: compareceu/faltou/cirurgia indicada movem o
  # card do contato (lógica compartilhada com a conduta do médico na
  # Central do Paciente — Crm::AttendanceReflector).
  def reflect_attendance_in_crm
    Crm::AttendanceReflector.call(account: Current.account, task: task)
  end

  # 🐢 Rodada 7 "Fôlego": janela padrão da lista quando a tela não diz o
  # período — 365 dias para trás e 365 para frente pela data do agendamento.
  # A Agenda e a Lixeira (AgendaBoard) chamam sem parâmetro e continuam
  # servidas; consulta mais antiga só com from/to explícito.
  # ⚠️ DECISÃO DO GUILHERME (pendente): a Agenda ainda não pede o mês que
  # está na tela, então um mês de MAIS de 1 ano atrás (ou cirurgia marcada
  # para daqui a mais de 1 ano) aparece vazio. Ficou 1 ano (e não 180 dias)
  # para não esconder o histórico recente da equipe; o histórico mais antigo
  # está no Espaço do Paciente. Quando o AgendaBoard puder mandar from/to,
  # dá para encurtar.
  INDEX_PAST_DAYS = 365
  INDEX_FUTURE_DAYS = 365
  # a Lixeira mostra o que foi cancelado/excluído nos últimos 60 dias — eles
  # vêm mesmo quando a consulta é de antes da janela (nada some da Lixeira)
  INDEX_TRASH_DAYS = 60
  INDEX_TZ = 'America/Sao_Paulo'.freeze

  # filtros da lista: responsável, unidade, só cards do quadro (board=1),
  # canceladas (canceled=0 tira, canceled=1 só elas) e o período
  def filter_index(tasks)
    tasks = tasks.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    tasks = tasks.where(unit: params[:unit]) if params[:unit].present?
    case params[:canceled].to_s
    when '0' then tasks = tasks.where(canceled_at: nil)
    when '1' then tasks = tasks.where.not(canceled_at: nil)
    end
    # quadro de Tarefas: só os cards (agendamento fica só na Agenda — item 305)
    return tasks.board_cards if truthy_param?(:board)

    within_period(tasks)
  end

  # cards do quadro e tarefas SEM data vêm sempre; agendamento só dentro da
  # janela (ou cancelado há pouco, para a Lixeira, quando é a janela padrão)
  def within_period(tasks)
    from, to = index_period
    scope = tasks.where(due_at: nil).or(tasks.where(due_at: from..to)).or(tasks.board_cards)
    scope = scope.or(tasks.where(canceled_at: INDEX_TRASH_DAYS.days.ago..)) if default_period?
    scope
  end

  def default_period?
    params[:from].blank? && params[:to].blank? && params[:days].blank?
  end

  # from/to = data (AAAA-MM-DD, dia inteiro no fuso de São Paulo) ou data e
  # hora ISO; days = últimos N dias até o fim da janela padrão
  def index_period
    from = parse_period_time(params[:from])
    from ||= params[:days].to_i.days.ago if params[:days].to_i.positive?
    to = parse_period_time(params[:to], end_of_day: true)
    [from || INDEX_PAST_DAYS.days.ago, to || INDEX_FUTURE_DAYS.days.from_now]
  end

  def parse_period_time(value, end_of_day: false)
    return nil if value.blank?

    time = ActiveSupport::TimeZone[INDEX_TZ].parse(value.to_s)
    return nil if time.nil?

    end_of_day && value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? time.end_of_day : time
  rescue ArgumentError
    nil
  end

  def light_list?
    @light_list = truthy_param?(:light) if @light_list.nil?
    @light_list
  end

  def truthy_param?(key)
    ActiveModel::Type::Boolean.new.cast(params[key]) == true
  end

  # 💰 achados #149/#301/#316: o valor do card no CRM de TODAS as cirurgias
  # da lista sai de UMA consulta (antes eram 1–2 por cirurgia). Na lista não
  # se procura contato por telefone — cirurgia sem paciente ligado fica sem
  # o valor ali (o modal/salvar de uma tarefa continua procurando).
  def preload_surgery_cards(tasks)
    return unless Current.account_user.administrator?

    ids = tasks.select { |t| t.task_type == 'cirurgia' }.filter_map(&:contact_id).uniq
    @surgery_cards = {}
    return if ids.empty?

    # o primeiro funil (posição) ganha, como na busca de uma tarefa só
    Crm::Contact.joins(:pipeline)
                .where(crm_pipelines: { account_id: Current.account.id }, contact_id: ids)
                .order('crm_pipelines.position', 'crm_contacts.id')
                .pluck('crm_contacts.contact_id', 'crm_contacts.value')
                .each { |contact_id, value| @surgery_cards[contact_id] = value unless @surgery_cards.key?(contact_id) }
  end

  # contato unificado (Fase 0) primeiro; telefone só para registro antigo sem link
  def patient_contact(task)
    task.contact || Task.match_contact(Current.account, task.phone)
  end

  # light: true = só o que o Meu Painel usa para as contas (sem observação,
  # comentários, anexos, cobranças e valor da cirurgia) — a Agenda pede a
  # versão completa
  def task_json(record, light: false)
    base = task_base_json(record)
    return base.merge(light: true) if light

    base.merge(
      description: record.description,
      # item 304: rastro da Lixeira
      canceled_by: record.canceled_by ? { id: record.canceled_by.id, name: record.canceled_by.name } : nil,
      # 💰 item 324: valores lançados à mão e o valor que vale (com a origem)
      charges: Array(record.charges),
      price: Crm::AppointmentPrice.resolve(price_config, record),
      source_detail: record.source_detail,
      # 🧭 item 362: como o paciente chegou (automático vale mais; senão o informado pela equipe)
      channel: Crm::LeadChannel.key_of(record.contact),
      comments: Array(record.comments),
      attachments: task_files_json(record)
    ).merge(surgery_value_json(record))
  end

  def task_base_json(record) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    {
      id: record.id,
      title: record.title,
      task_type: record.task_type,
      priority: record.priority,
      status: record.status,
      due_at: record.due_at,
      completed_at: record.completed_at,
      created_at: record.created_at,
      unit: record.unit,
      phone: record.phone,
      contact_id: record.contact_id,
      procedure: record.procedure,
      doctor: record.doctor,
      modality: record.modality,
      canceled_at: record.canceled_at,
      cancel_reason: record.cancel_reason,
      rescheduled_count: record.rescheduled_count,
      attendance: record.attendance,
      surgery_indication: record.surgery_indication,
      indicated_procedure: record.indicated_procedure,
      booking_kind: record.booking_kind,
      # item 300: confirmou/disse não ao lembrete + de quem é o paciente
      confirmed_at: record.confirmed_at,
      declined_at: record.declined_at,
      origin: record.origin,
      color: record.color, # item 290: cor escolhida pela equipe (nil = cor do tipo)
      # 🔁 item 343: retorno que ESTA pessoa (da equipe dos retornos) vê como dela (filtro "Minhas")
      retorno_team: record.modality == Crm::TaskOwner::RETORNO && retorno_member?,
      # 💰 item 324: particular (os valores vão na versão completa)
      particular: record.particular,
      # item 228: origem do agendamento (nil = nasceu aqui)
      source: record.source,
      creator: { id: record.creator.id, name: record.creator.name },
      assignee: record.assignee ? { id: record.assignee.id, name: record.assignee.name } : nil
    }
  end

  # 💰 valor da cirurgia (SÓ ADMIN): valor do card no CRM + forma de
  # pagamento captada pelo agente de Fechamento (contact.surgery_closing)
  def surgery_value_json(record)
    return {} unless record.task_type == 'cirurgia' && Current.account_user.administrator?
    return listed_surgery_value_json(record) if @surgery_cards

    contact = patient_contact(record)
    return {} if contact.blank?

    card = Crm::Contact.joins(:pipeline)
                       .where(crm_pipelines: { account_id: Current.account.id }, contact_id: contact.id)
                       .order('crm_pipelines.position').first
    surgery_value_hash(contact, card&.value)
  rescue StandardError
    {}
  end

  # na LISTA: contato já carregado + card do lote (preload_surgery_cards)
  def listed_surgery_value_json(record)
    return {} if record.contact.blank?

    surgery_value_hash(record.contact, @surgery_cards[record.contact_id])
  end

  def surgery_value_hash(contact, card_value)
    closing = contact.additional_attributes&.dig('surgery_closing') || {}
    {
      crm_value: closing['value'].presence || card_value,
      surgery_payment: closing['payment']
    }
  rescue StandardError
    {}
  end
end
