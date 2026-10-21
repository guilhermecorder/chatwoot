require 'rails_helper'

# 🔒 Rodada 4 da auditoria — "Dados que não se perdem" (achados #351, #413, #414):
# os controllers que gravavam agenda_config/ai_config INTEIROS (lê → altera →
# grava, sem trava) agora passam pelo Cevico::SettingMerge e gravam só as
# chaves recebidas. O cenário de cada achado vira teste: alguém (um job ou um
# colega) grava no MESMO crm_settings entre a leitura e a gravação do
# controller — e nada do que esse alguém escreveu pode sumir.
RSpec.describe 'Rodada 4 — controllers gravam agenda_config/ai_config pelo SettingMerge', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  before { CrmSetting.create!(account: account, agenda_config: { 'base' => 1 }, ai_config: {}) }

  # sempre a linha FRESCA do banco (um `let` memorizado devolveria a foto velha
  # de antes da requisição — o mesmo erro que esta rodada conserta no código)
  def settings
    CrmSetting.find_by!(account: account)
  end

  # Simula o colega/job que grava no MESMO crm_settings logo depois de o
  # controller carregar a linha — exatamente a janela do padrão antigo
  # ("lê → altera → grava"): o controller já tem a foto velha na mão.
  def alguem_grava_no_meio!(column, key, value, finder: :find_or_create_by!)
    done = false
    allow(CrmSetting).to receive(finder).and_wrap_original do |original, *args, **kwargs, &blk|
      row = original.call(*args, **kwargs, &blk)
      if row && !done
        done = true
        outro = CrmSetting.find(row.id)
        outro.update!(column => (outro[column] || {}).merge(key => value))
      end
      row
    end
  end

  describe 'POST settings/update_agenda (#351 — Modo edição do Meu Painel)' do
    let(:url) { "#{base}/settings/update_agenda" }

    it 'o arrasto no Modo edição não apaga o recorde que o painel gravou no meio-tempo', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'panel_records', { 'agendamento.leads.day' => { 'best' => 9 } })

      post url, params: { kpi_layout: { agendamento: { order: ['leads'] } } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['panel_records']).to eq('agendamento.leads.day' => { 'best' => 9 })
      expect(cfg['base']).to eq(1)
      expect(cfg.dig('kpi_layout', 'agendamento', 'order')).to eq(['leads'])
    end

    it 'a tela manda só o painel editado e o servidor mescla painel a painel — o painel do colega fica', :aggregate_failures do
      settings.update!(agenda_config: settings.agenda_config.merge(
        'kpi_layout' => { 'agendamento' => { 'order' => ['a'] }, 'conducao' => { 'order' => ['c'] } }
      ))

      post url, params: { kpi_layout: { conducao: { order: ['c2'] } } }, headers: headers, as: :json

      layout = settings.agenda_config['kpi_layout']
      expect(layout.keys).to contain_exactly('agendamento', 'conducao')
      expect(layout.dig('agendamento', 'order')).to eq(['a'])
      expect(layout.dig('conducao', 'order')).to eq(['c2'])
      expect(response.parsed_body.dig('kpi_layout', 'agendamento', 'order')).to eq(['a']) # a resposta traz o quadro inteiro
    end

    it 'painel enviado como null apaga só aquele painel ("restaurar o padrão" dos blocos)' do
      settings.update!(agenda_config: settings.agenda_config.merge(
        'block_layout' => { 'agendamento' => { 'top' => ['x'] }, 'gestor' => { 'top' => ['y'] } }
      ))

      post url, params: { block_layout: { agendamento: nil } }, headers: headers, as: :json

      expect(settings.agenda_config['block_layout']).to eq('gestor' => { 'top' => ['y'] })
    end

    it 'paleta: null ou entrada vazia some só do painel enviado' do
      settings.update!(agenda_config: settings.agenda_config.merge(
        'panel_palettes' => { 'agendamento' => { 'mode' => 'fixed', 'key' => 'bondi' }, 'gestor' => { 'mode' => 'fixed', 'key' => 'bondi' },
                              'cirurgia' => { 'mode' => 'fixed', 'key' => 'bondi' } }
      ))

      post url, params: { panel_palettes: { agendamento: nil, gestor: { mode: 'day' } } }, headers: headers, as: :json

      expect(settings.agenda_config['panel_palettes'].keys).to eq(['cirurgia'])
    end

    it 'só as chaves recebidas vão para o banco (o resto nem é reescrito)' do
      expect(Cevico::SettingMerge).to receive(:merge!).with(instance_of(CrmSetting), :agenda_config).and_wrap_original do |m, *args, &blk|
        m.call(*args) do |fresh|
          keys_before = fresh.keys
          out = blk.call(fresh)
          expect(out.keys - keys_before).to eq(['theme'])
          out
        end
      end

      post url, params: { theme: 'santorini' }, headers: headers, as: :json

      expect(settings.agenda_config).to eq('base' => 1, 'theme' => 'santorini')
    end

    describe 'cards de indicador do "+" (custom_kpis_patch)' do
      let(:card) { ->(id, label) { { 'id' => id, 'label' => label, 'expr' => 'leads' } } }

      before do
        settings.update!(agenda_config: settings.agenda_config.merge(
          'custom_kpis' => [card.call('k1', 'Do admin A'), card.call('agendamento_p_x', 'Modelo antigo')]
        ))
      end

      it 'criar um card não apaga o card que o colega criou no meio-tempo', :aggregate_failures do
        colega = settings.agenda_config['custom_kpis'] + [card.call('k2', 'Do admin B')]
        alguem_grava_no_meio!(:agenda_config, 'custom_kpis', colega)

        post url, params: { custom_kpis_patch: { upsert: [card.call('k3', 'Meu novo')] } }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(settings.agenda_config['custom_kpis'].pluck('id')).to eq(%w[k1 agendamento_p_x k2 k3])
        expect(response.parsed_body['custom_kpis'].pluck('id')).to include('k2', 'k3')
      end

      it 'editar troca pelo id; apagar tira só aquele; modelo pronto troca só os cards do prefixo', :aggregate_failures do
        post url, params: { custom_kpis_patch: { upsert: [card.call('k1', 'Renomeado')] } }, headers: headers, as: :json
        expect(settings.agenda_config['custom_kpis'].first['label']).to eq('Renomeado')

        post url, params: { custom_kpis_patch: { remove_prefix: 'agendamento_p_', upsert: [card.call('agendamento_p_y', 'Modelo novo')] } },
                  headers: headers, as: :json
        expect(settings.agenda_config['custom_kpis'].pluck('id')).to eq(%w[k1 agendamento_p_y])

        post url, params: { custom_kpis_patch: { remove: ['k1'] } }, headers: headers, as: :json
        expect(settings.agenda_config['custom_kpis'].pluck('id')).to eq(%w[agendamento_p_y])
      end
    end
  end

  describe 'POST settings/update_ai (#413)' do
    it 'salvar um agente não apaga o alerta do Radar nem o estado da Colheitadeira gravados no meio-tempo', :aggregate_failures do
      settings.update!(ai_config: { 'agents' => { 'sales' => { 'enabled' => true } }, 'harvest_state' => { 'sent' => [1] } })
      alguem_grava_no_meio!(:ai_config, 'opportunity_state', { 'alerts' => [{ 'id' => 1 }] })

      post "#{base}/settings/update_ai", params: { agents: { nps: { enabled: true } } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ai = settings.ai_config
      expect(ai['opportunity_state']).to eq('alerts' => [{ 'id' => 1 }])
      expect(ai['harvest_state']).to eq('sent' => [1])
      expect(ai.dig('agents', 'sales', 'enabled')).to be(true)
      expect(ai.dig('agents', 'nps', 'enabled')).to be(true)
    end
  end

  describe 'as outras ações de Configurações que gravam agenda_config (#413)' do
    it 'update_oftalmofacil mexe só na chave oftalmofacil e mantém o cursor do sync e as chaves irmãs', :aggregate_failures do
      settings.update!(agenda_config: settings.agenda_config.merge('oftalmofacil' => { 'cursor' => 5, 'db_host' => 'a' }))
      alguem_grava_no_meio!(:agenda_config, 'windows', ['seg'])

      post "#{base}/settings/update_oftalmofacil", params: { db_host: 'b' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['windows']).to eq(['seg'])
      expect(cfg.dig('oftalmofacil', 'cursor')).to eq(5)
      expect(cfg.dig('oftalmofacil', 'db_host')).to eq('b')
    end

    it 'update_calls mexe só na chave calls', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'birthdays', { 'x' => 1 })

      post "#{base}/settings/update_calls", params: { permission_message: 'Podemos ligar?' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['birthdays']).to eq('x' => 1)
      expect(cfg.dig('calls', 'permission_message')).to eq('Podemos ligar?')
    end

    it 'update_price_table mexe só na tabela de preços', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'nps_survey_state', { 'sent' => [3] })

      # Rodada 5 (#401): a unidade virou obrigatória — sem ela a tabela é recusada (422)
      post "#{base}/settings/update_price_table", params: { items: [{ name: 'Lente', price: 10, unit: 'por_olho' }] }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['nps_survey_state']).to eq('sent' => [3])
      expect(cfg.dig('price_table', 'items', 0, 'name')).to eq('Lente')
    end
  end

  describe 'Painel do empresário e Estratégia (#413/#414)' do
    let(:url) { "#{base}/strategy/save_business_board" }
    let(:board) { { kanban: { todo: [{ id: 'k1', text: 'Nova campanha' }] } } }

    it 'save_business_board grava só o quadro e mantém o que o job escreveu no meio-tempo', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'appointment_reminders_state', { 'sent' => [1] })

      post url, params: { business: board }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['appointment_reminders_state']).to eq('sent' => [1])
      expect(cfg.dig('business_board', 'kanban', 'todo', 0, 'text')).to eq('Nova campanha')
      expect(cfg.dig('business_board', 'updated_at')).to be_present
      expect(response.parsed_body.dig('business', 'updated_at')).to eq(cfg.dig('business_board', 'updated_at'))
    end

    it 'recusa com 409 quando o quadro gravado é mais novo que o que a tela carregou — e devolve o quadro atual', :aggregate_failures do
      post url, params: { business: board }, headers: headers, as: :json
      v1 = response.parsed_body.dig('business', 'updated_at')

      # aba B (carregou v1) salva um objetivo
      post url, params: { business: board.merge(objectives: ['Dobrar cirurgias']), version: v1 }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      v2 = response.parsed_body.dig('business', 'updated_at')
      expect(v2).not_to eq(v1)

      # aba A (ainda em v1) tenta salvar por cima
      post url, params: { business: board.merge(objectives: ['Outra coisa']), version: v1 }, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      body = response.parsed_body
      expect(body['conflict']).to be(true)
      expect(body.dig('business', 'objectives', 0, 'text')).to eq('Dobrar cirurgias')
      expect(body.dig('business', 'updated_at')).to eq(v2)
      expect(settings.agenda_config.dig('business_board', 'objectives', 0, 'text')).to eq('Dobrar cirurgias') # nada foi apagado

      # com a versão atual na mão, salva normalmente
      post url, params: { business: board.merge(objectives: ['Agora sim']), version: v2 }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(settings.agenda_config.dig('business_board', 'objectives', 0, 'text')).to eq('Agora sim')
    end

    it 'quadro antigo sem versão: duas abas mandando version nula — a segunda leva 409', :aggregate_failures do
      settings.update!(agenda_config: settings.agenda_config.merge('business_board' => { 'objectives' => [{ 'id' => 'o1', 'text' => 'Antigo' }] }))

      # aba A (carregou o quadro sem updated_at) salva primeiro
      post url, params: { business: board.merge(objectives: ['Da aba A']), version: nil }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      # aba B (também carregou sem updated_at) tenta salvar por cima
      post url, params: { business: board.merge(objectives: ['Da aba B']), version: nil }, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(settings.agenda_config.dig('business_board', 'objectives', 0, 'text')).to eq('Da aba A')
    end

    it 'tela sem versão (de antes desta rodada) continua salvando' do
      post url, params: { business: board }, headers: headers, as: :json
      post url, params: { business: board.merge(objectives: ['Sem versão']) }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(settings.agenda_config.dig('business_board', 'objectives', 0, 'text')).to eq('Sem versão')
    end

    it 'save_processes grava só os processos' do
      alguem_grava_no_meio!(:agenda_config, 'birthdays', { 'x' => 1 })

      post "#{base}/strategy/save_processes", params: { processes: [{ name: 'Jornada' }] }, headers: headers, as: :json

      cfg = settings.agenda_config
      expect(cfg['birthdays']).to eq('x' => 1)
      expect(cfg['process_designs'].pluck('name')).to eq(['Jornada'])
    end
  end

  describe 'Jornada, Metas, Páginas, Fechamento, Médicos e Radar (#413)' do
    it 'journey_messages#update_settings mexe só em journey', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'panel_records', { 'a' => 1 })

      post "#{base}/journey_messages/update_settings", params: { daily_cap: 120 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['panel_records']).to eq('a' => 1)
      expect(cfg.dig('journey', 'daily_cap')).to eq(120)
    end

    it 'goal_plans#update_routines mexe só nas rotinas', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'scheduler_log', ['x'])

      post "#{base}/goal_plans/update_routines", params: { routines: ['Abrir a clínica'] }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['scheduler_log']).to eq(['x'])
      expect(cfg['team_routines']).to eq(['Abrir a clínica'])
    end

    it 'pages_dashboards#save_funnel_sources mexe só nas fontes', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'insight_log', ['x'])

      post "#{base}/pages_dashboard/save_funnel_sources", params: { funnel_sources: { '1' => ['meta'] } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['insight_log']).to eq(['x'])
      expect(cfg['funnel_sources']).to eq('1' => ['meta'])
    end

    it 'closing_tools#update_script mexe só no script', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'birthdays', { 'x' => 1 })

      post "#{base}/closing_tools/update_script", params: { script: 'Olá, tudo bem?' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['birthdays']).to eq('x' => 1)
      expect(cfg['closing_script']).to eq('Olá, tudo bem?')
    end

    it 'doctors_dashboards#save_profiles mexe só nos perfis', :aggregate_failures do
      alguem_grava_no_meio!(:agenda_config, 'birthdays', { 'x' => 1 })

      post "#{base}/doctors_dashboard/save_profiles", params: { profiles: { 'Dr. X' => { status: 'ativo' } } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      cfg = settings.agenda_config
      expect(cfg['birthdays']).to eq('x' => 1)
      expect(cfg.dig('doctor_profiles', 'Dr. X', 'status')).to eq('ativo')
    end

    it 'home#toggle_radar vira o interruptor sem apagar os alertas que o Radar gravou no meio-tempo', :aggregate_failures do
      alguem_grava_no_meio!(:ai_config, 'opportunity_state', { 'alerts' => [{ 'id' => 1 }] }, finder: :find_by)

      post "#{base}/home/toggle_radar", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ai = settings.ai_config
      expect(ai.dig('agents', 'opportunity', 'enabled')).to be(true)
      expect(ai.dig('opportunity_state', 'alerts')).to eq([{ 'id' => 1 }])
      expect(ai.dig('opportunity_state', 'manual_log').size).to eq(1)
    end
  end
end
