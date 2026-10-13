require 'rails_helper'

# 🛡️ auditoria R3: o teste da jornada (#416) só vai para o celular da própria
# pessoa, com dados fictícios, e não cria contato por qualquer número; a
# aprovação/reenvio (#21/#412) nunca manda o mesmo balão duas vezes.
RSpec.describe 'CEVICO Jornada — teste no meu número e aprovação sem duplicar', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, name: 'Guilherme Admin', role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tz) { Crm::Journey::Settings::TZ }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:headers) { admin.create_new_auth_token }
  let(:template_params) do
    { 'name' => 'cirurgia_amanha', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'processed_params' => { 'body' => { '1' => '{{primeiro_nome}}', '2' => '{{procedimento}}', '3' => '{{medico}}' } } }
  end
  let!(:message) do
    Crm::JourneyMessage.create!(account: account, name: 'Cirurgia amanhã', step: 'cirurgia', inbox: inbox,
                                trigger: { 'kind' => 'surgery', 'offset_days' => -1, 'at' => '09:00' },
                                content: { 'mode' => 'template', 'template_params' => template_params,
                                           'message_preview' => 'Olá {{1}}, sua {{2}} é amanhã com {{3}}.' })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    CrmSetting.create!(account: account, agenda_config: {})
    allow(Crm::SendTemplateService).to receive(:new).and_return(instance_double(Crm::SendTemplateService, perform: conversation, message: nil))
  end

  def test!(phone, own_phone: nil)
    post "#{base}/journey_messages/#{message.id}/test_send", params: { phone: phone, own_phone: own_phone }.compact,
                                                             headers: headers, as: :json
  end

  describe 'POST test_send' do
    it 'recusa o número de um paciente cadastrado (nem com a caixinha marcada) e não cria envio', :aggregate_failures do
      paciente = create(:contact, account: account, name: 'João Paciente', phone_number: '+5511977776666')
      account.tasks.create!(task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                            title: 'Consulta: João', due_at: tz.now + 2.days, contact: paciente)
      expect { test!('5511977776666', own_phone: true) }.not_to change(Crm::JourneySend, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('João Paciente', 'paciente cadastrado')
    end

    it 'número novo sem a caixinha "este celular é meu" não sai nem cria contato', :aggregate_failures do
      expect { test!('5511955554444') }.not_to change(Contact, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('este celular é meu')
      expect(Crm::JourneySend.count).to eq(0)
    end

    it 'com a caixinha marcada cria UM contato de teste nomeado e marcado para a pessoa e manda dados fictícios', :aggregate_failures do
      expect { test!('5511955554444', own_phone: true) }.to change(Contact, :count).by(1)
      expect(response).to have_http_status(:success), response.body
      body = response.parsed_body
      expect(body['ok']).to be(true)
      expect(body['send']['variables']).to include('nome' => 'Ana Exemplo', 'procedimento' => 'Cirurgia de exemplo', 'medico' => 'Dr. Exemplo')
      expect(body['send']['preview']).to eq('Olá Ana, sua Cirurgia de exemplo é amanhã com Dr. Exemplo.')

      teste = Contact.order(:id).last
      expect(teste.name).to eq("Teste da jornada · #{admin.available_name}")
      expect(teste.additional_attributes[Crm::Journey::TestContact::KEY]).to eq(admin.id)

      # da segunda vez o número já é "o meu": não precisa da caixinha e não nasce outro contato
      expect { test!('5511955554444') }.not_to change(Contact, :count)
      expect(response).to have_http_status(:success)
      expect(Crm::JourneySend.where("event_key LIKE 'teste:%'").count).to eq(2)
    end

    it 'o celular de teste de UMA pessoa não serve para outra sem confirmar de novo', :aggregate_failures do
      outra = create(:user, account: account, name: 'Outra Pessoa', role: :administrator)
      test!('5511955554444', own_phone: true)
      post "#{base}/journey_messages/#{message.id}/test_send", params: { phone: '5511955554444' },
                                                               headers: outra.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('este celular é meu')
    end

    it 'contato que já existe mas sem rastro de paciente vira o celular de teste da pessoa (sem contato novo)', :aggregate_failures do
      meu = create(:contact, account: account, name: 'Guilherme', phone_number: '+5511955554444')
      expect { test!('5511955554444', own_phone: true) }.not_to change(Contact, :count)
      expect(response).to have_http_status(:success)
      expect(meu.reload.additional_attributes[Crm::Journey::TestContact::KEY]).to eq(admin.id)
    end

    it 'a cirurgia real de outro paciente nunca entra no teste', :aggregate_failures do
      paciente = create(:contact, account: account, name: 'Outro Paciente', phone_number: '+5511977776666')
      Crm::OftalmofacilSurgery.create!(account: account, contact: paciente, item_token: 'tok1', patient_name: 'Outro Paciente',
                                       surgery_date: tz.today + 1, surgery_hour: '07:00', status_kind: 'agendada',
                                       procedure_name: 'Catarata do Outro', provider_name: 'Dra. Real', clinic_name: 'IOP', raw: {})
      test!('5511955554444', own_phone: true)
      expect(response).to have_http_status(:success)
      send = Crm::JourneySend.last
      expect(send.source).to be_nil
      expect(send.variables.values.join).not_to include('Outro', 'Dra. Real')
    end

    it 'o celular de teste NÃO vira paciente: sem card no funil, sem carimbo, fora dos leads, IA calada — e o teste chega', :aggregate_failures do
      pipeline = Crm::Pipeline.create!(account: account, name: 'CEVICO')
      pipeline.stages.create!(name: 'Novos Contatos', position: 0)
      test!('5511955554444', own_phone: true)
      expect(response).to have_http_status(:success), response.body
      teste = Contact.order(:id).last
      expect(teste.label_list).to include('nao_perturbe')

      # a conversa do teste não cria card nem carimba a origem (um paciente de verdade cria)
      listener = CrmListener.instance
      conv_teste = create(:conversation, account: account, inbox: inbox, contact: teste)
      listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conv_teste))
      expect(Crm::Contact.where(contact_id: teste.id)).not_to exist
      expect(teste.reload.cevico_source_id).to be_nil
      paciente = create(:contact, account: account, name: 'Paciente Real', phone_number: '+5511977770001')
      conv_real = create(:conversation, account: account, inbox: inbox, contact: paciente)
      listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conv_real))
      expect(Crm::Contact.where(contact_id: paciente.id)).to exist

      # não conta como lead novo
      leads = Crm::LeadsUniverse.scope(account, 1.day.ago, 1.day.from_now)
      expect(leads).to include(paciente)
      expect(leads).not_to include(teste)

      # se a pessoa da equipe responder ao teste, a IA não entra
      incoming = create(:message, account: account, inbox: inbox, conversation: conv_teste, message_type: :incoming, content: 'oi')
      job = Crm::ResponderAgentJob.new
      allow(job).to receive(:agent_cfg).and_return('enabled' => true)
      job.perform(conv_teste.id, incoming.id, 'atendente_agendamento')
      expect(job).not_to have_received(:agent_cfg)

      # mesmo com nao_perturbe e a mensagem respeitando silêncio, o teste chega no celular
      expect(message.respect_quiet).to be(true)
      test!('5511955554444')
      expect(response.parsed_body['outcome']).to eq('sent')
    end
  end

  describe 'aprovar / reenviar sem duplicar (#21/#412)' do
    let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511988887777') }
    let(:surgery) do
      Crm::OftalmofacilSurgery.create!(account: account, contact: contact, item_token: 'tok2', patient_name: 'Maria Teste',
                                       surgery_date: tz.today + 1, surgery_hour: '08:00', status_kind: 'agendada',
                                       procedure_name: 'Catarata', provider_name: 'Dra. Fulana', clinic_name: 'IOP', raw: {})
    end
    let!(:send) do
      Crm::JourneySend.create!(account: account, journey_message: message, contact: contact, source: surgery,
                               event_key: "surgery:#{surgery.id}", scheduled_for: Time.current, status: 'pending_review')
    end

    it 'aprova uma vez; a segunda aprovação (outra aba) leva 409 e nada sai de novo', :aggregate_failures do
      post "#{base}/journey_sends/#{send.id}/approve", headers: headers, as: :json
      expect(response).to have_http_status(:success), response.body
      expect(response.parsed_body['outcome']).to eq('sent')

      post "#{base}/journey_sends/#{send.id}/approve", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(Crm::SendTemplateService).to have_received(:new).once
    end

    it 'quando outra pessoa pegou o envio no mesmo instante, responde 409 "já está sendo tratado"', :aggregate_failures do
      allow(Crm::JourneySend).to receive(:claim!).and_return(false)
      post "#{base}/journey_sends/#{send.id}/approve", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to include('já está sendo tratado')
      expect(Crm::SendTemplateService).not_to have_received(:new)
    end

    it 'Aprovar todos conta como "busy" o que outra pessoa pegou no meio e manda o resto', :aggregate_failures do
      outro = create(:contact, account: account, name: 'José', phone_number: '+5511988880000')
      send2 = Crm::JourneySend.create!(account: account, journey_message: message, contact: outro, source: surgery,
                                       event_key: 'surgery:x', scheduled_for: Time.current, status: 'pending_review')
      allow(Crm::JourneySend).to(receive(:claim!).and_wrap_original { |m, id, **kw| id == send2.id ? false : m.call(id, **kw) })
      post "#{base}/journey_sends/approve_all", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['results']).to eq('sent' => 1, 'busy' => 1)
      expect(send.reload.status).to eq('sent')
      expect(send2.reload.status).to eq('pending_review')
    end

    it 'envio em "sending" não pode ser aprovado nem reenviado', :aggregate_failures do
      send.update!(status: 'sending')
      post "#{base}/journey_sends/#{send.id}/approve", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      post "#{base}/journey_sends/#{send.id}/retry", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(send.reload.status).to eq('sending')
    end

    it 'reenviar pega direto de "falhou" (sem passar pela fila do cron) e manda', :aggregate_failures do
      send.update!(status: 'failed', error: 'A Meta recusou a mensagem: 131047')
      expect(Crm::JourneySend).to receive(:claim!).with(send.id, from: Crm::JourneySend::RETRYABLE).and_call_original
      post "#{base}/journey_sends/#{send.id}/retry", headers: headers, as: :json
      expect(response).to have_http_status(:success), response.body
      expect(response.parsed_body['outcome']).to eq('sent')
      expect(send.reload.status).to eq('sent')
      expect(send.error).to be_nil
    end

    it 'pular é atômico: envio em "sending" não vira "Pulada" (409) e continua saindo; pendente é pulado', :aggregate_failures do
      send.update!(status: 'sending')
      post "#{base}/journey_sends/#{send.id}/skip", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to include('já está sendo tratado')
      expect(response.parsed_body['send']).to include('status' => 'sending')
      expect(send.reload.status).to eq('sending')

      send.update!(status: 'pending_review')
      post "#{base}/journey_sends/#{send.id}/skip", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(send.reload.status).to eq('skipped')
      expect(send.error).to eq("Pulado por #{admin.available_name}")

      # pular de novo (ou pular o que já saiu) não grava por cima
      send.update!(status: 'sent')
      post "#{base}/journey_sends/#{send.id}/skip", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(send.reload.status).to eq('sent')
    end

    it 'quando o cron expirou o envio um instante antes do clique, diz "expirou", não "sendo tratado"', :aggregate_failures do
      allow(Crm::JourneySend).to receive(:claim!).and_wrap_original do |m, id, **kw|
        Crm::JourneySend.where(id: id).update_all(status: 'expired', error: 'A hora passou sem envio') # rubocop:disable Rails/SkipsModelValidations
        m.call(id, **kw)
      end
      post "#{base}/journey_sends/#{send.id}/approve", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('Este envio já foi tratado (Expirou).')
      expect(response.parsed_body['send']).to include('status' => 'expired')
      expect(Crm::SendTemplateService).not_to have_received(:new)
    end

    it 'a fila do dia mostra "Enviando" com rótulo' do
      send.update!(status: 'sending')
      get "#{base}/journey_sends/queue", headers: headers, as: :json
      expect(response.parsed_body['sends'].first).to include('status' => 'sending', 'status_label' => 'Enviando')
    end
  end
end
