# 🏥 SINCRONIZADOR DO OFTALMOFÁCIL (item 157)
#
# Lê o banco MySQL do OftalmoFácil com um usuário SÓ-LEITURA (nenhuma
# alteração no sistema dele) e espelha as cirurgias da CEVICO (fornecedor
# CATARATA_SP) em cevico_oftalmofacil_surgeries. Depois TRATA cada uma:
#   1. casa o paciente: telefone → CPF → nome exato (o que sobrar pode ir
#      pro casador por IA da planilha, opcional) → senão CRIA o paciente
#   2. enriquece o cadastro (CPF em custom_attributes, e-mail, nome vazio)
#   3. card do CRM: agendada/aguardando pagamento → "Cirurgia Agendada";
#      realizada até 30 dias → "Cirurgia Realizada" (roda a jornada de
#      pós-op); realizada antiga → "Pós Operatório"; cancelada/ausente NÃO
#      movem (só etiqueta). 🛡️ card já ADIANTE nunca volta (rodada 137).
#   4. valor do card = valor da cirurgia lá (fonte da verdade do dinheiro)
#   5. StageLog retrodatado pra data real da cirurgia (dashboards contam o
#      mês certo) — igual à importação da planilha
#   6. automações: a PRIMEIRA carga (histórico) é silenciosa; depois, só
#      cirurgia nova/futura dispara as automações da coluna
#
# Incremental por SCH_ITE_LAST_MODIFICATION (cursor em
# agenda_config.oftalmofacil.last_sync_at); idempotente por SCH_ITE_TOKEN.
#
# 🏥 item 228 (24/09, "saindo do Google Agenda"): o OftalmoFácil é um HUB de
# parceiros de aquisição. O fornecedor CATARATA_SP é a própria CEVICO; os
# OUTROS são parceiros. Com `partners_enabled`, o sync lê todos:
#   · nosso (CATARATA_SP)  → funil da CEVICO (como sempre)
#   · parceiro             → funil `partner_pipeline_id` (OFTALMOFÁCIL), contato
#                            com etiqueta `oftalmofacil` + `of_<parceiro>`
# Parceiro com data anterior a `agenda_from` fica SÓ no espelho (sem paciente,
# card ou agendamento). E, com `agenda_enabled`, cada item com data ≥
# `agenda_from` vira um agendamento na Agenda (Task com source='oftalmofacil', idempotente por
# external_ref = SCH_ITE_TOKEN) — cirurgia, exame ou consulta conforme o
# tipo do procedimento lá; local pelo de-para `clinics` (clínica → unidade).
class Crm::OftalmofacilSyncService # rubocop:disable Metrics/ClassLength
  BATCH = 500
  RECENT_DAYS = 30           # realizada até aqui → "Cirurgia Realizada"; depois → Pós
  FIRE_WINDOW_DAYS = 2       # cirurgia nova/futura (até 2 dias atrás) dispara automações
  ORIGIN_LABEL = 'oftalmofacil'.freeze

  Result = Struct.new(:pulled, :created_contacts, :moved, :ahead, :labeled, :errors, :cursor,
                      :tasks_created, :tasks_updated, :partners, :skipped_partners, keyword_init: true)

  def initialize(account:, config: nil, silent: nil, since: :cursor)
    @account = account
    @config = config || (CrmSetting.find_by(account: account)&.agenda_config || {})['oftalmofacil'] || {}
    @since = since == :cursor ? @config['last_sync_at'].presence : since
    # sem cursor = primeira carga (histórico) = silêncio nas automações
    @silent = silent.nil? ? @since.blank? : silent
    @result = Result.new(pulled: 0, created_contacts: 0, moved: 0, ahead: 0, labeled: 0, errors: [], cursor: @since,
                         tasks_created: 0, tasks_updated: 0, partners: 0, skipped_partners: 0)
  end

  # ── parceiros × nosso ──────────────────────────────────────────────────
  def partners_enabled?
    @config['partners_enabled'] == true
  end

  def agenda_enabled?
    @config['agenda_enabled'] == true
  end

  # o fornecedor da CEVICO lá (CATARATA_SP): tudo que NÃO casa é parceiro
  def own_provider?(provider_name)
    own = @config['provider_name'].to_s.strip.downcase
    own.present? && provider_name.to_s.downcase.include?(own)
  end

  def own_pipeline
    @own_pipeline ||= begin
      id = @config['own_pipeline_id'].to_i
      (id.positive? && @account.crm_pipelines.find_by(id: id)) || @account.crm_pipelines.order(:id).first
    end
  end

  def partner_pipeline
    return @partner_pipeline if defined?(@partner_pipeline)

    id = @config['partner_pipeline_id'].to_i
    @partner_pipeline = id.positive? ? @account.crm_pipelines.find_by(id: id) : nil
  end

  def agenda_from
    @agenda_from ||= begin
      d = Date.parse(@config['agenda_from'].to_s)
      d
    rescue ArgumentError, TypeError
      Date.current.beginning_of_week
    end
  end

  # ── conexão (usuário só-leitura) ───────────────────────────────────────
  def self.configured?(config)
    %w[db_host db_name db_user db_password provider_name].all? { |k| config[k].present? }
  end

  # ruby-mysql (puro Ruby): conecta e já entra em modo só-leitura na sessão
  # — mesmo que alguém troque o usuário por um com escrita, nada grava lá
  def connection
    @connection ||= begin
      my = Mysql.connect(@config['db_host'], @config['db_user'], @config['db_password'], @config['db_name'],
                         (@config['db_port'].presence || 3306).to_i, nil, nil,
                         connect_timeout: 10, read_timeout: 30, write_timeout: 10)
      my.query('SET SESSION TRANSACTION READ ONLY')
      my
    end
  end

  # teste de conexão + retrato: quantas cirurgias do fornecedor existem lá
  def probe # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
    rows = query(<<~SQL.squish, [provider_pattern, provider_pattern])
      SELECT COUNT(*) AS total, MAX(i.SCH_ITE_LAST_MODIFICATION) AS last_mod, MIN(i.SCH_ITE_DATE) AS first_date
      FROM SCHEDULING_ITEMS i
      JOIN SCHEDULING s ON s.SCH_ID = i.SCH_ITE_SCH_ID
      JOIN PROVIDERS p ON p.PROV_ID = s.SCH_PROVIDER
      WHERE (p.PROV_NAME LIKE ? OR p.PROV_SOCIAL_NAME LIKE ?)
    SQL
    r = rows.first || {}
    # retrato do HUB inteiro (item 228): quem são os parceiros, as clínicas e
    # os tipos de procedimento que existem lá — para o admin montar o de-para
    partners = query(<<~SQL.squish)
      SELECT p.PROV_NAME AS name, COUNT(*) AS total, MAX(i.SCH_ITE_DATE) AS last_date
      FROM SCHEDULING_ITEMS i
      JOIN SCHEDULING s ON s.SCH_ID = i.SCH_ITE_SCH_ID
      JOIN PROVIDERS p ON p.PROV_ID = s.SCH_PROVIDER
      GROUP BY p.PROV_NAME ORDER BY total DESC
    SQL
    clinics = query(<<~SQL.squish)
      SELECT c.CLI_NAME AS name, COUNT(*) AS total
      FROM SCHEDULING_ITEMS i LEFT JOIN CLINICS c ON c.CLI_ID = i.SCH_ITE_CLINIC
      GROUP BY c.CLI_NAME ORDER BY total DESC
    SQL
    types = query(<<~SQL.squish)
      SELECT pt.PRO_TYP_VALUE AS name, COUNT(*) AS total
      FROM SCHEDULING_ITEMS i LEFT JOIN PROCEDURES_TYPE pt ON pt.PRO_TYP_ID = i.SCH_ITE_PROCEDURE_TYPE
      GROUP BY pt.PRO_TYP_VALUE ORDER BY total DESC
    SQL
    {
      ok: true, total: r['total'].to_i, last_modification: r['last_mod'].to_s.presence, first_date: r['first_date'].to_s.presence,
      partners: partners.map do |x|
        { name: x['name'].to_s, total: x['total'].to_i, last_date: x['last_date'].to_s.presence, own: own_provider?(x['name']) }
      end,
      clinics: clinics.map { |x| { name: x['name'].to_s.presence || '(sem clínica)', total: x['total'].to_i } },
      procedure_types: types.map { |x| { name: x['name'].to_s.presence || '(sem tipo)', total: x['total'].to_i } }
    }
  rescue StandardError => e
    { ok: false, error: friendly_error(e) }
  end

  # ── rodada completa: puxa → espelha → trata ────────────────────────────
  def call # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return @result.tap { |r| r.errors << 'Conexão não configurada' } unless self.class.configured?(@config)

    max_seen = @since
    loop do
      rows = pull_batch(max_seen)
      break if rows.empty?

      rows.each do |row|
        surgery = upsert_mirror(row)
        apply(surgery)
        @result.pulled += 1
        mod = row['SCH_ITE_LAST_MODIFICATION'].to_s.presence || row['SCH_ITE_DATE_CREATION'].to_s
        max_seen = mod if mod.present? && (max_seen.blank? || mod > max_seen)
      rescue StandardError => e
        @result.errors << "item #{row['SCH_ITE_TOKEN']}: #{e.message}"
        Rails.logger.error "[OftalmoFácil sync] #{row['SCH_ITE_TOKEN']}: #{e.class} #{e.message}"
      end
      break if rows.size < BATCH
    end
    @result.cursor = max_seen
    Crm::PartnerGuard.forget!(@account) # a lista de pacientes de parceiro pode ter mudado
    @result
  rescue StandardError => e
    @result.errors << friendly_error(e)
    @result
  ensure
    @connection&.close
  end

  private

  def provider_pattern
    "%#{@config['provider_name'].to_s.strip}%"
  end

  # uma linha por ITEM (a cirurgia), com paciente, prestador, procedimento,
  # olho, status e o total pago (transações aprovadas do agendamento)
  def pull_batch(since) # rubocop:disable Metrics/MethodLength
    sql = <<~SQL.squish
      SELECT i.SCH_ITE_ID, i.SCH_ITE_SCH_ID, i.SCH_ITE_TOKEN, i.SCH_ITE_STATUS,
             i.SCH_ITE_DATE, i.SCH_ITE_HOUR, i.SCH_ITE_AMOUNT, i.SCH_ITE_CLINIC_PRICE, i.SCH_ITE_PROFIT,
             i.SCH_ITE_REBATE, i.SCH_ITE_DATE_CREATION, i.SCH_ITE_LAST_MODIFICATION, i.SCH_ITE_CLINIC,
             s.SCH_DOCTOR, s.SCH_PATIENT_NAME, s.SCH_PATIENT_CPF, s.SCH_PATIENT_PHONE, s.SCH_PATIENT_MAIL,
             p.PROV_NAME, c.CLI_NAME, pr.PRO_NAME, pt.PRO_TYP_VALUE, e.EYE_VALUE,
             st.TB_STA_APP_ID_VALUE AS STATUS_LABEL,
             pat.PAT_CPF, pat.PAT_EMAIL, pat.PAT_PHONE,
             (SELECT COALESCE(SUM(t.TRA_RECEIVED_AMOUNT), 0) FROM TRANSACTIONS t
               WHERE t.TRA_SCHEDULING_ID = s.SCH_ID AND t.TRA_STATUS = 'Y') AS PAID_AMOUNT
      FROM SCHEDULING_ITEMS i
      JOIN SCHEDULING s ON s.SCH_ID = i.SCH_ITE_SCH_ID
      JOIN PROVIDERS p ON p.PROV_ID = s.SCH_PROVIDER
      LEFT JOIN CLINICS c ON c.CLI_ID = i.SCH_ITE_CLINIC
      LEFT JOIN PROCEDURES pr ON pr.PRO_ID = i.SCH_ITE_PROCEDURE
      LEFT JOIN PROCEDURES_TYPE pt ON pt.PRO_TYP_ID = i.SCH_ITE_PROCEDURE_TYPE
      LEFT JOIN EYES e ON e.EYE_ID = i.SCH_ITE_EYE
      LEFT JOIN TB_STATUS_APPOINTMENTS st ON st.TB_STA_APP_ID = i.SCH_ITE_STATUS
      LEFT JOIN PAT_SCHEDULING_LINK lk ON lk.PAT_SCH_SCH_ID = s.SCH_ID
      LEFT JOIN PAT_PATIENTS pat ON pat.PAT_ID = lk.PAT_SCH_PAT_ID
      WHERE #{partners_enabled? ? '1 = 1' : '(p.PROV_NAME LIKE ? OR p.PROV_SOCIAL_NAME LIKE ?)'}
        #{since.present? ? 'AND COALESCE(i.SCH_ITE_LAST_MODIFICATION, i.SCH_ITE_DATE_CREATION) > ?' : ''}
      ORDER BY COALESCE(i.SCH_ITE_LAST_MODIFICATION, i.SCH_ITE_DATE_CREATION) ASC, i.SCH_ITE_ID ASC
      LIMIT #{BATCH}
    SQL
    binds = partners_enabled? ? [] : [provider_pattern, provider_pattern]
    binds << since if since.present?
    query(sql, binds)
  end

  # prepared statement de verdade: os "?" viram binds no servidor
  def query(sql, binds = [])
    stmt = connection.prepare(sql)
    result = stmt.execute(*binds)
    rows = result.each_hash.to_a
    stmt.close
    rows
  end

  # ── espelho ────────────────────────────────────────────────────────────
  def upsert_mirror(row) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    surgery = Crm::OftalmofacilSurgery.find_or_initialize_by(account: @account, item_token: row['SCH_ITE_TOKEN'].to_s)
    cpf = digits(row['PAT_CPF'].presence || row['SCH_PATIENT_CPF'])
    phone = digits(row['SCH_PATIENT_PHONE'].presence || row['PAT_PHONE'])
    surgery.assign_attributes(
      scheduling_id: row['SCH_ITE_SCH_ID'], item_id: row['SCH_ITE_ID'],
      status_id: row['SCH_ITE_STATUS'].to_s, status_label: row['STATUS_LABEL'].to_s.presence,
      status_kind: classify_status(row['STATUS_LABEL'], row['SCH_ITE_STATUS']),
      patient_name: row['SCH_PATIENT_NAME'].to_s.strip.presence,
      patient_cpf: cpf.presence, patient_phone: phone.presence,
      patient_email: (row['SCH_PATIENT_MAIL'].presence || row['PAT_EMAIL']).to_s.strip.downcase.presence,
      provider_name: row['PROV_NAME'].to_s.presence, clinic_name: row['CLI_NAME'].to_s.presence,
      clinic_id: row['SCH_ITE_CLINIC'], doctor_crm: row['SCH_DOCTOR'].to_s.strip.presence,
      procedure_name: row['PRO_NAME'].to_s.presence, procedure_type: row['PRO_TYP_VALUE'].to_s.presence,
      eye: row['EYE_VALUE'].to_s.presence,
      surgery_date: parse_date(row['SCH_ITE_DATE']), surgery_hour: Crm::OftalmofacilSurgery.normalize_hour(row['SCH_ITE_HOUR']),
      amount: row['SCH_ITE_AMOUNT'], clinic_price: row['SCH_ITE_CLINIC_PRICE'], profit: row['SCH_ITE_PROFIT'],
      rebate: row['SCH_ITE_REBATE'], paid_amount: row['PAID_AMOUNT'],
      of_created_at: parse_time(row['SCH_ITE_DATE_CREATION']), of_modified_at: parse_time(row['SCH_ITE_LAST_MODIFICATION']),
      raw: row.transform_values { |v| v.is_a?(Numeric) || v.nil? ? v : v.to_s }
    )
    surgery.save!
    surgery
  end

  # classificação pelo RÓTULO (a tabela de status é dado, não código) com
  # os ids conhecidos como reserva (0 cancelada · 1 ativa · 3 ausente · 5 aguardando)
  def classify_status(label, id) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    l = label.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
    return 'realizada' if l.include?('realiz')
    return 'cancelada' if l.include?('cancel')
    return 'ausente' if l.include?('ausent') || l.include?('falt')
    return 'aguardando_pagamento' if l.include?('aguard') && l.include?('pag')
    return 'agendada' if l.include?('ativ') || l.include?('agend') || l.include?('aguardando atend')

    { '0' => 'cancelada', '1' => 'agendada', '3' => 'ausente', '5' => 'aguardando_pagamento' }[id.to_s] || 'outro'
  end

  # ── tratamento: paciente + card ────────────────────────────────────────
  def apply(surgery) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    partner = !own_provider?(surgery.provider_name)
    @result.partners += 1 if partner
    # parceiro com data ANTES da janela (pedido dele: "desta semana em diante"):
    # fica só no espelho — não vira paciente, card nem agendamento. A CEVICO
    # (CATARATA_SP) continua com o histórico inteiro, como sempre foi.
    if partner && (surgery.surgery_date.blank? || surgery.surgery_date < agenda_from)
      surgery.update_columns(applied_action: 'mirror_only', applied_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      return
    end
    contact = resolve_contact(surgery)
    surgery.update_columns(contact_id: contact.id, match_via: @match_via) # rubocop:disable Rails/SkipsModelValidations
    enrich_contact(contact, surgery, partner: partner)
    tag_origin(contact, surgery, partner)

    target = target_stage(surgery)
    action = target ? place_card(contact, surgery, target) : 'no_move'
    if partner && target.nil? && partner_pipeline.nil?
      @result.skipped_partners += 1
      action = 'no_partner_pipeline'
    end
    label_for(surgery).then { |l| l && (fast_add_label(contact, l) and @result.labeled += 1) }
    sync_task!(contact, surgery, partner) if agenda_enabled?
    surgery.update_columns(applied_action: action, applied_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # etiqueta de ORIGEM no contato: `oftalmofacil` para todos e `of_<parceiro>`
  # para quem veio de um parceiro (pedido dele: "só de ter uma tag com a
  # origem de onde veio, fica bem interessante")
  def tag_origin(contact, surgery, partner)
    fast_add_label(contact, ORIGIN_LABEL)
    fast_add_label(contact, partner_label(surgery.provider_name)) if partner
  end

  def partner_label(provider_name)
    slug = provider_name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')
    "of_#{slug.first(40)}"
  end

  def resolve_contact(surgery)
    @match_via = nil
    if (c = find_by_phone(surgery.patient_phone))
      @match_via = 'phone'
      return c
    end
    if surgery.patient_cpf.present? && (c = find_by_cpf(surgery.patient_cpf))
      @match_via = 'cpf'
      return c
    end
    if (c = find_by_name(surgery.patient_name))
      @match_via = 'name'
      return c
    end
    @match_via = 'created'
    @result.created_contacts += 1
    create_contact(surgery)
  end

  def find_by_phone(digits)
    return nil if digits.to_s.length < 8

    @account.contacts.where.not(phone_number: [nil, ''])
            .where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
            .order(:id)
            .find { |c| Crm::AppointmentRecorder.same_phone_line?(digits, c.phone_number) }
  end

  def find_by_cpf(cpf)
    @account.contacts.where("custom_attributes->>'cpf' = ?", cpf).order(:id).first
  end

  # nome EXATO normalizado e único — homônimo não casa (fica pro CPF/telefone)
  def find_by_name(name)
    key = normalize_name(name)
    return nil if key.blank?

    matches = @account.contacts.where('LOWER(name) LIKE ?', "%#{key.split.last}%").select { |c| normalize_name(c.name) == key }
    matches.size == 1 ? matches.first : nil
  end

  def create_contact(surgery)
    attrs = { name: surgery.patient_name.presence || 'Paciente', additional_attributes: origin_attributes(surgery) }
    attrs[:phone_number] = e164(surgery.patient_phone) if surgery.patient_phone.to_s.length >= 10
    attrs[:email] = surgery.patient_email if surgery.patient_email.present?
    @account.contacts.create!(attrs)
  rescue ActiveRecord::RecordInvalid
    # telefone/e-mail já existem com outra máscara — acha de novo antes de desistir
    find_by_phone(surgery.patient_phone) || @account.contacts.create!(name: surgery.patient_name.presence || 'Paciente',
                                                                      additional_attributes: origin_attributes(surgery))
  end

  def origin_attributes(surgery)
    attrs = { 'origem' => 'oftalmofacil' }
    attrs['parceiro'] = surgery.provider_name.to_s.first(80) unless own_provider?(surgery.provider_name)
    attrs
  end

  # CPF vira chave de ouro; e-mail/nome só COMPLETAM o que estava vazio
  def enrich_contact(contact, surgery, partner: false) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
    changes = {}
    if surgery.patient_cpf.present? && contact.custom_attributes&.dig('cpf').blank?
      changes[:custom_attributes] = (contact.custom_attributes || {}).merge('cpf' => surgery.patient_cpf)
    end
    changes[:email] = surgery.patient_email if contact.email.blank? && surgery.patient_email.present?
    changes[:name] = surgery.patient_name if contact.name.blank? && surgery.patient_name.present?
    # parceiro: o contato lembra de onde veio (mesmo quando já existia)
    if partner && contact.additional_attributes&.dig('parceiro').blank?
      current = contact.additional_attributes || {}
      changes[:additional_attributes] = current.merge('origem' => current['origem'].presence || 'oftalmofacil',
                                                      'parceiro' => surgery.provider_name.to_s.first(80))
    end
    contact.update_columns(changes) if changes.any? # rubocop:disable Rails/SkipsModelValidations
  end

  # nosso → funil da CEVICO; parceiro → funil dos parceiros (sem funil
  # configurado, o parceiro não ganha card: fica no espelho e na Agenda)
  def target_stage(surgery) # rubocop:disable Metrics/CyclomaticComplexity
    pipeline = own_provider?(surgery.provider_name) ? own_pipeline : partner_pipeline
    return nil unless pipeline

    case surgery.status_kind
    when 'agendada', 'aguardando_pagamento' then stage_like('cirurgia agendada', pipeline)
    when 'realizada'
      recent = surgery.surgery_date.present? && surgery.surgery_date >= RECENT_DAYS.days.ago.to_date
      recent ? stage_like('cirurgia realizada', pipeline) : (stage_like('pós operat', pipeline) || stage_like('pos operat', pipeline))
    end
  end

  # coluna pelo nome, DENTRO do funil escolhido (antes procurava em qualquer
  # funil da conta — ficou ambíguo quando o funil OFTALMOFÁCIL nasceu)
  def stage_like(pattern, pipeline)
    @stages ||= {}
    key = "#{pipeline.id}:#{pattern}"
    return @stages[key] if @stages.key?(key)

    @stages[key] = pipeline.stages.where('crm_stages.name ILIKE ?', "%#{pattern}%").order(:position).first
  end

  # move/cria o card com as regras: 🛡️ adiante nunca volta; valor = o dele;
  # StageLog retrodatado; automações só pra cirurgia nova/futura
  def place_card(contact, surgery, stage) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    card = Crm::Contact.find_or_initialize_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
    value = surgery.amount.to_f.positive? ? surgery.amount : nil
    if card.persisted? && card.stage_id != stage.id && card.stage&.position.to_i > stage.position.to_i
      card.update_column(:value, value) if value # rubocop:disable Rails/SkipsModelValidations
      @result.ahead += 1
      return 'ahead'
    end

    previous_stage = card.persisted? ? card.stage : nil
    moved = false
    if card.new_record?
      card.origin = 'oftalmofacil'
      card.stage_id = stage.id
      card.value = value if value
      card.save!
      moved = true
    elsif card.stage_id != stage.id
      card.update!(stage_id: stage.id)
      moved = true
    end
    card.update_column(:value, value) if value && card.value != value # rubocop:disable Rails/SkipsModelValidations
    if surgery.procedure_name.present? && card.procedure_of_interest.blank?
      card.update_column(:procedure_of_interest, surgery.procedure_name.to_s.truncate(120)) # rubocop:disable Rails/SkipsModelValidations
    end

    if moved
      @result.moved += 1
      backdate!(card, stage, surgery)
      # 🚧 item 231: card no funil dos PARCEIROS nunca dispara automação
      fire_automations(card, stage, previous_stage) if !@silent && recent_event?(surgery) && !partner_card?(card)
      return card.previous_changes.key?('id') ? 'created_card' : 'moved'
    end
    'kept'
  end

  def partner_card?(card)
    partner_pipeline.present? && card.pipeline_id == partner_pipeline.id
  end

  def recent_event?(surgery)
    (surgery.surgery_date.present? && surgery.surgery_date >= FIRE_WINDOW_DAYS.days.ago.to_date) ||
      (surgery.of_created_at.present? && surgery.of_created_at >= FIRE_WINDOW_DAYS.days.ago)
  end

  def fire_automations(card, stage, previous_stage)
    CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, previous_stage: previous_stage,
                                    event_type: 'card_entered').call
  rescue StandardError => e
    Rails.logger.warn "[OftalmoFácil sync] automações: #{e.message}"
  end

  # 15/09: vale para TODOS os status — antes só a realizada era retrodatada e
  # a primeira carga jogou 723 "Entrou em Cirurgia Agendada" no dia da carga
  def backdate!(card, stage, surgery)
    real = reference_time(surgery)
    return if real.blank? || real > Time.current

    log = Crm::StageLog.where(crm_contact_id: card.id, stage_id: stage.id).order(entered_at: :desc).first
    log&.update_columns(entered_at: real) # rubocop:disable Rails/SkipsModelValidations
    card.update_column(:stage_moved_at, real) # rubocop:disable Rails/SkipsModelValidations
  rescue ArgumentError
    nil
  end

  # realizada = dia/hora da cirurgia; agendada/aguardando = quando foi
  # marcada lá no OftalmoFácil (a data da cirurgia pode ser futura)
  def reference_time(surgery)
    return surgery.of_created_at unless surgery.status_kind == 'realizada'

    surgery.local_time('12:00')
  end

  def label_for(surgery)
    { 'cancelada' => 'cirurgia_cancelada', 'ausente' => 'falta_cirurgia' }[surgery.status_kind]
  end

  # ── Agenda unificada (item 228) ────────────────────────────────────────
  # Cada item com data ≥ agenda_from vira UM agendamento (Task) e acompanha
  # o OftalmoFácil: data/hora, realizada (concluída + compareceu), cancelada,
  # ausente (faltou). Idempotente por external_ref. `booking_kind = registro`
  # (não conta como agendamento novo nos indicadores).
  def sync_task!(contact, surgery, partner) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return if surgery.surgery_date.blank? || surgery.surgery_date < agenda_from

    task = @account.tasks.find_by(external_ref: surgery.item_token)
    return if task.nil? && surgery.status_kind == 'cancelada' # cancelada lá e nunca esteve aqui: nada a criar

    kind = task_kind(surgery)
    attrs = {
      title: "#{kind[:prefix]}: #{surgery.patient_name.presence || contact.name}",
      task_type: kind[:task_type], modality: kind[:modality],
      due_at: surgery.local_time, # item 242: hora certa (segundos → HH:MM) no fuso de São Paulo
      phone: surgery.patient_phone.presence && e164(surgery.patient_phone),
      procedure: [surgery.procedure_name, surgery.eye].compact_blank.join(' · ').presence,
      doctor: doctor_name_for(surgery.doctor_crm),
      unit: unit_for(surgery.clinic_name),
      contact_id: contact.id,
      booking_kind: 'registro',
      source: 'oftalmofacil',
      source_detail: partner ? surgery.provider_name.to_s.first(80) : nil,
      external_ref: surgery.item_token
    }
    attrs[:unit] ||= task&.unit
    attrs[:doctor] ||= task&.doctor
    case surgery.status_kind
    when 'realizada'
      attrs.merge!(status: :done, attendance: 'attended', canceled_at: nil, completed_at: task&.completed_at || attrs[:due_at])
    when 'cancelada'
      attrs[:canceled_at] = task&.canceled_at || Time.current
    when 'ausente'
      attrs[:attendance] = 'missed'
      attrs[:canceled_at] = nil
    else
      attrs[:status] = :todo
      attrs[:canceled_at] = nil
      attrs[:attendance] = nil if task&.attendance.present? && task.attendance != 'attended'
    end

    if task
      # observação do sync só substitui a que ELE escreveu; a da equipe fica
      attrs[:description] = sync_description(surgery, partner) if task.description.blank? || task.description.to_s.start_with?('Oftalmofácil')
      task.update!(attrs)
      @result.tasks_updated += 1
    else
      creator = @account.administrators.first || @account.users.first
      return if creator.nil?

      @account.tasks.create!(attrs.merge(creator: creator, description: sync_description(surgery, partner),
                                         assignee: Crm::TaskOwner.resolve(@account, contact: contact, task_type: kind[:task_type])))
      @result.tasks_created += 1
    end
  rescue ActiveRecord::RecordInvalid => e
    @result.errors << "agenda #{surgery.item_token}: #{e.message}"
  end

  # tipo do agendamento pelo tipo do procedimento lá: exame → trilho Exames,
  # consulta → Consultas (avaliação), o resto → Cirurgias
  def task_kind(surgery)
    t = surgery.procedure_type.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
    return { task_type: 'consulta', modality: 'exames', prefix: 'Exame' } if t.include?('exam')
    return { task_type: 'consulta', modality: 'pos_op', prefix: 'Pós-operatório' } if t.match?(/p[o]s.?op|pos.?operat|retorno p/) # item 234
    return { task_type: 'consulta', modality: 'avaliacao', prefix: 'Consulta' } if t.include?('consult')

    { task_type: 'cirurgia', modality: nil, prefix: 'Cirurgia' }
  end

  def sync_description(surgery, partner)
    parts = ['Oftalmofácil']
    parts << surgery.provider_name if partner && surgery.provider_name.present?
    parts << surgery.clinic_name if surgery.clinic_name.present?
    parts << surgery.procedure_type if surgery.procedure_type.present?
    parts << "R$ #{format('%.2f', surgery.amount.to_f).tr('.', ',')}" if surgery.amount.to_f.positive?
    parts << "status lá: #{surgery.status_label}" if surgery.status_label.present?
    parts.join(' · ')
  end

  # de-para de médicos (CRM → nome) já existe na integração
  def doctor_name_for(crm)
    key = crm.to_s.gsub(/\D/, '')
    (@config['doctors'] || {})[key].presence
  end

  # de-para clínica do OftalmoFácil → unidade/local da Agenda (chaves: paulista,
  # tatuape ou um local de cirurgia cadastrado, ex.: iop)
  def unit_for(clinic_name)
    map = @config['clinics'] || {}
    return nil if clinic_name.blank? || map.blank?

    key = clinic_name.to_s.strip.downcase
    hit = map.find { |name, _unit| name.to_s.strip.downcase == key }
    hit && hit[1].presence
  end

  # etiqueta leve, sem duplicar (mesmo padrão da importação da planilha)
  def fast_add_label(taggable, tag_name)
    tag = ActsAsTaggableOn::Tag.find_or_create_by!(name: tag_name)
    ActsAsTaggableOn::Tagging.find_or_create_by!(tag_id: tag.id, taggable_type: taggable.class.name,
                                                 taggable_id: taggable.id, context: 'labels')
    if taggable.has_attribute?(:cached_label_list)
      list = (taggable.cached_label_list || '').split(',').map(&:strip).reject(&:blank?)
      unless list.include?(tag_name)
        taggable.update_column(:cached_label_list, (list + [tag_name]).join(', ')) # rubocop:disable Rails/SkipsModelValidations
      end
    end
    true
  rescue ActiveRecord::RecordNotUnique
    true
  end

  # ── utilidades ─────────────────────────────────────────────────────────
  def digits(value)
    value.to_s.gsub(/\D/, '')
  end

  def e164(digits)
    digits.start_with?('55') && digits.length >= 12 ? "+#{digits}" : "+55#{digits}"
  end

  def normalize_name(name)
    name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z\s]/, ' ').squeeze(' ').strip
  end

  def parse_date(raw)
    s = raw.to_s.strip
    return nil if s.blank?

    s.match?(%r{^\d{1,2}/\d{1,2}/\d{4}}) ? Date.strptime(s[0, 10], '%d/%m/%Y') : Date.parse(s[0, 10])
  rescue ArgumentError
    nil
  end

  def parse_time(raw)
    raw.present? ? Time.zone.parse(raw.to_s) : nil
  rescue ArgumentError
    nil
  end

  def friendly_error(err)
    msg = err.message.to_s
    return 'Acesso recusado: confira usuário e senha (e se o IP da CEVICO está liberado no Remote MySQL).' if msg.match?(/denied|1045/i)
    if msg.match?(/connect|timed? ?out|refused|unreachable/i)
      return 'Não alcancei o servidor do OftalmoFácil: confira o endereço/porta e a liberação do IP.'
    end
    return "Banco/tabela não encontrada: #{msg}" if msg.match?(/doesn't exist|unknown database|1146|1049/i)

    "Erro na leitura: #{msg.truncate(160)}"
  end
end
