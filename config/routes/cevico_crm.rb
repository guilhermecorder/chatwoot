# rubocop:disable Metrics/BlockLength
# 🔧 ROTAS CEVICO DO CRM (rodada 171 — facilitar as atualizações do Chatwoot)
# Chamado por `draw(:cevico_crm)` dentro de api/v1/accounts/:account_id
# (scope module: :accounts) no config/routes.rb — a posição/aninhamento
# continuam os mesmos; só o texto saiu do arquivo do upstream, que agora
# fica quase intocado no merge. Tudo aqui vira /api/v1/accounts/:id/crm/…
namespace :crm do
  resources :campaigns, only: [:index, :show, :create, :destroy] do
    member do
      post :send_now
      post :schedule
      get :results
    end
    collection do
      post :preview_audience
      get :templates
    end
  end
  resources :message_automations, only: [:index, :create, :update, :destroy] do
    member { get :preview_eligible }
  end
  # 🗺️ Mensagens da jornada (item 168): regras + fila de envios
  resources :journey_messages, only: [:index, :create, :update, :destroy] do
    member do
      post :test_send
      post :plan_now
    end
    collection do
      post :preview
      get :settings, action: :settings_show
      post :update_settings
    end
  end
  resources :journey_sends, only: [:index] do
    member do
      post :approve
      post :skip
      post :retry
    end
    collection do
      get :queue
      post :approve_all
    end
  end
  resources :followup_bots, only: [:index, :create, :update, :destroy] do
    member { post :toggle } # chave de emergência — aberta às atendentes
  end
  resource :traffic_report, only: [:show]
  resource :ads_report, only: [:show], controller: 'ads_reports' do
    post :backfill
  end
  resource :conversation_summary, only: [:show], controller: 'conversation_summaries' do
    post :analyze
    post :sales_help
    post :move_stage
    post :toggle_followup
  end
  # Radar de Oportunidades: "Atender agora" tira o aviso da fila
  # (se o paciente seguir sem resposta, a próxima auditoria recoloca)
  post 'radar/attend', to: 'radar#attend'
  resources :forms, only: [:index, :create, :update, :destroy] do
    member do
      get :summary
      post :generate_insights
      get :preview_link
    end
  end
  resource :retro_labels, only: [] do
    post :preview
    post :apply
  end
  resource :batch_updates, only: [] do
    post :preview
    post :apply
  end
  resource :external_surgeries, only: [] do
    post :preview
    post :apply
    # 📄 planilha de fechamento (item 132): upload + prévia + aplicar
    post :preview_sheet
    post :apply_sheet
    # 🤖 IA acha "mesma pessoa escrita diferente" nos não-casados (item 154)
    post :ai_match_sheet
    # ↩️ desfazer a última importação (item 133)
    get :import_status
    post :undo_last
  end
  resource :label_replacements, only: [] do
    post :preview
    post :apply
  end
  resource :label_removals, only: [] do
    post :preview
    post :apply
  end
  resource :contact_unification, only: [], controller: 'contact_unifications' do
    post :preview
    post :apply
  end
  resource :settings, only: [:show, :update] do
    post :test_n8n
    post :fetch_workflows
    post :update_meta_ads
    post :test_meta_ads
    post :update_ai
    post :test_ai
    post :test_gemini
    # Estúdio do Copywriter: conteúdo multi-formato (carrossel, reels...)
    post :copywriter_content
    post :update_google_ads
    post :test_google_ads
    post :update_sheets
    post :test_sheets
    # OftalmoFácil: conexão nativa (endereço + chave)
    post :update_oftalmofacil
    # 🏥 item 157: testar a conexão só-leitura + sincronizar agora
    post :test_oftalmofacil
    post :sync_oftalmofacil
    # 📞 item 167: ligações nativas (config + ligar na Meta + estado)
    post :update_calls
    post :enable_calls_at_meta
    get :calls_meta_status
    # 🤖📞 item 169: agente de ligação (ElevenLabs) — config, teste,
    # sincronizar agente/ferramentas/webhook, contas WhatsApp, vozes, estado
    post :update_voice
    post :test_voice
    post :sync_voice
    get :voice_whatsapp_accounts
    get :voice_voices
    get :voice_state
    post :update_agenda
    post :agenda_backfill
    # Configurações → Domínio (público das páginas/formulários)
    get :public_domain
    post :update_public_domain
    post :update_public_hub
    post :update_public_tracking
    post :check_public_domain
    post :sync_scheduler_stages
    post :sync_agent_stages
    post :sales_insights
    post :radar_scan
    post :run_mentor
    # 🌾 Colheitadeira da Base + 📊 Gestor Autônomo (item 128)
    get :harvest_status
    post :harvest_preview
    post :harvest_approve
    post :harvest_pause
    post :harvest_resume
    post :harvest_skip_lead
    post :harvest_send_now
    post :run_manager
    # 🎓 Auditor de Conversas (item 130)
    post :run_auditor
    get :auditor_summary
    # 🎨 Criativo Perpétuo (item 131)
    post :run_creative
    get :creative_state
    post :creative_review
    get :ai_usage
    # concessão de acessos por atendente (allow-list, admin)
    post :update_agent_grants
    # tabela de preços oficial (Espaço do Paciente + prompts da IA)
    post :update_price_table
    # investimento mensal por caixa (ROI/CAC do Dashboard CRM)
    post :update_inbox_investments
  end
  # Feedback de bugs do time (vira card 🐞 no board do admin)
  resources :bug_reports, only: [:create], controller: 'bug_reports'
  # Páginas públicas (ambiente Páginas)
  resources :pages, only: [:index, :create, :update, :destroy], controller: 'pages' do
    # agente copywriter escreve a página inteira em seções
    # (item 111: geração roda em segundo plano — start + status)
    collection do
      post :generate
      post :generate_start
      get :generate_status
      post :upload_image
    end
    # estúdio de copy: comentários do time na página
    member do
      post :add_comment
      post :delete_comment
    end
  end
  # Resultados de tráfego das Páginas: origem (Google/SEO/Meta) →
  # visitas → cliques → leads (Protocolo) → agendou → cirurgia
  resource :pages_report, only: [:show], controller: 'pages_reports'
  # Análise de Páginas + montador de funis (PÁGINAS PRO, admin)
  resource :pages_dashboard, only: [:show], controller: 'pages_dashboards' do
    # 🌪 Montador de Funis (item 60): fontes de captação
    post :save_funnel_sources
  end
  # Planejamento de conteúdos (workflow kanban de marketing)
  resources :content_items, only: [:index, :create, :update, :destroy] do
    # renovar o ambiente: publicados → coluna oculta (item 95)
    collection { post :archive_published }
  end
  # Ambiente Pessoas: DISC + desenvolvimento pessoal + feedbacks
  resource :people, only: [:show], controller: 'people' do
    post :save_disc
    post :save_goals
    post :save_assessment
    post :save_life
  end
  # Painel de Metas (admin cria; time acompanha)
  resource :goal_plans, only: [:show], controller: 'goal_plans' do
    post :upsert
    post :add_note
    post :delete_note
    post :update_routines
  end
  # Ferramentas de Fechamento (script + mapa de objeções)
  resource :closing_tools, only: [:show], controller: 'closing_tools' do
    post :update_script
    post :generate_map
  end
  # Dashboard Google (Ads + GA4): conversões enviadas + integração
  resource :google_dashboard, only: [:show], controller: 'google_dashboards'
  # Gestão Financeira (receitas, custos, tributos, investimentos) — só admin
  resource :finance, only: [:show], controller: 'finance' do
    post :create_entry
    post :update_entry
    post :delete_entry
    get :compare
    # 🏥 item 157: lucratividade real das cirurgias (OftalmoFácil)
    get :profitability
  end
  # Ferramentas da Academia (item 77): time lê, admin escreve
  resources :team_tools, only: [:index, :create, :update, :destroy], controller: 'team_tools'
  # Estoque (item 68): dashboard/CRUD são área financeira;
  # lookup + pedido são do fluxo clínico (abertos ao time)
  resource :stock, only: [:show], controller: 'stock' do
    post :create_item
    post :update_item
    post :delete_item
    get :lookup
    post :create_order
    post :update_order
    post :delete_order
  end
  # Painel Estratégico (a empresa por pilares) — só admin
  resource :strategy, only: [:show], controller: 'strategy' do
    post :create_pillar
    post :update_pillar
    post :delete_pillar
    post :create_item
    post :update_item
    post :delete_item
    # 🏭 Desenho do Processo (item 59)
    post :save_processes
    # 🧭 Painel do Empresário (quadro de gestão do dono)
    post :save_business_board
  end
  # Central do Paciente: espaço do paciente + anotações do médico
  resources :patients, only: [:show], controller: 'patients' do
    member { post :update_profile }
    resources :clinical_notes, only: [:index, :create, :update, :destroy], controller: 'clinical_notes'
  end
  resource :home, only: [:show], controller: 'home' do
    # popup de prioridade máxima do Radar (checagem leve) e
    # pausa manual do radar pela atendente (com registro)
    get :radar_ping
    post :toggle_radar
    # cesto de indicadores c/ série + período anterior (item 141)
    get :kpis
  end
  resource :campaigns_dashboard, only: [:show], controller: 'campaigns_dashboards'
  resource :automations_dashboard, only: [:show], controller: 'automations_dashboards'
  resource :doctors_dashboard, only: [:show], controller: 'doctors_dashboards' do
    # 🩺 Ambiente do médico (item 104): perfis de gestão — só admin
    post :save_profiles
  end
  resource :agents_dashboard, only: [:show], controller: 'agents_dashboards'
  # Dashboard dos AGENTES DE IA (item 85, só admin)
  resource :ai_dashboard, only: [:show], controller: 'ai_dashboards'
  resource :agenda_dashboard, only: [:show], controller: 'agenda_dashboards'
  # 📞 Ligações nativas de WhatsApp (item 167): lista/atender/recusar/
  # desligar/gravação/transcrição, ligar p/ o paciente e o dashboard
  resources :calls, only: [:index, :show], controller: 'calls' do
    member do
      post :accept
      post :reject
      post :hangup
      post :recording
      post :transcribe
    end
    collection do
      get :dashboard
      post :initiate
      post :request_permission
      get :permission_status
    end
  end
  # 🤖📞 item 169: campanhas de ligação (a assistente virtual liga p/ o público)
  resources :call_campaigns, only: [:index, :show, :create, :update, :destroy], controller: 'call_campaigns' do
    member do
      post :start
      post :pause
      post :resume
    end
    collection { post :preview_audience }
  end
  # 🗺️ item 170: mapa de fluxos dos agentes/automações (Mermaid + estado ao vivo)
  resources :flows, only: [:index, :show], controller: 'flows', param: :key
  resources :pipelines, only: [:index, :show, :create, :update, :destroy] do
    resources :stages, only: [:index, :create, :update, :destroy] do
      collection { post :reorder }
      resources :automations, only: [:index, :create, :update, :destroy] do
        member { post :trigger }
      end
    end
    resources :contacts, only: [:index, :create, :update, :destroy] do
      member do
        get  :history
        post :trigger_label_change
        post :detect_value
        post :start_conversation
      end
      collection do
        post :detect_values_bulk
      end
    end
    resource :dashboard, only: [:show] do
      # PRO MAX (item 129): séries diárias p/ o estúdio de análise
      get :pro_series
      # lista de resgate das perdas por motivo (item 145)
      get :loss_contacts
    end
  end
end
# rubocop:enable Metrics/BlockLength
