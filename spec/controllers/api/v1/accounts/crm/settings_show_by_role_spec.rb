require 'rails_helper'

# 🔐 Rodada 2 da auditoria (12/10) — "Portas fechadas", grupo R2-G4:
# GET crm/settings montado POR PAPEL (#295/#337), sync/teste do OftalmoFácil só
# para quem tem a área "settings" e nunca com a integração desligada
# (#171/#366/#427/#193), token da Página fora do rascunho (#338) e chave da
# conta de serviço do Google fora do log (#176).
RSpec.describe 'CRM settings — JSON por papel e portas do OftalmoFácil (Rodada 2)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }

  let(:oftalmofacil_cfg) do
    { 'enabled' => true, 'db_host' => 'hub.parceiro.local', 'db_port' => 3306, 'db_name' => 'app_oftalmo',
      'db_user' => 'cevico_leitura', 'db_password' => 'segredo', 'provider_name' => 'CATARATA_SP',
      'partners_enabled' => true, 'doctors' => { '7' => 'Dr. Exemplo' } }
  end

  let!(:settings) do
    CrmSetting.create!(
      account: account,
      column_presets: [{ 'name' => 'Meu funil', 'stage_ids' => [1, 2] }],
      agent_permissions: { 'grants' => { colleague.id.to_s => %w[finance strategy] } },
      agenda_config: {
        'oftalmofacil' => oftalmofacil_cfg,
        'windows' => [{ 'doctor' => 'Dr. Exemplo', 'weekday' => 1, 'start' => '08:00', 'end' => '12:00' }],
        'person_colors' => { agent.id.to_s => 'bondi' },
        'list_clean_mode' => 'clean',
        'kpi_layout' => { 'inicio' => [{ 'key' => 'leads', 'x' => 0, 'y' => 0, 'w' => 2, 'h' => 2 }] },
        'team_roles' => { admin.id.to_s => 'gerente' },
        'scheduler_log' => [{ 'at' => '2026-10-10T10:00:00Z', 'name' => 'Paciente Sigiloso', 'note' => 'consulta 15/10' }],
        'price_table' => { 'items' => [{ 'group' => 'Cirurgias', 'name' => 'Catarata', 'price' => 9000, 'promo_price' => nil }],
                           'updated_at' => '2026-10-01T00:00:00Z' },
        'clinical_access' => { 'doctor_user_ids' => [agent.id, admin.id], 'team_view' => true },
        Crm::AppointmentReminderSendJob::STATE_KEY => { 'd2' => { 'sent' => [{ 'name' => 'Paciente Sigiloso', 'phone_tail' => '1234' }] } },
        Crm::NpsSurvey::STATE_KEY => { 'answers' => [{ 'name' => 'Paciente Sigiloso', 'score' => 9 }] }
      },
      ai_config: {
        'api_key' => 'sk-teste',
        'script' => { 'persona' => 'Você é a Clara, da CEVICO.' },
        'agents' => {
          'atendente_agendamento' => { 'enabled' => true, 'stage_ids' => [1], 'inbox_ids' => [3], 'mode' => 'shadow',
                                       'prompt' => 'PROMPT SECRETO DA ETAPA' },
          'comments' => { 'enabled' => false, 'prompt' => 'prompt publicado', 'page_access_token' => 'EAAB-publicado',
                          'draft' => { 'prompt' => 'prompt rascunho', 'page_access_token' => 'EAAB-no-rascunho-antigo' } },
          'sales' => { 'insights' => { 'text' => 'Melhores horários: 10h' } }
        },
        'manager_state' => { 'brief' => 'Diagnóstico da semana', 'last_run_at' => '2026-10-10T10:00:00Z' }
      }
    )
  end

  def show_as(user)
    get base, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  # marcações próprias na árvore de acessos de UMA pessoa (sem perder as concessões antigas)
  def grant_tree!(user, nodes)
    tree = (settings.agent_permissions['tree'] || {}).merge(user.id.to_s => nodes)
    settings.update!(agent_permissions: settings.agent_permissions.merge('tree' => tree))
  end

  describe 'GET settings para atendente SEM a área "settings"' do
    it 'não entrega Roteiro, prompts, concessões dos colegas, preços, registros com paciente nem conexão do hub', :aggregate_failures do
      grant_tree!(agent, 'pacientes' => 'view') # só vê a ficha: nem a tabela de preços viaja
      json = show_as(agent)
      expect(json.keys).not_to include('agent_permissions', 'price_table', 'scheduler_log', 'team_roles',
                                       'appointment_reminders_state', 'nps_survey_state', 'n8n_base_url', 'n8n_workflows')
      expect(json['ai'].keys).not_to include('script', 'script_v2', 'responder_events', 'voice_shadow', 'comments_events',
                                             'sales_insights', 'manager_state', 'instagram_events', 'harvest_last')
      expect(json.dig('ai', 'agents', 'atendente_agendamento').keys).not_to include('prompt', 'draft', 'default_prompt')
      expect(json.dig('ai', 'agents', 'comments').keys).not_to include('prompt', 'draft', 'page_token_set', 'fb_page_id')
      hub_secrets = %w[db_host db_port db_name db_user db_password_set base_url key_set]
      expect(json['oftalmofacil'].keys).not_to include(*hub_secrets)
      expect(json['voice'].keys).not_to include('prompt', 'full_prompt', 'inbound_prompt', 'default_prompt', 'api_key_set')
      expect(json['meta_ads'].keys).to contain_exactly('configured', 'insights_configured')
      expect(json['google_ads'].keys).to contain_exactly('configured', 'insights_configured', 'cost_configured')
      expect(json['sheets'].keys).to contain_exactly('configured')
      # nada do paciente escapa em lugar nenhum do JSON
      expect(response.body).not_to include('Paciente Sigiloso', 'PROMPT SECRETO', 'EAAB-', 'hub.parceiro.local', 'Clara, da CEVICO')
    end

    it 'mantém o que o dia a dia usa (CRM, Conversas, Meu Painel, Agenda, Chamadas, Espaço do Paciente)', :aggregate_failures do
      json = show_as(agent)
      expect(json['column_presets']).to eq([{ 'name' => 'Meu funil', 'stage_ids' => [1, 2] }])
      expect(json['person_colors']).to eq(agent.id.to_s => 'bondi')
      expect(json['list_clean_mode']).to eq('clean')
      expect(json['agenda_windows'].size).to eq(1)
      expect(json['kpi_layout']).to include('inicio')
      expect(json['calls']).to include('enabled')
      expect(json['access']).to include('me', 'catalog')
      expect(json['company']).to be_a(Hash)
      expect(json.dig('ai', 'opportunity_alerts_count')).to eq(0)
      expect(json.dig('ai', 'agents', 'atendente_agendamento'))
        .to include('enabled' => true, 'stage_ids' => [1], 'inbox_ids' => [3], 'mode' => 'shadow')
      expect(json['oftalmofacil']).to include('enabled' => true, 'configured' => true, 'partners_enabled' => true)
      expect(json['voice']).to include('enabled', 'configured', 'permission_template')
    end

    it 'do cadeado clínico só sabe de si mesmo (a lista de médicos não viaja)' do
      json = show_as(agent)
      expect(json['clinical_access']).to eq('team_view' => true, 'doctor_user_ids' => [agent.id])

      json = show_as(colleague)
      expect(json['clinical_access']).to eq('team_view' => true, 'doctor_user_ids' => [])
    end

    # decisão R2-G4: a tabela oficial vai para quem ALTERA o orçamento no Espaço
    # do Paciente (padrão da equipe) — senão a tela usaria os preços fixos do
    # código e um valor errado iria ao paciente sem ninguém perceber
    describe 'tabela de preços' do
      it 'quem altera o orçamento do paciente (padrão da equipe) recebe a tabela — e nada mais do admin', :aggregate_failures do
        json = show_as(agent)
        expect(json.dig('price_table', 'items').first).to include('name' => 'Catarata', 'price' => 9000)
        expect(json.keys).not_to include('agent_permissions', 'scheduler_log', 'team_roles')
        expect(json['ai'].keys).not_to include('script')
      end

      it 'quem só VÊ a ficha do paciente fica sem a tabela' do
        grant_tree!(agent, 'pacientes' => 'view')
        json = show_as(agent)
        expect(json.keys).not_to include('price_table')
        expect(response.body).not_to include('9000')
      end

      it 'quem pode VER a Tabela de preços recebe a tabela mesmo sem editar paciente' do
        grant_tree!(agent, 'pacientes' => 'view', 'configuracoes.precos' => 'view')
        json = show_as(agent)
        expect(json.dig('price_table', 'items').first).to include('name' => 'Catarata', 'price' => 9000)
      end
    end

    it 'quem cuida de lembretes/confirmação/NPS (nó "modelos") vê o estado das rodadas — e só isso a mais', :aggregate_failures do
      grant_tree!(agent, 'configuracoes.modelos' => 'view')
      json = show_as(agent)
      expect(json.dig('appointment_reminders_state', 'd2', 'sent').first).to include('name' => 'Paciente Sigiloso')
      expect(json.dig('nps_survey_state', 'answers').first).to include('score' => 9)
      expect(json.keys).not_to include('agent_permissions', 'scheduler_log', 'team_roles')
      expect(json['ai'].keys).not_to include('script', 'responder_events')
    end

    it 'o domínio público (nó só de admin) é 403 para a equipe e abre para o admin' do
      get "#{base}/public_domain", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      get "#{base}/public_domain", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('host')
    end
  end

  describe 'GET settings para quem tem a área "settings" e para admin' do
    it 'atendente com a área "settings" recebe o JSON completo', :aggregate_failures do
      settings.update!(agent_permissions: { 'grants' => { agent.id.to_s => ['settings'], colleague.id.to_s => ['finance'] } })
      json = show_as(agent)
      expect(json.dig('agent_permissions', 'grants')).to include(colleague.id.to_s => ['finance'])
      expect(json.dig('ai', 'script')).to be_present
      expect(json.dig('price_table', 'items')).to be_present
      expect(json['scheduler_log'].first).to include('name' => 'Paciente Sigiloso')
      expect(json['oftalmofacil']).to include('db_host' => 'hub.parceiro.local', 'db_password_set' => true)
      expect(json.dig('ai', 'agents', 'atendente_agendamento', 'prompt')).to eq('PROMPT SECRETO DA ETAPA')
    end

    it 'admin recebe tudo, mas o rascunho volta SEM o token (só o aviso de que há um guardado)', :aggregate_failures do
      json = show_as(admin)
      comments = json.dig('ai', 'agents', 'comments')
      expect(comments['draft']).to eq('prompt' => 'prompt rascunho')
      expect(comments['draft_token_set']).to be(true)
      expect(comments['page_token_set']).to be(true)
      expect(response.body).not_to include('EAAB-')
      expect(json['clinical_access']['doctor_user_ids']).to contain_exactly(agent.id, admin.id)
    end
  end

  describe 'POST update_ai — rascunho nunca guarda token (#338)' do
    it 'apaga page_access_token do rascunho antes de gravar e não devolve o token', :aggregate_failures do
      post "#{base}/update_ai",
           params: { agents: { comments: { draft: { prompt: 'novo rascunho', page_access_token: 'EAAB-colado-no-salvar' } } } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      saved = CrmSetting.find(settings.id).ai_config.dig('agents', 'comments')
      expect(saved['draft']).to eq('prompt' => 'novo rascunho')
      expect(saved['page_access_token']).to eq('EAAB-publicado') # o publicado não muda ao salvar rascunho
      expect(response.parsed_body.dig('agents', 'comments', 'draft')).to eq('prompt' => 'novo rascunho')
      expect(response.parsed_body.dig('agents', 'comments', 'draft_token_set')).to be(false)
      expect(response.body).not_to include('EAAB-')
    end

    it 'agente que NUNCA foi salvo (conta nova): o primeiro rascunho também entra sem o token', :aggregate_failures do
      settings.update!(ai_config: {})
      post "#{base}/update_ai",
           params: { agents: { comments: { draft: { prompt: 'primeiro rascunho', page_access_token: 'EAAB-primeiro' } } } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      saved = CrmSetting.find(settings.id).ai_config
      expect(saved.dig('agents', 'comments', 'draft')).to eq('prompt' => 'primeiro rascunho')
      expect(saved.to_json).not_to include('EAAB-')
      expect(response.body).not_to include('EAAB-')
    end

    it 'rascunho só com o token vira rascunho nenhum' do
      post "#{base}/update_ai", params: { agents: { comments: { draft: { page_access_token: 'EAAB-sozinho' } } } },
                                headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(CrmSetting.find(settings.id).ai_config.dig('agents', 'comments')).not_to have_key('draft')
    end

    it 'Publicar continua gravando o token no campo de verdade' do
      post "#{base}/update_ai", params: { agents: { comments: { page_access_token: 'EAAB-publicado-2', draft: {} } } },
                                headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(CrmSetting.find(settings.id).ai_config.dig('agents', 'comments', 'page_access_token')).to eq('EAAB-publicado-2')
    end
  end

  describe 'OftalmoFácil: sincronizar e testar (#171/#366/#427/#193)' do
    before { allow(Crm::OftalmofacilSyncJob).to receive(:perform_later) }

    it 'atendente sem a área "settings" leva 403 em sync, teste e gasto da IA', :aggregate_failures do
      post "#{base}/sync_oftalmofacil", params: { full: true }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/test_oftalmofacil", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      get "#{base}/ai_usage", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Crm::OftalmofacilSyncJob).not_to have_received(:perform_later)
    end

    it '"Sincronizar agora" com a integração DESLIGADA é recusado e nada entra na fila', :aggregate_failures do
      settings.update!(agenda_config: settings.agenda_config.merge('oftalmofacil' => oftalmofacil_cfg.merge('enabled' => false)))
      post "#{base}/sync_oftalmofacil", params: { full: true }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('ok' => false)
      expect(response.parsed_body['error']).to include('desligada')
      expect(Crm::OftalmofacilSyncJob).not_to have_received(:perform_later)
    end

    it 'ligada e configurada, o admin enfileira (inclusive a carga completa)' do
      post "#{base}/sync_oftalmofacil", params: { full: true }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('ok' => true, 'queued' => true)
      expect(Crm::OftalmofacilSyncJob).to have_received(:perform_later).with(account.id, full: true)
    end
  end

  describe 'OftalmoFácil: "Trazer para a Agenda" (reconcile_day) com a integração desligada' do
    it 'é recusado com o mesmo aviso e não reprocessa nada' do
      settings.update!(agenda_config: settings.agenda_config.merge('oftalmofacil' => oftalmofacil_cfg.merge('enabled' => false)))
      allow(Crm::OftalmofacilDayCheck).to receive(:new)
      post "/api/v1/accounts/#{account.id}/crm/oftalmofacil/reconcile_day", params: { date: '2026-10-10' },
                                                                            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('desligada')
      expect(Crm::OftalmofacilDayCheck).not_to have_received(:new)
    end
  end

  describe 'Crm::OftalmofacilSyncJob — account_id é filtro, não atalho da chave (#193)' do
    it 'com enabled=false não abre conexão nenhuma, mesmo chamado para a conta' do
      settings.update!(agenda_config: settings.agenda_config.merge('oftalmofacil' => oftalmofacil_cfg.merge('enabled' => false)))
      allow(Crm::OftalmofacilSyncService).to receive(:new)
      Crm::OftalmofacilSyncJob.new.perform(account.id, full: true)
      expect(Crm::OftalmofacilSyncService).not_to have_received(:new)
      expect(CrmSetting.find(settings.id).agenda_config['oftalmofacil']).not_to have_key('last_run_at')
    end

    it 'com enabled=true a conta pedida roda' do
      allow(Crm::OftalmofacilSyncService).to receive(:new).and_raise(StandardError, 'parou aqui de propósito')
      allow(Rails.logger).to receive(:error)
      Crm::OftalmofacilSyncJob.new.perform(account.id)
      expect(Crm::OftalmofacilSyncService).to have_received(:new).with(hash_including(account: account))
      expect(Rails.logger).to have_received(:error).with(a_string_including('parou aqui de propósito'))
    end
  end

  describe 'log: chave da conta de serviço do Google (#176)' do
    it 'service_account_json e qualquer *_json ficam [FILTERED]; o id da propriedade continua legível' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter('service_account_json' => '{"private_key":"-----BEGIN PRIVATE KEY-----"}',
                               'credentials_json' => '{"x":1}', 'ga4_property_id' => '123456')
      expect(filtered['service_account_json']).to eq('[FILTERED]')
      expect(filtered['credentials_json']).to eq('[FILTERED]')
      expect(filtered['ga4_property_id']).to eq('123456')
    end
  end
end
