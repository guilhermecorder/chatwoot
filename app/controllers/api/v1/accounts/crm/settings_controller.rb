class Api::V1::Accounts::Crm::SettingsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  # integração/config sensível = admin (ou área concedida). Leitura (show) e os
  # atalhos usados pela tela do atendente ficam livres.
  ADMIN_SETTINGS_ACTIONS = %i[
    update test_n8n fetch_workflows update_meta_ads test_meta_ads update_ai test_ai test_gemini
    update_google_ads test_google_ads update_sheets test_sheets update_agenda agenda_backfill
    update_oftalmofacil
    update_public_domain check_public_domain sync_scheduler_stages sync_agent_stages
    sales_insights radar_scan run_mentor copywriter_content update_price_table
    update_inbox_investments update_segment
    harvest_status harvest_preview harvest_approve harvest_pause harvest_resume
    harvest_skip_lead harvest_send_now run_manager run_auditor auditor_summary
    run_creative creative_state creative_review
  ].freeze
  before_action -> { require_capability(:settings) }, only: ADMIN_SETTINGS_ACTIONS
  # conceder acesso NUNCA é delegável (evita escalada de privilégio): só admin
  before_action :require_administrator!, only: [:update_agent_grants]

  def show
    render json: settings_json(crm_settings)
  end

  # POST update_agent_grants — admin configura os acessos de UM atendente.
  # body: { user_id:, grants: ["reports",...], menu: ["crm","tasks",...] }
  # - grants: áreas administrativas CONCEDIDAS (allow-list, vale na API)
  # - menu: itens do dia a dia visíveis no menu dela(e) (só visual)
  # Mescla por usuário no servidor — nunca sobrescreve os demais.
  def update_agent_grants
    user_id = params[:user_id].to_s
    return render json: { error: 'Informe o atendente.' }, status: :unprocessable_entity if user_id.blank?

    perms = crm_settings.agent_permissions || {}

    if params.key?(:grants)
      valid = Array(params[:grants]).map(&:to_s) & Crm::AccessControl::CAPABILITIES
      grants = perms['grants'] || {}
      valid.empty? ? grants.delete(user_id) : grants[user_id] = valid
      perms['grants'] = grants
    end

    if params.key?(:menu)
      valid_menu = Array(params[:menu]).map(&:to_s) & Crm::AccessControl::DAY_MENU_ITEMS
      menu = perms['menu'] || {}
      # padrão (sem registro) = DAY_MENU_DEFAULT; gravar lista própria só
      # quando for diferente do padrão mantém o banco enxuto
      if valid_menu.sort == Crm::AccessControl::DAY_MENU_DEFAULT.sort
        menu.delete(user_id)
      else
        menu[user_id] = valid_menu
      end
      perms['menu'] = menu
    end

    # quais RELATÓRIOS o atendente vê (item 62): lista vazia/ausente = todos
    if params.key?(:report_keys)
      keys = Array(params[:report_keys]).map(&:to_s).first(40)
      report_keys = perms['report_keys'] || {}
      keys.empty? ? report_keys.delete(user_id) : report_keys[user_id] = keys
      perms['report_keys'] = report_keys
    end

    crm_settings.update!(agent_permissions: perms)
    render json: { grants: perms['grants'] || {}, menu: perms['menu'] || {},
                   report_keys: perms['report_keys'] || {} }
  end

  def update
    # bloqueios de acesso por agente: só administradores podem alterar
    if params.key?(:agent_permissions) && !Current.account_user.administrator?
      return render json: { error: 'Apenas administradores podem alterar acessos.' }, status: :forbidden
    end

    crm_settings.update!(settings_params)
    render json: settings_json(crm_settings)
  end

  # POST update_price_table — Tabela de preços oficial (Configurações →
  # Tabela de preços). Alimenta o Espaço do Paciente e os prompts da IA.
  def update_price_table
    items = Array(params[:items]).first(60).filter_map do |raw|
      name = raw[:name].to_s.strip[0, 80]
      next if name.blank?

      {
        'group' => raw[:group].to_s.strip[0, 80].presence || 'Outros',
        'name' => name,
        'price' => raw[:price].to_f.round(2),
        'promo_price' => raw[:promo_price].present? ? raw[:promo_price].to_f.round(2) : nil
      }.compact
    end

    cfg = crm_settings.agenda_config || {}
    cfg['price_table'] = { 'items' => items, 'updated_at' => Time.current.iso8601 }
    crm_settings.update!(agenda_config: cfg)
    render json: { price_table: cfg['price_table'] }
  end

  # POST update_inbox_investments — investimento em anúncios por caixa de
  # entrada (Dashboard CRM → Resultados por caixa). Dois modos por caixa:
  # manual (R$/mês, proporcional aos dias do período) ou meta_auto (gasto
  # REAL do período puxado da conta de anúncios do Meta já integrada).
  # body: { investments: { "12" => { mode: 'manual', monthly: 1500 },
  #                        "15" => { mode: 'meta_auto' } } }
  def update_inbox_investments
    investments = sanitized_investments
    cfg = crm_settings.agenda_config || {}
    cfg['inbox_investments'] = investments
    apply_capture_inboxes(cfg)
    crm_settings.update!(agenda_config: cfg)
    render json: { inbox_investments: investments, capture_inbox_ids: cfg['capture_inbox_ids'] }
  end

  def sanitized_investments
    valid_ids = Current.account.inboxes.pluck(:id).map(&:to_s)
    investments = {}
    (params[:investments] || {}).each do |inbox_id, raw|
      next unless valid_ids.include?(inbox_id.to_s)

      entry = sanitize_investment(raw)
      investments[inbox_id.to_s] = entry if entry
    end
    investments
  end

  # portas de entrada (caixas de captação): a régua da atribuição por
  # caixa — Dashboard, Meu Painel e automações usam a mesma lista
  def apply_capture_inboxes(cfg)
    return unless params.key?(:capture_inbox_ids)

    cfg['capture_inbox_ids'] = Array(params[:capture_inbox_ids]).map(&:to_i) & Current.account.inboxes.pluck(:id)
  end

  # aceita o formato novo {mode, monthly} e o legado (número puro = manual)
  def sanitize_investment(raw)
    if raw.respond_to?(:dig) # hash / ActionController::Parameters
      mode = %w[meta_auto google_auto].include?(raw[:mode].to_s) ? raw[:mode].to_s : 'manual'
      return { 'mode' => mode } unless mode == 'manual'

      monthly = raw[:monthly].to_f.round(2)
      monthly.positive? ? { 'mode' => 'manual', 'monthly' => monthly } : nil
    else
      value = raw.to_f.round(2)
      value.positive? ? { 'mode' => 'manual', 'monthly' => value } : nil
    end
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

  # ── 🌾 Colheitadeira da Base (item 128) ──────────────────────────────────────
  # A tela opera a colheita por aqui; o cron faz o mesmo caminho sozinho.

  def harvest_status
    render json: Crm::HarvestService.new(account: Current.account).results
  end

  def harvest_preview
    Crm::HarvestJob.perform_later(Current.account.id, 'preview')
    render json: { enqueued: true }
  end

  def harvest_approve
    render json: Crm::HarvestService.new(account: Current.account).approve!(Current.user)
  end

  def harvest_pause
    render json: Crm::HarvestService.new(account: Current.account).pause!
  end

  def harvest_resume
    render json: Crm::HarvestService.new(account: Current.account).resume!
  end

  def harvest_skip_lead
    render json: Crm::HarvestService.new(account: Current.account).skip_lead!(params[:contact_id])
  end

  def harvest_send_now
    Crm::HarvestJob.perform_later(Current.account.id, 'batch')
    render json: { enqueued: true }
  end

  # ── 📊 Gestor Autônomo (item 128): rodar agora ───────────────────────────────
  def run_manager
    Crm::AutoManagerJob.perform_later(Current.account.id)
    render json: { enqueued: true }
  end

  # ── 🎓 Auditor de Conversas (item 130) ───────────────────────────────────────
  def run_auditor
    Crm::ConversationAuditorJob.perform_later(Current.account.id)
    render json: { enqueued: true }
  end

  # ranking dos atendentes + falhas mais comuns do time (últimos N dias)
  def auditor_summary
    days = params[:days].to_i.clamp(1, 30)
    days = 7 if days.zero?
    render json: Crm::ConversationAuditorService.new(account: Current.account).summary(days: days)
  end

  # ── 🎨 Criativo Perpétuo (item 131) ──────────────────────────────────────────
  def run_creative
    Crm::CreativeJob.perform_later(Current.account.id)
    render json: { enqueued: true }
  end

  def creative_state
    render json: Crm::CreativeService.new(account: Current.account).state
  end

  # body: { winner_index:, variation_index:, status: 'approved'|'rejected' }
  def creative_review
    result = Crm::CreativeService.new(account: Current.account)
                                 .review!(params[:winner_index], params[:variation_index], params[:status].to_s, Current.user)
    render json: result, status: result[:error] ? :unprocessable_entity : :ok
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
    apply_google_cost_config(cfg)
    crm_settings.update!(google_ads_config: cfg)
    render json: google_ads_json(crm_settings)
  end

  # Custo automático via API de dados do GA4 (sem developer token):
  # property id + JSON da conta de serviço (write-only, nunca volta)
  def apply_google_cost_config(cfg)
    cfg['ga4_property_id'] = params[:ga4_property_id].to_s.gsub(/\D/, '') if params.key?(:ga4_property_id)
    cfg['service_account_json'] = params[:service_account_json] if params[:service_account_json].present?
  end

  # ── IA (análise de conversas — Anthropic) ──────────────────────────────────

  def update_ai
    unless Current.account_user.administrator?
      return render json: { error: 'Apenas administradores podem configurar a IA.' }, status: :forbidden
    end

    cfg = crm_settings.ai_config || {}
    cfg['api_key'] = params[:api_key] if params[:api_key].present?
    # Gemini (Google): reservada para geração de IMAGENS das Páginas
    cfg['gemini_api_key'] = params[:gemini_api_key] if params[:gemini_api_key].present?
    cfg['model']   = params[:model]   if params.key?(:model)
    cfg['effort']  = params[:effort]  if params.key?(:effort)
    # sistema coringa: descrição do negócio injetada em {{CONTEXTO_DO_NEGOCIO}}
    # nos prompts dos robôs (sem ela, vale o contexto do segmento)
    cfg['business_context'] = params[:business_context].to_s[0, 8000] if params.key?(:business_context)
    # agentes internos: ligar/pausar, prompt, modelo e esforço por agente
    # (o Radar de Oportunidades ainda tem as vigias: coluna + painel do
    # atendente + janela de tempo, além dos minutos de espera).
    # MERGE por agente: dá para mandar só { opportunity: { enabled: true } }
    # (o interruptor da tela) sem apagar prompt/modelo/vigias já salvos.
    # "draft" = RASCUNHO (botão Salvar): fica guardado mas os services só
    # leem os campos publicados — Publicar copia o rascunho pros campos
    # de verdade e manda draft: {} para limpar.
    if params[:agents].present?
      agent_fields = [:enabled, :prompt, :model, :effort, { draft: {} }]
      permitted = params.require(:agents)
                        .permit(conversation: agent_fields,
                                form: agent_fields,
                                scheduler: agent_fields,
                                closing: agent_fields,
                                nps: agent_fields,
                                sales: agent_fields,
                                copywriter: agent_fields + [:references],
                                # Construtor PRO (23/07): referências de estilo + teto de resposta
                                pagebuilder: agent_fields + [:references, :max_tokens],
                                instagram: agent_fields + [{ inbox_ids: [] }],
                                mentor: agent_fields,
                                comments: agent_fields + [:page_access_token, :fb_page_id, :ig_user_id],
                                opportunity: agent_fields + [:wait_minutes, :lookback_hours, :response_goal_minutes,
                                                             { stage_ids: [],
                                                               watchers: %i[stage_id user_id lookback_hours] }],
                                # 🌾 Colheitadeira (item 128): tamanho/frio/teto/dia + caixa e modelo
                                harvest: agent_fields + [:monthly_size, :cold_days, :daily_cap, :day_of_month,
                                                         :inbox_id, :require_approval, :message_preview, :mode,
                                                         { stage_ids: [], template_params: {} }],
                                # 📊 Gestor Autônomo (item 128): limiar de desvio
                                manager: agent_fields + [:drop_pct],
                                # 🎓 Auditor de Conversas (item 130): teto diário
                                auditor: agent_fields + [:daily_cap],
                                # 🎨 Criativo Perpétuo (item 131)
                                creative: agent_fields + [:winners_count, :variations_count])
                        .to_h
      existing = cfg['agents'] || {}
      cfg['agents'] = existing.merge(permitted) do |_key, old_agent, new_agent|
        merged = (old_agent || {}).merge(new_agent || {})
        # draft vazio = limpar o rascunho (acontece no Publicar)
        merged.delete('draft') if merged['draft'].blank?
        merged
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

  # testa a chave do Gemini (Google) de verdade — lista os modelos da conta
  def test_gemini
    cfg = crm_settings.ai_config || {}
    key = cfg['gemini_api_key']
    return render json: { success: false, message: 'Configure a chave do Gemini primeiro.' } if key.blank?

    response = HTTParty.get(
      'https://generativelanguage.googleapis.com/v1beta/models',
      query: { key: key, pageSize: 1 },
      timeout: 20
    )
    if response.code == 200
      render json: { success: true, message: 'Gemini conectado! Chave válida. ✓' }
    elsif [401, 403].include?(response.code)
      render json: { success: false, message: 'Chave do Gemini inválida ou sem permissão.' }
    else
      render json: { success: false, message: "Gemini respondeu com erro #{response.code}." }
    end
  rescue StandardError => e
    render json: { success: false, message: "Erro de conexão: #{e.message}" }
  end

  # Estúdio do Copywriter: gera conteúdo multi-formato (carrossel, roteiro
  # de reels, post, anúncio) — o resultado é copiado pela equipe, nada é
  # publicado sozinho
  def copywriter_content
    unless Current.account_user.administrator?
      return render json: { error: 'Apenas administradores usam o Estúdio por enquanto.' }, status: :forbidden
    end

    form = params[:form_id].present? ? Current.account.crm_forms.find_by(id: params[:form_id]) : nil
    result = Crm::CopywriterService.new(
      account: Current.account,
      briefing: params[:briefing].to_s,
      modality: params[:modality].to_s,
      structure: params[:structure].presence || 'auto',
      form: form
    ).call
    return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error]

    render json: result
  end

  def test_google_ads
    result = GoogleAdsConversionsService.new(
      account: Current.account,
      event_name: 'test_event'
    ).call
    # se o custo automático estiver configurado, testa também a leitura do
    # gasto dos últimos 7 dias pela API de dados do GA4
    cost_service = Crm::GoogleAdCostService.new(account: Current.account, since_date: 7.days.ago.to_date)
    result[:cost_test] = cost_service.call if cost_service.configured?
    render json: result
  end

  # ── Google Sheets (planilha de cirurgias → Dashboard) ──────────────────────

  # ── OftalmoFácil: conexão nativa (endereço + chave da API) ─────────────────
  # A chave nunca volta na resposta (só o selo key_set); o fluxo de dados
  # liga em cima desta conexão quando a documentação da API for plugada.
  def update_oftalmofacil # rubocop:disable Metrics/AbcSize
    cfg = crm_settings.agenda_config || {}
    of = cfg['oftalmofacil'] || {}
    of['base_url'] = params[:base_url].to_s.strip if params.key?(:base_url)
    of['api_key'] = params[:api_key].to_s.strip if params[:api_key].to_s.strip.present?
    of['updated_at'] = Time.current.iso8601
    cfg['oftalmofacil'] = of
    crm_settings.update!(agenda_config: cfg)
    render json: { oftalmofacil: oftalmofacil_json(crm_settings) }
  end

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
    # médicos com a agenda FECHADA (item 76): janelas deles somem de toda
    # parte (agenda, ocupação, saúde) até reabrir
    cfg['closed_doctors'] = Array(params[:closed_doctors]).map(&:to_s) if params.key?(:closed_doctors)
    # locais de cirurgia (clínicas parceiras — IOP etc.) do trilho de cirurgias
    if params.key?(:surgery_locations)
      cfg['surgery_locations'] = Array(params[:surgery_locations]).map do |l|
        l.permit(:key, :label).to_h
      end.select { |l| l['label'].present? }
    end
    # janelas da SALA CIRÚRGICA (clínica parceira + dia + horário + bloco)
    if params.key?(:surgery_windows)
      cfg['surgery_windows'] = Array(params[:surgery_windows]).map do |w|
        w.permit(:dow, :location, :start, :end, :block).to_h
      end
    end
    # tema visual dos ambientes (Santorini, Flor del Mar...) — escolha do admin
    cfg['theme'] = params[:theme].to_s if params.key?(:theme)
    # qual versão do Meu Painel cada agente vê ({user_id => panel_key})
    if params.key?(:panel_assignments)
      cfg['panel_assignments'] = params.require(:panel_assignments)
                                       .permit!.to_h.transform_values(&:to_s)
    end
    # qual LOGIN o Atendimento IA usa pra responder (Configurações → Painéis)
    # — alimenta o bloco "Meu desempenho" (a pessoa se compara com o robô)
    if params.key?(:ai_user_id)
      uid = params[:ai_user_id].presence&.to_i
      cfg['ai_user_id'] = uid && Current.account.users.exists?(id: uid) ? uid : nil
    end
    # LAYOUT da fileira de indicadores por painel (item 142): ordem dos cards
    # (arrasto magnético) + cards ocultos + COR escolhida por card (item 143)
    # — {painel => {order: [], hidden: [], colors: {id => grad}}}
    if params.key?(:kpi_layout)
      raw = params.require(:kpi_layout).permit!.to_h
      cfg['kpi_layout'] = raw.slice('agendamento', 'conducao', 'cirurgia', 'medico', 'gestor').transform_values do |v|
        h = v.to_h
        {
          'order' => Array(h['order']).map { |x| x.to_s[0, 40] }.reject(&:blank?).first(40),
          'hidden' => Array(h['hidden']).map { |x| x.to_s[0, 40] }.reject(&:blank?).first(40),
          'colors' => sanitize_kpi_colors(h['colors'])
        }
      end
    end
    # ORDEM DOS BLOCOS do Meu Painel (item 143): arrasto magnético em TODOS
    # os blocos — duas áreas (acima e abaixo do seletor de painel), pode
    # cruzar entre elas — {painel => {top: [ids], main: [ids]}}
    if params.key?(:block_layout)
      raw = params.require(:block_layout).permit!.to_h
      cfg['block_layout'] = raw.slice('agendamento', 'conducao', 'cirurgia', 'medico', 'gestor').transform_values do |v|
        h = v.to_h
        {
          'top' => Array(h['top']).map { |x| x.to_s[0, 40] }.reject(&:blank?).first(20),
          'main' => Array(h['main']).map { |x| x.to_s[0, 40] }.reject(&:blank?).first(20)
        }
      end
    end
    # CARDS DE INDICADOR criados pelo admin no "+" do Meu Painel (item 141):
    # indicador pronto OU fórmula sobre o cesto de indicadores, com cor,
    # formato e painel de destino. Sanitizado campo a campo.
    if params.key?(:custom_kpis)
      cfg['custom_kpis'] = Array(params[:custom_kpis]).first(40).filter_map do |raw|
        k = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
        expr = k['expr'].to_s.strip[0, 200]
        next if expr.blank? || expr !~ %r{\A[a-z0-9_+\-*/().\s]+\z}i
        next if k['label'].to_s.strip.blank?

        {
          'id' => k['id'].to_s[/\A[a-z0-9_-]{1,40}\z/i] || SecureRandom.hex(4),
          'label' => k['label'].to_s.strip[0, 60],
          'expr' => expr,
          'format' => %w[number percent currency].include?(k['format'].to_s) ? k['format'].to_s : 'number',
          'color' => k['color'].to_s[0, 120],
          'icon' => k['icon'].to_s[/\Ai-lucide-[a-z0-9-]{1,40}\z/] || 'i-lucide-sparkles',
          'panel' => %w[all agendamento conducao cirurgia medico gestor].include?(k['panel'].to_s) ? k['panel'].to_s : 'all',
          'note' => k['note'].to_s.strip[0, 200]
        }
      end
    end
    # TEMA por painel do Meu Painel ({painel => tema}) — opção do admin
    # (item 140): cada ambiente com sua família de cores
    if params.key?(:panel_themes)
      raw = params.require(:panel_themes).permit!.to_h
      cfg['panel_themes'] = raw.slice('agendamento', 'conducao', 'cirurgia', 'medico', 'gestor')
                               .transform_values { |v| v.to_s[/\A[a-z_]{1,30}\z/] }.compact
    end
    # MÉTRICAS do "Meu desempenho" por pessoa ({user_id => [chaves]}) —
    # o admin propõe o painel individual de cada função (item 139)
    if params.key?(:performance_metrics)
      raw = params.require(:performance_metrics).permit!.to_h
      valid_ids = Current.account.users.pluck(:id).map(&:to_s)
      cfg['performance_metrics'] = raw.slice(*valid_ids).transform_values do |keys|
        Array(keys).map(&:to_s) & Crm::AgentPerformance::METRIC_KEYS
      end.reject { |_, v| v.empty? }
    end
    # RESPONSÁVEL por painel ({painel => user_id}) — o nome aparece na
    # pílula do Meu Painel ("Cirurgias · Elizangela"). Configurações → Painéis.
    if params.key?(:panel_owners)
      raw = params.require(:panel_owners).permit!.to_h
      cfg['panel_owners'] = raw.slice('agendamento', 'conducao', 'cirurgia')
                               .transform_values { |v| v.presence&.to_i }.compact
    end
    # METAS por painel ({painel => {indicador => meta mensal}}): os cards
    # do Meu Painel mudam de cor conforme o desempenho contra a meta
    if params.key?(:panel_goals)
      cfg['panel_goals'] = params.require(:panel_goals).permit!.to_h
                                 .transform_values { |g| g.to_h.transform_values(&:to_f) }
    end
    # conferência do dia: RESPONSÁVEIS (consultas/cirurgias) + prazo — se
    # passar do horário sem conferir, nasce a tarefa "Concluir a conferência"
    if params.key?(:attendance_owners)
      cfg['attendance_owners'] = params.require(:attendance_owners)
                                       .permit(:consulta_user_id, :cirurgia_user_id, :deadline)
                                       .to_h
                                       .transform_values(&:presence)
    end
    # conferência do dia → CRM: para onde vai o card em cada caso
    if params.key?(:attendance_stages)
      cfg['attendance_stages'] = params.require(:attendance_stages)
                                       .permit(:attended_stage_id, :missed_stage_id, :indicated_stage_id,
                                               :surgery_done_stage_id, :surgery_missed_stage_id)
                                       .to_h.transform_values { |v| v.presence&.to_i }
    end
    # Central do Paciente: quem são os MÉDICOS no sistema (editam anotações
    # clínicas) e se a equipe pode visualizar as anotações (LGPD: fechado
    # por padrão)
    if params.key?(:clinical_access)
      access = params.require(:clinical_access).permit(:team_view, doctor_user_ids: []).to_h
      cfg['clinical_access'] = {
        'doctor_user_ids' => Array(access['doctor_user_ids']).map(&:to_i),
        'team_view' => ActiveModel::Type::Boolean.new.cast(access['team_view']) == true
      }
    end
    # PAINÉIS DO CONSTRUTOR salvos por CONTA (06/08): cada um vira uma pílula
    # no Meu Painel e pode ser atribuído ao time — só admin mexe
    if params.key?(:custom_panels) && Current.account_user.administrator?
      cfg['custom_panels'] = Array(params[:custom_panels]).first(24).map do |p|
        panel = p.permit(:id, :name, :palette, widgets: [:key, :size]).to_h
        {
          'id' => panel['id'].to_s.downcase.gsub(/[^a-z0-9\-]/, '')[0, 40],
          'name' => panel['name'].to_s[0, 60],
          'palette' => panel['palette'].to_s[0, 20],
          'widgets' => Array(panel['widgets']).first(40).map do |w|
            { 'key' => w['key'].to_s[0, 40], 'size' => %w[sm md lg].include?(w['size']) ? w['size'] : 'sm' }
          end
        }
      end.select { |p| p['id'].present? && p['name'].present? && p['widgets'].any? }
    end
    # painel PRINCIPAL da conta: o padrão do Meu Painel para quem não tem
    # painel atribuído ('' volta ao padrão de fábrica) — só admin
    if params.key?(:main_panel) && Current.account_user.administrator?
      cfg['main_panel'] = params[:main_panel].to_s[0, 60].presence
    end
    # 📌 PRO MAX (item 129): histórico de AÇÕES DA EMPRESA (LP nova no ar,
    # campanha X, deploy…) — marcadores na linha do tempo do estúdio, para
    # entender o que cada ação gerou. Lista inteira substituída a cada save.
    if params.key?(:company_actions) && Current.account_user.administrator?
      cfg['company_actions'] = Array(params[:company_actions]).first(200).filter_map do |raw|
        a = raw.permit(:id, :date, :title, :category, :notes).to_h
        date = begin
          Date.iso8601(a['date'].to_s).iso8601
        rescue StandardError
          nil
        end
        title = a['title'].to_s.strip[0, 80]
        next if date.blank? || title.blank?

        {
          'id' => a['id'].presence || SecureRandom.hex(4),
          'date' => date,
          'title' => title,
          'category' => %w[campanha pagina sistema whatsapp outro].include?(a['category']) ? a['category'] : 'outro',
          'notes' => a['notes'].to_s[0, 240].presence
        }.compact
      end.sort_by { |a| a['date'] }
    end
    crm_settings.update!(agenda_config: cfg)
    render json: {
      agenda_windows: cfg['windows'] || [],
      agenda_blocked: cfg['blocked'] || [],
      agenda_blocked_days: cfg['blocked_days'] || [],
      agenda_closed_doctors: cfg['closed_doctors'] || [],
      attendance_stages: cfg['attendance_stages'] || {},
      attendance_owners: cfg['attendance_owners'] || {},
      surgery_locations: cfg['surgery_locations'] || [],
      surgery_windows: cfg['surgery_windows'] || [],
      agenda_theme: cfg['theme'],
      panel_assignments: cfg['panel_assignments'] || {},
      panel_owners: panel_owners_json(cfg),
      ai_user_id: cfg['ai_user_id'],
      panel_themes: cfg['panel_themes'] || {},
      custom_kpis: cfg['custom_kpis'] || [],
      kpi_layout: cfg['kpi_layout'] || {},
      block_layout: cfg['block_layout'] || {},
      performance_metrics: cfg['performance_metrics'] || {},
      clinical_access: cfg['clinical_access'] || {}
    }
  end

  # ── SISTEMA CORINGA: Personalização da conta (Configurações → Personalização)
  # O admin ajusta profissionais, unidades, listas e metas SEM tocar no
  # pacote do segmento — gravado em agenda_config['segment'] e resolvido
  # em todo lugar como: conta > segmento > preset clínica.
  def update_segment
    cfg = crm_settings.agenda_config || {}
    seg = cfg['segment'] || {}
    if params.key?(:professionals)
      seg['professionals'] = Array(params[:professionals]).map do |p|
        p.permit(:nome, :apelido, :cor, :grafias).to_h
      end.select { |p| p['nome'].present? }.first(30)
    end
    if params.key?(:units)
      seg['units'] = Array(params[:units]).map do |u|
        u.permit(:key, :nome, :cor, :endereco).to_h
      end.select { |u| u['key'].present? && u['nome'].present? }.first(20)
    end
    seg['problemas'] = Array(params[:problemas]).map { |v| v.to_s[0, 60] }.select(&:present?).first(30) if params.key?(:problemas)
    seg['procedimentos'] = Array(params[:procedimentos]).map { |v| v.to_s[0, 60] }.select(&:present?).first(30) if params.key?(:procedimentos)
    if params.key?(:metas)
      seg['metas'] = params.require(:metas).permit(:vendas_mes).to_h
                           .transform_values { |v| v.to_i.positive? ? v.to_i : nil }.compact
    end
    cfg['segment'] = seg
    crm_settings.update!(agenda_config: cfg)
    render json: { segment: seg }
  end

  # Colunas onde o Secretário da Agenda atua: a tela manda a lista de
  # colunas e aqui as automações (card entrou → anotar na Agenda) são
  # criadas/removidas de acordo. Só mexe nas automações com o nome-marcador —
  # automações criadas à mão no Modo Programação ficam intactas.
  SCHEDULER_MARKER = 'Secretário da Agenda (automático)'.freeze

  def sync_scheduler_stages
    unless Current.account_user.administrator?
      return render json: { error: 'Apenas administradores.' }, status: :forbidden
    end

    wanted = Array(params[:stage_ids]).map(&:to_i).reject(&:zero?).uniq
    managed = Crm::Automation.joins(stage: :pipeline)
                             .where(crm_pipelines: { account_id: Current.account.id })
                             .where(action_type: 'schedule_appointment', name: SCHEDULER_MARKER)

    managed.where.not(stage_id: wanted).destroy_all
    existing_ids = managed.pluck(:stage_id)
    (wanted - existing_ids).each do |stage_id|
      stage = Crm::Stage.joins(:pipeline)
                        .where(crm_pipelines: { account_id: Current.account.id })
                        .find_by(id: stage_id)
      next if stage.blank?

      Crm::Automation.create!(stage_id: stage.id, name: SCHEDULER_MARKER,
                              trigger_type: 'card_entered', action_type: 'schedule_appointment',
                              action_config: {}, active: true)
    end

    render json: { scheduler_stage_ids: managed.reload.pluck(:stage_id) }
  end

  # Insights comerciais do Consultor Comercial: analisa as conversas que
  # geraram fechamento e grava o relatório p/ a gestão (job assíncrono).
  def sales_insights
    unless Current.account_user.administrator?
      return render json: { error: 'Apenas administradores.' }, status: :forbidden
    end

    Crm::SalesInsightsJob.perform_later(Current.account.id)
    render json: { success: true, message: 'Análise iniciada! Os insights aparecem aqui em 1-2 minutos.' }
  end

  # Colunas de atuação de QUALQUER agente de coluna (Analista, Monitor de
  # Fechamento, NPS...): a tela manda agent + stage_ids e as automações
  # marcadas são criadas/removidas — as manuais do Modo Programação ficam.
  AGENT_STAGE_ACTIONS = {
    'conversation' => 'ai_analyze',
    'scheduler' => 'schedule_appointment',
    'closing' => 'closing_extract',
    'nps' => 'nps_score'
  }.freeze

  def agent_marker(agent)
    agent == 'scheduler' ? SCHEDULER_MARKER : "Agente de IA: #{agent} (automático)"
  end

  def sync_agent_stages
    unless Current.account_user.administrator?
      return render json: { error: 'Apenas administradores.' }, status: :forbidden
    end

    agent = params[:agent].to_s
    action = AGENT_STAGE_ACTIONS[agent]
    return render json: { error: 'Agente desconhecido.' }, status: :unprocessable_entity if action.blank?

    marker = agent_marker(agent)
    wanted = Array(params[:stage_ids]).map(&:to_i).reject(&:zero?).uniq
    managed = Crm::Automation.joins(stage: :pipeline)
                             .where(crm_pipelines: { account_id: Current.account.id })
                             .where(action_type: action, name: marker)

    managed.where.not(stage_id: wanted).destroy_all
    existing_ids = managed.pluck(:stage_id)
    (wanted - existing_ids).each do |stage_id|
      stage = Crm::Stage.joins(:pipeline)
                        .where(crm_pipelines: { account_id: Current.account.id })
                        .find_by(id: stage_id)
      next if stage.blank?

      Crm::Automation.create!(stage_id: stage.id, name: marker,
                              trigger_type: 'card_entered', action_type: action,
                              action_config: {}, active: true)
    end

    render json: { agent: agent, stage_ids: managed.reload.pluck(:stage_id) }
  end

  # Preencher a Agenda com o histórico: varre conversas com confirmação de
  # agendamento e registra as consultas (Agente de Agendamento). Admin-only.
  def agenda_backfill
    unless Current.account_user.administrator?
      return render json: { error: 'Apenas administradores.' }, status: :forbidden
    end

    Crm::AgendaBackfillJob.perform_later(Current.account.id, {
                                           'since_days' => params[:since_days].to_i,
                                           'limit' => params[:limit].to_i
                                         })
    render json: { success: true, message: 'Preenchimento da agenda iniciado! As consultas aparecem na Agenda conforme as conversas são lidas.' }
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

  # Mentor do Time pontual (admin): gera o feedback dos últimos 7 dias agora,
  # sem esperar a segunda-feira — bom para testar e para a primeira rodada.
  def run_mentor
    unless Current.account_user.administrator?
      return render json: { error: 'Só administradores rodam o Mentor.' }, status: :forbidden
    end

    Crm::WeeklyMentorJob.perform_later(Current.account.id)
    render json: { success: true, message: 'Mentor do Time iniciado! Os feedbacks aparecem no Meu Painel em alguns minutos.' }
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

  # ── Configurações → Domínio (público das páginas/formulários) ──────────────

  def public_domain
    render json: public_domain_json
  end

  def update_public_domain
    return render json: { error: 'Apenas administradores podem alterar o domínio.' }, status: :forbidden unless Current.account_user.administrator?

    value = Cevico::PublicSite.normalize(params[:host].to_s)
    if params[:host].to_s.present? && value.blank?
      return render json: { error: 'Endereço inválido. Use só o domínio, ex.: sistema.cevico.com.br' }, status: :unprocessable_entity
    end
    if value.present? && !value.match?(/\A[a-z0-9]([a-z0-9.-]*[a-z0-9])?\z/i)
      return render json: { error: 'Endereço inválido. Use só o domínio, sem https:// e sem barras.' }, status: :unprocessable_entity
    end

    Cevico::PublicSite.save_host!(params[:host].to_s)
    render json: public_domain_json
  end

  # HUB (porta de entrada): WhatsApp do atendimento + frase + texto do botão
  def update_public_hub
    return render json: { error: 'Apenas administradores podem alterar o hub.' }, status: :forbidden unless Current.account_user.administrator?

    Cevico::PublicSite.save_hub!(params.permit(:whatsapp, :tagline, :cta_text).to_h)
    render json: public_domain_json
  end

  # 📊 Rastreamento central (item 117): Pixel da Meta + GA4 — preenche uma
  # vez e toda página publicada (e o hub) sai carimbada, com o nome da
  # página dentro dos eventos
  def update_public_tracking
    return render json: { error: 'Apenas administradores podem alterar isso.' }, status: :forbidden unless Current.account_user.administrator?

    error = tracking_params_error
    return render json: { error: error }, status: :unprocessable_entity if error

    Cevico::PublicSite.save_tracking!('meta_pixel_id' => params[:meta_pixel_id].to_s,
                                      'ga4_id' => params[:ga4_id].to_s,
                                      'gtm_id' => params[:gtm_id].to_s)
    render json: public_domain_json
  end

  # verifica DNS + resposta HTTPS do domínio (antes/depois de salvar)
  def check_public_domain
    host = Cevico::PublicSite.normalize(params[:host].presence.to_s) || Cevico::PublicSite.host
    return render json: { error: 'Nenhum domínio para verificar.' }, status: :unprocessable_entity if host.blank?

    render json: domain_check_result(host)
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

  # {painel => user_id} vira {painel => {user_id, name}} — o front mostra o
  # 1º nome na pílula do Meu Painel sem depender da lista de agentes
  def panel_owners_json(cfg)
    owners = cfg['panel_owners'] || {}
    return {} if owners.blank?

    users = Current.account.users.where(id: owners.values).index_by(&:id)
    owners.each_with_object({}) do |(panel, uid), out|
      user = users[uid.to_i]
      next unless user

      out[panel] = { user_id: user.id, name: user.available_name }
    end
  end

  # validação amigável dos IDs do card 📊 Rastreamento
  def tracking_params_error
    ga4 = params[:ga4_id].to_s.strip.upcase
    return 'ID do GA4 inválido — é o código que começa com G-, ex.: G-AB12CD34EF' if ga4.present? && !ga4.match?(/\AG-[A-Z0-9]{4,16}\z/)

    pixel = params[:meta_pixel_id].to_s.strip
    return 'ID do Pixel inválido — é só o número que a Meta mostra, ex.: 1234567890123456' if pixel.present? && pixel.gsub(/\D/, '').blank?

    gtm = params[:gtm_id].to_s.strip.upcase
    return 'ID do Tag Manager inválido — é o código que começa com GTM-, ex.: GTM-MWDV8T35' if gtm.present? && !gtm.match?(/\AGTM-[A-Z0-9]{4,12}\z/)

    nil
  end

  def public_domain_json
    db_value = InstallationConfig.find_by(name: 'CEVICO_PUBLIC_HOST')&.value.presence
    {
      host: Cevico::PublicSite.host,
      dedicated: Cevico::PublicSite.dedicated_host?,
      app_host: Cevico::PublicSite.app_host,
      from_env: db_value.blank? && ENV['CEVICO_PUBLIC_HOST'].present?,
      example_page_url: Cevico::PublicSite.configured? ? Cevico::PublicSite.page_url('preoperatorio') : nil,
      example_form_url: "#{Cevico::PublicSite.base_url}/forms/…",
      hub: Cevico::PublicSite.hub_config,
      hub_whatsapp_url: Cevico::PublicSite.hub_whatsapp_url,
      tracking: Cevico::PublicSite.tracking_config
    }
  end

  def domain_check_result(host)
    result = { host: host }
    begin
      require 'resolv'
      result[:dns_ip] = Resolv.getaddress(host)
      result[:dns_ok] = true
    rescue StandardError
      result[:dns_ok] = false
    end
    result.merge!(domain_http_check(host)) if result[:dns_ok]
    result
  end

  def domain_http_check(host)
    res = HTTParty.get("https://#{host}/health", timeout: 6)
    { http_ok: res.code == 200, http_code: res.code }
  rescue StandardError => e
    { http_ok: false, http_error: e.class.name.demodulize }
  end

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

  def oftalmofacil_json(s)
    of = (s.agenda_config || {})['oftalmofacil'] || {}
    {
      base_url: of['base_url'],
      key_set: of['api_key'].present?,
      configured: of['base_url'].present? && of['api_key'].present?,
      updated_at: of['updated_at']
    }
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
      oftalmofacil: oftalmofacil_json(s),
      agenda_windows: (s.agenda_config || {})['windows'] || [],
      agenda_blocked: (s.agenda_config || {})['blocked'] || [],
      agenda_blocked_days: (s.agenda_config || {})['blocked_days'] || [],
      agenda_closed_doctors: (s.agenda_config || {})['closed_doctors'] || [],
      attendance_stages: (s.agenda_config || {})['attendance_stages'] || {},
      attendance_owners: (s.agenda_config || {})['attendance_owners'] || {},
      surgery_locations: (s.agenda_config || {})['surgery_locations'] || [],
      surgery_windows: (s.agenda_config || {})['surgery_windows'] || [],
      agenda_theme: (s.agenda_config || {})['theme'],
      # Personalização da conta (sistema coringa): ajustes sobre o segmento
      segment: (s.agenda_config || {})['segment'] || {},
      # HUB: recursos ligáveis da saúde (ex.: boxe) — o menu lê daqui
      health_features: (s.agenda_config || {}).dig('health', 'features') || {},
      # tabela de preços vigente (com os padrões quando não há tabela salva)
      price_table: {
        items: Cevico::PriceList.items(Current.account),
        customized: (s.agenda_config || {}).dig('price_table', 'items').present?,
        updated_at: (s.agenda_config || {}).dig('price_table', 'updated_at')
      },
      panel_assignments: (s.agenda_config || {})['panel_assignments'] || {},
      panel_owners: panel_owners_json(s.agenda_config || {}),
      ai_user_id: (s.agenda_config || {})['ai_user_id'],
      panel_themes: (s.agenda_config || {})['panel_themes'] || {},
      custom_kpis: (s.agenda_config || {})['custom_kpis'] || [],
      kpi_layout: (s.agenda_config || {})['kpi_layout'] || {},
      block_layout: (s.agenda_config || {})['block_layout'] || {},
      performance_metrics: (s.agenda_config || {})['performance_metrics'] || {},
      performance_metric_keys: Crm::AgentPerformance::METRIC_KEYS,
      panel_goals: (s.agenda_config || {})['panel_goals'] || {},
      custom_panels: (s.agenda_config || {})['custom_panels'] || [],
      main_panel: (s.agenda_config || {})['main_panel'].presence,
      company_actions: (s.agenda_config || {})['company_actions'] || [],
      clinical_access: (s.agenda_config || {})['clinical_access'] || {},
      agenda_backfill_last_run: (s.agenda_config || {})['backfill_last_run'],
      scheduler_log: Array((s.agenda_config || {})['scheduler_log']).first(30),
      scheduler_stage_ids: Crm::Automation.joins(stage: :pipeline)
                                          .where(crm_pipelines: { account_id: Current.account.id })
                                          .where(action_type: 'schedule_appointment', name: SCHEDULER_MARKER)
                                          .pluck(:stage_id),
      agent_stage_ids: AGENT_STAGE_ACTIONS.to_h do |agent, action|
        [agent, Crm::Automation.joins(stage: :pipeline)
                               .where(crm_pipelines: { account_id: Current.account.id })
                               .where(action_type: action, name: agent_marker(agent))
                               .pluck(:stage_id)]
      end
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
    # prompt padrão exibido na UI: o do SEGMENTO quando existir (sistema
    # coringa), senão o chumbado no serviço (preset clínica)
    default_prompts = {
      'conversation' => Segmento.prompt('conversation_insight') || Crm::ConversationInsightService::SYSTEM_PROMPT,
      'form' => Segmento.prompt('form_insight') || Crm::FormInsightService::SYSTEM_PROMPT,
      'scheduler' => Segmento.prompt('appointment_extraction') || Crm::AppointmentExtractionService::SYSTEM_PROMPT,
      'opportunity' => Segmento.prompt('opportunity_radar') || Crm::OpportunityRadarService::SYSTEM_PROMPT,
      'closing' => Segmento.prompt('surgery_closing') || Crm::SurgeryClosingService::SYSTEM_PROMPT,
      'nps' => Segmento.prompt('nps') || Crm::NpsService::SYSTEM_PROMPT,
      'sales' => Segmento.prompt('sales_coach') || Crm::SalesCoachService::SYSTEM_PROMPT,
      'instagram' => Segmento.prompt('instagram_agent') || Crm::InstagramAgentService::SYSTEM_PROMPT,
      'copywriter' => Segmento.prompt('copywriter') || Crm::CopywriterService::SYSTEM_PROMPT,
      'pagebuilder' => Segmento.prompt('page_builder') || Crm::PageBuilderService::SYSTEM_PROMPT,
      'mentor' => Segmento.prompt('weekly_mentor') || Crm::WeeklyMentorService::SYSTEM_PROMPT,
      'comments' => Segmento.prompt('comments_agent') || Crm::CommentsAgentService::SYSTEM_PROMPT,
      'harvest' => Segmento.prompt('harvest') || Crm::HarvestService::SYSTEM_PROMPT,
      'manager' => Segmento.prompt('auto_manager') || Crm::AutoManagerService::SYSTEM_PROMPT,
      'auditor' => Segmento.prompt('conversation_auditor') || Crm::ConversationAuditorService::SYSTEM_PROMPT,
      'creative' => Segmento.prompt('creative') || Crm::CreativeService::SYSTEM_PROMPT
    }
    {
      api_key_set: cfg['api_key'].present?,
      gemini_key_set: cfg['gemini_api_key'].present?,
      model: cfg['model'].presence || Crm::AiAgentConfig::DEFAULT_MODEL,
      effort: cfg['effort'].presence || 'high',
      business_context: cfg['business_context'].presence,
      configured: cfg['api_key'].present?,
      opportunity_last_run_at: cfg.dig('opportunity_state', 'last_run_at'),
      opportunity_alerts_count: visible_alerts_count(cfg),
      opportunity_last_run: cfg.dig('opportunity_state', 'last_run'),
      sales_insights: cfg.dig('agents', 'sales', 'insights'),
      instagram_events: Array(cfg.dig('instagram_state', 'events')).first(30),
      comments_events: Array(cfg.dig('comments_state', 'events')).first(30),
      comments_last_run_at: cfg.dig('comments_state', 'last_run_at'),
      # 🌾 resumo da colheita do mês (a lista completa vem por harvest_status)
      harvest_last: (cfg['harvest_state'] || {}).slice('month_key', 'status', 'generated_at', 'approved_at', 'stats', 'last_error'),
      # 📊 último diagnóstico do Gestor Autônomo
      manager_state: (cfg['manager_state'] || {}).slice('last_run_at', 'brief', 'findings', 'tasks_opened'),
      # 🎓 resumo do Auditor (ranking 7 dias sai por auditor_summary)
      auditor_last: { last_run_at: cfg.dig('auditor_state', 'last_run_at'),
                      days_done: (cfg.dig('auditor_state', 'days_done') || {}).keys.max },
      # 🎨 semana atual do Criativo Perpétuo (lista completa por creative_state)
      creative_last: { week_key: cfg.dig('creative_state', 'week_key'),
                       generated_at: cfg.dig('creative_state', 'generated_at'),
                       winners: Array(cfg.dig('creative_state', 'winners')).size,
                       pending: Array(cfg.dig('creative_state', 'winners'))
                         .sum { |w| Array(w['variations']).count { |v| v['status'] == 'pending' } } },
      agents: default_prompts.to_h do |key, default_prompt|
        recommended = Crm::AiAgentConfig::RECOMMENDED[key] || {}
        [key, {
          # opt-in: sem enabled true gravado, o agente está DESLIGADO
          enabled: agents.dig(key, 'enabled') == true,
          prompt: agents.dig(key, 'prompt').presence,
          references: agents.dig(key, 'references').presence,
          model: agents.dig(key, 'model').presence,
          effort: agents.dig(key, 'effort').presence,
          recommended_model: recommended['model'],
          recommended_effort: recommended['effort'],
          stage_ids: Array(agents.dig(key, 'stage_ids')).map(&:to_i),
          inbox_ids: Array(agents.dig(key, 'inbox_ids')).map(&:to_i),
          wait_minutes: agents.dig(key, 'wait_minutes').presence&.to_i,
          response_goal_minutes: agents.dig(key, 'response_goal_minutes').presence&.to_i,
          lookback_hours: agents.dig(key, 'lookback_hours').presence&.to_i,
          # Respondedor de Comentários (token nunca volta pro navegador)
          page_token_set: agents.dig(key, 'page_access_token').present?,
          fb_page_id: agents.dig(key, 'fb_page_id').presence,
          ig_user_id: agents.dig(key, 'ig_user_id').presence,
          # 🌾 Colheitadeira (item 128)
          monthly_size: agents.dig(key, 'monthly_size').presence&.to_i,
          cold_days: agents.dig(key, 'cold_days').presence&.to_i,
          daily_cap: agents.dig(key, 'daily_cap').presence&.to_i,
          day_of_month: agents.dig(key, 'day_of_month').presence&.to_i,
          inbox_id: agents.dig(key, 'inbox_id').presence&.to_i,
          require_approval: agents.dig(key, 'require_approval') != false,
          message_preview: agents.dig(key, 'message_preview').presence,
          mode: agents.dig(key, 'mode').presence,
          template_params: agents.dig(key, 'template_params').presence,
          # 📊 Gestor Autônomo (item 128)
          drop_pct: agents.dig(key, 'drop_pct').presence&.to_i,
          watchers: Array(agents.dig(key, 'watchers')).map do |w|
            {
              stage_id: w['stage_id'].to_i,
              user_id: w['user_id'].presence&.to_i,
              lookback_hours: w['lookback_hours'].presence&.to_i || 24
            }
          end,
          draft: agents.dig(key, 'draft').presence,
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

  # cor escolhida pelo admin por card da fileira (item 143): só strings de
  # cor/gradiente CSS simples — nada de caracteres que escapem do style
  def sanitize_kpi_colors(raw)
    (raw || {}).to_h.to_a.first(40).each_with_object({}) do |(k, v), acc|
      key = k.to_s[0, 40]
      color = v.to_s.strip[0, 160]
      next if key.blank? || color.blank?
      next unless color.match?(/\A[#(),.%a-zA-Z0-9\s-]+\z/)

      acc[key] = color
    end
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
      insights_configured: cfg['developer_token'].present? && cfg['customer_id'].present?,
      ga4_property_id: cfg['ga4_property_id'],
      service_account_set: cfg['service_account_json'].present?,
      cost_configured: cfg['ga4_property_id'].present? && cfg['service_account_json'].present?
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
