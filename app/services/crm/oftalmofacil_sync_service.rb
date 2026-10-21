# 🏥 SINCRONIZADOR DO OFTALMOFÁCIL (item 157)
#
# Lê o banco MySQL do OftalmoFácil com um usuário SÓ-LEITURA (nenhuma
# alteração no sistema dele) e espelha as cirurgias da CEVICO (fornecedor
# CATARATA_SP) em cevico_oftalmofacil_surgeries. Depois TRATA cada uma:
#   1. casa o paciente: telefone → CPF → nome + e-mail iguais → senão CRIA o
#      paciente (nome sozinho NUNCA casa — auditoria 07/10, #170: homônimo)
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

  Result = Struct.new(:pulled, :created_contacts, :moved, :ahead, :labeled, :errors, :cursor, :cursor_id,
                      :tasks_created, :tasks_updated, :partners, :skipped_partners, :healed, :unread_found,
                      :tasks_adopted, :fatal, keyword_init: true)
  # Rodada 4 (revisão do achado #382): a rodada inteira falhou (hub fora do ar,
  # senha errada, IP bloqueado, tempo esgotado). O call continua devolvendo o
  # Result (quem chama decide), mas com result.fatal preenchido; o
  # Crm::OftalmofacilSyncJob transforma isso neste erro para gravar a falha e
  # mostrar a faixa vermelha, sem fingir que a rodada foi boa.
  class Unreachable < StandardError; end
  # 🔁 auditoria 10/2026 (#462/#472): a consulta lançada pela recepção e a
  # mesma consulta vinda do hub só são "a mesma" quando a hora bate com esta folga
  TWIN_WINDOW = 30.minutes
  # item 254: a Agenda se conserta sozinha nos próximos dias (ver heal_agenda!)
  HEAL_DAYS = 14
  UPCOMING_DAYS = 7

  attr_reader :result

  # heartbeat: chamado a cada lote lido do hub (o job usa para renovar a trava
  # da conta numa recarga longa, ver Crm::OftalmofacilSyncJob.renew_lock)
  def initialize(account:, config: nil, silent: nil, since: :cursor, heartbeat: nil)
    @account = account
    @heartbeat = heartbeat
    @config = config || (CrmSetting.find_by(account: account)&.agenda_config || {})['oftalmofacil'] || {}
    # item 249 (26/09): cursor em DUAS partes (momento + id do último item lido).
    # Antes, dois itens gravados no MESMO segundo na virada de um lote de 500
    # eram pulados para sempre ("> momento" deixava o segundo de fora).
    @since, @since_id = since == :cursor ? [@config['last_sync_at'].presence, @config['last_sync_id'].to_i] : [since, 0]
    # sem cursor = primeira carga (histórico) = silêncio nas automações
    @silent = silent.nil? ? @since.blank? : silent
    @result = Result.new(pulled: 0, created_contacts: 0, moved: 0, ahead: 0, labeled: 0, errors: [], cursor: @since,
                         cursor_id: @since_id, tasks_created: 0, tasks_updated: 0, partners: 0, skipped_partners: 0,
                         healed: 0, unread_found: 0, tasks_adopted: 0)
  end

  # 🔁 auditoria 10/2026 (#462/#472): "gêmea" = agendamento ATIVO do mesmo
  # paciente (mesmo contato, ou mesmo telefone com DDD), do mesmo tipo, que a
  # equipe/robô já lançou na Agenda SEM vínculo com o hub (external_ref vazio),
  # na mesma hora (±30 min; sem hora no hub, o mesmo dia). É a consulta que o
  # sync deve ADOTAR em vez de criar outra — duas tasks = dois lembretes pagos
  # e o "sim" do paciente confirmando só uma. O rake cevico:oftalmofacil_dedupe_tasks
  # usa a mesma regra para unir as que já nasceram duplicadas.
  #
  # 👪 Revisão: a família usa o MESMO número ("marca para a minha mãe", #101).
  # Por isso: (a) consulta que já é de OUTRO contato nunca é gêmea ("o dono
  # não muda", regra do AppointmentRecorder); (b) casou só pelo telefone → o
  # nome do hub tem que bater com o nome na consulta; (c) casou pelo contato →
  # o título não pode nomear outra pessoa. Sem prova, não adota (duplicar é
  # bem menos grave do que engolir a consulta de um terceiro).
  def self.twin_task(account, contact_id:, phone:, task_type:, at:, name: nil, exact_hour: true) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity
    digits = phone.to_s.gsub(/\D/, '')
    return nil if at.blank? || task_type.blank? || (contact_id.blank? && digits.length < 8)

    sp = at.in_time_zone('America/Sao_Paulo')
    window = exact_hour ? ((sp - TWIN_WINDOW)..(sp + TWIN_WINDOW)) : sp.all_day
    conds = []
    conds << 'tasks.contact_id = :cid' if contact_id.present?
    conds << "regexp_replace(COALESCE(tasks.phone, ''), '\\D', '', 'g') LIKE :tail" if digits.length >= 8
    account.tasks
           .where(task_type: task_type, external_ref: nil, canceled_at: nil, archived_at: nil, due_at: window)
           .where(conds.join(' OR '), cid: contact_id, tail: "%#{digits.last(8)}")
           .order(:due_at, :id)
           .find do |t|
      next false if t.contact_id.present? && contact_id.present? && t.contact_id != contact_id # é de outra pessoa

      same_contact = contact_id.present? && t.contact_id == contact_id
      # o LIKE pelos 8 últimos dígitos é só o filtro grosso: o DDD é conferido aqui
      same_line = digits.length >= 8 && Crm::AppointmentRecorder.same_phone_line?(digits, t.phone)
      (same_contact || same_line) && twin_name_ok?(name, t, same_contact: same_contact)
    end
  end

  # palavras de título que não são nome de gente ("Consulta", "Retorno Maria")
  GENERIC_TITLE_WORDS = %w[consulta consultas exame exames retorno avaliacao cirurgia teleconsulta paciente recepcao
                           agendamento pos operatorio posop].freeze

  # o nome do hub bate com quem está na consulta da equipe?
  #   · casou pelo CONTATO: título sem nome ("Consulta") vale; com um nome só,
  #     ele tem que aparecer no nome do hub; nome completo = mesma régua da IA.
  #   · casou só pelo TELEFONE: o título precisa trazer o nome (régua da IA).
  def self.twin_name_ok?(name, task, same_contact:)
    words = Crm::AppointmentRecorder.name_words(Crm::AppointmentRecorder.patient_title(task)) - GENERIC_TITLE_WORDS
    return same_contact if words.empty? || name.blank?
    return Crm::AppointmentRecorder.name_words(name).intersect?(words) if same_contact && words.size == 1

    Crm::AppointmentRecorder.same_patient_name?(name, words.join(' '))
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
  # tipo da task da Agenda pelo procedimento do hub (público: o rake
  # cevico:of_colunas, item 344, reclassifica com a MESMA regra)
  def self.kind_for(surgery)
    t = surgery.procedure_type.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
    return { task_type: 'consulta', modality: 'exames', prefix: 'Exame' } if t.include?('exam')
    return { task_type: 'consulta', modality: 'pos_op', prefix: 'Pós-operatório' } if t.match?(/p[o]s.?op|pos.?operat|retorno p/) # item 234
    # 🧩 item 344 (13/10): "retorno vindo do oftalmofácil é consulta de retorno"
    # (antes caía no fim e virava CIRURGIA)
    return { task_type: 'consulta', modality: 'retorno', prefix: 'Retorno' } if t.include?('retorno')
    # 🧩 item 344: adaptação de lente rígida/escleral é consulta (não cirurgia);
    # "lente" sozinho não — catarata é "facectomia com LIO (lente intraocular)"
    return { task_type: 'consulta', modality: 'avaliacao', prefix: 'Lente Rígida' } if t.match?(Crm::AppointmentKind::LENTE)
    return { task_type: 'consulta', modality: 'avaliacao', prefix: 'Consulta' } if t.include?('consult')

    { task_type: 'cirurgia', modality: nil, prefix: 'Cirurgia' }
  end

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
    max_seen_id = @since_id
    loop do
      rows = pull_batch(max_seen, max_seen_id)
      break if rows.empty?

      rows.each do |row|
        surgery = upsert_mirror(row)
        apply(surgery)
        @result.pulled += 1
        mod = cursor_stamp(row['SCH_ITE_LAST_MODIFICATION'].presence || row['SCH_ITE_DATE_CREATION'])
        next if mod.blank?

        if max_seen.blank? || mod > max_seen
          max_seen = mod
          max_seen_id = row['SCH_ITE_ID'].to_i
        elsif mod == max_seen
          max_seen_id = [max_seen_id, row['SCH_ITE_ID'].to_i].max
        end
      rescue StandardError => e
        @result.errors << "item #{row['SCH_ITE_TOKEN']}: #{e.message}"
        Rails.logger.error "[OftalmoFácil sync] #{row['SCH_ITE_TOKEN']}: #{e.class} #{e.message}"
      end
      @heartbeat&.call
      break if rows.size < BATCH
    end
    @result.cursor = max_seen
    @result.cursor_id = max_seen_id
    Crm::PartnerGuard.forget!(@account) # a lista de pacientes de parceiro pode ter mudado
    @result
  rescue StandardError => e
    @result.errors << friendly_error(e)
    # falha da rodada inteira (não de um item): o cursor fica onde estava
    @result.fatal = friendly_error(e)
    Rails.logger.error "[OftalmoFácil sync] rodada falhou: #{e.class} #{e.message}"
    @result
  ensure
    @connection&.close
    @connection = nil
  end

  # ── item 249: conferência de UM DIA direto no hub (só leitura) ──────────
  # Tudo o que está marcado lá para a data, sem depender do cursor — é o que
  # a "Conferência do dia" usa para achar item que o incremental nunca leu.
  def pull_day(date)
    pull_dates([date.to_date])
  end

  # item 254: vários dias numa consulta só. A data lá pode vir como DATE,
  # DATETIME ou texto "dd/mm/aaaa" (com ou sem zero à esquerda) — aceita todos.
  def pull_dates(dates)
    dates = Array(dates).map(&:to_date).uniq
    return [] if dates.empty?

    clause, binds = date_clause(dates)
    sql = "#{PULL_SELECT} WHERE #{clause} " \
          "#{partners_enabled? ? '' : 'AND (p.PROV_NAME LIKE ? OR p.PROV_SOCIAL_NAME LIKE ?) '}" \
          "ORDER BY i.SCH_ITE_DATE ASC, i.SCH_ITE_HOUR ASC, i.SCH_ITE_ID ASC LIMIT #{BATCH * 2}"
    binds += [provider_pattern, provider_pattern] unless partners_enabled?
    query(sql, binds)
  ensure
    @connection&.close
    @connection = nil
  end

  # item 255: contagem CRUA do hub para o dia (sem nenhum JOIN) — se passar da
  # leitura completa, há item lá sem agendamento-pai (SCHEDULING) e a
  # conferência mostra a diferença em vez de sumir com ele em silêncio
  def count_raw_dates(dates)
    clause, binds = date_clause(Array(dates).map(&:to_date).uniq)
    query("SELECT COUNT(*) AS total FROM SCHEDULING_ITEMS i WHERE #{clause}", binds).first&.[]('total').to_i
  ensure
    @connection&.close
    @connection = nil
  end

  def date_clause(dates)
    texts = dates.flat_map { |d| [d.iso8601, d.strftime('%d/%m/%Y'), "#{d.day}/#{d.month}/#{d.year}"] }.uniq
    isos = dates.map(&:iso8601)
    ["(i.SCH_ITE_DATE IN (#{(['?'] * texts.size).join(', ')}) OR DATE(i.SCH_ITE_DATE) IN (#{(['?'] * isos.size).join(', ')}))",
     texts + isos]
  end

  # ── item 254 (26/09): A AGENDA SE CONSERTA SOZINHA ─────────────────────
  # Caso real: 28/09 tinha 11 itens ativos no hub e só 3 na Agenda — os itens
  # lidos ANTES de a Agenda unificada ser ligada nunca voltaram pelo
  # incremental (ele só relê o que muda lá). A cada rodada, todo item do
  # espelho dos próximos HEAL_DAYS dias SEM agendamento (ou com agendamento
  # em outro dia, ou cancelado lá e ativo aqui) passa de novo pelo tratamento
  # da Agenda. Não precisa do hub (usa o espelho) e é idempotente.
  def heal_agenda!(days: HEAL_DAYS)
    return @result unless agenda_enabled?

    heal_candidates(days).each do |surgery|
      heal_one!(surgery)
    rescue StandardError => e
      @result.errors << "agenda #{surgery.item_token}: #{e.message}"
    end
    @result
  end

  # uma vez por hora: pergunta ao hub tudo o que está marcado nos próximos
  # UPCOMING_DAYS dias e traz o que o sistema nunca leu (cursor pulou, linha
  # com erro, etc.). Só leitura lá; em silêncio aqui.
  def refresh_upcoming!(days: UPCOMING_DAYS) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    return @result unless self.class.configured?(@config) && agenda_enabled?

    rows = pull_dates((Date.current..(Date.current + days)).to_a)
    known = Crm::OftalmofacilSurgery.where(account_id: @account.id, item_token: rows.map { |r| r['SCH_ITE_TOKEN'].to_s })
                                    .pluck(:item_token).to_set
    unread = rows.reject { |r| r['SCH_ITE_TOKEN'].blank? || known.include?(r['SCH_ITE_TOKEN'].to_s) }
    @result.unread_found += unread.size
    reprocess_rows!(unread) if unread.any?
    @result
  rescue StandardError => e
    @result.errors << "próximos dias: #{friendly_error(e)}"
    @result
  end

  # reprocessa linhas vindas do hub (pull_day) — espelha e trata cada uma,
  # em silêncio (sem disparar automação de coluna). Devolve o Result.
  def reprocess_rows!(rows)
    Array(rows).each do |row|
      surgery = upsert_mirror(row)
      apply(surgery)
      @result.pulled += 1
    rescue StandardError => e
      @result.errors << "item #{row['SCH_ITE_TOKEN']}: #{e.message}"
    end
    Crm::PartnerGuard.forget!(@account)
    @result
  end

  # reprocessa a partir do ESPELHO (quando o hub não responde): a linha crua
  # guardada em `raw` passa de novo por espelho + tratamento
  def reapply_from_mirror!(surgeries)
    Array(surgeries).each do |s|
      next if s.raw.blank?

      apply(upsert_mirror(s.raw))
      @result.pulled += 1
    rescue StandardError => e
      @result.errors << "item #{s.item_token}: #{e.message}"
    end
    Crm::PartnerGuard.forget!(@account)
    @result
  end

  # 🔁 Revisão (#462/#472, ordem inversa): o hub trouxe o item PRIMEIRO (task
  # com vínculo) e a recepção lançou a mesma consulta na Agenda DEPOIS. Roda a
  # cada sincronização (depois de heal_agenda!) e pelo rake
  # cevico:oftalmofacil_dedupe_tasks: a consulta da equipe fica (quem criou,
  # observações, hora) e ganha o vínculo; a cópia do hub vai para a Lixeira com
  # o motivo "duplicada_hub". Resposta do paciente (sim/não) e as marcas de
  # lembrete já enviadas passam para a que fica, para nada sair de novo.
  # Devolve os pares [consulta da equipe, cópia do hub] unidos (ou que seriam,
  # em `dry`). `days: nil` = sem limite para a frente; `past: true` olha também
  # consultas já passadas.
  def dedupe_tasks!(days: HEAL_DAYS, past: false, dry: false) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return [] unless agenda_enabled?

    today = ActiveSupport::TimeZone['America/Sao_Paulo'].now.beginning_of_day
    scope = @account.tasks.where(source: 'oftalmofacil', canceled_at: nil, archived_at: nil)
                    .where.not(external_ref: nil).where.not(due_at: nil)
    scope = scope.where(due_at: today..) unless past
    scope = scope.where(due_at: ..(today + days.days).end_of_day) if days
    seen = Set.new # cirurgia OD+OE = dois itens do hub para UMA consulta da equipe: conta uma vez
    pairs = []
    scope.order(:due_at, :id).each do |hub|
      surgery = Crm::OftalmofacilSurgery.find_by(account_id: @account.id, item_token: hub.external_ref)
      twin = self.class.twin_task(@account, contact_id: hub.contact_id, phone: hub.phone, task_type: hub.task_type,
                                            at: hub.due_at, exact_hour: surgery.nil? || surgery.hour_hhmm.present?,
                                            name: surgery&.patient_name.presence || Crm::AppointmentRecorder.patient_title(hub))
      next if twin.nil? || seen.include?(twin.id)

      seen << twin.id
      merge_twin!(twin, hub) unless dry
      pairs << [twin, hub]
    rescue StandardError => e
      @result.errors << "duplicada #{hub.external_ref}: #{e.message}"
    end
    pairs
  end

  private

  def heal_candidates(days) # rubocop:disable Metrics/AbcSize
    from = [Date.current, agenda_from].max
    scope = Crm::OftalmofacilSurgery.where(account_id: @account.id, surgery_date: from..(Date.current + days))
    tasks = @account.tasks.where(external_ref: scope.select(:item_token)).index_by(&:external_ref)
    scope.to_a.select do |s|
      task = tasks[s.item_token]
      next s.status_kind != 'cancelada' if task.nil?
      next false if task.archived_at.present?
      next task.canceled_at.nil? if s.status_kind == 'cancelada'
      next false if task.canceled_at.present? # a equipe cancelou aqui: não reabre sozinho

      task.due_at.nil? || task.due_at.in_time_zone('America/Sao_Paulo').to_date != s.surgery_date
    end
  end

  def heal_one!(surgery)
    # casado só pelo nome (antes do #170) não é de confiança: passa pelo casamento de novo
    contact = surgery.contact_id && surgery.match_via != 'name' ? @account.contacts.find_by(id: surgery.contact_id) : nil
    before = @result.tasks_created + @result.tasks_updated
    if contact
      Crm::Stamp.with(via: 'sync') { sync_task!(contact, surgery, !own_provider?(surgery.provider_name)) }
    else
      apply(surgery)
    end
    @result.healed += 1 if @result.tasks_created + @result.tasks_updated > before
  end

  # momento do cursor sempre no MESMO formato ("AAAA-MM-DD HH:MM:SS"): o
  # ruby-mysql devolve Time para DATETIME e o to_s trazia o fuso no fim
  def cursor_stamp(value)
    return nil if value.blank?
    return value.strftime('%Y-%m-%d %H:%M:%S') if value.respond_to?(:strftime)

    value.to_s.strip[0, 19]
  end

  def provider_pattern
    "%#{@config['provider_name'].to_s.strip}%"
  end

  # uma linha por ITEM (a cirurgia), com paciente, prestador, procedimento,
  # olho, status e o total pago (transações aprovadas do agendamento)
  PULL_SELECT = <<~SQL.squish
    SELECT i.SCH_ITE_ID, i.SCH_ITE_SCH_ID, i.SCH_ITE_TOKEN, i.SCH_ITE_STATUS,
           i.SCH_ITE_DATE, i.SCH_ITE_HOUR, i.SCH_ITE_AMOUNT, i.SCH_ITE_CLINIC_PRICE, i.SCH_ITE_PROFIT,
           i.SCH_ITE_REBATE, i.SCH_ITE_DATE_CREATION, i.SCH_ITE_LAST_MODIFICATION, i.SCH_ITE_CLINIC,
           s.SCH_DOCTOR, s.SCH_PATIENT_NAME, s.SCH_PATIENT_CPF, s.SCH_PATIENT_PHONE, s.SCH_PATIENT_MAIL,
           COALESCE(p.PROV_NAME, '(sem fornecedor)') AS PROV_NAME, c.CLI_NAME, pr.PRO_NAME, pt.PRO_TYP_VALUE, e.EYE_VALUE,
           st.TB_STA_APP_ID_VALUE AS STATUS_LABEL,
           pat.PAT_CPF, pat.PAT_EMAIL, pat.PAT_PHONE,
           (SELECT COALESCE(SUM(t.TRA_RECEIVED_AMOUNT), 0) FROM TRANSACTIONS t
             WHERE t.TRA_SCHEDULING_ID = s.SCH_ID AND t.TRA_STATUS = 'Y') AS PAID_AMOUNT
    FROM SCHEDULING_ITEMS i
    JOIN SCHEDULING s ON s.SCH_ID = i.SCH_ITE_SCH_ID
    LEFT JOIN PROVIDERS p ON p.PROV_ID = s.SCH_PROVIDER
    LEFT JOIN CLINICS c ON c.CLI_ID = i.SCH_ITE_CLINIC
    LEFT JOIN PROCEDURES pr ON pr.PRO_ID = i.SCH_ITE_PROCEDURE
    LEFT JOIN PROCEDURES_TYPE pt ON pt.PRO_TYP_ID = i.SCH_ITE_PROCEDURE_TYPE
    LEFT JOIN EYES e ON e.EYE_ID = i.SCH_ITE_EYE
    LEFT JOIN TB_STATUS_APPOINTMENTS st ON st.TB_STA_APP_ID = i.SCH_ITE_STATUS
    LEFT JOIN PAT_SCHEDULING_LINK lk ON lk.PAT_SCH_SCH_ID = s.SCH_ID
    LEFT JOIN PAT_PATIENTS pat ON pat.PAT_ID = lk.PAT_SCH_PAT_ID
  SQL

  def pull_batch(since, since_id = 0)
    where = [partners_enabled? ? '1 = 1' : '(p.PROV_NAME LIKE ? OR p.PROV_SOCIAL_NAME LIKE ?)']
    if since.present?
      where << '(COALESCE(i.SCH_ITE_LAST_MODIFICATION, i.SCH_ITE_DATE_CREATION) > ? ' \
               'OR (COALESCE(i.SCH_ITE_LAST_MODIFICATION, i.SCH_ITE_DATE_CREATION) = ? AND i.SCH_ITE_ID > ?))'
    end
    sql = "#{PULL_SELECT} WHERE #{where.join(' AND ')} " \
          'ORDER BY COALESCE(i.SCH_ITE_LAST_MODIFICATION, i.SCH_ITE_DATE_CREATION) ASC, i.SCH_ITE_ID ASC ' \
          "LIMIT #{BATCH}"
    binds = partners_enabled? ? [] : [provider_pattern, provider_pattern]
    binds += [since, since, since_id.to_i] if since.present?
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
  # 🏷️ item 322: tudo o que o sync cria ou move nasce carimbado como "sync"
  def apply(surgery)
    Crm::Stamp.with(via: 'sync') { apply_surgery(surgery) }
  end

  def apply_surgery(surgery) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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
  #
  # 📱 item 346 (15/10, pedido dele): paciente da CEVICO (CATARATA_SP) que JÁ
  # tinha cadastro continua só da CEVICO — sem a etiqueta `oftalmofacil` (o
  # dado é da própria CEVICO). Só quem nasce pelo hub ganha a de origem.
  def tag_origin(contact, surgery, partner)
    fast_add_label(contact, ORIGIN_LABEL) if partner || @match_via == 'created'
    fast_add_label(contact, partner_label(surgery.provider_name)) if partner
  end

  def partner_label(provider_name)
    slug = provider_name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')
    "of_#{slug.first(40)}"
  end

  # 🛡️ auditoria 07/10 (#170): NUNCA casar só pelo nome. Homônimo (duas "Maria
  # Silva" no mundo, uma só na base) virava a mesma pessoa — e o CPF, a etiqueta
  # do parceiro, o card e o lembrete de confirmação iam parar no WhatsApp do
  # paciente errado. Sem telefone ou CPF casando, só nome + e-mail iguais ainda
  # casa; senão nasce um paciente novo (duplicado a equipe junta depois; mensagem
  # mandada para a pessoa errada não volta).
  def resolve_contact(surgery) # rubocop:disable Metrics/CyclomaticComplexity
    @match_via = nil
    if (c = find_by_phone(surgery.patient_phone))
      @match_via = 'phone'
      return c
    end
    # cirurgia que ANTES do #170 casou só pelo nome: o CPF e o e-mail que estão
    # nesse contato foram gravados pelo próprio sync, então não servem de prova.
    # Só o telefone confirma que é a mesma pessoa; senão nasce um paciente novo
    # (ação pós-deploy limpa o rastro no contato antigo).
    suspect_id = surgery.match_via == 'name' ? surgery.contact_id : nil
    if surgery.patient_cpf.present? && (c = find_by_cpf(surgery.patient_cpf)) && c.id != suspect_id
      @match_via = 'cpf'
      return c
    end
    if (c = find_by_name_and_email(surgery.patient_name, surgery.patient_email)) && c.id != suspect_id
      @match_via = 'name_email'
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

  # nome EXATO normalizado + e-mail igual (o e-mail é chave forte; o nome
  # sozinho nunca casa — ver #170)
  def find_by_name_and_email(name, email)
    key = normalize_name(name)
    return nil if key.blank? || email.blank?

    c = @account.contacts.where('LOWER(email) = ?', email.to_s.strip.downcase).order(:id).first
    c if c && normalize_name(c.name) == key
  end

  def create_contact(surgery)
    attrs = { name: surgery.patient_name.presence || 'Paciente', additional_attributes: origin_attributes(surgery) }
    attrs[:phone_number] = e164(surgery.patient_phone) if surgery.patient_phone.to_s.length >= 10
    attrs[:email] = surgery.patient_email if surgery.patient_email.present?
    @account.contacts.create!(attrs)
  rescue ActiveRecord::RecordInvalid
    # telefone/e-mail já existem com outra máscara — acha de novo antes de desistir
    find_by_phone(surgery.patient_phone) || create_contact_without_email(attrs)
  end

  # e-mail da família (o mesmo e-mail já é de OUTRO paciente da conta) não pode
  # derrubar o telefone junto: tenta de novo só sem o e-mail, e só então nasce
  # o cadastro só com nome e origem. Sem telefone o paciente não recebe lembrete
  # e a próxima sincronização da mesma cirurgia criava mais um duplicado.
  def create_contact_without_email(attrs)
    @account.contacts.create!(attrs.except(:email))
  rescue ActiveRecord::RecordInvalid
    @account.contacts.create!(attrs.slice(:name, :additional_attributes))
  end

  def origin_attributes(surgery)
    attrs = { 'origem' => 'oftalmofacil' }
    attrs['parceiro'] = surgery.provider_name.to_s.first(80) unless own_provider?(surgery.provider_name)
    attrs
  end

  # CPF vira chave de ouro; e-mail/nome só COMPLETAM o que estava vazio.
  # 📱 item 346 (15/10, pedido dele): na CEVICO (CATARATA_SP) os dados do
  # OftalmoFácil são os mais atuais ("captados da porta da clínica pra dentro")
  # e MANDAM — nome e e-mail são trocados quando o primeiro nome bate. Nome
  # diferente no mesmo telefone (mãe que marcou para o filho) e CPF diferente
  # não mexem em nada: viram alerta de conferência (Crm::PatientReview).
  def enrich_contact(contact, surgery, partner: false) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
    changes = {}
    cpf = contact.custom_attributes&.dig('cpf')
    if surgery.patient_cpf.present? && cpf.blank?
      changes[:custom_attributes] = (contact.custom_attributes || {}).merge('cpf' => surgery.patient_cpf)
    elsif surgery.patient_cpf.present? && cpf.to_s.gsub(/\D/, '') != surgery.patient_cpf.to_s.gsub(/\D/, '')
      Crm::PatientReview.flag!(contact, 'cpf_diferente', "OftalmoFácil: #{surgery.patient_name} com outro CPF neste cadastro")
    end
    # cadastro com o nome de DUAS pessoas (Francislene … E Alice …) não é
    # trocado: as consultas da outra pessoa estão nele — fica para conferir
    trusted = !partner && @match_via != 'created' && !Crm::PatientReview.two_people?(contact.name) &&
              Crm::PatientReview.compatible_names?(surgery.patient_name, contact.name)
    new_email = contact.email.blank? || (trusted && contact.email.to_s.casecmp(surgery.patient_email.to_s).nonzero?)
    changes[:email] = surgery.patient_email if new_email && email_free?(surgery.patient_email, contact)
    new_name = contact.name.blank? || (trusted && contact.name != surgery.patient_name)
    changes[:name] = surgery.patient_name if surgery.patient_name.present? && new_name
    contact.update_columns(changes) if changes.any? # rubocop:disable Rails/SkipsModelValidations
    review_name!(contact, surgery) unless partner
    remember_partner!(contact, surgery) if partner && contact.additional_attributes&.dig('parceiro').blank?
  end

  # 📱 item 346: o cadastro achado pelo telefone tem OUTRO primeiro nome (ou o
  # nome de duas pessoas): não troca nada, deixa para a equipe conferir
  def review_name!(contact, surgery)
    return if @match_via == 'created' || surgery.patient_name.blank?

    if Crm::PatientReview.two_people?(contact.name)
      Crm::PatientReview.flag!(contact, 'duas_pessoas', "#{contact.name} (OftalmoFácil: #{surgery.patient_name})")
    elsif !Crm::PatientReview.compatible_names?(surgery.patient_name, contact.name)
      Crm::PatientReview.flag!(contact, 'nome_diferente', "OftalmoFácil: #{surgery.patient_name} · cadastro: #{contact.name}")
    end
  end

  # parceiro: o contato lembra de onde veio (mesmo quando já existia).
  # Rodada 4 da auditoria: gravado pelo Cevico::AttributeMerge e o 'parceiro' é
  # conferido de novo DENTRO da trava — o lê→altera→grava antigo apagava, no
  # contato, marcas que outro escritor guardou no meio (lembrete, NPS, pausa da IA).
  def remember_partner!(contact, surgery)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      next attrs if attrs['parceiro'].present?

      attrs.merge('origem' => attrs['origem'].presence || 'oftalmofacil',
                  'parceiro' => surgery.provider_name.to_s.first(80))
    end
  end

  # e-mail só completa o cadastro se NINGUÉM mais da conta já o tem (o e-mail é
  # único por conta; gravar por cima derrubava o item inteiro com erro do banco)
  def email_free?(email, contact)
    return false if email.blank?

    !@account.contacts.where('LOWER(email) = ?', email.to_s.strip.downcase).where.not(id: contact.id).exists?
  end

  # nosso → funil da CEVICO; parceiro → funil dos parceiros (sem funil
  # configurado, o parceiro não ganha card: fica no espelho e na Agenda)
  def target_stage(surgery) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    pipeline = own_provider?(surgery.provider_name) ? own_pipeline : partner_pipeline
    return nil unless pipeline
    return consult_stage(surgery, pipeline) if task_kind(surgery)[:task_type] == 'consulta'

    # 🧩 item 344: no funil do parceiro a coluna é achada pelo PAPEL (em
    # produção ela se chama só "Cirurgia" — o nome exato não era achado e a
    # cirurgia de parceiro ficava sem card)
    partner = pipeline.id == partner_pipeline&.id
    case surgery.status_kind
    when 'agendada', 'aguardando_pagamento'
      partner ? Crm::PartnerFunnel.find_stage(pipeline, :surgery) : stage_like('cirurgia agendada', pipeline)
    when 'realizada'
      recent = surgery.surgery_date.present? && surgery.surgery_date >= RECENT_DAYS.days.ago.to_date
      key = recent ? :realized : :postop
      next_stage = partner && Crm::PartnerFunnel.find_stage(pipeline, key)
      next_stage || (recent ? stage_like('cirurgia realizada', pipeline) : (stage_like('pós operat', pipeline) || stage_like('pos operat', pipeline)))
    end
  end

  # 🧩 item 344 (13/10): consulta, exame, retorno e pós-op do hub NÃO são
  # cirurgia — antes todo item "agendada" ia para "Cirurgia Agendada" e todo
  # "realizada" para "Cirurgia Realizada" (inflava as cirurgias do parceiro).
  # Só no funil do PARCEIRO: no da CEVICO quem move consulta é a Agenda/IA
  # (uma entrada do sync em "Agendamento de Consulta" contaria como agendamento).
  def consult_stage(surgery, pipeline) # rubocop:disable Metrics/CyclomaticComplexity
    return nil if pipeline.id != partner_pipeline&.id

    modality = task_kind(surgery)[:modality]
    key = case surgery.status_kind
          when 'agendada', 'aguardando_pagamento' then :booked
          when 'ausente' then :missed
          when 'realizada' then modality == 'pos_op' ? :postop : :consulted
          end
    key && Crm::PartnerFunnel.find_stage(pipeline, key)
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
    # 🔁 auditoria 10/2026 (#462/#472): a recepção (ou o Atendente) já lançou
    # esta consulta na Agenda? Então ela é ADOTADA: ganha o vínculo com o hub e
    # fica como está (quem criou, observações, hora da equipe). Antes nascia uma
    # segunda task → dois lembretes no mesmo dia e o "sim" confirmava só um.
    # Adotada, segue direto para o bloco de STATUS (item já realizado/ausente
    # na primeira vez que aparece também conclui/marca falta).
    if task.nil?
      twin = twin_for(contact, surgery, kind)
      task = adopt_twin!(twin, contact, surgery, partner) if twin
    end

    # 🔒 Revisão: consulta que NÃO nasceu do sync (adotada) só acompanha o
    # STATUS do hub. Título, hora, unidade, médico, telefone, paciente e tipo são
    # da equipe — senão a hora do hub (ou o 08:00 de item sem hora) trocava a
    # hora certa, 'registro' tirava a consulta de "Consultas agendadas" e a
    # remarcação apagava o "sim" do paciente (lembrete de novo, na hora errada).
    # (born_via vazio = task de antes do carimbo: o sync a criou, segue como sempre)
    adopted = task.present? && task.cevico_born_via.present? && task.cevico_born_via != 'sync'
    attrs = adopted ? {} : hub_task_attrs(contact, surgery, kind, partner, task)
    case surgery.status_kind
    when 'realizada'
      attrs.merge!(status: :done, attendance: 'attended', canceled_at: nil,
                   completed_at: task&.completed_at || attrs[:due_at] || task&.due_at)
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

  # tudo o que o hub manda para a task que ELE criou (ou vai criar)
  def hub_task_attrs(contact, surgery, kind, partner, task) # rubocop:disable Metrics/AbcSize
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
    attrs
  end

  def twin_for(contact, surgery, kind)
    self.class.twin_task(@account, contact_id: contact.id, phone: surgery.patient_phone, task_type: kind[:task_type],
                                   at: surgery.local_time, name: surgery.patient_name.presence || contact.name,
                                   exact_hour: surgery.hour_hhmm.present?)
  end

  # só o CARIMBO do hub entra na task da equipe (vínculo + de onde veio); o resto
  # — título, hora, médico, observação, quem criou — continua sendo dela.
  # Daqui em diante o item do hub acompanha só o STATUS desta task (ver sync_task!).
  # Devolve a task adotada.
  def adopt_twin!(twin, contact, surgery, partner)
    twin.update!(external_ref: surgery.item_token, source: 'oftalmofacil',
                 source_detail: adopted_source_detail(twin, contact, partner ? surgery.provider_name : nil),
                 # casou só pelo telefone (com o nome conferido no twin_task): ganha o paciente
                 contact_id: twin.contact_id || contact.id,
                 # "como nasceu" nunca fica vazio na adotada — é o que diz ao sync
                 # que ela é da equipe (o carimbo escreveria 'sync' por causa da fonte)
                 cevico_born_via: twin.cevico_born_via.presence || 'equipe')
    @result.tasks_adopted += 1
    twin
  end

  # 🏷️ Revisão: item de PARCEIRO adotando consulta que a recepção marcou como
  # "CEVICO" (origem do formulário, item 300) ou de paciente "CEVICO primeiro"
  # (regra B) NÃO carimba a consulta como do parceiro — senão o lembrete
  # passaria a sair pela caixa/modelo do Oftalmofácil e os números por fonte
  # mudariam. O vínculo (external_ref) sozinho já evita a duplicata. Decisão
  # final de quem manda o lembrete nesse caso fica com o Guilherme; até lá, o
  # lado mais seguro: a consulta continua sendo da CEVICO.
  def adopted_source_detail(twin, contact, provider_name)
    return nil if provider_name.blank?
    return nil if twin.origin == 'cevico' || Crm::PartnerGuard.cevico_first?(contact)

    provider_name.to_s.first(80)
  end

  def merge_twin!(twin, hub)
    contact = twin.contact || hub.contact
    ref = hub.external_ref
    provider = hub.source_detail
    Task.transaction do
      # a cópia do hub solta o vínculo ANTES (o vínculo é único por conta) e vai para a Lixeira
      hub.update_columns(external_ref: nil, source: nil, canceled_at: Time.current, cancel_reason: 'duplicada_hub') # rubocop:disable Rails/SkipsModelValidations
      twin.update!(external_ref: ref, source: 'oftalmofacil',
                   source_detail: adopted_source_detail(twin, contact, provider),
                   contact_id: twin.contact_id || hub.contact_id,
                   confirmed_at: twin.confirmed_at || hub.confirmed_at, declined_at: twin.declined_at || hub.declined_at,
                   cevico_born_via: twin.cevico_born_via.presence || 'equipe')
    end
    carry_reminder_marks!(contact, from: hub, to: twin)
    @result.tasks_adopted += 1
  end

  # as marcas de lembrete (D-n, reforço, resposta) da cópia passam para a que
  # fica; marca que a que fica já tinha vence
  def carry_reminder_marks!(contact, from:, to:)
    return if contact.nil?

    Cevico::AttributeMerge.merge!(contact) do |attrs|
      all = attrs['cevico_appt_reminders'] || {}
      src = all[from.id.to_s]
      next attrs if src.blank?

      all[to.id.to_s] = src.merge(all[to.id.to_s] || {})
      attrs.merge('cevico_appt_reminders' => all)
    end
  end

  # tipo do agendamento pelo tipo do procedimento lá: exame → trilho Exames,
  # consulta → Consultas (avaliação), o resto → Cirurgias
  def task_kind(surgery)
    self.class.kind_for(surgery)
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
