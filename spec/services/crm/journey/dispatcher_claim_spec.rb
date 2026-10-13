require 'rails_helper'

# 🛡️ auditoria R3 (#21/#412/#46/#45): o despachante PEGA o envio no banco
# antes de mandar (nunca dois balões), reenvia sem passar pela fila do cron,
# pula variável obrigatória vazia, reconfere a recusa da Meta na rodada
# seguinte e o teste sai com dados fictícios.
RSpec.describe Crm::Journey::Dispatcher do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:now) { tz.local(2026, 9, 18, 10, 5) }
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:template_params) do
    { 'name' => 'consulta_hoje', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'processed_params' => { 'body' => { '1' => '{{primeiro_nome}}', '2' => '{{data}}', '3' => '{{hora}}' } } }
  end
  let(:content) { { 'mode' => 'template', 'template_params' => template_params, 'message_preview' => 'Olá {{1}}, sua consulta é {{2}} às {{3}}.' } }
  let(:sent_messages) { [] }
  let(:dispatcher) { described_class.new(account: account, now: now) }
  let!(:message) do
    Crm::JourneyMessage.create!(account: account, name: 'Consulta hoje', step: 'consulta', inbox: inbox, approval: 'review',
                                trigger: { 'kind' => 'appointment', 'offset_days' => 0, 'at' => '10:00' }, content: content)
  end
  let(:task) do
    account.tasks.create!(task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                          title: 'Consulta: Maria', due_at: tz.local(2026, 9, 18, 15, 0), contact: contact)
  end

  def tz = Crm::Journey::Settings::TZ

  def create_send(status: 'pending_review', source: task, key: "task:#{task.id}", msg: message, **extra)
    Crm::JourneySend.create!({ account: account, journey_message: msg, contact: contact, source: source, event_key: key,
                               scheduled_for: now, status: status }.merge(extra))
  end

  # o "SendTemplateService" de mentira cria a mensagem na conversa (como o de verdade)
  before do
    CrmSetting.create!(account: account, agenda_config: {})
    allow(Crm::SendTemplateService).to receive(:new) do |source:, contact: nil| # rubocop:disable Lint/UnusedBlockArgument
      svc = instance_double(Crm::SendTemplateService)
      allow(svc).to receive(:perform) do
        msg = conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: 'modelo')
        sent_messages << msg
        conversation
      end
      # como o serviço de verdade: diz qual mensagem ELE criou
      allow(svc).to receive(:message) { sent_messages.last }
      svc
    end
  end

  describe '#dispatch pega o envio de forma atômica (#21/#412)' do
    it 'o segundo clique no mesmo envio devolve :busy e nada sai duas vezes', :aggregate_failures do
      send = create_send
      expect(dispatcher.dispatch(send)).to eq(:sent)
      expect(dispatcher.dispatch(Crm::JourneySend.find(send.id))).to eq(:busy)
      expect(described_class.new(account: account, now: now).dispatch(send.reload)).to eq(:busy)
      expect(sent_messages.size).to eq(1)
      expect(send.reload.status).to eq('sent')
    end

    it 'o cron que chega NO MEIO do envio (entre pegar e gravar "enviada") não manda de novo', :aggregate_failures do
      send = create_send(status: 'queued')
      cron_outcome = nil
      allow(Crm::SendTemplateService).to receive(:new) do
        svc = instance_double(Crm::SendTemplateService)
        allow(svc).to receive(:perform) do
          # a outra ponta pega o mesmo envio enquanto este ainda está mandando
          cron_outcome = described_class.new(account: account, now: now).dispatch(Crm::JourneySend.find(send.id))
          sent_messages << conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: 'modelo')
          conversation
        end
        allow(svc).to receive(:message) { sent_messages.last }
        svc
      end
      expect(dispatcher.dispatch(send)).to eq(:sent)
      expect(cron_outcome).to eq(:busy)
      expect(sent_messages.size).to eq(1)
      expect(send.reload.status).to eq('sent')
    end

    it 'envio já tratado (pulado, enviado, falhou) não é pego pelo dispatch', :aggregate_failures do
      %w[sent skipped failed expired sending].each_with_index do |status, i|
        send = create_send(status: status, key: "task:#{task.id}:#{i}")
        expect(dispatcher.dispatch(send)).to eq(:busy)
        expect(send.reload.status).to eq(status)
      end
      expect(sent_messages).to be_empty
    end

    it 'guarda o id da mensagem que saiu (fora das variáveis que a tela vê)', :aggregate_failures do
      send = create_send
      dispatcher.dispatch(send)
      expect(send.reload.sent_message_id).to eq(sent_messages.last.id)
      expect(send.to_payload[:variables].keys).not_to include('_mensagem_id')
      expect(send.to_payload[:variables]).to include('primeiro_nome' => 'Maria')
    end

    it 'bloqueio (consulta cancelada) depois de pegar deixa o envio pulado, não preso em "sending"', :aggregate_failures do
      send = create_send
      task.to_trash!(by: admin)
      expect(dispatcher.dispatch(send)).to eq(:skipped)
      expect(send.reload.status).to eq('skipped')
    end
  end

  describe '#retry ("Reenviar" da tela)' do
    it 'pega direto de falhou → sending → enviada, sem passar pela fila do cron', :aggregate_failures do
      send = create_send(status: 'failed', error: 'janela')
      statuses_seen = []
      allow(Crm::JourneySend).to receive(:claim!).and_wrap_original do |m, id, **kw|
        statuses_seen << kw[:from]
        m.call(id, **kw)
      end
      expect(dispatcher.retry(send)).to eq(:sent)
      expect(statuses_seen).to eq([Crm::JourneySend::RETRYABLE])
      expect(send.reload.status).to eq('sent')
      expect(send.error).to be_nil
    end

    it 'não reenvia o que já está sendo mandado ou já saiu', :aggregate_failures do
      expect(dispatcher.retry(create_send(status: 'sending'))).to eq(:busy)
      expect(dispatcher.retry(create_send(status: 'sent', key: 'x:2'))).to eq(:busy)
      expect(sent_messages).to be_empty
    end
  end

  describe 'variável obrigatória vazia (#46)' do
    let(:surgery_message) do
      Crm::JourneyMessage.create!(account: account, name: 'Cirurgia amanhã', step: 'cirurgia', inbox: inbox,
                                  trigger: { 'kind' => 'surgery', 'offset_days' => -1, 'at' => '10:00' },
                                  content: { 'mode' => 'template', 'message_preview' => 'Olá {{1}}, sua cirurgia é às {{2}} na {{3}}.',
                                             'template_params' => { 'name' => 'cirurgia',
                                                                    'processed_params' => { 'body' => { '1' => '{{primeiro_nome}}', '2' => '{{hora}}',
                                                                                                        '3' => '{{unidade}}' } } } })
    end

    def surgery(hour:, clinic: 'IOP')
      Crm::OftalmofacilSurgery.create!(account: account, contact: contact, item_token: SecureRandom.hex(4), patient_name: 'Maria Teste',
                                       surgery_date: Date.new(2026, 9, 19), surgery_hour: hour, status_kind: 'agendada',
                                       procedure_name: 'Catarata', clinic_name: clinic, raw: {})
    end

    it 'cirurgia SEM hora com mensagem que usa {{hora}}: pulada com o motivo, nada vai para a Meta', :aggregate_failures do
      send = create_send(status: 'queued', source: surgery(hour: nil), key: 'cir:1', msg: surgery_message)
      expect(dispatcher.dispatch(send)).to eq(:skipped)
      expect(send.reload.error).to start_with('Variável sem valor: hora')
      expect(sent_messages).to be_empty
    end

    it 'cirurgia com hora mas sem lugar configurado sai com o texto de reserva na unidade', :aggregate_failures do
      send = create_send(status: 'queued', source: surgery(hour: '08:30', clinic: ''), key: 'cir:2', msg: surgery_message)
      expect(dispatcher.dispatch(send)).to eq(:sent)
      expect(send.reload.variables['unidade']).to eq('nossa clínica')
      expect(send.preview).to eq('Olá Maria, sua cirurgia é às 08:30 na nossa clínica.')
    end
  end

  describe 'teste "Testar no meu número" (#416)' do
    it 'sai com dados FICTÍCIOS, nunca com a consulta de um paciente real', :aggregate_failures do
      outro = create(:contact, account: account, name: 'Outro Paciente', phone_number: '+5511999990002')
      consulta_do_outro = account.tasks.create!(task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                                                title: 'Consulta: Outro', due_at: tz.local(2026, 9, 21, 15, 0), contact: outro)
      send = create_send(status: 'queued', source: consulta_do_outro, key: 'teste:abcd1234')
      expect(dispatcher.dispatch(send)).to eq(:sent)
      vars = send.reload.variables
      expect(vars['nome']).to eq('Ana Exemplo')
      expect(vars['data']).to eq((tz.today + 1).strftime('%d/%m'))
      expect(vars.values.join).not_to include('Outro', '21/09')
      expect(send.preview).to eq("Olá Ana, sua consulta é #{(tz.today + 1).strftime('%d/%m')} às 09:30.")
    end
  end

  describe '#perform reconfere a rodada anterior (#45)' do
    def sent_send(message_id, key:, sent_at: now - 20.minutes)
      create_send(status: 'sent', key: key, sent_at: sent_at, conversation: conversation,
                  variables: { 'nome' => 'Maria Teste', Crm::JourneySend::MESSAGE_ID_KEY => message_id })
    end

    it 'envio "enviado" cuja mensagem a Meta recusou vira "falhou" com o erro da Meta', :aggregate_failures do
      recusada = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                  status: :failed, content_attributes: { external_error: '131047: Re-engagement message' })
      ok = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, status: :sent)
      falhou = sent_send(recusada.id, key: 'a:1')
      entregue = sent_send(ok.id, key: 'a:2')
      sem_id = create_send(status: 'sent', key: 'a:3', sent_at: now - 20.minutes, variables: { 'nome' => 'x' })

      # fora da janela de envio: a reconferência roda mesmo assim
      result = described_class.new(account: account, now: tz.local(2026, 9, 18, 23, 30)).perform
      expect(result[:reconciled]).to eq(1)
      expect(falhou.reload.status).to eq('failed')
      expect(falhou.error).to eq('A Meta recusou a mensagem: 131047: Re-engagement message')
      expect(entregue.reload.status).to eq('sent')
      expect(sem_id.reload.status).to eq('sent')
    end

    it 'depois de virar "falhou" a equipe pode reenviar pela tela' do
      recusada = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, status: :failed)
      send = sent_send(recusada.id, key: 'b:1')
      dispatcher.perform
      expect(send.reload.status).to eq('failed')
      expect(dispatcher.retry_blocker(send)).to be_nil
    end

    it 'envio preso em "sending" há mais de 15 min vira "falhou" pedindo para conferir a conversa; o recente fica', :aggregate_failures do
      preso = create_send(status: 'sending', key: 'c:1')
      preso.update_columns(updated_at: now - 20.minutes) # rubocop:disable Rails/SkipsModelValidations
      recente = create_send(status: 'sending', key: 'c:2')
      recente.update_columns(updated_at: now - 2.minutes) # rubocop:disable Rails/SkipsModelValidations
      dispatcher.perform
      expect(preso.reload.status).to eq('failed')
      expect(preso.error).to include('travou no meio')
      expect(recente.reload.status).to eq('sending')
    end
  end
end
