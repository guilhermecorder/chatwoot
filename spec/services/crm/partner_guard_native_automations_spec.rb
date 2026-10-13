require 'rails_helper'

# 🚧 Auditoria 10/2026 (#237): a cerca dos parceiros vale também para as
# automações NATIVAS do Chatwoot e para os macros. Paciente de parceiro /
# Oftalmofácil nunca recebe mensagem automática — só gente da caixa dele fala
# com ele. Etiqueta, nota privada e afins continuam funcionando.
RSpec.describe Crm::PartnerGuard do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:cevico_inbox) { create(:inbox, account: account, name: 'GOOGLE') }
  let(:partner_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
  let!(:settings) do # rubocop:disable RSpec/LetSetup
    CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'partner_inbox_ids' => [partner_inbox.id] } })
  end
  let(:patient) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:partner_conversation) { create(:conversation, account: account, inbox: partner_inbox, contact: patient) }
  let(:cevico_conversation) { create(:conversation, account: account, inbox: cevico_inbox, contact: patient) }

  before do
    Rails.cache.clear
    allow(Rails.logger).to receive(:info).and_call_original
  end

  describe AutomationRules::ActionService do
    let(:rule) do
      create(:automation_rule, account: account, name: 'Boas-vindas',
                               actions: [
                                 { action_name: 'send_message', action_params: ['Olá! Como posso ajudar?'] },
                                 { action_name: 'add_label', action_params: ['boas_vindas'] }
                               ])
    end

    it 'na conversa de parceiro pula a mensagem, mantém a etiqueta e registra o bloqueio', :aggregate_failures do
      described_class.new(rule, account, partner_conversation).perform

      expect(partner_conversation.reload.messages.outgoing.where(private: false)).to be_empty
      expect(partner_conversation.label_list).to include('boas_vindas')
      expect(Rails.logger).to have_received(:info).with(/\[cerca OF\] bloqueado: automação nativa 'Boas-vindas' · send_message/)
    end

    it 'na conversa da CEVICO a mensagem sai normalmente' do
      described_class.new(rule, account, cevico_conversation).perform

      expect(cevico_conversation.reload.messages.outgoing.where(private: false).last&.content).to eq('Olá! Como posso ajudar?')
    end

    # anexo DE VERDADE na regra e time DA CONTA: sem isso o anexo e o e-mail já
    # sairiam antes da cerca e a spec passaria mesmo sem ela
    describe 'com anexo na regra, e-mail de transcrição e aviso para o time' do
      let(:team) { create(:team, account: account) }
      let(:blob_id) do
        rule.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
        rule.files.first.blob_id
      end

      before do
        rule.update!(actions: [
                       { action_name: 'send_attachment', action_params: [blob_id] },
                       { action_name: 'send_email_transcript', action_params: ['{{contact.email}}'] },
                       { action_name: 'send_email_to_team', action_params: [{ message: 'olha', team_ids: [team.id] }] }
                     ])
        allow(TeamNotifications::AutomationNotificationMailer).to receive(:conversation_creation)
          .and_return(instance_double(ActionMailer::MessageDelivery, deliver_now: true))
      end

      it 'na conversa de parceiro pula anexo e transcrição, mas o aviso para o TIME sai', :aggregate_failures do
        described_class.new(rule, account, partner_conversation).perform

        expect(partner_conversation.reload.messages.where(private: false)).to be_empty
        expect(Rails.logger).to have_received(:info).with(/\[cerca OF\] bloqueado: automação nativa 'Boas-vindas' · send_attachment/)
        expect(Rails.logger).to have_received(:info).with(/\[cerca OF\] bloqueado: automação nativa 'Boas-vindas' · send_email_transcript/)
        expect(Rails.logger).not_to have_received(:info).with(/\[cerca OF\] bloqueado: .* · send_email_to_team/)
        expect(TeamNotifications::AutomationNotificationMailer).to have_received(:conversation_creation).with(partner_conversation, team, 'olha')
      end

      it 'na conversa da CEVICO o anexo sai (prova que o anexo da regra é real)' do
        described_class.new(rule, account, cevico_conversation).perform

        expect(cevico_conversation.reload.messages.where(private: false).last&.attachments).to be_present
      end
    end
  end

  describe Macros::ExecutionService do
    let(:macro) do
      create(:macro, account: account, name: 'Resposta pronta',
                     actions: [
                       { action_name: 'send_message', action_params: ['Mensagem pronta'] },
                       { action_name: 'add_private_note', action_params: ['nota interna'] }
                     ])
    end

    before do
      create(:inbox_member, user: user, inbox: partner_inbox)
      create(:inbox_member, user: user, inbox: cevico_inbox)
    end

    # macro não é IA: é a pessoa clicando. A caixa dos parceiros é livre para a
    # equipe dela; a cerca pega o paciente de parceiro numa caixa da CEVICO.
    describe 'com paciente de parceiro (marcado pelo sync)' do
      before { patient.update!(additional_attributes: { 'parceiro' => 'Clínica Parceira' }) }

      it 'na CAIXA DOS PARCEIROS a equipe dela manda o macro normalmente (só a caixa 12 fala com ele)', :aggregate_failures do
        described_class.new(macro, partner_conversation, user).perform

        messages = partner_conversation.reload.messages
        expect(messages.where(private: false).outgoing.last&.content).to eq('Mensagem pronta')
        expect(messages.where(private: true).pluck(:content)).not_to include(described_class::PARTNER_BLOCKED_NOTE)
        expect(Rails.logger).not_to have_received(:info).with(/\[cerca OF\] bloqueado: macro/)
      end

      it 'numa caixa da CEVICO pula a mensagem ao paciente, deixa nota privada do motivo e a nota do macro entra', :aggregate_failures do
        described_class.new(macro, cevico_conversation, user).perform

        messages = cevico_conversation.reload.messages
        expect(messages.where(private: false).outgoing).to be_empty
        expect(messages.where(private: true).pluck(:content)).to include('nota interna', described_class::PARTNER_BLOCKED_NOTE)
        expect(Rails.logger).to have_received(:info).with(/\[cerca OF\] bloqueado: macro 'Resposta pronta' · send_message/)
      end
    end

    it 'paciente da CEVICO na caixa da CEVICO: a mensagem do macro sai normalmente' do
      described_class.new(macro, cevico_conversation, user).perform

      expect(cevico_conversation.reload.messages.where(private: false).outgoing.last&.content).to eq('Mensagem pronta')
    end
  end
end
