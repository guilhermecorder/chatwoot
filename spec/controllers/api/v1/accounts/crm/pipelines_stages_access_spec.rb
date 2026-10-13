require 'rails_helper'

# 🔐🧹 Auditoria 12/10 — Rodada 2 "Portas fechadas" (achados #19, #245, #299, #288):
# · funis e colunas só mudam com a concessão "Funis e colunas" (crm.funis, editar);
#   ver e listar continuam abertos ao time;
# · funil com cards não pode ser apagado (antes cascateava cards, colunas,
#   automações e histórico de uma vez);
# · "Excluir coluna" com cards vira UMA operação no servidor: move TODOS os
#   cards (não só os carregados na tela) e apaga a coluna numa transação, sem
#   disparar as automações da coluna de destino e sem inflar os indicadores.
RSpec.describe 'CEVICO funis e colunas (acesso + excluir coluna no servidor)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
  let(:origem) { Crm::Stage.create!(pipeline: pipeline, name: 'Novos contatos', position: 0) }
  let(:destino) { Crm::Stage.create!(pipeline: pipeline, name: 'Em contato', position: 1) }

  def perms!(hash)
    CrmSetting.find_or_create_by!(account: account).update!(agent_permissions: hash)
  end

  def new_card(stage, name)
    contact = create(:contact, account: account, name: name)
    Crm::Contact.create!(contact: contact, pipeline: stage.pipeline, stage: stage)
  end

  describe 'funis (pipelines)' do
    it 'atendente sem concessão vê e lista, mas não cria, renomeia nem apaga', :aggregate_failures do
      get "#{base}/pipelines/#{pipeline.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/pipelines", params: { pipeline: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      put "#{base}/pipelines/#{pipeline.id}", params: { pipeline: { name: 'Outro nome' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(pipeline.reload.name).to eq('Funil CEVICO')

      delete "#{base}/pipelines/#{pipeline.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Crm::Pipeline.exists?(pipeline.id)).to be(true)
    end

    it 'com a concessão crm.funis o atendente renomeia e apaga um funil vazio', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'crm.funis' => 'edit' } })

      put "#{base}/pipelines/#{pipeline.id}", params: { pipeline: { name: 'Renomeado' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(pipeline.reload.name).to eq('Renomeado')

      delete "#{base}/pipelines/#{pipeline.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(Crm::Pipeline.exists?(pipeline.id)).to be(false)
    end

    it 'nem o administrador apaga um funil que ainda tem cards (explica quantos)', :aggregate_failures do
      new_card(origem, 'Paciente A')
      new_card(origem, 'Paciente B')

      delete "#{base}/pipelines/#{pipeline.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('2 card(s)')
      expect(Crm::Pipeline.exists?(pipeline.id)).to be(true)
      expect(Crm::Contact.where(pipeline_id: pipeline.id).count).to eq(2)
    end
  end

  describe 'colunas (stages)' do
    let(:stages_base) { "#{base}/pipelines/#{pipeline.id}/stages" }

    it 'atendente sem concessão lista, mas não cria, edita, reordena nem apaga', :aggregate_failures do
      origem

      get stages_base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      post stages_base, params: { stage: { name: 'Nova' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      put "#{stages_base}/#{origem.id}", params: { stage: { name: 'Mudou' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(origem.reload.name).to eq('Novos contatos')

      post "#{stages_base}/reorder", params: { stage_ids: [origem.id] }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      delete "#{stages_base}/#{origem.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Crm::Stage.exists?(origem.id)).to be(true)

      delete "#{stages_base}/#{origem.id}/destroy_moving_to", params: { target_stage_id: destino.id },
                                                              headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Crm::Stage.exists?(origem.id)).to be(true)
    end

    it 'com a concessão crm.funis o atendente cria e reordena colunas', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'crm.funis' => 'edit' } })
      origem
      destino

      post stages_base, params: { stage: { name: 'Nova' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)

      post "#{stages_base}/reorder", params: { stage_ids: [destino.id, origem.id] }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(destino.reload.position).to eq(0)
      expect(origem.reload.position).to eq(1)
    end

    it 'apagar coluna simples continua recusando quando há cards' do
      new_card(origem, 'Paciente A')

      delete "#{stages_base}/#{origem.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Crm::Stage.exists?(origem.id)).to be(true)
    end

    # 🤖 revisão 12/10: a chave estrangeira dos robôs travava o apagar no
    # banco e virava erro 500 mudo — agora recusa explicando
    it 'coluna com robô de follow-up ou automação de mensagem não é apagada (explica)', :aggregate_failures do
      origem
      destino
      Crm::FollowupBot.create!(account: account, name: 'Cutucada', stage: origem,
                               steps: [{ 'delay_hours' => 3, 'message' => 'oi' }])
      inbox = create(:inbox, account: account)
      Crm::MessageAutomation.create!(account: account, name: 'Lembrete', inbox: inbox, trigger_stage: origem,
                                     template_params: { 'name' => 'lembrete' })

      delete "#{stages_base}/#{origem.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('1 robô(s) de follow-up').and include('1 automação(ões) de mensagem')

      card = new_card(origem, 'Paciente A')
      delete "#{stages_base}/#{origem.id}/destroy_moving_to", params: { target_stage_id: destino.id },
                                                              headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('robô')
      expect(Crm::Stage.exists?(origem.id)).to be(true)
      expect(card.reload.stage_id).to eq(origem.id)
    end

    it 'funil com robô de follow-up não é apagado (explica)', :aggregate_failures do
      Crm::FollowupBot.create!(account: account, name: 'Robô do funil', pipeline: pipeline,
                               steps: [{ 'delay_hours' => 3, 'message' => 'oi' }])

      delete "#{base}/pipelines/#{pipeline.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Este funil').and include('robô')
      expect(Crm::Pipeline.exists?(pipeline.id)).to be(true)
    end
  end

  # 🔐 revisão 12/10: crm.funis é nó SEM HERANÇA no catálogo — "CRM = editar"
  # (marcação própria, do papel ou o modelo antigo convertido) continua movendo
  # cards, mas NÃO cria, renomeia, reordena nem apaga funis e colunas
  describe 'CRM = editar não abre a estrutura (crm.funis não herda)' do
    let(:stages_base) { "#{base}/pipelines/#{pipeline.id}/stages" }

    # as 8 portas da estrutura, todas 403, e nada mudou no banco
    def estrutura_fechada!(user) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      headers = user.create_new_auth_token
      origem
      destino

      post "#{base}/pipelines", params: { pipeline: { name: 'Novo' } }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      put "#{base}/pipelines/#{pipeline.id}", params: { pipeline: { name: 'Outro' } }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "#{base}/pipelines/#{pipeline.id}", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post stages_base, params: { stage: { name: 'Nova' } }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      put "#{stages_base}/#{origem.id}", params: { stage: { name: 'Mudou' } }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{stages_base}/reorder", params: { stage_ids: [destino.id, origem.id] }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "#{stages_base}/#{destino.id}", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "#{stages_base}/#{origem.id}/destroy_moving_to", params: { target_stage_id: destino.id }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)

      expect(Crm::Pipeline.exists?(pipeline.id)).to be(true)
      expect(pipeline.reload.name).to eq('Funil CEVICO')
      expect(Crm::Stage.where(pipeline_id: pipeline.id).count).to eq(2)
      expect(origem.reload.name).to eq('Novos contatos')
    end

    it 'marcação própria CRM = editar: move card, mas a estrutura fica fechada', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'crm' => 'edit' } })
      estrutura_fechada!(agent)

      # o dia a dia continua: mover card é CRM = editar
      card = new_card(origem, 'Paciente A')
      put "#{base}/pipelines/#{pipeline.id}/contacts/#{card.id}",
          params: { stage_id: destino.id }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(card.reload.stage_id).to eq(destino.id)
    end

    it 'papel com CRM = editar: estrutura fechada', :aggregate_failures do
      perms!('roles' => [{ 'id' => 'r_vend', 'name' => 'Vendedor', 'tree' => { 'crm' => 'edit' } }],
             'role_by_user' => { agent.id.to_s => 'r_vend' })
      expect(Cevico::Access.for(account, agent).level('crm')).to eq('edit')
      estrutura_fechada!(agent)
    end

    it 'modelo antigo (menu com crm): estrutura fechada', :aggregate_failures do
      perms!('menu' => { agent.id.to_s => %w[crm conversation] })
      expect(Cevico::Access.for(account, agent).level('crm')).to eq('edit')
      estrutura_fechada!(agent)
    end

    it 'modelo antigo (lista de bloqueio vazia = tudo do dia a dia): estrutura fechada', :aggregate_failures do
      perms!(agent.id.to_s => [])
      expect(Cevico::Access.for(account, agent).level('crm')).to eq('edit')
      estrutura_fechada!(agent)
    end

    it 'só a marcação própria em crm.funis abre (mesmo com CRM = ver)', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'crm' => 'view', 'crm.funis' => 'edit' } })

      post "#{base}/pipelines", params: { pipeline: { name: 'Novo' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
    end
  end

  describe 'DELETE stages/:id/destroy_moving_to (#288)' do
    let(:stages_base) { "#{base}/pipelines/#{pipeline.id}/stages" }

    it 'move TODOS os cards da coluna para o destino e apaga a coluna de uma vez', :aggregate_failures do
      cards = Array.new(3) { |i| new_card(origem, "Paciente #{i}") }
      ja_la = new_card(destino, 'Já estava')

      delete "#{stages_base}/#{origem.id}/destroy_moving_to", params: { target_stage_id: destino.id },
                                                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('moved' => 3, 'target_stage_id' => destino.id)
      expect(Crm::Stage.exists?(origem.id)).to be(false)
      expect(cards.map { |c| c.reload.stage_id }).to all(eq(destino.id))
      expect(ja_la.reload.stage_id).to eq(destino.id)
      expect(Crm::Contact.where(pipeline_id: pipeline.id).count).to eq(4)
    end

    it 'não dispara as automações da coluna de destino e grava a entrada como carga (bulk)', :aggregate_failures do
      Crm::Automation.create!(stage: destino, name: 'Boas-vindas', trigger_type: 'card_entered',
                              action_type: 'webhook', delay_minutes: 0, action_config: {}, active: true)
      card = new_card(origem, 'Paciente A')
      # o que o update_columns de fato evita: o espelho da confirmação
      # (ConfirmationReflector — se o destino fosse "Consulta Confirmada",
      # confirmaria a consulta do paciente) e a entrada 'entered' que infla
      # os indicadores de "Entrou em…"
      expect(Crm::ConfirmationReflector).not_to receive(:from_stage)

      expect do
        delete "#{stages_base}/#{origem.id}/destroy_moving_to", params: { target_stage_id: destino.id },
                                                                headers: admin.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(CrmAutomationFireJob)

      expect(response).to have_http_status(:success)
      logs = card.stage_logs.order(:entered_at)
      expect(logs.find_by(stage_id: origem.id).left_at).to be_present
      entrada = logs.find_by(stage_id: destino.id)
      expect(entrada.event_type).to eq(Crm::StageLogBulk::BULK)
      expect(entrada.stage_name).to eq('Em contato')
      expect(card.stage_logs.where(stage_id: destino.id, event_type: Crm::StageLogBulk::ENTERED)).to be_empty
      expect(card.reload.stage_moved_at).to be_present
    end

    it 'recusa destino inválido (outra coluna de outro funil, a própria coluna ou vazio) sem mexer em nada', :aggregate_failures do
      outro_funil = Crm::Pipeline.create!(account: account, name: 'Parceiros')
      coluna_de_fora = Crm::Stage.create!(pipeline: outro_funil, name: 'Lá')
      card = new_card(origem, 'Paciente A')

      [coluna_de_fora.id, origem.id, nil].each do |alvo|
        delete "#{stages_base}/#{origem.id}/destroy_moving_to", params: { target_stage_id: alvo },
                                                                headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(Crm::Stage.exists?(origem.id)).to be(true)
      expect(card.reload.stage_id).to eq(origem.id)
    end

    it 'é tudo ou nada: se apagar a coluna falhar, nenhum card muda', :aggregate_failures do
      card = new_card(origem, 'Paciente A')
      destino
      # a coluna é achada pela associação do funil; forçar a falha no destroy! pede any_instance
      allow_any_instance_of(Crm::Stage).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed, 'travou') # rubocop:disable RSpec/AnyInstance

      delete "#{stages_base}/#{origem.id}/destroy_moving_to", params: { target_stage_id: destino.id },
                                                              headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(Crm::Stage.exists?(origem.id)).to be(true)
      expect(card.reload.stage_id).to eq(origem.id)
      expect(card.stage_logs.where(stage_id: destino.id)).to be_empty
    end
  end
end
