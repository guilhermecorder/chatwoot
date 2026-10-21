require 'rails_helper'

# 🔐 Auditoria 10/2026 — Rodada 2 "Portas fechadas" (achados #18/#130/#315,
# #147, #131, #148, #307): dono da tarefa, Lixeira sem desvio, consulta sem
# unidade e tarefa ⚠️ visíveis à equipe, respostas de formulário só com
# acesso clínico
RSpec.describe 'Tasks — portas fechadas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Gui') }
  let(:agent_user) { create(:user, account: account, role: :agent, name: 'Nat') }
  let(:colega) { create(:user, account: account, role: :agent, name: 'Bia') }
  let(:base) { "/api/v1/accounts/#{account.id}/tasks" }
  let(:contact) { create(:contact, account: account, name: 'Maria', phone_number: '+5511999990000') }

  # a porta "tarefas" é fechada por padrão: os dois atendentes recebem editar
  before do
    CrmSetting.create!(account: account, agent_permissions: {
                         'tree' => { agent_user.id.to_s => { 'tarefas' => 'edit' }, colega.id.to_s => { 'tarefas' => 'edit' } }
                       })
  end

  def card_de(user, attrs = {})
    Task.create!({ account: account, creator: user, assignee: user, title: 'Ligar para o laboratório' }.merge(attrs))
  end

  describe 'dono da tarefa (achados #18/#130/#315)' do
    it 'atendente não edita, não apaga nem comenta card pessoal de outra pessoa', :aggregate_failures do
      alheio = card_de(colega)

      put "#{base}/#{alheio.id}", params: { title: 'hack', assignee_id: agent_user.id }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(alheio.reload).to have_attributes(title: 'Ligar para o laboratório', assignee_id: colega.id)

      delete "#{base}/#{alheio.id}", headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Task.exists?(alheio.id)).to be(true)

      post "#{base}/#{alheio.id}/comment", params: { text: 'oi' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'card 🐞 do admin (criado para ele) continua fora do alcance do atendente' do
      bug = card_de(admin, title: '🐞 Bug na Agenda')
      put "#{base}/#{bug.id}", params: { status: 'done' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(bug.reload.status).to eq('todo')
    end

    it 'quem criou, o responsável e o admin seguem editando e apagando', :aggregate_failures do
      meu = card_de(agent_user)
      put "#{base}/#{meu.id}", params: { status: 'done' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      para_mim = card_de(colega, assignee: agent_user)
      put "#{base}/#{para_mim.id}", params: { status: 'doing' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      delete "#{base}/#{para_mim.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it 'agendamento é da clínica toda: atendente confirma consulta de outra pessoa, mesmo sem unidade' do
      consulta = Task.create!(account: account, creator: admin, title: 'Consulta: Maria', task_type: 'consulta', due_at: 1.day.from_now)
      put "#{base}/#{consulta.id}", params: { confirmed: true }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(consulta.reload.confirmed_at).to be_present
    end

    # decisão pendente com o Guilherme: comentar/anexar em agendamento para a
    # equipe toda. Até lá fica como sempre foi: criador, responsável e admin.
    it 'comentar em consulta de outra pessoa continua fechado (lado mais fechado até a decisão)' do
      consulta = Task.create!(account: account, creator: admin, title: 'Consulta: Maria', task_type: 'consulta', due_at: 1.day.from_now)
      post "#{base}/#{consulta.id}/comment", params: { text: 'oi' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'começar o título com ⚠️ pela tela NÃO abre a porta: card da colega segue pessoal', :aggregate_failures do
      # a colega cria pela API (carimbo 'equipe'), como acontece na tela
      post base, params: { title: '⚠️ Conferir estoque' }, headers: colega.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      alheio = Task.find(response.parsed_body['id'])
      expect(alheio.cevico_born_via).to eq('equipe')

      put "#{base}/#{alheio.id}", params: { status: 'done' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "#{base}/#{alheio.id}", headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      get base, headers: agent_user.create_new_auth_token, as: :json
      expect(response.parsed_body.pluck('id')).not_to include(alheio.id)

      # renomear o próprio card (criado pela tela) para ⚠️ também não vira "da clínica toda"
      post base, params: { title: 'Ligar para o laboratório' }, headers: agent_user.create_new_auth_token, as: :json
      meu = Task.find(response.parsed_body['id'])
      put "#{base}/#{meu.id}", params: { title: '⚠️ Urgente' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      put "#{base}/#{meu.id}", params: { status: 'done' }, headers: colega.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'linha antiga sem carimbo: ⚠️ criada em nome do admin é da equipe; de atendente, não', :aggregate_failures do
      antiga_robo = Task.create!(account: account, creator: admin, title: '⚠️ Confirmar consulta: Zé', task_type: 'Atendimento', contact: contact)
      antiga_robo.update_column(:cevico_born_via, nil) # rubocop:disable Rails/SkipsModelValidations
      antiga_pessoal = card_de(colega, title: '⚠️ Lembrete meu')
      antiga_pessoal.update_column(:cevico_born_via, nil) # rubocop:disable Rails/SkipsModelValidations

      get base, headers: agent_user.create_new_auth_token, as: :json
      ids = response.parsed_body.pluck('id')
      expect(ids).to include(antiga_robo.id)
      expect(ids).not_to include(antiga_pessoal.id)
      expect(antiga_robo.reload.shared_with_team?).to be(true)
      expect(antiga_pessoal.reload.shared_with_team?).to be(false)
    end
  end

  describe 'Lixeira sem desvio (achado #147)' do
    let(:consulta) do
      Task.create!(account: account, creator: admin, title: 'Consulta: Maria', task_type: 'consulta', unit: 'tatuape', due_at: 1.day.from_now)
    end

    it 'atendente não troca a consulta por card para apagar de vez; o Excluir continua indo para a Lixeira', :aggregate_failures do
      put "#{base}/#{consulta.id}", params: { task_type: 'ligacao' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(consulta.reload.task_type).to eq('consulta')

      delete "#{base}/#{consulta.id}", headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(Task.exists?(consulta.id)).to be(true)
      expect(consulta.reload.canceled_by).to eq(agent_user)
    end

    it 'agendamento antigo só com unidade e data (sem tipo) também vai para a Lixeira, nunca some', :aggregate_failures do
      antigo = Task.create!(account: account, creator: admin, title: 'Maria', task_type: nil, unit: 'tatuape', due_at: 1.day.from_now)

      delete "#{base}/#{antigo.id}", headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(antigo.reload).to have_attributes(canceled_by: agent_user, cancel_reason: 'excluida_agenda')

      delete "#{base}/#{antigo.id}", params: { force: 1 }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Task.exists?(antigo.id)).to be(true)
    end

    it 'card ⚠️ do robô excluído pela equipe guarda rastro (sai do quadro, fica no banco com quem apagou)', :aggregate_failures do
      revisao = Crm::Stamp.with(via: 'robo') do
        Task.create!(account: account, creator: admin, title: '⚠️ Confirmar consulta: Maria', task_type: 'Atendimento', contact: contact)
      end

      delete "#{base}/#{revisao.id}", headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(revisao.reload).to have_attributes(canceled_by: agent_user, cancel_reason: 'excluida_tarefas')
      expect(revisao.archived_at).to be_present

      get base, headers: agent_user.create_new_auth_token, as: :json
      expect(response.parsed_body.pluck('id')).not_to include(revisao.id)

      delete "#{base}/#{revisao.id}", params: { force: 1 }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "#{base}/#{revisao.id}", params: { force: 1 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it 'nem o caminho contrário: card pessoal não vira consulta pela mão do atendente' do
      card = card_de(agent_user)
      put "#{base}/#{card.id}", params: { task_type: 'consulta', due_at: 1.day.from_now.iso8601 },
                                headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(card.reload.task_type).to be_nil
    end

    it 'trocar entre tipos de card continua livre; consulta → cirurgia cobra a Agenda cirúrgica; admin muda o que quiser',
       :aggregate_failures do
      card = card_de(agent_user, task_type: 'Atendimento')
      put "#{base}/#{card.id}", params: { task_type: 'Follow-up' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(card.reload.task_type).to eq('Follow-up')

      CrmSetting.find_by!(account: account).update!(agent_permissions: {
                                                      'tree' => { agent_user.id.to_s => { 'tarefas' => 'edit', 'agenda.cirurgias' => 'view' } }
                                                    })
      put "#{base}/#{consulta.id}", params: { task_type: 'cirurgia' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(consulta.reload.task_type).to eq('consulta')

      put "#{base}/#{consulta.id}", params: { task_type: 'ligacao' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(consulta.reload.task_type).to eq('ligacao')
    end
  end

  describe 'o que o atendente vê (achados #131/#148)' do
    it 'consulta sem unidade e tarefa ⚠️ de revisão aparecem; card pessoal de outra pessoa não', :aggregate_failures do
      sem_unidade = Task.create!(account: account, creator: admin, title: 'Consulta: Maria', task_type: 'consulta', due_at: 1.day.from_now)
      revisao = Task.create!(account: account, creator: admin, title: '⚠️ Confirmar consulta: Maria', task_type: 'Atendimento', contact: contact)
      alheio = card_de(colega)

      get base, headers: agent_user.create_new_auth_token, as: :json
      ids = response.parsed_body.pluck('id')
      expect(ids).to include(sem_unidade.id, revisao.id)
      expect(ids).not_to include(alheio.id)
    end

    it 'a tarefa de revisão da IA nasce como card do quadro (sem data) e a equipe consegue concluir', :aggregate_failures do
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      result = { found: false, name: 'Maria', phone: '+5511999990000', starts_at: nil, unit: '', procedure: '', doctor: '',
                 notes: '', cancel: false, confirmation: false, model: 'x' }
      allow(Crm::AppointmentExtractionService).to receive(:new)
        .and_return(instance_double(Crm::AppointmentExtractionService, call: result))

      Crm::AppointmentApplier.call(account: account, contact: contact, conversation: conversation)
      task = account.tasks.find_by!('title LIKE ?', '⚠️ Confirmar consulta%')
      expect(task.task_type).to eq('Atendimento')
      expect(task.appointment?).to be(false)
      expect(task.cevico_born_via).to eq('robo')
      expect(account.tasks.board_cards).to include(task)

      put "#{base}/#{task.id}", params: { status: 'done' }, headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(task.reload.status).to eq('done')
    end

    it 'IA achou a unidade mas não a data: a tarefa de revisão continua card (unidade vai no texto) e a equipe vê', :aggregate_failures do
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      result = { found: false, name: 'Maria', phone: '+5511999990000', starts_at: nil, unit: 'tatuape', procedure: '', doctor: '',
                 notes: '', cancel: false, confirmation: false, model: 'x' }
      allow(Crm::AppointmentExtractionService).to receive(:new)
        .and_return(instance_double(Crm::AppointmentExtractionService, call: result))

      Crm::AppointmentApplier.call(account: account, contact: contact, conversation: conversation)
      task = account.tasks.find_by!('title LIKE ?', '⚠️ Confirmar consulta%')
      expect(task.unit).to be_nil
      expect(task.description).to include('Unidade citada: Tatuapé')
      expect(account.tasks.board_cards).to include(task)

      get base, headers: agent_user.create_new_auth_token, as: :json
      row = response.parsed_body.find { |t| t['id'] == task.id }
      expect(row).to be_present
      expect(row['unit']).to be_nil # o quadro de Tarefas (isAppointmentTask) não esconde
    end
  end

  describe 'respostas do formulário na lista do dia (achado #307)' do
    let(:form) { Crm::Form.create!(account: account, name: 'Pré-consulta', questions: [], funnel_stats: {}, ai_insight: {}) }
    let!(:consulta) do
      Task.create!(account: account, creator: admin, title: 'Consulta: Maria', task_type: 'consulta', unit: 'tatuape',
                   contact: contact, due_at: 1.day.from_now)
    end

    before do
      Crm::FormResponse.create!(account: account, form: form, contact: contact, completed_at: 1.hour.ago,
                                answers: [{ 'id' => 'q1', 'label' => 'Usa colírio?', 'type' => 'text', 'value' => 'Sim, todo dia' }])
    end

    def details(user, ids)
      get "#{base}/agenda_details", params: { ids: ids.join(',') }, headers: user.create_new_auth_token, as: :json
      response.parsed_body
    end

    it 'atendente sem acesso clínico recebe o formulário sem as respostas (com o cadeado no título)', :aggregate_failures do
      row = details(agent_user, [consulta.id]).first
      expect(row['form_response']).to include('restricted' => true, 'answers' => [])
      expect(row['form_response']['form']).to include('🔒')
      expect(response.body).not_to include('todo dia')
    end

    it 'médico marcado, equipe com team_view e admin leem as respostas', :aggregate_failures do
      expect(details(admin, [consulta.id]).first['form_response']['answers'].first['value']).to eq('Sim, todo dia')

      CrmSetting.find_by!(account: account)
                .update!(agenda_config: { 'clinical_access' => { 'doctor_user_ids' => [agent_user.id], 'team_view' => false } })
      expect(details(agent_user, [consulta.id]).first['form_response']).to include('restricted' => false)
      expect(details(colega, [consulta.id]).first['form_response']).to include('restricted' => true)

      CrmSetting.find_by!(account: account).update!(agenda_config: { 'clinical_access' => { 'doctor_user_ids' => [], 'team_view' => true } })
      expect(details(colega, [consulta.id]).first['form_response']['answers'].size).to eq(1)
    end

    it 'a lista do dia obedece à mesma visibilidade do index: card pessoal de outra pessoa não vem' do
      alheio = card_de(colega, contact: contact)
      expect(details(agent_user, [alheio.id, consulta.id]).pluck('task_id')).to eq([consulta.id])
    end
  end

  # 🐢 Rodada 7 "Fôlego" (achados #149/#301/#316): a lista vem por período,
  # o valor das cirurgias sai em lote e a barra lateral pede só a contagem
  describe 'lista por período e sem N+1 (achados #149/#301/#316)' do
    def ids_de(user, params = {})
      get base, params: params, headers: user.create_new_auth_token
      expect(response).to have_http_status(:ok)
      response.parsed_body.pluck('id')
    end

    def consulta_em(at, attrs = {})
      Task.create!({ account: account, creator: admin, title: 'Consulta: Maria', task_type: 'consulta', unit: 'tatuape', due_at: at }.merge(attrs))
    end

    it 'sem parâmetro: janela de −365/+365 dias, cards do quadro sempre e a Lixeira dos últimos 60 dias', :aggregate_failures do
      recente = consulta_em(10.days.ago)
      futura = consulta_em(200.days.from_now)
      do_ano = consulta_em(200.days.ago) # mês de 6+ meses atrás continua aparecendo na Agenda
      antiga = consulta_em(400.days.ago)
      longe = consulta_em(400.days.from_now)
      card_sem_data = card_de(admin)
      card_vencido_antigo = card_de(admin, due_at: 500.days.ago)
      cancelada_na_janela = consulta_em(5.days.from_now, canceled_at: 1.day.ago)
      lixeira_antiga = consulta_em(450.days.ago, canceled_at: 3.days.ago, cancel_reason: 'excluida_agenda')
      cancelada_velha = consulta_em(450.days.ago, canceled_at: 90.days.ago)

      ids = ids_de(admin)
      expect(ids).to include(recente.id, futura.id, do_ano.id, card_sem_data.id, card_vencido_antigo.id, cancelada_na_janela.id,
                             lixeira_antiga.id)
      expect(ids).not_to include(antiga.id, longe.id, cancelada_velha.id)
    end

    it 'from/to (ou days) trazem o período pedido; canceled=0 tira e canceled=1 só canceladas', :aggregate_failures do
      antiga = consulta_em(200.days.ago)
      hoje = consulta_em(1.hour.from_now)
      cancelada = consulta_em(2.hours.from_now, canceled_at: 1.hour.ago)
      card = card_de(admin)

      expect(ids_de(admin, from: 210.days.ago.to_date.iso8601, to: 190.days.ago.to_date.iso8601)).to include(antiga.id, card.id)
      expect(ids_de(admin, from: 210.days.ago.to_date.iso8601, to: 190.days.ago.to_date.iso8601)).not_to include(hoje.id)
      expect(ids_de(admin, days: 300)).to include(antiga.id, hoje.id)
      expect(ids_de(admin, canceled: 0)).to include(hoje.id)
      expect(ids_de(admin, canceled: 0)).not_to include(cancelada.id)
      expect(ids_de(admin, canceled: 1)).to eq([cancelada.id])
    end

    it 'board=1 (quadro de Tarefas) traz só os cards, nunca os agendamentos', :aggregate_failures do
      consulta = consulta_em(1.day.from_now)
      card = card_de(admin, due_at: 400.days.ago)
      expect(ids_de(admin, board: 1)).to eq([card.id])
      expect(ids_de(admin, board: 1)).not_to include(consulta.id)
    end

    it 'light=1 devolve só o que o Meu Painel usa (sem observação, comentários, anexos e valores)', :aggregate_failures do
      consulta_em(1.day.from_now, description: 'Convênio X — observação longa', comments: [{ 'text' => 'oi' }])
      get base, params: { light: 1 }, headers: admin.create_new_auth_token
      row = response.parsed_body.first
      expect(row).to include('light' => true, 'task_type' => 'consulta', 'unit' => 'tatuape')
      expect(row.keys).not_to include('description', 'comments', 'attachments', 'charges', 'price')
      expect(response.body).not_to include('observação longa')
    end

    it 'a janela respeita a visibilidade: card pessoal de outra pessoa continua fora', :aggregate_failures do
      alheio = card_de(colega)
      meu = card_de(agent_user)
      ids = ids_de(agent_user, light: 1, canceled: 0, from: 35.days.ago.iso8601)
      expect(ids).to include(meu.id)
      expect(ids).not_to include(alheio.id)
    end

    describe 'valor das cirurgias para o admin' do
      let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil', position: 1) }
      let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia agendada') }

      def cirurgia_de(nome, valor)
        paciente = create(:contact, account: account, name: nome, phone_number: "+55119#{rand(10_000_000..99_999_999)}")
        Crm::Contact.create!(contact: paciente, pipeline: pipeline, stage: stage, value: valor)
        Task.create!(account: account, creator: admin, title: "Cirurgia: #{nome}", task_type: 'cirurgia', contact: paciente,
                     due_at: 3.days.from_now)
      end

      def consultas_ao_crm(&)
        count = 0
        callback = lambda { |*, payload|
          count += 1 if payload[:sql].to_s.include?('crm_contacts') || payload[:sql].to_s.include?('regexp_replace')
        }
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
        count
      end

      it 'sai em UMA consulta para a lista toda (não cresce com o número de cirurgias)', :aggregate_failures do
        primeira = cirurgia_de('Ana', 9000)
        uma = consultas_ao_crm { get base, headers: admin.create_new_auth_token }
        expect(response.parsed_body.find { |t| t['id'] == primeira.id }['crm_value'].to_f).to eq(9000.0)

        3.times { |i| cirurgia_de("Paciente #{i}", 5000 + i) }
        quatro = consultas_ao_crm { get base, headers: admin.create_new_auth_token }
        expect(quatro).to eq(uma)
        expect(quatro).to be <= 1
        expect(response.parsed_body.count { |t| t['crm_value'].present? }).to eq(4)
      end

      it 'na lista nunca procura o paciente pelo telefone (cirurgia sem paciente ligado fica sem valor)', :aggregate_failures do
        sem_link = Task.create!(account: account, creator: admin, title: 'Cirurgia: Zé', task_type: 'cirurgia',
                                phone: contact.phone_number, due_at: 2.days.from_now)
        expect(Task).not_to receive(:match_contact)
        get base, headers: admin.create_new_auth_token
        row = response.parsed_body.find { |t| t['id'] == sem_link.id }
        expect(row).to be_present
        expect(row['crm_value']).to be_nil
      end

      it 'atendente não recebe o valor da cirurgia', :aggregate_failures do
        cirurgia = cirurgia_de('Bea', 7000)
        get base, headers: agent_user.create_new_auth_token
        row = response.parsed_body.find { |t| t['id'] == cirurgia.id }
        expect(row).to be_present
        expect(row.keys).not_to include('crm_value')
      end
    end

    describe 'contagem do badge de Tarefas (tasks/alert_count)' do
      it 'conta só os cards do quadro esperando a pessoa: a fazer, atrasados ou vencendo em 24 h', :aggregate_failures do
        card_de(agent_user) # a fazer
        card_de(agent_user, status: :doing, due_at: 2.days.ago) # atrasado
        card_de(agent_user, status: :doing, due_at: 5.hours.from_now) # vence hoje
        card_de(agent_user, status: :doing, due_at: 5.days.from_now) # longe — não conta
        card_de(agent_user, status: :done, due_at: 2.days.ago) # concluído — não conta
        card_de(colega) # de outra pessoa — não conta
        Task.create!(account: account, creator: admin, assignee: agent_user, title: 'Consulta: Maria', task_type: 'consulta',
                     unit: 'tatuape', due_at: 1.hour.from_now) # agendamento — não conta (item 305)

        get "#{base}/alert_count", headers: agent_user.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('count' => 3)
      end

      it 'segue a mesma porta da lista: sem Tarefas e sem Agenda, nem a contagem', :aggregate_failures do
        sem_porta = create(:user, account: account, role: :agent, name: 'Leo')
        CrmSetting.find_by!(account: account).update!(agent_permissions: {
                                                        'tree' => { sem_porta.id.to_s => { 'tarefas' => 'none', 'agenda' => 'none' } }
                                                      })
        get base, headers: sem_porta.create_new_auth_token
        lista = response.status
        get "#{base}/alert_count", headers: sem_porta.create_new_auth_token
        expect(response.status).to eq(lista)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
