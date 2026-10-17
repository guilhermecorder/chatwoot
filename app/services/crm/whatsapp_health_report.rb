# 🚦 SAÚDE DO WHATSAPP (16/10/2026) — o que a tela Relatórios → Saúde do
# WhatsApp mostra, em 4 blocos:
#   numbers  → cada caixa: nota da Meta agora + linha do tempo, limite de
#              envios, entregues/lidas na semana, erros da Meta por dia
#   templates→ modelos de cada caixa: situação, nota, envios e entrega
#   people   → quem não quer mais receber: CERTO × SUSPEITA, com o motivo
#   silence  → o que veio antes do silêncio: por quem mandou e por modelo
# + rules (as chavinhas dos robôs e quantas pessoas estão fora agora).
class Crm::WhatsappHealthReport # rubocop:disable Metrics/ClassLength
  DAY_SQL = "DATE(messages.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')".freeze
  ERROR_CODE_SQL = "substring(COALESCE(messages.content_attributes::text, '') from '(?:^|[^0-9])(13[0-9]{4})(?:[^0-9]|$)')".freeze
  # o que cada erro da Meta quer dizer (PT-BR simples)
  ERRORS = {
    '131048' => { label: 'Limite por spam no número', hint: 'muita gente bloqueou ou denunciou — a Meta freou este número', grave: true },
    '131049' => { label: 'A Meta segurou o marketing', hint: 'limite de marketing por pessoa (ela já recebeu muito de várias empresas)',
                  grave: false },
    '131050' => { label: 'Parou de receber marketing', hint: 'a pessoa desligou o marketing desta empresa — vira etiqueta certo_sem_marketing',
                  grave: true },
    '131026' => { label: 'Não entregue', hint: 'número sem WhatsApp, aplicativo antigo ou termos da Meta não aceitos', grave: false },
    '131047' => { label: 'Fora da janela de 24h', hint: 'passou 24h da última mensagem do paciente — só mensagem modelo entrega', grave: false },
    '131056' => { label: 'Muitas para a mesma pessoa', hint: 'mensagens demais para o mesmo paciente em pouco tempo', grave: false },
    '131000' => { label: 'Erro da Meta', hint: 'falha do lado da Meta — costuma passar sozinha', grave: false },
    '132000' => { label: 'Modelo com variáveis erradas', hint: 'número de campos do modelo não bate', grave: false },
    '132001' => { label: 'Modelo inexistente', hint: 'nome ou idioma do modelo não existe nesta caixa', grave: false }
  }.freeze
  PEOPLE_CAP = 400
  SILENCE_WINDOW = 60.days
  SILENCE_MIN = 15 # menos que isso recebendo = "poucos dados"

  def initialize(account:, now: Time.current)
    @account = account
    @now = now
    @inboxes = Crm::WhatsappHealthLog.whatsapp_inboxes(account).to_a
    @inbox_ids = @inboxes.map(&:id)
  end

  def call
    {
      generated_at: @now.iso8601,
      signals: Crm::StopSignals::SIGNALS.map { |k, v| { key: k, **v } },
      numbers: numbers,
      errors_legend: ERRORS.map { |code, v| { code: code, **v } },
      templates: templates,
      people: people,
      silence: silence,
      rules: rules
    }
  end

  private

  def outgoing
    @account.messages.reorder(nil).where(inbox_id: @inbox_ids, message_type: :outgoing, private: false)
  end

  # ── bloco 1: números ─────────────────────────────────────────────────────
  def numbers
    log = Crm::WhatsappHealthLog.history(@account)
    week = delivery_by_inbox(@now - 7.days)
    stuck = outgoing.where(status: :sent, created_at: (@now - 7.days)..(@now - 48.hours)).where.not(source_id: nil).group(:inbox_id).count
    errors = errors_by_inbox_day(@now - 14.days)
    @inboxes.map do |inbox|
      h = Crm::WhatsappHealthLog.health(inbox.channel)
      { id: inbox.id, name: inbox.name, phone: inbox.channel.try(:phone_number),
        cloud: inbox.channel.try(:provider) == 'whatsapp_cloud',
        quality: h[:quality_rating].to_s.upcase.presence, limit_tier: h[:messaging_limit_tier], status: h[:status],
        name_status: h[:name_status], throughput: h[:throughput_level],
        history: Array(log[inbox.id.to_s]), week: week[inbox.id] || empty_delivery, stuck_48h: stuck[inbox.id] || 0,
        errors: errors[inbox.id] || { days: [], totals: {} } }
    end
  end

  def empty_delivery
    { sent: 0, delivered: 0, read: 0, failed: 0, total: 0, delivered_pct: nil, read_pct: nil }
  end

  def delivery_by_inbox(since)
    rows = outgoing.where(created_at: since..@now).where.not(source_id: nil).group(:inbox_id, :status).count
    rows.each_with_object({}) do |((inbox_id, status), n), acc|
      acc[inbox_id] ||= empty_delivery.dup
      acc[inbox_id][status.to_sym] = n if acc[inbox_id].key?(status.to_sym)
      acc[inbox_id][:total] += n
    end.transform_values { |d| with_pcts(d) }
  end

  def with_pcts(row)
    total = row[:total].to_i
    return row if total.zero?

    row.merge(delivered_pct: (((row[:delivered] + row[:read]) * 100.0) / total).round(1),
              read_pct: ((row[:read] * 100.0) / total).round(1))
  end

  def errors_by_inbox_day(since)
    rows = outgoing.where(status: :failed, created_at: since..@now)
                   .group(:inbox_id, Arel.sql(DAY_SQL), Arel.sql(ERROR_CODE_SQL)).count
    rows.each_with_object({}) do |((inbox_id, day, code), n), acc|
      code = code.presence || 'outro'
      acc[inbox_id] ||= { by_day: Hash.new { |h, k| h[k] = {} }, totals: Hash.new(0) }
      acc[inbox_id][:by_day][day.to_s][code] = n
      acc[inbox_id][:totals][code] += n
    end.transform_values do |v|
      days = (0..13).map { |i| (@now.in_time_zone('America/Sao_Paulo').to_date - (13 - i)).to_s }
      { days: days.map { |d| { day: d, codes: v[:by_day].fetch(d, {}) } }, totals: v[:totals] }
    end
  end

  # ── bloco 2: modelos ─────────────────────────────────────────────────────
  def templates
    sends = outgoing.where(created_at: (@now - 14.days)..@now)
                    .where(Arel.sql("#{Crm::StopSignals::TEMPLATE_SQL} IS NOT NULL"))
                    .group(:inbox_id, Arel.sql(Crm::StopSignals::TEMPLATE_SQL), :status).count
    by_tpl = sends.each_with_object({}) do |((inbox_id, name, status), n), acc|
      row = (acc[[inbox_id, name]] ||= empty_delivery.dup)
      row[status.to_sym] = n if row.key?(status.to_sym)
      row[:total] += n
    end
    @inboxes.map do |inbox|
      list = Crm::WhatsappHealthLog.templates(inbox.channel).map do |t|
        t.merge(sends: with_pcts(by_tpl.delete([inbox.id, t[:name]]) || empty_delivery.dup))
      end
      { inbox_id: inbox.id, inbox: inbox.name, list: list.sort_by { |t| [-t[:sends][:total], t[:name].to_s] } }
    end
  end

  # ── bloco 3: pessoas ─────────────────────────────────────────────────────
  def people
    keys = Crm::StopSignals::KEYS
    contacts = @account.contacts.tagged_with(keys, any: true)
                       .order(updated_at: :desc).limit(PEOPLE_CAP).to_a
    last_conv = Conversation.where(contact_id: contacts.map(&:id)).group(:contact_id).maximum(:display_id)
    counts = keys.index_with { |k| @account.contacts.tagged_with(k).count }
    inbox_names = @inboxes.to_h { |i| [i.id, i.name] }
    { counts: counts, cap: PEOPLE_CAP,
      list: contacts.flat_map { |c| person_rows(c, keys, last_conv[c.id], inbox_names) }
                    .sort_by { |r| r[:at].to_s }.reverse }
  end

  def person_rows(contact, keys, conversation_id, inbox_names)
    proof = Crm::StopSignals.evidence(contact)
    (contact.label_list & keys).map do |key|
      ev = proof[key] || {}
      { contact_id: contact.id, name: contact.name, phone: contact.phone_number, key: key,
        certeza: Crm::StopSignals::SIGNALS.dig(key, :certeza), at: ev['at'], since: ev['desde'],
        # marcação antiga (detector de antes de 16/10) que o detector novo NÃO faria
        review: ev['revisar'] == true,
        reason: reason_text(key, ev, inbox_names), evidence: decorate_evidence(ev, inbox_names),
        conversation_id: ev['conversa'] || ev.dig('primeira_presa', 'conversa') || conversation_id,
        other_keys: (contact.label_list & keys) - [key] }
    end
  end

  def reason_text(key, ev, inbox_names) # rubocop:disable Metrics/CyclomaticComplexity
    return 'marcada antes de 16/10 — sem registro do motivo (veja a conversa)' if ev.blank?

    case key
    when 'nao_perturbe', 'suspeita_nao_quer'
      "escreveu: “#{ev['texto']}”#{' — marcação antiga: o detector novo não marcaria, confira' if ev['revisar']}"
    when 'certo_sem_marketing'
      "a Meta recusou o marketing pela caixa #{inbox_names[ev['inbox_id'].to_i] || ev['inbox_id']} (erro 131050)"
    when 'suspeita_bloqueio'
      caixas = Array(ev['caixas']).map { |c| "#{c['presas']} na caixa #{inbox_names[c['inbox_id'].to_i] || c['inbox_id']}" }
      "#{caixas.join(' · ')} só em “enviado” desde #{fmt_time(ev['desde'])} — já tinha recebido antes"
    end
  end

  def decorate_evidence(ev, inbox_names)
    bot_names = bot_names_cache
    %w[ultima_entregue primeira_presa mensagem].each_with_object(ev.except('_historico', '_dispensados').deep_dup) do |k, out|
      next unless out[k].is_a?(Hash)

      out[k]['origem_label'] = Crm::StopSignals.origin_label(out[k]['origem'], bot_names)
      out[k]['caixa'] = inbox_names[out[k]['inbox_id'].to_i]
    end
  end

  def fmt_time(iso)
    Time.zone.parse(iso.to_s).in_time_zone('America/Sao_Paulo').strftime('%d/%m %Hh%M')
  rescue ArgumentError, TypeError
    iso.to_s
  end

  def bot_names_cache
    @bot_names_cache ||= Crm::FollowupBot.where(account_id: @account.id).pluck(:id, :name).to_h
  end

  # ── bloco 4: o que mais gera silêncio ────────────────────────────────────
  # recebeu = pessoas cuja ÚLTIMA mensagem nossa entregue (60 dias) veio dali
  # silêncio/parou = quantas dessas estão marcadas, pelo registro do motivo
  def silence
    base = last_delivered_rows
    marked = marked_origins
    { window_days: SILENCE_WINDOW.in_days.to_i, min: SILENCE_MIN,
      by_origin: silence_rows(base.group_by { |r| r[:origin] }, marked, :origin) { |k| Crm::StopSignals.origin_label(k, bot_names_cache) },
      by_template: silence_rows(base.select { |r| r[:template] }.group_by { |r| r[:template] }, marked, :template) { |k| k } }
  end

  def last_delivered_rows
    sql = outgoing.joins(:conversation).where(status: %i[delivered read], created_at: (@now - SILENCE_WINDOW)..@now)
                  .select(Arel.sql("DISTINCT ON (conversations.contact_id) conversations.contact_id AS cid, #{Crm::StopSignals::ORIGIN_SQL} AS origin, " \
                                   "#{Crm::StopSignals::TEMPLATE_SQL} AS tpl"))
                  .order(Arel.sql('conversations.contact_id, messages.created_at DESC'))
    ActiveRecord::Base.connection.select_all(sql.to_sql).map { |r| { cid: r['cid'].to_i, origin: r['origin'], template: r['tpl'] } }
  end

  # contato → { chave do sinal → origem/modelo da última entregue antes dele }
  def marked_origins
    @account.contacts.tagged_with(Crm::StopSignals::KEYS, any: true).find_each.each_with_object({}) do |c, acc|
      proof = Crm::StopSignals.evidence(c)
      (c.label_list & Crm::StopSignals::KEYS).each do |key|
        last = proof.dig(key, 'ultima_entregue')
        next unless last.is_a?(Hash)

        (acc[c.id] ||= {})[key] = { origin: last['origem'], template: last['modelo'] }
      end
    end
  end

  def silence_rows(groups, marked, field)
    rows = groups.map do |key, list|
      ids = list.map { |r| r[:cid] }
      counts = ids.each_with_object(Hash.new(0)) do |cid, acc|
        (marked[cid] || {}).each { |sig, o| acc[sig] += 1 if o[field] == key }
      end
      total = ids.size
      blocked = counts['suspeita_bloqueio']
      stopped = counts['nao_perturbe'] + counts['certo_sem_marketing'] + counts['suspeita_nao_quer']
      { key: key, label: yield(key), received: total, blocked: blocked, stopped: stopped, by_signal: counts,
        blocked_pct: pct(blocked, total), stopped_pct: pct(stopped, total), enough: total >= SILENCE_MIN }
    end
    rows.sort_by { |r| [r[:enough] ? 0 : 1, -(r[:blocked_pct].to_f + r[:stopped_pct].to_f), -r[:received]] }.first(25)
  end

  def pct(part, total)
    total.to_i.positive? ? ((part * 100.0) / total).round(1) : nil
  end

  # ── regras dos robôs ─────────────────────────────────────────────────────
  def rules
    cfg = Crm::StopSignals.settings(@account)
    { robots: cfg['robos'], hours: cfg['horas'], stuck: cfg['presas'],
      limits: { hours: Crm::StopSignals::SCAN_LIMITS['horas'].minmax, stuck: Crm::StopSignals::SCAN_LIMITS['presas'].minmax } }
  end
end
