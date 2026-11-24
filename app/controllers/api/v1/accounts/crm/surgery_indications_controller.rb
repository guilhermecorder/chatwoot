# 🎯 INDICAÇÕES CIRÚRGICAS (item 402, 23/11): a FILA de quem compareceu à
# consulta e ainda espera a resposta do médico. Quem cuida das cirurgias marca,
# em um toque: Indicação (qual procedimento) | Sem indicação | Aguardando exame.
# A marca fica na própria consulta da Agenda (tasks.surgery_indication), então
# Jornada, Meu Painel e Agenda leem o mesmo dado; o card anda no CRM pelo
# Crm::AttendanceReflector (colunas escolhidas em Agenda → Conferência do dia).
# ✉️ item 410 (24/11): depois da decisão, a tela oferece a MENSAGEM MODELO já
# preenchida (boa notícia / retorno sem indicação). Quem envia é a pessoa da
# equipe, sem IA: a conta toda mora em Crm::IndicationMessages.
class Api::V1::Accounts::Crm::SurgeryIndicationsController < Api::V1::Accounts::BaseController
  include Crm::ResolvesPeriod

  before_action :require_administrator!, only: [:request_model]

  LIMIT = 400
  PROCEDURES = ['Refrativa Lasik', 'Refrativa PRK', 'Catarata', 'Facorrefrativa', 'Lente Fácica',
                'Lente de Foco Estendido', 'Trifocal', 'Anel de Ferrara', 'Pterígio', 'Capsulotomia YAG', 'Outro'].freeze
  # o que a tela chama de situação × o que fica gravado na consulta
  STATUS = { nil => 'pendente', 'awaiting_exam' => 'aguardando_exame',
             'indicated' => 'indicado', 'not_indicated' => 'sem_indicacao' }.freeze
  # retorno, pós-operatório e exame avulso não são consulta de decisão
  SKIP_MODALITIES = %w[retorno pos_op exames].freeze

  def index # rubocop:disable Metrics/AbcSize
    since, until_at = standard_period_range || [(Crm::ResolvesPeriod::PERIOD_TZ.now - 6.days).beginning_of_day,
                                                Crm::ResolvesPeriod::PERIOD_TZ.now.end_of_day]
    tasks = queue_scope.where(due_at: since..until_at).includes(:contact).order(due_at: :desc).limit(LIMIT).to_a
    cards = cards_for(tasks)
    partners = Crm::PartnerGuard.marked_contact_ids(Current.account).to_set
    rows = tasks.map { |t| row_for(t, cards, partners) }

    render json: {
      rows: rows,
      counts: STATUS.values.index_with { |s| rows.count { |r| r[:status] == s } },
      procedures: PROCEDURES,
      moves: move_names,
      period: { since: since, until: until_at }
    }
  end

  def update # rubocop:disable Metrics/AbcSize
    task = queue_scope.find(params[:id])
    value = params[:surgery_indication].presence
    return render json: { error: 'Situação desconhecida.' }, status: :unprocessable_entity unless STATUS.key?(value)

    procedure = value == 'indicated' ? params[:indicated_procedure].to_s.strip.first(80).presence : nil
    return render json: { error: 'Escolha o procedimento indicado.' }, status: :unprocessable_entity if value == 'indicated' && procedure.blank?

    task.update!(surgery_indication: value, indicated_procedure: procedure)
    Crm::AttendanceReflector.call(account: Current.account, task: task) if task.saved_change_to_surgery_indication?

    render json: row_for(task, cards_for([task]), Crm::PartnerGuard.marked_contact_ids(Current.account).to_set)
  end

  # GET :id/message — prévia preenchida para este paciente (modelos, números, janela de 24 h)
  def message
    task = queue_scope.find(params[:id])
    data = indication_messages(task).preview
    render json: data, status: data[:error] ? :unprocessable_entity : :ok
  end

  # POST :id/send_message { model:, inbox_id:, mode: 'text'|'template', text:, values: { '1' => … } }
  def send_message # rubocop:disable Metrics/AbcSize
    task = queue_scope.find(params[:id])
    result = indication_messages(task).deliver(
      model_key: params[:model], inbox_id: params[:inbox_id], mode: params[:mode], text: params[:text],
      values: params[:values].respond_to?(:to_unsafe_h) ? params[:values].to_unsafe_h : {}
    )
    return render json: { error: result[:error] }, status: :unprocessable_entity unless result[:ok]

    row = row_for(task, cards_for([task]), Crm::PartnerGuard.marked_contact_ids(Current.account).to_set)
    render json: { row: row, conversation_id: result[:conversation_id] }
  end

  # GET message_models — os modelos desta tela e a situação de cada um na Meta, por número
  def message_models
    render json: Crm::IndicationMessages.new(account: Current.account).catalog
  end

  # POST request_model { model:, inbox_ids: [] } — pede a aprovação à Meta (só administrador)
  def request_model
    result = Crm::IndicationMessages.new(account: Current.account).request_approval(params[:model], Array(params[:inbox_ids]))
    render json: result, status: result[:errors].any? ? :unprocessable_entity : :ok
  end

  private

  def indication_messages(task)
    Crm::IndicationMessages.new(account: Current.account, task: task, user: Current.user)
  end

  def queue_scope
    scope = Current.account.tasks.where(task_type: 'consulta', attendance: 'attended', archived_at: nil, canceled_at: nil)
                   .where('tasks.modality IS NULL OR tasks.modality NOT IN (?)', SKIP_MODALITIES)
    allowed_units = cevico_access.units
    scope = scope.where(unit: allowed_units + [nil]) if allowed_units.any?
    scope
  end

  def row_for(task, cards, partners) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contact = task.contact
    {
      id: task.id,
      due_at: task.due_at,
      name: task.title.to_s.sub(/\A(Consulta|Teleconsulta|Exame|Cirurgia):\s*/i, '').strip.presence || contact&.name || 'Paciente',
      phone: task.phone.presence || contact&.phone_number,
      contact_id: task.contact_id,
      doctor: task.doctor,
      unit: task.unit,
      unit_label: Crm::AgendaSlots::UNIT_LABELS[task.unit] || task.unit,
      procedure: task.procedure,
      modality: task.modality,
      status: STATUS[task.surgery_indication] || 'pendente',
      indicated_procedure: task.indicated_procedure,
      # Oftalmofácil: paciente do parceiro (regra de ouro: sem IA, só a caixa 12 fala com ele)
      partner: Crm::PartnerGuard.partner_task?(task) || (task.contact_id.present? && partners.include?(task.contact_id)),
      card: cards[task.contact_id],
      message: last_message_for(task),
      waiting_days: ((Time.current - task.due_at) / 1.day).floor.clamp(0, 9999)
    }
  end

  # ✉️ último envio da mensagem da indicação anotado na consulta (nil = nenhum)
  def last_message_for(task)
    entry = Crm::IndicationMessages.history(task).last
    return nil unless entry

    refused = Crm::SendTemplateService.refused([entry['message_id']])[entry['message_id']]
    entry.slice('at', 'name', 'model_label', 'mode', 'inbox', 'conversation_id').merge('refused' => refused)
  end

  def cards_for(tasks)
    Crm::Contact.where(contact_id: tasks.filter_map(&:contact_id).uniq).includes(:stage, :pipeline)
                .order(:updated_at).each_with_object({}) do |card, acc|
      acc[card.contact_id] = { stage: card.stage&.name, stage_color: card.stage&.color, pipeline: card.pipeline&.name }
    end
  end

  # nome da coluna de destino de cada botão ("Não mover" quando ninguém escolheu)
  def move_names
    cfg = (CrmSetting.find_by(account: Current.account)&.agenda_config || {})['attendance_stages'] || {}
    ids = { 'indicado' => cfg['indicated_stage_id'],
            'sem_indicacao' => cfg['not_indicated_stage_id'].presence || cfg['attended_stage_id'],
            'aguardando_exame' => cfg['awaiting_exam_stage_id'].presence || cfg['attended_stage_id'] }
    names = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: Current.account.id }, id: ids.values.compact)
                      .pluck(:id, :name).to_h
    ids.transform_values { |id| names[id.to_i] }
  end
end
