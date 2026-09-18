require 'rails_helper'

# 🗺️ Motor das mensagens da jornada (item 168): planejador, despachante e
# leitura da resposta do paciente — tudo com o envio real stubado.
RSpec.describe 'Crm::Journey (motor)' do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tz) { Crm::Journey::Settings::TZ }
  let(:now) { tz.local(2026, 9, 18, 10, 5) }
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511999990000') }
  let(:template_params) do
    { 'name' => 'confirmar_cirurgia', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'processed_params' => { 'body' => { '1' => '{{primeiro_nome}}', '2' => '{{data}}', '3' => '{{hora}}' } } }
  end
  let!(:message) do
    Crm::JourneyMessage.create!(
      account: account, name: 'Confirmação de cirurgia', step: 'cirurgia', inbox: inbox,
      trigger: { 'kind' => 'surgery', 'offset_days' => -1, 'at' => '10:00' },
      content: { 'mode' => 'template', 'template_params' => template_params,
                 'message_preview' => 'Olá {{1}}, sua cirurgia é {{2}} às {{3}}. Confirma?' },
      expects_reply: true, confirm_label: 'cirurgia_confirmada'
    )
  end
  let!(:surgery) do
    Crm::OftalmofacilSurgery.create!(account: account, contact: contact, item_token: 'tok1', patient_name: 'Maria Teste',
                                     surgery_date: Date.new(2026, 9, 19), surgery_hour: '08:30', status_kind: 'agendada',
                                     procedure_name: 'Catarata', clinic_name: 'IOP', raw: {})
  end

  before do
    CrmSetting.create!(account: account, agenda_config: {
                         'journey' => { 'places' => { 'clinics' => { 'IOP' => { 'unidade' => 'Alameda Casa Branca',
                                                                                'endereco' => 'Al. Casa Branca, 35' } } } }
                       })
  end

  describe Crm::Journey::Planner do
    it 'cria 1 envio para a cirurgia de amanhã, na hora da regra, e não duplica' do
      planner = described_class.new(account: account, now: now)
      expect { planner.perform }.to change(Crm::JourneySend, :count).by(1)
      send = Crm::JourneySend.last
      expect(send.status).to eq('queued')
      expect(send.event_key).to eq("surgery:#{surgery.id}")
      expect(send.scheduled_for.in_time_zone(tz).strftime('%H:%M')).to eq('10:00')
      expect { planner.perform }.not_to change(Crm::JourneySend, :count)
    end

    it 'nasce aguardando aprovação quando a regra exige revisão' do
      message.update!(approval: 'review')
      described_class.new(account: account, now: now).perform
      expect(Crm::JourneySend.last.status).to eq('pending_review')
    end

    it 'ignora cirurgia de outro dia e quem está fora do público' do
      surgery.update!(surgery_date: Date.new(2026, 9, 25))
      expect { described_class.new(account: account, now: now).perform }.not_to change(Crm::JourneySend, :count)
    end
  end

  describe Crm::Journey::Dispatcher do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'manda o modelo com as variáveis preenchidas e registra a prévia' do
      Crm::Journey::Planner.new(account: account, now: now).perform
      captured = nil
      allow(Crm::SendTemplateService).to receive(:new) do |source:, contact: nil|
        captured = source
        instance_double(Crm::SendTemplateService, perform: conversation)
      end

      result = described_class.new(account: account, now: now).perform
      expect(result[:sent]).to eq(1)
      expect(captured.template_params.dig('processed_params', 'body')).to eq('1' => 'Maria', '2' => '19/09', '3' => '08:30')
      send = Crm::JourneySend.last
      expect(send.status).to eq('sent')
      expect(send.preview).to eq('Olá Maria, sua cirurgia é 19/09 às 08:30. Confirma?')
      expect(send.variables).to include('unidade' => 'Alameda Casa Branca', 'procedimento' => 'Catarata')
    end

    it 'não manda antes da hora nem fora da janela, e pula quem pediu silêncio' do
      Crm::Journey::Planner.new(account: account, now: now).perform
      early = described_class.new(account: account, now: tz.local(2026, 9, 18, 9, 0)).perform
      expect(early[:sent]).to eq(0)

      contact.add_labels(['nao_perturbe'])
      result = described_class.new(account: account, now: now).perform
      expect(result[:skipped]).to eq(1)
      expect(Crm::JourneySend.last.error).to include('silêncio').or include('não receber')
    end

    it 'expira o que ficou 12 h sem sair' do
      Crm::Journey::Planner.new(account: account, now: now).perform
      described_class.new(account: account, now: now + 13.hours).perform
      expect(Crm::JourneySend.last.status).to eq('expired')
    end
  end

  describe Crm::Journey::ReplyService do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let!(:send) do
      Crm::JourneySend.create!(account: account, journey_message: message, contact: contact, conversation: conversation,
                               source: surgery, event_key: 'surgery:x', scheduled_for: now, status: 'sent', sent_at: now)
    end

    def incoming(text)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: text)
    end

    it '"confirmo" marca o envio, põe a etiqueta e deixa a nota ✅' do
      verdict = described_class.handle(incoming('Confirmo sim!'), contact)
      expect(verdict).to eq('confirmed')
      expect(send.reload.reply).to eq('confirmed')
      expect(contact.reload.label_list).to include('cirurgia_confirmada')
      expect(conversation.messages.where(private: true).last.content).to include('CONFIRMOU')
    end

    it '"não vou, preciso remarcar" recusa, reabre a conversa e avisa o Radar' do
      conversation.update!(status: :resolved)
      verdict = described_class.handle(incoming('Não vou conseguir, preciso remarcar'), contact)
      expect(verdict).to eq('declined')
      expect(send.reload.reply).to eq('declined')
      expect(conversation.reload).to be_open
      alerts = CrmSetting.find_by!(account: account).ai_config.dig('opportunity_state', 'alerts')
      alert = alerts.find { |a| a['kind'] == 'journey_reply' }
      expect(alert).to include('send_id' => send.id, 'contact_name' => 'Maria Teste')
      expect(Crm::RadarExtraAlerts.still_open?(account, alert)).to be(true)
    end

    it 'ignora resposta sem sim/não e quem não tem envio esperando resposta' do
      expect(described_class.handle(incoming('Que horas abre?'), contact)).to be_nil
      send.update!(reply: 'confirmed')
      expect(described_class.handle(incoming('sim'), contact)).to be_nil
    end
  end
end
