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
    # Gemini (Google): reservada para geração de IMAGENS das Páginas
    cfg['gemini_api_key'] = params[:gemini_api_key] if params[:gemini_api_key].present?
    cfg['model']   = params[:model]   if params.key?(:model)
    cfg['effort']  = params[:effort]  if params.key?(:effort)
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
                                pagebuilder: agent_fields,
                                instagram: agent_fields + [{ inbox_ids: [] }],
                                mentor: agent_fields,
                                comments: agent_fields + [:page_access_token, :fb_page_id, :ig_user_id],
                                opportunity: agent_fields + [:wait_minutes, :lookback_hours, :response_goal_minutes,
                                                             { stage_ids: [],
                                                               watchers: %i[stage_id user_id lookback_hours] }])
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
      clinical_access: cfg['clinical_access'] || {}
    }
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

  def public_domain_json
    db_value = InstallationConfig.find_by(name: 'CEVICO_PUBLIC_HOST')&.value.presence
    {
      host: Cevico::PublicSite.host,
      dedicated: Cevico::PublicSite.dedicated_host?,
      app_host: Cevico::PublicSite.app_host,
      from_env: db_value.blank? && ENV['CEVICO_PUBLIC_HOST'].present?,
      example_page_url: Cevico::PublicSite.configured? ? Cevico::PublicSite.page_url('preoperatorio') : nil,
      example_form_url: "#{Cevico::PublicSite.base_url}/forms/…"
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
      # tabela de preços vigente (com os padrões quando não há tabela salva)
      price_table: {
        items: Cevico::PriceList.items(Current.account),
        customized: (s.agenda_config || {}).dig('price_table', 'items').present?,
        updated_at: (s.agenda_config || {}).dig('price_table', 'updated_at')
      },
      panel_assignments: (s.agenda_config || {})['panel_assignments'] || {},
      panel_goals: (s.agenda_config || {})['panel_goals'] || {},
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
    default_prompts = {
      'conversation' => Crm::ConversationInsightService::SYSTEM_PROMPT,
      'form' => Crm::FormInsightService::SYSTEM_PROMPT,
      'scheduler' => Crm::AppointmentExtractionService::SYSTEM_PROMPT,
      'opportunity' => Crm::OpportunityRadarService::SYSTEM_PROMPT,
      'closing' => Crm::SurgeryClosingService::SYSTEM_PROMPT,
      'nps' => Crm::NpsService::SYSTEM_PROMPT,
      'sales' => Crm::SalesCoachService::SYSTEM_PROMPT,
      'instagram' => Crm::InstagramAgentService::SYSTEM_PROMPT,
      'copywriter' => Crm::CopywriterService::SYSTEM_PROMPT,
      'pagebuilder' => Crm::PageBuilderService::SYSTEM_PROMPT,
      'mentor' => Crm::WeeklyMentorService::SYSTEM_PROMPT,
      'comments' => Crm::CommentsAgentService::SYSTEM_PROMPT
    }
    {
      api_key_set: cfg['api_key'].present?,
      gemini_key_set: cfg['gemini_api_key'].present?,
      model: cfg['model'].presence || Crm::AiAgentConfig::DEFAULT_MODEL,
      effort: cfg['effort'].presence || 'high',
      configured: cfg['api_key'].present?,
      opportunity_last_run_at: cfg.dig('opportunity_state', 'last_run_at'),
      opportunity_alerts_count: visible_alerts_count(cfg),
      opportunity_last_run: cfg.dig('opportunity_state', 'last_run'),
      sales_insights: cfg.dig('agents', 'sales', 'insights'),
      instagram_events: Array(cfg.dig('instagram_state', 'events')).first(30),
      comments_events: Array(cfg.dig('comments_state', 'events')).first(30),
      comments_last_run_at: cfg.dig('comments_state', 'last_run_at'),
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
