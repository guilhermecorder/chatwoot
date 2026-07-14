class Api::V1::Accounts::Crm::SettingsController < Api::V1::Accounts::BaseController
  def show
    render json: settings_json(crm_settings)
  end

  def update
    # bloqueios de acesso por agente: só administradores podem alterar
    if params.key?(:agent_permissions) && !Current.account_user.administrator?
      return render json: { error: 'Apenas administradores podem alterar acessos.' }, status: :forbidden
    end

    crm_settings.update!(settings_params)
    render json: settings_json(crm_settings)
  end

  def test_n8n
    s = crm_settings
    unless s.n8n_configured?
      render json: { success: false, message: 'URL e API Key não configurados.' }
      return
    end

    response = HTTParty.get(
      "#{s.n8n_base_url_clean}/api/v1/workflows?limit=1",
      headers: { 'X-N8N-API-KEY' => s.n8n_api_key, 'Accept' => 'application/json' },
      timeout: 10
    )

    if response.success?
      render json: { success: true, message: 'Conexão bem-sucedida com o n8n! ✓' }
    else
      render json: { success: false, message: "n8n respondeu com status #{response.code}. Verifique a URL e a API Key." }
    end
  rescue StandardError => e
    render json: { success: false, message: "Erro de conexão: #{e.message}" }
  end

  def fetch_workflows
    s = crm_settings
    unless s.n8n_configured?
      render json: { success: false, message: 'Configure a URL e a API Key primeiro.' }
      return
    end

    response = HTTParty.get(
      "#{s.n8n_base_url_clean}/api/v1/workflows?limit=100&active=true",
      headers: { 'X-N8N-API-KEY' => s.n8n_api_key, 'Accept' => 'application/json' },
      timeout: 15
    )

    unless response.success?
      render json: { success: false, message: "Erro ao buscar workflows: status #{response.code}" }
      return
    end

    raw_workflows = response.parsed_response['data'] || []

    workflows = raw_workflows.map do |w|
      # Tenta extrair o caminho do webhook do nó Webhook, se existir
      webhook_path = extract_webhook_path(w)
      {
        id: w['id'].to_s,
        name: w['name'],
        active: w['active'],
        webhook_url: webhook_path ? "#{s.n8n_base_url_clean}/webhook/#{webhook_path}" : nil
      }
    end

    s.update!(n8n_workflows: workflows, n8n_workflows_fetched_at: Time.current)
    render json: { success: true, workflows: workflows, count: workflows.size }
  rescue StandardError => e
    render json: { success: false, message: "Erro: #{e.message}" }
  end

  # ── Meta Ads ────────────────────────────────────────────────────────────────

  def update_meta_ads
    cfg = crm_settings.meta_ads_config || {}
    cfg['pixel_id']          = params[:pixel_id]          if params[:pixel_id].present?
    cfg['access_token']      = params[:access_token]      if params[:access_token].present?
    cfg['ad_account_id']     = params[:ad_account_id]     if params.key?(:ad_account_id)
    cfg['test_event_code']   = params[:test_event_code]   # pode ser blank
    # etapas do CRM que contam como conversão no relatório de anúncios
    cfg['conversion_stage_ids'] = Array(params[:conversion_stage_ids]).map(&:to_i) if params.key?(:conversion_stage_ids)
    crm_settings.update!(meta_ads_config: cfg)
    render json: meta_ads_json(crm_settings)
  end

  def test_meta_ads
    result = MetaAdsConversionsService.new(
      account: Current.account,
      event_name: 'PageView'
    ).call
    render json: result
  end

  # ── Google Ads ───────────────────────────────────────────────────────────────

  def update_google_ads
    cfg = crm_settings.google_ads_config || {}
    cfg['measurement_id']  = params[:measurement_id]  if params[:measurement_id].present?
    cfg['api_secret']      = params[:api_secret]      if params[:api_secret].present?
    cfg['client_id']       = params[:client_id]       if params[:client_id].present?
    # Google Ads API (insights) — aguardando developer token (processo no Google)
    cfg['developer_token'] = params[:developer_token] if params[:developer_token].present?
    cfg['customer_id']     = params[:customer_id]     if params.key?(:customer_id)
    crm_settings.update!(google_ads_config: cfg)
    render json: google_ads_json(crm_settings)
  end

  # ── IA (análise de conversas — Anthropic) ──────────────────────────────────

  def update_ai
    unless Current.account_user.administrator?
      return render json: { error: 'Apenas administradores podem configurar a IA.' }, status: :forbidden
    end

    cfg = crm_settings.ai_config || {}
    cfg['api_key'] = params[:api_key] if params[:api_key].present?
    cfg['model']   = params[:model]   if params.key?(:model)
    cfg['effort']  = params[:effort]  if params.key?(:effort)
    # agentes internos: ligar/pausar, prompt, modelo e esforço por agente
    # (o Radar de Oportunidades ainda tem as vigias: coluna + painel do
    # atendente + janela de tempo, além dos minutos de espera).
    # MERGE por agente: dá para mandar só { opportunity: { enabled: true } }
    # (o interruptor da tela) sem apagar prompt/modelo/vigias já salvos.
    if params[:agents].present?
      agent_fields = [:enabled, :prompt, :model, :effort]
      permitted = params.require(:agents)
                        .permit(conversation: agent_fields,
                                form: agent_fields,
                                scheduler: agent_fields,
                                opportunity: agent_fields + [:wait_minutes, :lookback_hours,
                                                             { stage_ids: [],
                                                               watchers: %i[stage_id user_id lookback_hours] }])
                        .to_h
      existing = cfg['agents'] || {}
      cfg['agents'] = existing.merge(permitted) do |_key, old_agent, new_agent|
        (old_agent || {}).merge(new_agent || {})
      end
    end
    crm_settings.update!(ai_config: cfg)
    render json: ai_json(crm_settings)
  end

  # testa a conexão com a Claude de verdade (mini-chamada à API)
  def test_ai
    cfg = crm_settings.ai_config || {}
    return render json: { success: false, message: 'Configure a chave da API primeiro.' } if cfg['api_key'].blank?

    model = cfg['model'].presence || Crm::ConversationInsightService::DEFAULT_MODEL
    client = Anthropic::Client.new(api_key: cfg['api_key'], timeout: 30)
    client.messages.create(
      model: model,
      max_tokens: 16,
      messages: [{ role: 'user', content: 'Responda apenas: ok' }]
    )
    render json: { success: true, message: "Claude conectada! Modelo #{model} respondendo. ✓" }
  rescue Anthropic::Errors::AuthenticationError
    render json: { success: false, message: 'Chave da API inválida.' }
  rescue Anthropic::Errors::NotFoundError
    render json: { success: false, message: "Modelo #{cfg['model']} indisponível para esta chave." }
  rescue StandardError => e
    render json: { success: false, message: "Erro de conexão: #{e.message}" }
  end

  def test_google_ads
    result = GoogleAdsConversionsService.new(
      account: Current.account,
      event_name: 'test_event'
    ).call
    render json: result
  end

  # ── Google Sheets (planilha de cirurgias → Dashboard) ──────────────────────

  def update_sheets
    cfg = crm_settings.sheets_config || {}
    if params.key?(:sheet_url)
      cfg['sheet_url'] = params[:sheet_url].to_s.strip
      # link novo = cache antigo não vale mais
      cfg.delete('cache_rows')
      cfg.delete('cache_headers')
      cfg.delete('fetched_at')
    end
    crm_settings.update!(sheets_config: cfg)
    render json: sheets_json(crm_settings)
  end

  # ── Agenda: janelas de avaliação dos médicos ────────────────────────────────

  def update_agenda
    cfg = crm_settings.agenda_config || {}
    if params.key?(:windows)
      cfg['windows'] = Array(params[:windows]).map do |w|
        w.permit(:dow, :unit, :doctor, :turno, :start, :end, :block).to_h
      end
    end
    # horários fechados com o cadeado (almoço, ausência do médico...)
    if params.key?(:blocked)
      cfg['blocked'] = Array(params[:blocked]).map do |b|
        b.permit(:date, :time, :unit, :doctor).to_h
      end
    end
    # dias inteiros fechados (feriado, congresso, folga...)
    cfg['blocked_days'] = Array(params[:blocked_days]).map(&:to_s) if params.key?(:blocked_days)
    crm_settings.update!(agenda_config: cfg)
    render json: {
      agenda_windows: cfg['windows'] || [],
      agenda_blocked: cfg['blocked'] || [],
      agenda_blocked_days: cfg['blocked_days'] || []
    }
  end

  # Radar PONTUAL: varredura única (coluna/etiqueta/período/atendente),
  # roda uma vez e não fica ativa
  def radar_scan
    overrides = {
      stage_ids: Array(params[:stage_ids]).map(&:to_i).reject(&:zero?),
      label: params[:label].presence,
      since_hours: params[:since_hours].to_i,
      user_id: params[:user_id].presence&.to_i
    }
    Crm::OpportunityRadarJob.perform_later(Current.account.id, overrides)
    render json: { success: true, message: 'Radar pontual iniciado! Os avisos aparecem no Meu Painel em alguns minutos.' }
  end

  # ── Relatório de uso/custo dos agentes de IA ────────────────────────────────

  def ai_usage
    scope = Crm::AiUsage.where(account: Current.account)
    render json: {
      by_agent: usage_breakdown(scope, :agent_key),
      by_model: usage_breakdown(scope, :model),
      periods: {
        today: usage_totals(scope.where(created_at: Date.current.all_day)),
        last7: usage_totals(scope.where(created_at: 7.days.ago..Time.current)),
        last30: usage_totals(scope.where(created_at: 30.days.ago..Time.current)),
        all: usage_totals(scope)
      }
    }
  end

  # baixa a planilha agora e devolve uma prévia das primeiras linhas
  def test_sheets
    result = Crm::SheetsSurgeryService.new(account: Current.account).fetch!
    if result[:success]
      render json: result.merge(preview: result[:rows].first(5), rows: nil, count: result[:rows].size)
    else
      render json: result
    end
  end

  private

  def usage_breakdown(scope, column)
    last30 = scope.where(created_at: 30.days.ago..Time.current)
    last30.group(column)
          .pluck(column, Arel.sql('COUNT(*)'), Arel.sql('SUM(input_tokens)'), Arel.sql('SUM(output_tokens)'), Arel.sql('SUM(cost_usd)'))
          .map do |key, calls, input, output, cost|
            { key: key, calls: calls, input_tokens: input.to_i, output_tokens: output.to_i, cost_usd: cost.to_f.round(4) }
          end
          .sort_by { |r| -r[:cost_usd] }
  end

  def usage_totals(scope)
    calls, input, output, cost = scope.pick(Arel.sql('COUNT(*)'), Arel.sql('SUM(input_tokens)'), Arel.sql('SUM(output_tokens)'), Arel.sql('SUM(cost_usd)'))
    { calls: calls.to_i, input_tokens: input.to_i, output_tokens: output.to_i, cost_usd: cost.to_f.round(4) }
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_or_create_by!(account: Current.account)
  end

  def settings_params
    params.permit(:n8n_base_url, :n8n_api_key, column_presets: [:name, { stage_ids: [] }], agent_permissions: {})
  end

  def settings_json(s)
    {
      n8n_base_url: s.n8n_base_url,
      n8n_api_key_configured: s.n8n_api_key.present?,
      n8n_workflows: s.n8n_workflows || [],
      n8n_workflows_fetched_at: s.n8n_workflows_fetched_at,
      column_presets: s.column_presets || [],
      agent_permissions: s.agent_permissions || {},
      meta_ads: meta_ads_json(s),
      google_ads: google_ads_json(s),
      ai: ai_json(s),
      sheets: sheets_json(s),
      agenda_windows: (s.agenda_config || {})['windows'] || [],
      agenda_blocked: (s.agenda_config || {})['blocked'] || [],
      agenda_blocked_days: (s.agenda_config || {})['blocked_days'] || []
    }
  end

  def sheets_json(s)
    cfg = s.sheets_config || {}
    {
      sheet_url: cfg['sheet_url'],
      configured: cfg['sheet_url'].present?,
      fetched_at: cfg['fetched_at'],
      cached_count: (cfg['cache_rows'] || []).size
    }
  end

  def ai_json(s)
    cfg = s.ai_config || {}
    agents = cfg['agents'] || {}
    default_prompts = {
      'conversation' => Crm::ConversationInsightService::SYSTEM_PROMPT,
      'form' => Crm::FormInsightService::SYSTEM_PROMPT,
      'scheduler' => Crm::AppointmentExtractionService::SYSTEM_PROMPT,
      'opportunity' => Crm::OpportunityRadarService::SYSTEM_PROMPT
    }
    {
      api_key_set: cfg['api_key'].present?,
      model: cfg['model'].presence || Crm::AiAgentConfig::DEFAULT_MODEL,
      effort: cfg['effort'].presence || 'high',
      configured: cfg['api_key'].present?,
      opportunity_last_run_at: cfg.dig('opportunity_state', 'last_run_at'),
      opportunity_alerts_count: visible_alerts_count(cfg),
      opportunity_last_run: cfg.dig('opportunity_state', 'last_run'),
      agents: default_prompts.to_h do |key, default_prompt|
        recommended = Crm::AiAgentConfig::RECOMMENDED[key] || {}
        [key, {
          # opt-in: sem enabled true gravado, o agente está DESLIGADO
          enabled: agents.dig(key, 'enabled') == true,
          prompt: agents.dig(key, 'prompt').presence,
          model: agents.dig(key, 'model').presence,
          effort: agents.dig(key, 'effort').presence,
          recommended_model: recommended['model'],
          recommended_effort: recommended['effort'],
          stage_ids: Array(agents.dig(key, 'stage_ids')).map(&:to_i),
          wait_minutes: agents.dig(key, 'wait_minutes').presence&.to_i,
          lookback_hours: agents.dig(key, 'lookback_hours').presence&.to_i,
          watchers: Array(agents.dig(key, 'watchers')).map do |w|
            {
              stage_id: w['stage_id'].to_i,
              user_id: w['user_id'].presence&.to_i,
              lookback_hours: w['lookback_hours'].presence&.to_i || 24
            }
          end,
          default_prompt: default_prompt
        }]
      end
    }
  end

  # badge do Radar na sidebar: admin vê tudo; atendente só vê os avisos
  # do próprio painel + os sem direcionamento
  def visible_alerts_count(cfg)
    alerts = Array(cfg.dig('opportunity_state', 'alerts'))
    return alerts.size if Current.account_user.administrator?

    alerts.count { |a| a['user_id'].blank? || a['user_id'].to_i == Current.user.id }
  end

  def meta_ads_json(s)
    cfg = s.meta_ads_config || {}
    {
      pixel_id: cfg['pixel_id'],
      access_token_set: cfg['access_token'].present?,
      ad_account_id: cfg['ad_account_id'],
      test_event_code: cfg['test_event_code'],
      configured: cfg['pixel_id'].present? && cfg['access_token'].present?,
      insights_configured: cfg['ad_account_id'].present? && cfg['access_token'].present?
    }
  end

  def google_ads_json(s)
    cfg = s.google_ads_config || {}
    {
      measurement_id: cfg['measurement_id'],
      api_secret_set: cfg['api_secret'].present?,
      client_id: cfg['client_id'],
      developer_token_set: cfg['developer_token'].present?,
      customer_id: cfg['customer_id'],
      configured: cfg['measurement_id'].present? && cfg['api_secret'].present?,
      insights_configured: cfg['developer_token'].present? && cfg['customer_id'].present?
    }
  end

  # Extrai o path do webhook do primeiro nó Webhook ativo no workflow
  def extract_webhook_path(workflow)
    nodes = workflow.dig('nodes') || []
    webhook_node = nodes.find { |n| n['type'] == 'n8n-nodes-base.webhook' }
    webhook_node&.dig('parameters', 'path')
  rescue StandardError
    nil
  end
end
