# 💸 item 303 (30/09/2026): GASTO DO WHATSAPP — os números da tela.
#
# Duas fontes, cada uma com o seu papel:
#   • FATURA DA META (crm_whatsapp_charges, via pricing_analytics): o valor
#     real, na moeda da conta, por dia/número/categoria. É "a verdade".
#   • ATRIBUIÇÃO POR MENSAGEM (additional_attributes.cevico_wa_billing, via
#     webhook de status): quem mandou cada mensagem cobrada — Atendente de IA,
#     follow-up, lembrete, jornada, campanha, cada pessoa da equipe. O custo
#     aqui é ESTIMADO pelas tarifas (Crm::WhatsappPricing); a Meta não manda
#     o valor no webhook.
class Crm::WhatsappSpendService # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  DAY_SQL = "DATE(messages.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')".freeze
  BILLING = "messages.additional_attributes -> 'cevico_wa_billing'".freeze
  TYPE_SQL = "COALESCE(#{BILLING} ->> 'type', 'unknown')".freeze
  CATEGORY_SQL = "COALESCE(#{BILLING} ->> 'category', '')".freeze
  # quem mandou: cada automação carimba a própria mensagem
  WHO_SQL = <<~SQL.squish.freeze
    CASE
      WHEN jsonb_exists(messages.additional_attributes, 'cevico_ia_agent') THEN 'ia:' || (messages.additional_attributes ->> 'cevico_ia_agent')
      WHEN jsonb_exists(messages.additional_attributes, 'cevico_followup_bot_id') THEN 'followup'
      WHEN jsonb_exists(messages.additional_attributes, 'cevico_journey') THEN 'jornada'
      WHEN jsonb_exists(messages.additional_attributes, 'cevico_auto') THEN 'auto:' || (messages.additional_attributes ->> 'cevico_auto')
      WHEN jsonb_exists(messages.additional_attributes, 'campaign_id') THEN 'campanha'
      WHEN messages.sender_type = 'User' THEN 'user:' || messages.sender_id::text
      ELSE 'sistema'
    END
  SQL
  # balões: respostas do robô = grupos de mensagens dele na mesma conversa
  # dentro do mesmo minuto (o item 200 espaça os balões em 3 s)
  REPLY_SQL = "messages.conversation_id::text || '@' || to_char(messages.created_at, 'YYYY-MM-DD HH24:MI')".freeze

  WHO_META = {
    'ia:atendente_agendamento' => { label: 'Atendente de Agendamento (IA)', kind: 'robo', color: '#059669', icon: 'i-lucide-message-square-heart' },
    'ia:atendente_pos' => { label: 'Atendente Pós-agendamento (IA)', kind: 'robo', color: '#0F5FA6', icon: 'i-lucide-life-buoy' },
    'ia:atendente_pos_op' => { label: 'Atendente de Pós-operatório (IA)', kind: 'robo', color: '#BE123C', icon: 'i-lucide-heart-pulse' },
    'followup' => { label: 'Follow-up (robô por coluna)', kind: 'automacao', color: '#7C3AED', icon: 'i-lucide-timer' },
    'jornada' => { label: 'Jornada do paciente', kind: 'automacao', color: '#FF2D55', icon: 'i-lucide-route' },
    'campanha' => { label: 'Campanha WhatsApp', kind: 'automacao', color: '#25D366', icon: 'i-lucide-send' },
    'sistema' => { label: 'Sistema (sem autor)', kind: 'sistema', color: '#8E8E93', icon: 'i-lucide-cpu' }
  }.freeze
  TEAM_COLORS = %w[#0A84FF #FF9F0A #AF52DE #34C759 #FF375F #5AC8FA #FFD60A #BF5AF2 #30D158 #64D2FF].freeze
  CATEGORY_LABELS = {
    'marketing' => 'Marketing', 'utility' => 'Utilidade', 'authentication' => 'Autenticação',
    'service' => 'Serviço (resposta livre)'
  }.freeze

  def self.outgoing_scope(account, since, until_at)
    inbox_ids = account.inboxes.where(channel_type: 'Channel::Whatsapp').pluck(:id)
    # reorder(nil): Message vem ordenada por created_at e o GROUP BY quebra
    account.messages.reorder(nil)
           .where(inbox_id: inbox_ids, message_type: :outgoing, private: false, created_at: since..until_at)
           .where.not(status: :failed)
  end

  def initialize(account:, since:, until_at:)
    @account = account
    @since = since
    @until_at = until_at
    @rates = Crm::WhatsappPricing.rates(account)
  end

  def call
    ttl = @until_at >= Time.current ? 3.minutes : 15.minutes
    Rails.cache.fetch("cevico:waspend:#{@account.id}:#{@since.to_i}:#{@until_at.to_i}:#{@rates.hash}", expires_in: ttl) do
      {
        period: { from: @since.iso8601, to: @until_at.iso8601, days: days_in_period },
        rates: @rates,
        service_charged_from: Crm::WhatsappPricing::SERVICE_CHARGED_FROM.iso8601,
        meta: meta_invoice,
        attributed: attributed
      }
    end
  end

  private

  def days_in_period
    (@until_at.to_date - @since.to_date).to_i + 1
  end

  # ── fatura da Meta ──────────────────────────────────────────────────
  def charges
    Crm::WhatsappCharge.where(account_id: @account.id)
  end

  BILLABLE_VOLUME_SQL = "SUM(CASE WHEN pricing_type = 'regular' THEN volume ELSE 0 END) AS v".freeze
  BILLABLE_COST_SQL = "SUM(CASE WHEN pricing_type = 'regular' THEN cost ELSE 0 END) AS c".freeze

  def meta_invoice
    rows = charges.where(day: @since.to_date..@until_at.to_date)
    synced_at = charges.maximum(:updated_at)
    return { synced: false, synced_at: nil } if synced_at.nil?

    by_type = meta_by_type(rows)
    volume = ->(type) { by_type.dig(type, :volume) || 0 }
    {
      synced: true,
      synced_at: synced_at.iso8601,
      currency: meta_currency(rows),
      cost: by_type.values.sum { |r| r[:cost] }.round(2),
      billable_volume: volume.call(Crm::WhatsappCharge::TYPE_REGULAR),
      free_window_volume: volume.call(Crm::WhatsappCharge::TYPE_FREE_WINDOW),
      free_ad_volume: volume.call(Crm::WhatsappCharge::TYPE_FREE_AD),
      by_category: meta_by_category(rows),
      by_phone: meta_by_phone(rows),
      daily: meta_daily(rows),
      months: meta_months
    }
  end

  def meta_currency(rows)
    (rows.first || charges.order(day: :desc).first)&.currency || 'USD'
  end

  def meta_by_type(rows)
    rows.group(:pricing_type).pluck(:pricing_type, Arel.sql('SUM(volume) AS v'), Arel.sql('SUM(cost) AS c'))
        .to_h { |t, v, c| [t, { volume: v.to_i, cost: c.to_f.round(2) }] }
  end

  def meta_by_category(rows)
    list = rows.billable.group(:category).pluck(:category, Arel.sql('SUM(volume) AS v'), Arel.sql('SUM(cost) AS c'))
    list.map { |cat, v, c| { category: cat, label: CATEGORY_LABELS[cat] || cat.humanize, volume: v.to_i, cost: c.to_f.round(2) } }
        .sort_by { |r| -r[:cost] }
  end

  def meta_by_phone(rows)
    phones = inbox_names_by_phone
    list = rows.group(:phone_number).pluck(:phone_number, Arel.sql('SUM(volume) AS v'), Arel.sql(BILLABLE_COST_SQL))
    list.map { |p, v, c| { phone: p, inbox: phones[p.to_s.delete('^0-9')] || p, volume: v.to_i, cost: c.to_f.round(2) } }
        .sort_by { |r| -r[:cost] }
  end

  def meta_daily(rows)
    rows.group(:day).pluck(:day, Arel.sql(BILLABLE_VOLUME_SQL), Arel.sql('SUM(cost) AS c'))
        .to_h { |d, v, c| [d.iso8601, { volume: v.to_i, cost: c.to_f.round(2) }] }
  end

  # últimos 12 meses fechados pela Meta — independe do período escolhido
  def meta_months
    month_sql = Arel.sql("to_char(day, 'YYYY-MM')")
    list = charges.where(day: 12.months.ago.to_date.beginning_of_month..)
                  .group(month_sql).pluck(month_sql, Arel.sql(BILLABLE_VOLUME_SQL), Arel.sql('SUM(cost) AS c'))
    list.map { |m, v, c| { month: m, volume: v.to_i, cost: c.to_f.round(2) } }.sort_by { |r| r[:month] }
  end

  def inbox_names_by_phone
    @account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).to_h do |inbox|
      [inbox.channel.phone_number.to_s.delete('^0-9'), inbox.name]
    end
  end

  # ── atribuição por mensagem (webhook) ───────────────────────────────
  def scope
    @scope ||= self.class.outgoing_scope(@account, @since, @until_at)
  end

  def rate_for(type, category, october: false)
    charged = type == Crm::WhatsappCharge::TYPE_REGULAR ||
              (october && type == Crm::WhatsappCharge::TYPE_FREE_WINDOW)
    charged ? @rates[category].to_f : 0.0
  end

  def attributed # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    who_rows = scope.group(Arel.sql(WHO_SQL), Arel.sql(TYPE_SQL), Arel.sql(CATEGORY_SQL)).count
    totals = Hash.new(0)
    cost = 0.0
    simulated = 0.0
    by_who = Hash.new { |h, k| h[k] = { messages: 0, billable: 0, free_window: 0, free_ad: 0, unknown: 0, cost: 0.0, simulated: 0.0 } }
    by_category = Hash.new { |h, k| h[k] = { messages: 0, cost: 0.0 } }
    who_rows.each do |(who, type, category), n|
      totals[type] += n
      c = n * rate_for(type, category)
      s = n * rate_for(type, category, october: true)
      cost += c
      simulated += s
      row = by_who[who]
      row[:messages] += n
      row[:cost] += c
      row[:simulated] += s
      row[type_bucket(type)] += n
      next unless category.present? && type != 'unknown'

      by_category[category][:messages] += n
      by_category[category][:cost] += c
    end
    {
      messages: totals.values.sum,
      billable: totals[Crm::WhatsappCharge::TYPE_REGULAR],
      free_window: totals[Crm::WhatsappCharge::TYPE_FREE_WINDOW],
      free_ad: totals[Crm::WhatsappCharge::TYPE_FREE_AD],
      unknown: totals['unknown'],
      cost: cost.round(2),
      simulated_october_cost: simulated.round(2),
      by_who: decorate_who(by_who),
      by_category: category_rows(by_category),
      by_inbox: by_inbox,
      daily: daily,
      balloons: balloons
    }
  end

  def type_bucket(type)
    case type
    when Crm::WhatsappCharge::TYPE_REGULAR then :billable
    when Crm::WhatsappCharge::TYPE_FREE_WINDOW then :free_window
    when Crm::WhatsappCharge::TYPE_FREE_AD then :free_ad
    else :unknown
    end
  end

  def category_rows(by_category)
    list = by_category.map do |cat, r|
      { category: cat, label: CATEGORY_LABELS[cat] || cat.humanize, messages: r[:messages], cost: r[:cost].round(2) }
    end
    list.sort_by { |r| -r[:messages] }
  end

  def decorate_who(by_who)
    user_ids = by_who.keys.filter_map { |k| k.delete_prefix('user:').to_i if k.start_with?('user:') }
    names = User.where(id: user_ids).pluck(:id, :name).to_h
    team_index = -1
    rows = by_who.map do |key, r|
      meta = WHO_META[key] || who_meta(key, names) { team_index += 1 }
      who_row(key, meta, r)
    end
    rows.sort_by { |r| [-r[:cost], -r[:messages]] }
  end

  def who_row(key, meta, row)
    { key: key, **meta, messages: row[:messages], billable: row[:billable], free_window: row[:free_window], free_ad: row[:free_ad],
      unknown: row[:unknown], cost: row[:cost].round(2), simulated: row[:simulated].round(2) }
  end

  # quem não está na tabela fixa: pessoa da equipe (cor da vez), automação
  # com nome próprio, agente de IA novo
  def who_meta(key, names)
    kind, value = key.split(':', 2)
    case kind
    when 'user'
      { label: names[value.to_i] || 'Pessoa removida', kind: 'equipe', color: TEAM_COLORS[yield % TEAM_COLORS.size], icon: 'i-lucide-user' }
    when 'auto'
      { label: auto_label(value), kind: 'automacao', color: '#FF9F0A', icon: 'i-lucide-bell-ring' }
    when 'ia'
      { label: "#{value.humanize} (IA)", kind: 'robo', color: '#059669', icon: 'i-lucide-bot' }
    else
      WHO_META['sistema']
    end
  end

  # 'cevico_auto' guarda o nome da automação (lembrete, NPS, campanha…)
  def auto_label(raw)
    label = raw.to_s.tr('_', ' ').strip
    label = label.humanize if label == label.downcase
    "#{label} (automático)"
  end

  def by_inbox # rubocop:disable Metrics/AbcSize
    names = @account.inboxes.where(channel_type: 'Channel::Whatsapp').pluck(:id, :name).to_h
    rows = scope.group(:inbox_id, Arel.sql(TYPE_SQL), Arel.sql(CATEGORY_SQL)).count
    acc = Hash.new { |h, k| h[k] = { messages: 0, billable: 0, cost: 0.0 } }
    rows.each do |(inbox_id, type, category), n|
      r = acc[inbox_id]
      r[:messages] += n
      r[:billable] += n if type == Crm::WhatsappCharge::TYPE_REGULAR
      r[:cost] += n * rate_for(type, category)
    end
    acc.map { |id, r| { inbox_id: id, name: names[id] || "Caixa #{id}", messages: r[:messages], billable: r[:billable], cost: r[:cost].round(2) } }
       .sort_by { |r| -r[:cost] }
  end

  def daily # rubocop:disable Metrics/AbcSize
    rows = scope.group(Arel.sql(DAY_SQL), Arel.sql(TYPE_SQL), Arel.sql(CATEGORY_SQL)).count
    acc = Hash.new { |h, k| h[k] = { messages: 0, billable: 0, cost: 0.0, simulated: 0.0 } }
    rows.each do |(day, type, category), n|
      r = acc[day.to_date.iso8601]
      r[:messages] += n
      r[:billable] += n if type == Crm::WhatsappCharge::TYPE_REGULAR
      r[:cost] += n * rate_for(type, category)
      r[:simulated] += n * rate_for(type, category, october: true)
    end
    (@since.to_date..@until_at.to_date).map do |d|
      r = acc[d.iso8601]
      { day: d.iso8601, label: d.strftime('%d/%m'), messages: r[:messages], billable: r[:billable],
        cost: r[:cost].round(2), simulated: r[:simulated].round(2) }
    end
  end

  # o robô manda até 3 balões por resposta (item 200) e cada balão é 1 cobrança
  def balloons
    robot = scope.where("jsonb_exists(messages.additional_attributes, 'cevico_ia_agent')")
    messages = robot.count
    replies = messages.positive? ? robot.distinct.count(Arel.sql(REPLY_SQL)) : 0
    { robot_messages: messages, robot_replies: replies,
      per_reply: replies.positive? ? (messages.to_f / replies).round(1) : 0 }
  end
end
