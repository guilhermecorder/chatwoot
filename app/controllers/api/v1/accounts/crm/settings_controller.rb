class Api::V1::Accounts::Crm::SettingsController < Api::V1::Accounts::BaseController
  def show
    render json: settings_json(crm_settings)
  end

  def update
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
  rescue => e
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
        id:           w['id'].to_s,
        name:         w['name'],
        active:       w['active'],
        webhook_url:  webhook_path ? "#{s.n8n_base_url_clean}/webhook/#{webhook_path}" : nil,
      }
    end

    s.update!(n8n_workflows: workflows, n8n_workflows_fetched_at: Time.current)
    render json: { success: true, workflows: workflows, count: workflows.size }
  rescue => e
    render json: { success: false, message: "Erro: #{e.message}" }
  end

  # ── Meta Ads ────────────────────────────────────────────────────────────────

  def update_meta_ads
    cfg = crm_settings.meta_ads_config || {}
    cfg['pixel_id']          = params[:pixel_id]          if params[:pixel_id].present?
    cfg['access_token']      = params[:access_token]      if params[:access_token].present?
    cfg['test_event_code']   = params[:test_event_code]   # pode ser blank
    crm_settings.update!(meta_ads_config: cfg)
    render json: meta_ads_json(crm_settings)
  end

  def test_meta_ads
    result = MetaAdsConversionsService.new(
      account:    Current.account,
      event_name: 'PageView',
    ).call
    render json: result
  end

  # ── Google Ads ───────────────────────────────────────────────────────────────

  def update_google_ads
    cfg = crm_settings.google_ads_config || {}
    cfg['measurement_id'] = params[:measurement_id] if params[:measurement_id].present?
    cfg['api_secret']     = params[:api_secret]     if params[:api_secret].present?
    cfg['client_id']      = params[:client_id]      if params[:client_id].present?
    crm_settings.update!(google_ads_config: cfg)
    render json: google_ads_json(crm_settings)
  end

  def test_google_ads
    result = GoogleAdsConversionsService.new(
      account:     Current.account,
      event_name:  'test_event',
    ).call
    render json: result
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_or_create_by!(account: Current.account)
  end

  def settings_params
    params.permit(:n8n_base_url, :n8n_api_key)
  end

  def settings_json(s)
    {
      n8n_base_url:              s.n8n_base_url,
      n8n_api_key_configured:    s.n8n_api_key.present?,
      n8n_workflows:             s.n8n_workflows || [],
      n8n_workflows_fetched_at:  s.n8n_workflows_fetched_at,
      meta_ads:                  meta_ads_json(s),
      google_ads:                google_ads_json(s),
    }
  end

  def meta_ads_json(s)
    cfg = s.meta_ads_config || {}
    {
      pixel_id:              cfg['pixel_id'],
      access_token_set:      cfg['access_token'].present?,
      test_event_code:       cfg['test_event_code'],
      configured:            cfg['pixel_id'].present? && cfg['access_token'].present?,
    }
  end

  def google_ads_json(s)
    cfg = s.google_ads_config || {}
    {
      measurement_id:    cfg['measurement_id'],
      api_secret_set:    cfg['api_secret'].present?,
      client_id:         cfg['client_id'],
      configured:        cfg['measurement_id'].present? && cfg['api_secret'].present?,
    }
  end

  # Extrai o path do webhook do primeiro nó Webhook ativo no workflow
  def extract_webhook_path(workflow)
    nodes = workflow.dig('nodes') || []
    webhook_node = nodes.find { |n| n['type'] == 'n8n-nodes-base.webhook' }
    webhook_node&.dig('parameters', 'path')
  rescue
    nil
  end
end
