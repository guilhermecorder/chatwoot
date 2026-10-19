# 🌅 A RODADA DIÁRIA do Agente de Campanhas (item 352) — de madrugada, depois
# da carga dos anúncios da Meta:
#   1. foto do Google por campanha (GA4 → cevico_campaign_days)
#   2. nossa média atualizada (7/30/90/180/360 dias)
#   3. sugestões antigas demais expiram
#   4. a janela é lida e as REGRAS geram recomendações (sem repetir as abertas)
#   5. o que foi aplicado há `learning_days` ganha o antes × depois
#   6. resumo do dia em agenda_config['campaign_agent_state'] (Meu Painel) e
#      uma tarefa para o administrador quando há recomendação nova esperando ok
# Idempotente por dia (force = true roda de novo, pelo botão "Ler agora").
class Cevico::CampaignAgent::Daily
  include Crm::AiAgentConfig

  AGENT_KEY = 'campaigns'.freeze
  STATE_KEY = 'campaign_agent_state'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o Agente de Campanhas de uma clínica: um gestor de tráfego experiente,
    direto e calmo. Recebe os números da janela recente comparados à nossa própria
    média e a lista de recomendações do dia. Escreva um RESUMO de no máximo 3 frases
    em português simples: como está a estrela-guia (1 frase), a recomendação mais
    importante e por quê (1 frase), e o que fazer hoje (1 frase, começando com um
    verbo). Sem jargão, sem enrolação, números arredondados.
  PROMPT

  def initialize(account:, today: TZ.today)
    @account = account
    @today = today
  end

  def self.state(account)
    (CrmSetting.find_by(account: account)&.agenda_config || {})[STATE_KEY] || {}
  end

  def call(force: false) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    return { skipped: 'desligado' } unless params['enabled']
    return { skipped: 'já rodou hoje' } if !force && self.class.state(@account)['last_run_date'] == @today.iso8601

    google = Cevico::CampaignAgent::GoogleSync.new(account: @account).call
    baselines = Cevico::CampaignAgent::Baselines.new(account: @account, goal: params['goal'], until_date: @today - 1).refresh!
    expired = expire_old
    window = read(@today - params['window_days'].to_i, @today - 1)
    enrich_budgets!(window)
    previous = read(@today - (2 * params['window_days'].to_i), @today - params['window_days'].to_i - 1)
    month = read(@today.beginning_of_month, [@today - 1, @today.beginning_of_month].max)
    proposals = Cevico::CampaignAgent::Rules.new(
      account: @account, params: params, baselines: baselines, window: window, previous: previous, month: month,
      touched: touched_ids, observing: Cevico::CampaignAgent::Learning.observing(@account), today: @today
    ).call
    created = persist(proposals)
    learned = Cevico::CampaignAgent::Learning.new(account: @account, params: params, today: @today).call
    open_count = Crm::CampaignAction.ads.where(account_id: @account.id, status: 'suggested').count
    summary = summary_for(window, baselines)
    brief = write_brief(summary, created) if params['brief_ai']
    task = open_task(created.size, open_count)
    write_state('last_run_date' => @today.iso8601, 'last_run_at' => Time.current.iso8601, 'google' => google.slice(:rows, :error, :configured),
                'new' => created.size, 'open' => open_count, 'learned' => learned, 'expired' => expired, 'summary' => summary,
                'top' => created.first(3).map { |a| a.slice(:title, :severity, :ref_name, :channel) }, 'brief' => brief, 'task_opened' => task,
                'series' => series)
    { ok: true, google: google, new: created.size, learned: learned, expired: expired, open: open_count }
  end

  private

  def params
    @params ||= Cevico::CampaignAgent::Params.for(@account)
  end

  def read(since, until_d)
    Cevico::CampaignAgent::Reader.new(account: @account, since_date: since, until_date: until_d, goal: params['goal']).call
  end

  # a verba de HOJE de cada conjunto da Meta (a sugestão de ±20 % precisa dela);
  # falha da Meta não derruba a rodada — a sugestão sai sem o número
  def enrich_budgets!(window) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    adsets = window[:campaigns].select { |c| c['channel'] == 'meta' }.flat_map { |c| Array(c['children']) }
    return if adsets.empty?

    graph = Crm::MetaGraph.new(account: @account)
    return unless graph.configured?

    found = graph.fetch_objects(adsets.pluck('id'), 'id,name,status,daily_budget,lifetime_budget')
    adsets.each do |adset|
      obj = found[adset['id']] || {}
      adset['daily_budget'] = obj['daily_budget'].to_f / 100 if obj['daily_budget'].present?
      adset['adset_status'] = obj['status'] if obj['status'].present?
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO campanhas] verba dos conjuntos: #{e.message}"
  end

  # itens com mudança aplicada há menos de respect_days (não mexer de novo)
  def touched_ids
    since = (@today - params['respect_days'].to_i).beginning_of_day
    Crm::CampaignAction.where(account_id: @account.id, status: 'applied', kind: Crm::CampaignAction::PLATFORM_KINDS)
                       .where('applied_at >= ?', since).pluck(:ref_id).to_set
  end

  def expire_old
    Crm::CampaignAction.ads.where(account_id: @account.id, status: 'suggested')
                       .where('suggested_on < ?', @today - Cevico::CampaignAgent::Rules::EXPIRE_DAYS)
                       .update_all(status: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # grava as propostas novas: sem repetir chave aberta, nem o que foi descartado
  # nos últimos 7 dias
  def persist(proposals) # rubocop:disable Metrics/AbcSize
    keys = proposals.pluck(:key)
    open_keys = Crm::CampaignAction.where(account_id: @account.id, key: keys, status: Crm::CampaignAction::OPEN).pluck(:key).to_set
    dismissed = Crm::CampaignAction.where(account_id: @account.id, key: keys, status: 'dismissed').where('decided_at >= ?',
                                                                                                         7.days.ago).pluck(:key).to_set
    proposals.reject { |a| open_keys.include?(a[:key]) || dismissed.include?(a[:key]) }.filter_map do |attrs|
      Crm::CampaignAction.create!(attrs.except(:weight).merge(account_id: @account.id, status: 'suggested', suggested_on: @today))
      attrs
    rescue StandardError => e
      Rails.logger.error "[CEVICO campanhas] não gravou a sugestão #{attrs[:key]}: #{e.message}"
      nil
    end
  end

  # o resumo que o Meu Painel mostra: janela × nossa média, por canal
  def summary_for(window, baselines)
    %w[all meta google].to_h do |ch|
      row = window[:totals][ch] || {}
      base = Cevico::CampaignAgent::Baselines.pick(baselines, ch, params['baseline_days'].to_i) || {}
      [ch, { 'spend' => row['spend'], 'leads' => row['leads'], 'booked' => row['booked'], 'surgeries' => row['surgeries'],
             'goal_cost' => row['goal_cost'], 'baseline_goal_cost' => base['goal_cost'], 'cpl' => row.dig('rates', 'cpl'),
             'baseline_cpl' => base.dig('rates', 'cpl'), 'window_days' => params['window_days'], 'baseline_days' => params['baseline_days'] }]
    end
  end

  # 14 dias de gasto e leads dos anúncios (a linha do bloco no Meu Painel)
  SERIES_DAYS = 14
  def series # rubocop:disable Metrics/AbcSize
    from = @today - SERIES_DAYS
    to = @today - 1
    meta = Crm::AdInsight.where(account_id: @account.id).between(from, to).group(:date).sum(Arel.sql("COALESCE((metrics->>'spend')::numeric, 0)"))
    google = Crm::CampaignDay.google.where(account_id: @account.id).between(from, to).group(:date).sum(:spend)
    leads = ad_leads_by_day(from, to)
    dates = (from..to).to_a
    { 'labels' => dates.map { |d| d.strftime('%d/%m') }, 'spend' => dates.map { |d| (meta[d].to_f + google[d].to_f).round(2) },
      'leads' => dates.map { |d| leads[d].to_i } }
  end

  def ad_leads_by_day(from, to)
    ctwa = @account.contacts.where("additional_attributes -> 'meta_ads' ->> 'source_id' IS NOT NULL")
                   .where("(additional_attributes -> 'meta_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?",
                          from.beginning_of_day, to.end_of_day)
                   .pluck(Arel.sql("additional_attributes -> 'meta_ads' ->> 'captured_at'"))
    pages = @account.contacts.where("additional_attributes -> 'page_ads' ->> 'source' IN (?)", %w[google_ads meta_ads])
                    .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?",
                           from.beginning_of_day, to.end_of_day)
                    .pluck(Arel.sql("additional_attributes -> 'page_ads' ->> 'captured_at'"))
    (ctwa + pages).each_with_object(Hash.new(0)) { |at, h| h[Time.zone.parse(at.to_s)&.to_date] += 1 }
  end

  def open_task(new_count, open_count)
    return false if new_count.zero?

    title = "🎯 Campanhas: #{open_count} recomendação(ões) esperando seu ok — #{@today.strftime('%d/%m')}"
    return false if @account.tasks.exists?(title: title)

    admin = @account.administrators.first
    return false if admin.nil?

    @account.tasks.create!(
      title: title, task_type: 'gestao', priority: :high, status: :todo, due_at: TZ.now.end_of_day, creator: admin, assignee: admin,
      description: "O Agente de Campanhas leu os últimos #{params['window_days']} dias contra a nossa média e deixou #{new_count} " \
                   'recomendação(ões) nova(s) em Análises → Campanhas. Nada muda sem o seu ok.'
    )
    true
  rescue StandardError => e
    Rails.logger.error "[CEVICO campanhas] tarefa falhou conta=#{@account.id}: #{e.message}"
    false
  end

  def write_brief(summary, created) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if api_key.blank?

    all = summary['all'] || {}
    lines = ["Estrela-guia: #{Cevico::CampaignAgent::Params.goal_label(params)} = #{all['goal_cost'] || 'sem resultado'} " \
             "(nossa média de #{all['baseline_days']} dias: #{all['baseline_goal_cost'] || '—'}); " \
             "gasto na janela de #{all['window_days']} dias: #{all['spend']}; " \
             "leads #{all['leads']}, agendamentos #{all['booked']}, cirurgias #{all['surgeries']}."]
    lines << "Recomendações novas: #{created.any? ? created.first(5).map { |a| "#{a[:title]} (#{a[:ref_name]})" }.join('; ') : 'nenhuma'}."
    message = client.messages.create(model: model, max_tokens: 400, system_: cached_system,
                                     messages: [{ role: 'user', content: "#{lines.join("\n")}\nEscreva o resumo de hoje." }])
    record_usage(message)
    message.content.find { |b| b.type == :text }&.text.to_s.strip.presence
  rescue StandardError => e
    Rails.logger.error "[CEVICO campanhas] resumo da IA falhou conta=#{@account.id}: #{e.message}"
    nil
  end

  def write_state(patch)
    settings = CrmSetting.find_or_create_by!(account: @account)
    Cevico::SettingMerge.merge_key!(settings, :agenda_config, STATE_KEY) { |h| (h || {}).merge(patch.deep_stringify_keys) }
  end
end
