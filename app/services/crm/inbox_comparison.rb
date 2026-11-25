# 🆚 item 413 (24/11) — COMPARATIVO DE CAIXAS DE ENTRADA.
# Pedido do Guilherme: "quero um ambiente de comparativo de caixas, em que eu
# posso entender no detalhe… comparar uma caixa de entrada com outra… prompt,
# modelo".
#
# A conta é de TURMA: quem CHEGOU por aquela caixa no período (contato novo; a
# caixa de chegada é a primeira conversa numa porta de entrada, a mesma régua do
# "Chegaram" e do Dashboard CRM) e o que virou dessas mesmas pessoas:
#   chegaram → responderam → receberam orçamento → agendaram → compareceram →
#   indicação → cirurgia marcada
# Assim uma caixa não leva o mérito do paciente que chegou por outra, e dá para
# pôr lado a lado caixas com volumes diferentes (o que compara é a TAXA).
#
# A base de comparação ganha a mesma folga de tempo que o período de agora já
# teve (quem chegou ontem teve um dia para agendar; a turma de antes também só
# conta o que fez em um dia). Sem isso o passado ganharia sempre.
#
# Junto de cada caixa vão: quem atendeu (motor e Roteiro de verdade, lidos do
# carimbo de cada conversa: Crm::AttendanceUsage), como ela está configurada
# hoje, o custo (Meta repartido pelo anúncio: Crm::MetaSpendByInbox; Google;
# valor informado), o tempo de resposta, em que coluna a turma está agora e de
# quais campanhas ela veio.
#
# Só LÊ. Conversa do 🧪 Simulador e caixa de parceiro (Oftalmofácil) ficam fora.
class Crm::InboxComparison # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  MONTH_AFTER_DAYS = 95
  SLICE = 5_000
  AGENT_LABELS = { 'atendente_agendamento' => 'Agendamento', 'atendente_pos' => 'Pós-agendamento',
                   'atendente_pos_op' => 'Pós-operatório' }.freeze
  FUNNEL = %i[chegaram responderam orcamento agendaram compareceram indicacoes cirurgias].freeze
  PALETTE = %w[#2563EB #EA580C #059669 #7C3AED #DB2777 #0D9488 #B8860B #DC2626 #475569 #0891B2].freeze

  # invest (só para administrador): { meta_total: R$ | nil, meta_note: texto | nil,
  #   google: { cost:, error:, configured: } | nil, config: { 'inbox_id' => { 'mode' =>, 'monthly' => } } }
  def initialize(account:, since:, until_at:, compare:, invest: nil, now: Time.current) # rubocop:disable Metrics/ParameterLists
    @account = account
    @since = since
    @until_at = until_at
    @compare = compare
    @invest = invest
    @now = now
    @by_month = ((until_at - since) / 86_400).ceil > MONTH_AFTER_DAYS
  end

  def call # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    slack = [@now - @until_at, 0].max
    cur = window(@since, @until_at, @now, full: true)
    prev = window(@compare.since, @compare.until_at, [@compare.until_at + slack, @now].min, full: false)
    keys = bucket_keys
    split = meta_split
    ids = (cur[:funnel].keys | prev[:funnel].keys | cur[:usage].keys | (split ? split[:by_inbox].keys : [])).compact
    rows = ids.map { |id| row_json(id, cur, prev, keys, split) }.reject { |row| empty_row?(row) }
              .sort_by { |row| [row[:porta] ? 0 : 1, -row[:funil][:chegaram], row[:nome].to_s] }
    rows.each_with_index { |row, index| row[:cor] = PALETTE[index % PALETTE.size] }
    {
      periodo: { de: @since.iso8601, ate: @until_at.iso8601, datas: range_label(@since, @until_at) },
      comparacao: @compare.to_h,
      financeiro: !@invest.nil?,
      balde: @by_month ? 'mes' : 'dia',
      rotulos: keys.map { |key| bucket_label(key) },
      meta: meta_json(split),
      google: @invest && @invest[:google] ? @invest[:google].slice(:cost, :error, :configured) : nil,
      caixas: rows,
      total: total_json(rows, cur, prev)
    }
  end

  private

  attr_reader :account

  # caixa sem ninguém, sem conversa e sem gasto não entra na comparação
  def empty_row?(row)
    row[:funil][:chegaram].zero? && row[:anterior][:chegaram].zero? && row[:ia][:conversas].zero? &&
      row.dig(:custo, :investimento).to_f.zero?
  end

  # ── UMA JANELA: a turma que chegou e o que virou dela até `horizon` ───────
  def window(since, until_at, horizon, full:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cohort = entry_cohort(since, until_at)
    contact_ids = cohort.keys
    budget = first_stage_entry(budget_stage_ids, contact_ids, since, horizon)
    booked = first_stage_entry(booking_stage_ids, contact_ids, since, horizon)
    agenda = agenda_outcomes(contact_ids, since, horizon)
    talk = talk_facts(contact_ids, since, horizon)
    funnel = Hash.new { |hash, key| hash[key] = FUNNEL.index_with { 0 } }
    people = Hash.new { |hash, key| hash[key] = [] }
    cohort.each do |contact_id, (inbox_id, created_at)|
      stat = funnel[inbox_id]
      facts = talk[contact_id] || {}
      stat[:chegaram] += 1
      stat[:responderam] += 1 if facts[:replied]
      stat[:orcamento] += 1 if budget[contact_id]
      stat[:agendaram] += 1 if booked[contact_id]
      stat[:compareceram] += 1 if agenda.dig(contact_id, :compareceu)
      stat[:indicacoes] += 1 if agenda.dig(contact_id, :indicacao)
      stat[:cirurgias] += 1 if agenda.dig(contact_id, :cirurgia)
      people[inbox_id] << { id: contact_id, at: created_at, booked_at: booked[contact_id], facts: facts } if full
    end
    return { funnel: funnel, usage: {} } unless full

    { funnel: funnel, people: people, usage: usage_by_inbox(since, until_at),
      stages: stages_now(cohort), campaigns: campaigns_of(cohort, booked) }
  end

  # { contact_id => [inbox_id de chegada, criado em] } dos contatos NOVOS do período
  def entry_cohort(since, until_at)
    capture = capture_inbox_ids
    priority = capture.any? ? "(CASE WHEN c.inbox_id IN (#{capture.join(',')}) THEN 0 ELSE 1 END)," : ''
    excluded = excluded_inbox_ids
    not_excluded = excluded.any? ? "AND c.inbox_id NOT IN (#{excluded.join(',')})" : ''
    sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { acc: account.id, s: since, u: until_at, test: Crm::Journey::TestContact::KEY }])
      SELECT DISTINCT ON (c.contact_id) c.contact_id, c.inbox_id, ct.created_at
      FROM conversations c JOIN contacts ct ON ct.id = c.contact_id
      WHERE c.account_id = :acc AND ct.account_id = :acc AND ct.created_at BETWEEN :s AND :u
        AND NOT jsonb_exists(ct.additional_attributes, :test) #{not_excluded}
      ORDER BY c.contact_id, #{priority} c.created_at ASC, c.id ASC
    SQL
    partner = Crm::PartnerGuard.excluded_contact_ids(account).to_set
    ActiveRecord::Base.connection.select_rows(sql).each_with_object({}) do |(contact_id, inbox_id, created_at), map|
      next if partner.include?(contact_id)

      map[contact_id] = [inbox_id, created_at.is_a?(String) ? Time.zone.parse(created_at) : created_at]
    end
  end

  def capture_inbox_ids
    @capture_inbox_ids ||= Crm::LeadsUniverse.capture_inbox_ids(account) - excluded_inbox_ids
  end

  # 🧪 Simulador + caixas dos parceiros nunca entram
  def excluded_inbox_ids
    @excluded_inbox_ids ||= (Crm::AgentSimulator.inbox_ids(account) | Crm::PartnerGuard.partner_inbox_ids(account)).map(&:to_i)
  end

  def budget_stage_ids
    @budget_stage_ids ||= [Crm::BudgetSideEffects.stage(account)&.id].compact
  end

  def booking_stage_ids
    @booking_stage_ids ||= [Crm::BookingRate.stage(account)&.id].compact
  end

  # { contact_id => 1ª entrada na coluna } (a régua oficial: mudança de coluna, sem remarcação nem carga em massa)
  def first_stage_entry(stage_ids, contact_ids, since, horizon)
    return {} if stage_ids.empty? || contact_ids.empty?

    contact_ids.each_slice(SLICE).with_object({}) do |slice, map|
      Crm::StageLog.joins(:crm_contact)
                   .where(stage_id: stage_ids, event_type: Crm::StageLogBulk::ENTERED, entered_at: since..horizon)
                   .where(crm_contacts: { contact_id: slice })
                   .group('crm_contacts.contact_id').minimum(:entered_at)
                   .each { |contact_id, at| map[contact_id] = at }
    end
  end

  # { contact_id => { compareceu:, indicacao:, cirurgia: } } lido na Agenda
  def agenda_outcomes(contact_ids, since, horizon) # rubocop:disable Metrics/CyclomaticComplexity
    contact_ids.each_slice(SLICE).with_object({}) do |slice, map|
      account.tasks.where(task_type: %w[consulta cirurgia], canceled_at: nil, contact_id: slice, created_at: since..horizon)
             .pluck(:contact_id, :task_type, :attendance, :surgery_indication).each do |contact_id, type, attendance, indication|
        row = (map[contact_id] ||= { compareceu: false, indicacao: false, cirurgia: false })
        row[:cirurgia] = true if type == 'cirurgia'
        next unless type == 'consulta'

        row[:compareceu] = true if attendance == 'attended'
        row[:indicacao] = true if indication == 'indicated'
      end
    end
  end

  # { contact_id => { replied:, first_reply_min:, human: } } — uma passada pelas mensagens da turma
  def talk_facts(contact_ids, since, horizon) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contact_ids.each_slice(SLICE).with_object({}) do |slice, map|
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { acc: account.id, ids: slice, s: since, h: horizon }])
        SELECT cv.contact_id,
               MIN(m.created_at) FILTER (WHERE m.message_type = 0) AS first_in,
               MAX(m.created_at) FILTER (WHERE m.message_type = 0) AS last_in,
               MIN(m.created_at) FILTER (WHERE m.message_type = 1 AND m.private = false) AS first_out,
               BOOL_OR(m.message_type = 1 AND m.private = false AND m.sender_type = 'User') AS human
        FROM messages m JOIN conversations cv ON cv.id = m.conversation_id
        WHERE cv.account_id = :acc AND cv.contact_id IN (:ids) AND m.created_at BETWEEN :s AND :h
        GROUP BY cv.contact_id
      SQL
      ActiveRecord::Base.connection.select_rows(sql).each do |contact_id, first_in, last_in, first_out, human|
        first_in, last_in, first_out = [first_in, last_in, first_out].map { |value| value.is_a?(String) ? Time.zone.parse(value) : value }
        wait = first_in && first_out && first_out > first_in ? ((first_out - first_in) / 60.0) : nil
        map[contact_id] = { replied: first_out.present? && last_in.present? && last_in > first_out,
                            first_reply_min: wait, human: [true, 't'].include?(human) }
      end
    end
  end

  # ── QUEM ATENDEU: as conversas abertas no período em cada caixa ──────────
  # { inbox_id => { conversas:, com_registro:, atendidas:, respostas:, custo_usd:, modelos: {}, roteiros: {}, humano: } }
  def usage_by_inbox(since, until_at) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    scope = account.conversations.where(created_at: since..until_at)
    scope = scope.where.not(inbox_id: excluded_inbox_ids) if excluded_inbox_ids.any?
    blank = lambda do
      { conversas: 0, com_registro: 0, atendidas: 0, respostas: 0, custo_usd: 0.0, modelos: Hash.new(0), roteiros: Hash.new(0), humano: 0 }
    end
    rows = scope.pluck(:inbox_id, Arel.sql("conversations.additional_attributes -> '#{Crm::AttendanceUsage::STAMP}'"),
                       Arel.sql("conversations.additional_attributes -> '#{Crm::EngineExperiment::STAMP}'"))
    rows.each_with_object(Hash.new { |hash, key| hash[key] = blank.call }) do |(inbox_id, usage, legacy), map|
      stat = map[inbox_id]
      stat[:conversas] += 1
      read = Crm::AttendanceUsage.read(Crm::AttendanceUsage::STAMP => parse_json(usage), Crm::EngineExperiment::STAMP => parse_json(legacy))
      next if read.nil?

      stat[:com_registro] += 1
      stat[:atendidas] += 1 if read[:respostas].positive?
      stat[:respostas] += read[:respostas]
      stat[:custo_usd] += read[:custo_usd]
      stat[:humano] += 1 if read[:humano]
      # a conversa conta UMA vez em cada motor/Roteiro que a atendeu
      read[:modelos].each_key { |model| stat[:modelos][model] += 1 }
      read[:roteiros].each_key { |script| stat[:roteiros][script] += 1 }
    end
  end

  def parse_json(value)
    value.is_a?(String) ? JSON.parse(value) : value
  rescue JSON::ParserError
    nil
  end

  # ── EM QUE COLUNA A TURMA ESTÁ AGORA ─────────────────────────────────────
  # { inbox_id => [{ nome:, n: }] } na ordem do funil principal da casa
  def stages_now(cohort) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    pipeline = account.crm_pipelines.order(:position, :id).first
    return {} if pipeline.nil? || cohort.empty?

    order = pipeline.stages.order(:position).pluck(:id, :name)
    current = cohort.keys.each_slice(SLICE).with_object({}) do |slice, map|
      Crm::Contact.where(pipeline_id: pipeline.id, contact_id: slice).order(:updated_at).pluck(:contact_id, :stage_id)
                  .each { |contact_id, stage_id| map[contact_id] = stage_id }
    end
    tally = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    cohort.each { |contact_id, (inbox_id, _)| tally[inbox_id][current[contact_id]] += 1 }
    tally.transform_values do |counts|
      list = order.filter_map { |id, name| { nome: name, n: counts[id] } if counts[id].positive? }
      counts[nil].positive? ? list + [{ nome: 'Sem card no funil', n: counts[nil] }] : list
    end
  end

  # ── DE QUAIS CAMPANHAS A TURMA VEIO (anúncio do Meta carimbado no contato) ──
  # { inbox_id => [{ nome:, chegaram:, agendaram: }] } — as 6 maiores
  def campaigns_of(cohort, booked) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    ads = ad_ids_of(cohort.keys)
    names = Crm::AdCreative.where(account_id: account.id, ad_id: ads.values.uniq).pluck(:ad_id, :campaign_name).to_h
    tally = Hash.new { |hash, key| hash[key] = Hash.new { |inner, name| inner[name] = { chegaram: 0, agendaram: 0 } } }
    cohort.each do |contact_id, (inbox_id, _)|
      ad_id = ads[contact_id]
      name = ad_id ? (names[ad_id].presence || 'Anúncio do Meta (campanha sem nome)') : 'Sem anúncio do Meta carimbado'
      stat = tally[inbox_id][name]
      stat[:chegaram] += 1
      stat[:agendaram] += 1 if booked[contact_id]
    end
    tally.transform_values do |list|
      list.map { |name, stat| stat.merge(nome: name) }.sort_by { |row| [-row[:chegaram], -row[:agendaram], row[:nome]] }.first(6)
    end
  end

  # { contact_id => id do anúncio do Meta carimbado no contato }
  def ad_ids_of(contact_ids)
    contact_ids.each_slice(SLICE).with_object({}) do |slice, map|
      account.contacts.where(id: slice).where("contacts.additional_attributes -> 'meta_ads' ->> 'source_id' IS NOT NULL")
             .pluck(:id, Arel.sql("contacts.additional_attributes -> 'meta_ads' ->> 'source_id'")).each { |id, ad_id| map[id] = ad_id.to_s }
    end
  end

  # ── COMO A CAIXA ESTÁ CONFIGURADA HOJE (atendentes de IA que leem nela) ──
  def config_for(inbox_id) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    agents.filter_map do |key, agent|
      next unless agent.is_a?(Hash) && agent['enabled'] == true && Array(agent['inbox_ids']).map(&:to_i).include?(inbox_id)

      experiment = Crm::EngineExperiment.active(agent)
      mode = experiment ? Crm::EngineExperiment.mode_for(experiment, inbox_id) : nil
      card = Crm::EngineExperiment.model_a(key, agent)
      staged = Crm::StageEngine.config(agent).values.map { |model| model.to_s.strip }.compact_blank
      { agente: key, nome: AGENT_LABELS[key], modo: agent['mode'].presence,
        motor: Crm::LlmCatalog.label(card), motores_por_coluna: (staged - [card]).uniq.map { |model| Crm::LlmCatalog.label(model) },
        teste: experiment && mode != 'a' ? test_json(experiment, mode) : nil,
        caixa: own_engine_json(agent, inbox_id) }
    end
  end

  # 📥 item 416: a caixa tem motor/esforço/Roteiro próprio neste atendente?
  def own_engine_json(agent, inbox_id)
    entry = Crm::InboxEngine.config(agent)[inbox_id.to_s]
    return nil unless entry.is_a?(Hash) && entry.values.any?(&:present?)

    { motor: entry['model'].present? ? Crm::LlmCatalog.label(entry['model']) : nil,
      esforco: entry['effort'].presence, roteiro: entry['script'].presence }
  end

  def test_json(experiment, mode)
    { nome: experiment['name'].presence, modo: mode, roteiro_b: experiment['script_b'].presence || 'v1',
      motor_b: experiment['model_b'].present? ? Crm::LlmCatalog.label(experiment['model_b']) : nil }
  end

  def agents
    @agents ||= ((CrmSetting.find_by(account: account)&.ai_config || {})['agents'] || {}).slice(*AGENT_LABELS.keys)
  end

  # ── O JSON DE UMA CAIXA ──────────────────────────────────────────────────
  def row_json(inbox_id, cur, prev, keys, split) # rubocop:disable Metrics/AbcSize
    funnel = cur[:funnel].key?(inbox_id) ? cur[:funnel][inbox_id] : FUNNEL.index_with { 0 }
    before = prev[:funnel].key?(inbox_id) ? prev[:funnel][inbox_id] : FUNNEL.index_with { 0 }
    people = cur[:people][inbox_id] || []
    {
      inbox_id: inbox_id, nome: inbox_names[inbox_id] || 'Caixa removida', porta: capture_inbox_ids.include?(inbox_id),
      funil: funnel, anterior: before,
      tempos: times_json(people),
      ia: usage_json(cur[:usage][inbox_id]),
      config: config_for(inbox_id),
      custo: cost_json(inbox_id, funnel, cur[:usage][inbox_id], split),
      serie: series_json(people, keys),
      colunas: cur[:stages][inbox_id] || [],
      campanhas: cur[:campaigns][inbox_id] || []
    }
  end

  def inbox_names
    @inbox_names ||= account.inboxes.pluck(:id, :name).to_h
  end

  def times_json(people) # rubocop:disable Metrics/CyclomaticComplexity
    waits = people.filter_map { |person| person[:facts][:first_reply_min] }
    books = people.filter_map { |person| person[:booked_at] && ((person[:booked_at] - person[:at]) / 3600.0) }.select { |hours| hours >= 0 }
    { primeira_resposta_min: median(waits)&.round(1), ate_agendar_h: median(books)&.round(1),
      com_humano: people.count { |person| person[:facts][:human] } }
  end

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  def usage_json(stat)
    stat ||= { conversas: 0, com_registro: 0, atendidas: 0, respostas: 0, custo_usd: 0.0, modelos: {}, roteiros: {}, humano: 0 }
    label = ->(tally, namer) { tally.sort_by { |_, count| -count }.map { |id, count| { id: id, nome: namer.call(id), conversas: count } } }
    stat.slice(:conversas, :com_registro, :atendidas, :respostas, :humano).merge(
      custo_usd: stat[:custo_usd].round(4),
      custo_por_conversa_usd: stat[:atendidas].positive? ? (stat[:custo_usd] / stat[:atendidas]).round(4) : nil,
      modelos: label.call(stat[:modelos], ->(id) { Crm::LlmCatalog.label(id) }),
      roteiros: label.call(stat[:roteiros], ->(id) { id.to_s == 'v2' ? 'Roteiro 2' : 'Roteiro 1' })
    )
  end

  def series_json(people, keys)
    arrived = Hash.new(0)
    booked = Hash.new(0)
    people.each do |person|
      key = bucket_of(person[:at])
      arrived[key] += 1
      booked[key] += 1 if person[:booked_at]
    end
    { chegaram: keys.map { |key| arrived[key] }, agendaram: keys.map { |key| booked[key] },
      taxa: keys.map { |key| arrived[key].positive? ? (booked[key] * 100.0 / arrived[key]).round(1) : nil } }
  end

  # ── CUSTO (só administrador) ─────────────────────────────────────────────
  def meta_split
    return nil if @invest.nil? || @invest[:meta_total].to_f <= 0

    Crm::MetaSpendByInbox.new(account: account, since: @since, until_at: @until_at, total: @invest[:meta_total]).call
  end

  def meta_json(split)
    return nil if @invest.nil?
    return { total: nil, sem_caixa: nil, metodo: nil, aviso: @invest[:meta_note] } if split.nil?

    { total: split[:total], sem_caixa: split[:unassigned], metodo: split[:method], aviso: nil }
  end

  def cost_json(inbox_id, funnel, usage, split) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if @invest.nil?

    cfg = (@invest[:config] || {})[inbox_id.to_s] || {}
    parts = []
    meta = split ? split[:by_inbox][inbox_id].to_f : 0.0
    parts << { origem: 'Meta Ads', valor: meta.round(2) } if meta.positive?
    google = cfg['mode'] == 'google_auto' ? @invest.dig(:google, :cost).to_f : 0.0
    parts << { origem: 'Google (GA4)', valor: google.round(2) } if google.positive?
    manual = cfg['mode'].to_s == 'manual' ? (cfg['monthly'].to_f * ((@until_at - @since) / 1.day) / 30.44) : 0.0
    parts << { origem: 'Valor informado', valor: manual.round(2) } if manual.positive?
    total = parts.sum { |part| part[:valor] }
    per = ->(count) { total.positive? && count.to_i.positive? ? (total / count).round(2) : nil }
    { investimento: total.round(2), partes: parts,
      aviso: cfg['mode'] == 'google_auto' && google.zero? ? @invest.dig(:google, :error).presence : nil,
      por_lead: per.call(funnel[:chegaram]), por_orcamento: per.call(funnel[:orcamento]),
      por_agendamento: per.call(funnel[:agendaram]), por_comparecimento: per.call(funnel[:compareceram]),
      por_cirurgia: per.call(funnel[:cirurgias]), ia_usd: usage ? usage[:custo_usd].round(4) : 0.0 }
  end

  # ── TOTAL (a soma das caixas mostradas) ──────────────────────────────────
  def total_json(rows, _cur, _prev)
    sum = ->(group) { FUNNEL.index_with { |key| rows.sum { |row| row[group][key] } } }
    invest = @invest.nil? ? nil : rows.sum { |row| row.dig(:custo, :investimento).to_f }.round(2)
    { funil: sum.call(:funil), anterior: sum.call(:anterior), investimento: invest,
      conversas: rows.sum { |row| row[:ia][:conversas] }, custo_ia_usd: rows.sum { |row| row[:ia][:custo_usd] }.round(4) }
  end

  # ── baldes (a mesma régua da Jornada: dia até ~3 meses; depois, mês) ─────
  def bucket_of(time)
    time.in_time_zone(TZ).strftime(@by_month ? '%Y-%m' : '%Y-%m-%d')
  end

  def bucket_keys
    day = @since.in_time_zone(TZ).to_date
    last = [@until_at, @now].min.in_time_zone(TZ).to_date
    keys = []
    while day <= last
      keys << bucket_of(day.in_time_zone(TZ))
      day = @by_month ? day.next_month.beginning_of_month : day + 1
    end
    keys.uniq
  end

  def bucket_label(key)
    @by_month ? "#{key[5, 2]}/#{key[2, 2]}" : "#{key[8, 2]}/#{key[5, 2]}"
  end

  def range_label(since, until_at)
    from = since.in_time_zone(TZ).strftime('%d/%m')
    to = until_at.in_time_zone(TZ).strftime('%d/%m')
    from == to ? from : "#{from}–#{to}"
  end
end
