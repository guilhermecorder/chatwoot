require 'rails_helper'

# 🚪 item 420: ACESSO DE TERCEIROS — o login de fora da equipe só abre o portal
# dele (a agenda particular de um médico); o resto do sistema responde 403. O
# que ele marca aparece na Agenda e trava o horário, mas fica fora de toda
# contagem da clínica (tipo próprio, sem paciente, sem card).
RSpec.describe 'CEVICO acesso de terceiros (API)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:third) { create(:user, account: account, role: :agent, name: 'Maria Souza') }
  let(:root) { "/api/v1/accounts/#{account.id}" }
  let(:base) { "#{root}/crm" }
  let(:doctor) { 'Dra. Roberta Negri' }
  let(:windows) { [{ 'dow' => 2, 'start' => '13:00', 'end' => '14:00', 'unit' => 'paulista', 'block' => 15 }] }
  # segunda-feira, 30/11/2026, meio-dia em São Paulo → a terça 01/12 é a próxima faixa
  let(:now) { Time.zone.parse('2026-11-30 12:00:00 -03:00') }
  let(:slot) { '2026-12-01T13:15:00-03:00' }

  def auth(user) = user.create_new_auth_token

  def mark!(user = third, attrs = {})
    Cevico::ThirdParty.save!(account, user.id, { 'kind' => 'agenda_medico', 'label' => 'Secretária da Dra. Roberta',
                                                 'doctor' => doctor, 'windows' => windows, 'active' => true }.merge(attrs), by: admin)
  end

  before { travel_to(now) }

  describe 'a trava: fechado por padrão' do
    before { mark! }

    it 'nenhuma porta do sistema abre para o terceiro (core do Chatwoot e CEVICO)', :aggregate_failures do
      %W[#{root}/contacts #{root}/conversations #{root}/inboxes #{root}/agents #{root}/labels #{root}/tasks
         #{root}/notifications #{base}/settings #{base}/pipelines #{base}/appointments/feed #{base}/home
         #{base}/third_parties].each do |path|
        get path, headers: auth(third), as: :json
        expect(response).to have_http_status(:forbidden), "#{path} respondeu #{response.status}"
        expect(response.parsed_body['third_party']).to be(true), "#{path} não foi barrado pela trava do terceiro"
      end
      post "#{root}/tasks", params: { title: 'x', task_type: 'consulta', unit: 'paulista' }, headers: auth(third), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'o portal abre, e o perfil avisa a tela que a pessoa é terceiro', :aggregate_failures do
      get "#{base}/portal/me", headers: auth(third), as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['third_party']).to include('kind' => 'agenda_medico', 'doctor' => doctor, 'active' => true)

      get "#{base}/portal", headers: auth(third), as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('doctor' => doctor, 'today' => '2026-11-30')
      expect(response.parsed_body['windows']).to eq(windows)

      get '/api/v1/profile', headers: auth(third), as: :json
      entry = response.parsed_body['accounts'].find { |a| a['id'] == account.id }
      expect(entry['cevico_third_party']).to include('doctor' => doctor, 'active' => true)
    end

    it 'acesso encerrado: nem o portal abre, e a pessoa não vira atendente', :aggregate_failures do
      mark!(third, 'active' => false)
      get "#{base}/portal", headers: auth(third), as: :json
      expect(response).to have_http_status(:forbidden)
      get "#{root}/contacts", headers: auth(third), as: :json
      expect(response).to have_http_status(:forbidden)
      get "#{base}/portal/me", headers: auth(third), as: :json
      expect(response.parsed_body.dig('third_party', 'active')).to be(false)
    end

    it 'atendente comum não é afetado e não abre o portal; administrador marcado por engano não é barrado', :aggregate_failures do
      get "#{root}/contacts", headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      get "#{base}/portal", headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)

      mark!(admin)
      get "#{root}/contacts", headers: auth(admin), as: :json
      expect(response).to have_http_status(:success)
      get '/api/v1/profile', headers: auth(admin), as: :json
      expect(response.parsed_body['accounts'].first).not_to have_key('cevico_third_party')
    end

    it 'o terceiro não aparece na lista de agentes da equipe (seletores de responsável)', :aggregate_failures do
      agent
      get "#{root}/agents", headers: auth(admin), as: :json
      ids = response.parsed_body.pluck('id')
      expect(ids).to include(admin.id, agent.id)
      expect(ids).not_to include(third.id)
    end

    it 'o terceiro não tem nível em nenhum nó do catálogo' do
      access = Cevico::Access.for(account, third)
      expect(access.effective.values.uniq).to eq(['none'])
    end
  end

  describe 'marcar pelo portal' do
    before { mark! }

    def book(params = {})
      post "#{base}/portal/appointments", headers: auth(third), as: :json,
                                          params: { name: 'João Particular', phone: '(11) 98888-7777', due_at: slot }.merge(params)
    end

    it 'nasce como consulta externa do médico dela, particular, sem paciente nem card', :aggregate_failures do
      contacts_before = account.contacts.count
      book(doctor: 'Dr. Henrique Gemelli', task_type: 'consulta', particular: false)
      expect(response).to have_http_status(:created)

      task = account.tasks.last
      expect(task).to have_attributes(task_type: 'consulta_externa', doctor: doctor, particular: true, unit: 'paulista',
                                      title: 'João Particular', contact_id: nil, cevico_born_via: 'terceiro',
                                      creator_id: third.id, assignee_id: nil)
      expect(task.due_at).to eq(Time.zone.parse(slot))
      expect(task.comments.first['text']).to include('Marcada pelo portal', 'Maria Souza')
      expect(account.contacts.count).to eq(contacts_before)
      expect(Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).count).to eq(0)
    end

    it 'não se liga a um cadastro da clínica mesmo com o mesmo telefone' do
      create(:contact, account: account, phone_number: '+5511988887777')
      book
      expect(account.tasks.last.contact_id).to be_nil
    end

    it 'fica fora das contagens da clínica e trava o horário para os robôs', :aggregate_failures do
      CrmSetting.find_or_create_by!(account: account).update!(
        agenda_config: { 'windows' => [windows.first.merge('doctor' => doctor)] }
      )
      day = Date.new(2026, 12, 1)
      expect(Crm::AgendaSlots.free_slots_on(account, day).pluck(:time)).to include('13:15')

      book
      expect(account.tasks.where(task_type: 'consulta').count).to eq(0)
      expect(account.tasks.where(task_type: Task::APPOINTMENT_TYPES).count).to eq(0)
      expect(account.tasks.bookings.primeira_consulta.where(task_type: 'consulta').count).to eq(0)
      expect(Crm::AgendaSlots.free_slots_on(account, day).pluck(:time)).not_to include('13:15')

      # a equipe enxerga na Agenda (lista de tarefas da clínica)
      get "#{root}/tasks", headers: auth(agent), as: :json
      expect(response.parsed_body.pluck('task_type')).to include('consulta_externa')
    end

    it 'recusa fora da faixa, no passado, em horário ocupado e sem nome', :aggregate_failures do
      book(due_at: '2026-12-01T14:00:00-03:00') # a faixa acaba às 14h
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('fora das faixas')

      book(due_at: '2026-12-01T13:10:00-03:00') # fora da grade de 15 em 15
      expect(response).to have_http_status(:unprocessable_entity)

      book(due_at: '2026-12-02T13:15:00-03:00') # quarta não está liberada
      expect(response).to have_http_status(:unprocessable_entity)

      book(due_at: '2026-11-24T13:15:00-03:00')
      expect(response.parsed_body['error']).to include('já passou')

      book(name: ' ')
      expect(response.parsed_body['error']).to include('nome')

      book
      expect(response).to have_http_status(:created)
      book(name: 'Outro Paciente')
      expect(response.parsed_body['error']).to include('ocupado')

      # paciente da clínica com o mesmo médico no horário também ocupa
      create_clinic_consulta('2026-12-01T13:30:00-03:00')
      book(due_at: '2026-12-01T13:30:00-03:00', name: 'Terceiro')
      expect(response.parsed_body['error']).to include('ocupado')
      expect(account.tasks.external.count).to eq(1)
    end

    it 'respeita o dia fechado pela clínica e a agenda fechada do médico', :aggregate_failures do
      settings = CrmSetting.find_or_create_by!(account: account)
      settings.update!(agenda_config: { 'blocked_days' => ['2026-12-01'] })
      book
      expect(response.parsed_body['error']).to include('fechou esse dia')

      settings.update!(agenda_config: { 'closed_doctors' => [doctor] })
      book
      expect(response.parsed_body['error']).to include('fechou a agenda')
    end

    def create_clinic_consulta(at, attrs = {})
      account.tasks.create!({ title: 'Paciente da Clínica', task_type: 'consulta', due_at: Time.zone.parse(at), unit: 'paulista',
                              doctor: doctor, creator: admin, modality: 'avaliacao' }.merge(attrs))
    end

    it 'mostra o paciente da clínica só como ocupado; particular da clínica só com o nome; outro médico não aparece', :aggregate_failures do
      create_clinic_consulta('2026-12-01T13:00:00-03:00', phone: '11977776666')
      create_clinic_consulta('2026-12-01T13:30:00-03:00', title: 'Particular Da Clinica', particular: true, phone: '11955554444')
      create_clinic_consulta('2026-12-01T13:45:00-03:00', title: 'De Outro Medico', doctor: 'Dr. Henrique Gemelli')
      book

      get "#{base}/portal", params: { from: '2026-12-01', to: '2026-12-31' }, headers: auth(third)
      body = response.parsed_body
      expect(body['appointments'].pluck('name')).to eq(['João Particular'])
      expect(body['clinic'].size).to eq(2)
      expect(body['clinic'].pluck('name')).to eq([nil, 'Particular Da Clinica'])
      expect(response.body).not_to include('Paciente da Clínica', 'De Outro Medico', '11977776666', '11955554444')
      expect(body['indicators']).to include('next7' => 1, 'to_confirm' => 1)
    end

    it 'remarca, confirma, cancela e reativa — sempre com rastro', :aggregate_failures do
      book
      id = response.parsed_body['id']

      patch "#{base}/portal/appointments/#{id}", params: { confirmed: true }, headers: auth(third), as: :json
      expect(response.parsed_body['confirmed_at']).to be_present

      patch "#{base}/portal/appointments/#{id}", params: { due_at: '2026-12-01T13:45:00-03:00' }, headers: auth(third), as: :json
      expect(response).to have_http_status(:success)
      task = account.tasks.find(id)
      expect(task).to have_attributes(rescheduled_count: 1, confirmed_at: nil, task_type: 'consulta_externa')
      expect(task.rescheduled_times.size).to eq(1)

      patch "#{base}/portal/appointments/#{id}", params: { canceled: true }, headers: auth(third), as: :json
      expect(task.reload).to have_attributes(cancel_reason: 'cancelada_terceiro', canceled_by_id: third.id)

      patch "#{base}/portal/appointments/#{id}", params: { canceled: false }, headers: auth(third), as: :json
      expect(task.reload.canceled_at).to be_nil
      expect(task.comments.pluck('text').join).to include('Confirmada pelo portal', 'Cancelada pelo portal', 'Reativada pelo portal')
    end

    it 'não mexe em consulta que não é do portal nem de outro médico', :aggregate_failures do
      clinic = create_clinic_consulta('2026-12-01T13:00:00-03:00', particular: true)
      other = account.tasks.create!(title: 'Externa de outro', task_type: 'consulta_externa', due_at: Time.zone.parse(slot), unit: 'paulista',
                                    doctor: 'Dr. Henrique Gemelli', creator: admin)
      [clinic, other].each do |task|
        patch "#{base}/portal/appointments/#{task.id}", params: { canceled: true }, headers: auth(third), as: :json
        expect(response).to have_http_status(:not_found)
        expect(task.reload.canceled_at).to be_nil
      end
    end
  end

  describe 'a equipe na Agenda da clínica' do
    let!(:external) do
      mark!
      Crm::ThirdPartyAgenda.new(account, Cevico::ThirdParty.for(account, third), third)
                           .create!(name: 'João Particular', phone: '11988887777', due_at: slot)
    end

    it 'edita a consulta externa sem trocar o tipo nem criar paciente, card ou origem', :aggregate_failures do
      contacts_before = account.contacts.count
      put "#{root}/tasks/#{external.id}", headers: auth(agent), as: :json,
                                          params: { title: 'João P. Editado', task_type: 'consulta', modality: 'avaliacao', origin: 'cevico',
                                                    channel: 'instagram', attendance: 'attended', confirmed: true }
      expect(response).to have_http_status(:success)
      expect(external.reload).to have_attributes(title: 'João P. Editado', task_type: 'consulta_externa', modality: nil, origin: nil,
                                                 contact_id: nil, attendance: 'attended')
      expect(account.contacts.count).to eq(contacts_before)
    end

    it 'ninguém cria consulta externa pela API de tarefas nem transforma uma consulta em externa', :aggregate_failures do
      post "#{root}/tasks", params: { title: 'x', task_type: 'consulta_externa', unit: 'paulista' }, headers: auth(admin), as: :json
      expect(response).to have_http_status(:forbidden)

      clinic = account.tasks.create!(title: 'Da clínica', task_type: 'consulta', due_at: 2.days.from_now, unit: 'paulista', creator: admin)
      put "#{root}/tasks/#{clinic.id}", params: { task_type: 'consulta_externa' }, headers: auth(admin), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(clinic.reload.task_type).to eq('consulta')
    end
  end

  describe 'a parte do administrador' do
    it 'só administrador lista, cria e encerra', :aggregate_failures do
      get "#{base}/third_parties", headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/third_parties", params: { name: 'X Y', email: 'x@y.com', doctor: doctor }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'cria o login já marcado (fechado desde o nascimento), ajusta e encerra', :aggregate_failures do
      post "#{base}/third_parties", headers: auth(admin), as: :json,
                                    params: { name: 'Maria Souza', email: 'maria.secretaria@example.com', doctor: doctor,
                                              label: 'Secretária da Dra. Roberta',
                                              windows: windows + [{ 'dow' => 9, 'start' => '10:00', 'end' => '09:00', 'unit' => 'lua' }] }
      expect(response).to have_http_status(:created)
      row = response.parsed_body['list'].first
      expect(row).to include('name' => 'Maria Souza', 'doctor' => doctor, 'active' => true, 'windows' => windows)

      user = User.find(row['user_id'])
      expect(account.account_users.find_by(user: user).role).to eq('agent')
      get "#{root}/contacts", headers: auth(user), as: :json
      expect(response).to have_http_status(:forbidden)

      # some da lista de Pessoas da tela de Acessos (a árvore não vale para terceiro)
      get "#{base}/settings/access_admin", headers: auth(admin), as: :json
      expect(response.parsed_body['users'].pluck('user_id')).not_to include(user.id)

      patch "#{base}/third_parties/#{user.id}", params: { windows: [] }, headers: auth(admin), as: :json
      expect(response.parsed_body['list'].first['windows']).to eq([])

      delete "#{base}/third_parties/#{user.id}", headers: auth(admin), as: :json
      expect(response.parsed_body['list'].first['active']).to be(false)
      get "#{base}/portal", headers: auth(user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'recusa e-mail de quem já é da equipe (para não trancar um atendente por engano)' do
      post "#{base}/third_parties", params: { name: 'Agente', email: agent.email, doctor: doctor }, headers: auth(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Cevico::ThirdParty.user_ids(account)).to be_empty
    end

    it 'confere o portal de alguém (as=), só leitura', :aggregate_failures do
      mark!
      get "#{base}/portal", params: { as: third.id }, headers: auth(admin)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('preview' => true, 'doctor' => doctor)

      post "#{base}/portal/appointments", params: { as: third.id, name: 'Teste', due_at: slot }, headers: auth(admin), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(account.tasks.external.count).to eq(0)
    end
  end

  # a trava mora no Api::V1::Accounts::BaseController: toda porta da conta tem que herdar dele
  describe 'nenhuma porta da conta escapa da trava' do
    # controllers da conta que NÃO herdam do BaseController e repetem a trava à mão
    let(:guarded_by_hand) { [Api::V1::Accounts::Conversations::DirectUploadsController] }

    it 'toda rota /api/v*/accounts/:account_id/… cai num controller que herda do BaseController da conta' do
      escaped = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s
        next unless path.match?(%r{\A/api/v\d+/accounts/:account_id/})

        klass = "#{route.defaults[:controller]}_controller".camelize.safe_constantize
        next if klass.nil? || klass <= Api::V1::Accounts::BaseController || guarded_by_hand.include?(klass)

        "#{path} → #{klass}"
      end
      expect(escaped.uniq).to eq([])
    end

    it 'o envio de arquivo de conversa (fora do BaseController) também barra o terceiro', :aggregate_failures do
      mark!
      conversation = create(:conversation, account: account)
      path = "#{root}/conversations/#{conversation.display_id}/direct_uploads"
      blob = { filename: 'x.txt', byte_size: 3, checksum: 'rL0Y20zC+Fzt72VPzMSk2A==', content_type: 'text/plain' }

      # pela chave de API do usuário (o caminho por sessão passa pela mesma trava)
      post path, params: { blob: blob }, headers: { api_access_token: third.access_token.token }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['third_party']).to be(true)

      post path, params: { blob: blob }, headers: { api_access_token: agent.access_token.token }, as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
