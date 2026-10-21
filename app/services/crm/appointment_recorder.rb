# Registra na Agenda o resultado do Agente de Agendamento:
# - cria a consulta nova, OU
# - REAGENDA a consulta futura já existente do mesmo paciente (telefone/nome)
#   em vez de duplicar — cobre "preciso remarcar" sem criar consulta fantasma.
# Usado pela ação de coluna "Agendar consulta (IA)" e pelo preenchimento do
# histórico (Crm::AgendaBackfillJob). NÃO fala com o paciente: só escreve na
# Agenda interna.
class Crm::AppointmentRecorder # rubocop:disable Metrics/ClassLength -- item 346 (mobile_key)
  # booking_kind (item 217): nil = agendamento novo; 'registro' = a consulta já
  # estava marcada fora do sistema (confirmação lida na conversa) — entra na
  # Agenda como "Lançada", fora de "Consultas agendadas"
  # new_only (item 333): consulta para OUTRA pessoa pelo mesmo telefone ("marca
  # para a minha mãe") — nasce uma consulta nova, a de quem ligou não é movida
  def self.record(account:, result:, contact: nil, conversation: nil, default_unit: nil, booking_kind: nil, new_only: false) # rubocop:disable Metrics/ParameterLists
    outcome = do_record(account: account, result: result, contact: contact, conversation: conversation,
                        default_unit: default_unit, booking_kind: booking_kind, new_only: new_only)
    stamp_gender(contact, result[:gender])
    log_activity(account, result, contact, conversation, outcome)
    outcome
  end

  # sexo do paciente detectado na conversa (nome/contexto) → anotado no
  # contato; o Espaço do Paciente muda de cor sozinho. Marcação manual da
  # equipe vence: só grava se ainda não tem.
  def self.stamp_gender(contact, gender)
    return if contact.blank? || gender.blank?
    return if contact.additional_attributes&.dig('sexo').present?

    # merge atômico: gravar o sexo não pode apagar a pausa/fechamento que outro
    # caminho escreveu no mesmo instante. Marcação manual da equipe vence.
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      attrs['sexo'].present? ? attrs : attrs.merge('sexo' => gender)
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::AppointmentRecorder] sexo: #{e.message}"
  end

  # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def self.do_record(account:, result:, contact: nil, conversation: nil, default_unit: nil, booking_kind: nil, new_only: false)
    return :skipped unless result[:found] && result[:starts_at].present?

    name  = result[:name].presence || contact&.name.presence || Segmento.termo_cap(:cliente)
    phone = result[:phone].presence || contact&.phone_number
    unit  = result[:unit].presence || default_unit
    creator = account.administrators.first || account.users.first
    return :skipped unless creator

    # 🔒 20/10: dia FECHADO na Agenda (cadeado do dia, da unidade ou do médico)
    # não recebe consulta nova nem remarcação pela IA. Os robôs conferem a vaga
    # antes, mas este é o caminho ÚNICO de gravação — a trava mora aqui, para
    # todos de uma vez. Passam: o "registro" (consulta que já estava marcada
    # fora do sistema, item 217) e datas passadas (histórico/backfill).
    if booking_kind.blank? && result[:starts_at] > Time.current &&
       Crm::AgendaSlots.closed_on?(account, result[:starts_at].in_time_zone(Crm::AgendaSlots::TZ).to_date,
                                   unit: unit, doctor: result[:doctor])
      return :dia_fechado
    end

    notes = [
      # 💰 auditoria 10/2026 (#132): o valor falado na conversa fica só como
      # registro — NÃO vale como valor da consulta (lembrete e confirmação usam
      # o pré-configurado do item 324). Por isso sai sem "R$" e sem "Valor:",
      # que são as formas que Crm::AppointmentPrice lê da observação.
      result[:price].presence && "Valor citado na conversa pela IA (não vale como valor da consulta): #{price_as_note(result[:price])}",
      # a observação livre da IA (Secretário/backfill) passa pela mesma limpeza:
      # "combinou R$ 150" ou "valor: 150" também viravam valor da consulta
      result[:notes].presence && ai_text_as_note(result[:notes]),
      conversation && "Conversa ##{conversation.display_id} — agendado pela IA"
    ].compact.join("\n")

    # mesmo paciente + mesmo horário = já está na Agenda
    return :already if account.tasks.exists?(due_at: result[:starts_at], title: "Consulta: #{name}")

    # REAGENDAMENTO: se o paciente já tem consulta FUTURA, ela vira o novo horário
    future = new_only ? nil : future_appointment_by_name(account, phone, name, contact)
    # 🔒 auditoria 10/10 (#99/#442): consulta futura achada só pelo TELEFONE e
    # que já é de OUTRO contato é de outra pessoa. Só é reaproveitada quando o
    # nome ditado bate com o dela (mesma régua das ferramentas) e, mesmo assim,
    # o dono não muda. Nome diferente → nasce consulta nova (duplicar é bem
    # menos grave do que mover a consulta de um terceiro para quem conversa).
    future = nil if future && other_owner?(future, contact) && !same_patient_name?(name, patient_title(future))
    # 👪 auditoria 10/2026 (#101): "marca para a minha mãe" — a consulta futura
    # é do PRÓPRIO contato (ou sem dono), mas o nome ditado é de OUTRA pessoa:
    # a consulta dele NÃO anda. Nasce consulta nova para o familiar, sem o
    # contato de quem conversa e com o telefone informado (mesmo desenho da
    # ferramenta da ligação, item 333). Sem nome ditado = é o próprio paciente.
    if future && family_member?(result[:name], future, contact)
      future = nil
      # o nome ditado é o do PRÓPRIO contato (a consulta achada era de um
      # familiar marcado pelo mesmo WhatsApp): a nova fica com ele. Nome de
      # outra pessoa: nasce sem dono.
      contact = nil unless same_person?(result[:name], contact&.name)
    end
    if future
      return :already if future.due_at == result[:starts_at]

      owner = future.contact || contact
      future.rescheduled_count += 1
      future.update!(
        due_at: result[:starts_at],
        unit: unit.presence || future.unit,
        doctor: result[:doctor].presence || future.doctor,
        procedure: result[:procedure].presence || future.procedure,
        phone: phone.presence || future.phone,
        contact: owner,
        description: [future.description.presence, "Reagendada pela IA:\n#{notes}"].compact.join("\n\n"),
        canceled_at: nil,
        status: :todo,
        assignee: future.assignee || Crm::TaskOwner.resolve(account, contact: owner, task_type: 'consulta')
      )
      return :rescheduled
    end

    account.tasks.create!(
      title: "Consulta: #{name}",
      description: notes,
      due_at: result[:starts_at],
      unit: unit,
      phone: phone,
      contact: contact,
      procedure: result[:procedure].presence,
      doctor: result[:doctor].presence,
      task_type: 'consulta',
      booking_kind: booking_kind.presence,
      priority: :medium,
      status: :todo,
      creator: creator,
      # no nome de quem cuida da coluna do paciente (aviso no painel dela)
      assignee: Crm::TaskOwner.resolve(account, contact: contact, task_type: 'consulta')
    )
    :created
  end
  # rubocop:enable Metrics/ParameterLists, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  # CANCELAMENTO (rodada 148): o paciente desmarcou sem novo horário → a
  # consulta futura dele sai da agenda (canceled_at), com rastro na descrição.
  # Sem consulta futura encontrada → :no_future (o chamador cria tarefa de
  # conferência — a consulta pode existir só no Google Calendar).
  def self.cancel_future(account:, result:, contact: nil, conversation: nil)
    phone = result[:phone].presence || contact&.phone_number
    future = future_appointment(account, phone, nil, contact)
    return :no_future if future.blank?

    future.update!(
      canceled_at: Time.current,
      cancel_reason: 'paciente_desmarcou', # item 304: aparece assim na Lixeira
      description: [future.description.presence,
                    "Cancelada pela conversa ##{conversation&.display_id} (Secretário da Agenda)"].compact.join("\n\n")
    )
    log_activity(account, result.merge(starts_at: future.due_at), contact, conversation, :canceled)
    :canceled
  end

  # Registro de atividade do Secretário (visível no card do agente):
  # cada leitura vira uma linha — criada/reagendada/já existia/sem dados/
  # cancelada/erro — para a equipe ENTENDER os números, conferir o
  # funcionamento e ENXERGAR quem escapou (rodada 148).
  def self.log_activity(account, result, contact, conversation, outcome)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    entry = {
      'at' => Time.current.iso8601,
      'name' => (result[:name].presence || contact&.name || 'Paciente').to_s.first(60),
      'when' => result[:starts_at]&.iso8601,
      'outcome' => outcome.to_s,
      'conversation_id' => conversation&.display_id
    }
    # Rodada 4 (achado #383): sob a trava da linha, só a lista do Secretário muda
    Cevico::SettingMerge.merge!(settings, :agenda_config) do |cfg|
      cfg['scheduler_log'] = Array(cfg['scheduler_log']).unshift(entry).first(100)
      cfg
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::AppointmentRecorder] log: #{e.message}"
  end

  # consulta futura ativa do mesmo CONTATO (unificado) ou telefone — nessa
  # ordem de confiança. NÃO adivinha mais por nome: reagendar pelo homônimo
  # (base tem ~20k contatos, e sem nome extraído o título virava "Consulta:
  # Paciente") movia a consulta de OUTRA pessoa, que sumia da agenda. Sem match
  # confiável → devolve nil e o chamador cria uma consulta nova (duplicar é bem
  # menos grave do que apagar a consulta de um terceiro).
  def self.future_appointment(account, phone, _name, contact = nil)
    scope = account.tasks.where(task_type: 'consulta', canceled_at: nil)
                   .where('due_at > ?', Time.current)
                   .where.not(status: 'done')

    if contact
      by_contact = scope.where(contact_id: contact.id).order(:due_at).first
      return by_contact if by_contact
    end

    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.length < 8

    # candidatos pelo fim do número e, entre eles, o primeiro que é a MESMA
    # linha (confirma DDD/prefixo — dois DDDs com o mesmo final de 8 não casam)
    scope.where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
         .order(:due_at)
         .find { |task| same_phone_line?(digits, task.phone) }
  end

  # 👪 (#101) o contato pode ter MAIS de uma consulta futura (a dele e a da
  # mãe, marcada pelo mesmo WhatsApp): a que casa com o nome ditado vem
  # primeiro; sem casamento, a regra de sempre (a mais próxima).
  def self.future_appointment_by_name(account, phone, name, contact)
    if contact && name.present?
      by_name = account.tasks.where(task_type: 'consulta', canceled_at: nil, contact_id: contact.id)
                       .where('due_at > ?', Time.current)
                       .where.not(status: 'done')
                       .order(:due_at)
                       .find { |task| same_person?(name, patient_title(task)) }
      return by_name if by_name
    end

    future_appointment(account, phone, name, contact)
  end

  # a consulta já tem um contato e ele NÃO é quem está conversando?
  def self.other_owner?(task, contact)
    task.contact_id.present? && (contact.nil? || task.contact_id != contact.id)
  end

  # nome do paciente no título da consulta ("Consulta: Maria da Silva" → "Maria da Silva")
  def self.patient_title(task)
    task.title.to_s.sub(/\A[^:]{0,40}:\s*/, '').strip
  end

  # 👪 (#101) o nome ditado é de OUTRA pessoa que não a dona da consulta futura?
  # Só com nome ditado. Título com nome de verdade manda: se não bate, é outra
  # pessoa — mesmo que o nome ditado seja o do contato que conversa (a consulta
  # da mãe fica amarrada ao WhatsApp da filha; o nome da filha não pode mover a
  # consulta da mãe). O nome do contato só vale de comparação quando o título
  # não tem nome ("Consulta: Paciente").
  def self.family_member?(given, future, contact)
    return false if given.blank? || placeholder_name?(given)

    title = patient_title(future)
    return !same_person?(given, contact&.name) if placeholder_name?(title)

    !same_person?(given, title)
  end

  # nome sem informação ("Paciente", vazio)
  def self.placeholder_name?(text)
    name_words(text).empty? || text.to_s.strip.casecmp?('Paciente')
  end

  # mesma pessoa para fins de REAGENDAMENTO: a régua forte (same_patient_name?)
  # ou, quando só veio UMA palavra ("Maria"), o primeiro nome igual. Uma palavra
  # DIFERENTE do primeiro nome é outra pessoa. (A prova das ferramentas da IA
  # continua exigindo nome completo.)
  def self.same_person?(given, registered)
    given_words = name_words(given)
    registered_words = name_words(registered)
    return false if given_words.empty? || registered_words.empty?
    return same_patient_name?(given, registered) if given_words.size >= 2

    given_words.first == registered_words.first
  end

  # 💰 (#132) "R$ 150" → "150" na observação: sem "R$" o valor não é lido como
  # valor da consulta por Crm::AppointmentPrice (que prefere o pré-configurado)
  def self.price_as_note(price)
    ai_text_as_note(price)
  end

  # texto livre vindo da IA, limpo das DUAS formas que Crm::AppointmentPrice lê
  # na observação ("Valor: 150" e "R$ 150") — o valor que vale é o pré-configurado
  def self.ai_text_as_note(text)
    text.to_s.gsub(/(valor)\s*:\s*/i, '\1 ').gsub(/R\$\s*/i, '').strip
  end

  # 🔒 mesmo nome de paciente? (prova de nome das ferramentas da IA e do
  # reagendamento). O nome ditado precisa ter 2+ palavras de verdade, trazer o
  # PRIMEIRO nome da consulta e bater em pelo menos 2 palavras (ou em todas,
  # quando a consulta tem só uma). Palavras curtas e de ligação (da, de, do…)
  # não contam: "Joao da Silva" NÃO é "Maria da Silva".
  NAME_CONNECTORS = %w[da de do das dos e].freeze
  def self.same_patient_name?(given, registered)
    given_words = name_words(given)
    registered_words = name_words(registered)
    return false if given_words.size < 2 || registered_words.empty?
    return false unless given_words.include?(registered_words.first)

    (given_words & registered_words).size >= [2, registered_words.size].min
  end

  def self.name_words(text)
    I18n.transliterate(text.to_s).downcase.scan(/[a-z0-9]+/)
        .reject { |word| word.length <= 2 || NAME_CONNECTORS.include?(word) }.uniq
  end

  # mesma linha telefônica: tolera o +55 e nº com/sem DDD. Mesmo comprimento
  # (ambos com DDD) exige igualdade — dois DDDs que só compartilham o final de
  # 8 dígitos NÃO casam. Comprimentos diferentes: o maior tem que terminar no
  # menor (ex.: "+55 11 9..." casa com "11 9...").
  #
  # 📱 item 346 (15/10): celular com e sem o 9 depois do DDD é a MESMA linha.
  # O WhatsApp ainda guarda vários números antigos sem o 9 (ex.: DDD 35) e o
  # OftalmoFácil/a equipe digitam com o 9 — o mesmo paciente virava dois.
  def self.same_phone_line?(a_digits, b_phone)
    b = b_phone.to_s.gsub(/\D/, '')
    return false if b.length < 8

    key = mobile_key(a_digits)
    return true if key && key == mobile_key(b)
    return a_digits == b if a_digits.length == b.length

    short, long = [a_digits, b].sort_by(&:length)
    long.end_with?(short)
  end

  # chave do CELULAR brasileiro com DDD: "DDD + 9 + 8 dígitos". Número de 8
  # dígitos começando com 6–9 (celular antigo, sem o 9) ganha o 9; fixo
  # (2–5) e número sem DDD não têm chave (nil → as regras de cima decidem).
  def self.mobile_key(digits) # rubocop:disable Metrics/CyclomaticComplexity
    d = digits.to_s.gsub(/\D/, '').sub(/\A0+/, '')
    d = d[2..] if d.start_with?('55') && d.length >= 12
    return nil unless d.length.between?(10, 11)

    local = d[2..]
    local = "9#{local}" if local.length == 8 && local[0].to_i >= 6
    local.length == 9 && local.start_with?('9') ? "#{d[0, 2]}#{local}" : nil
  end
end
