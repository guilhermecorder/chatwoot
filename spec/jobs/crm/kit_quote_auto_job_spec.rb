require 'rails_helper'

# ⚡ Orçamento automático: pronto → envia (PDF + fechamento); falhou → avisa a instabilidade e abre tarefa urgente.
RSpec.describe Crm::KitQuoteAutoJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account, name: 'Marcos Bueno', phone_number: '+5519999990000') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    create(:user, account: account, role: :administrator, name: 'Fernando')
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'não vai aumentar')
  end

  it 'pronto: manda o orçamento oficial com a pergunta de fechamento e deixa nota', :aggregate_failures do
    quote = Crm::Quote.create!(account: account, contact: contact, price: 12_880, kind: 'micro', payload: { 'opcao' => { 'placas' => 7 } })
    quote.files.attach(io: StringIO.new('%PDF-1'), filename: 'Proposta-Marcos.pdf', content_type: 'application/pdf')
    allow(Crm::KitQuote::AutoBuild).to receive(:new).and_return(
      instance_double(Crm::KitQuote::AutoBuild, call: Crm::KitQuote::AutoBuild::Result.new(status: :pronto, quote: quote))
    )

    described_class.perform_now(conversation.id, 'atendente_agendamento')

    sent = conversation.messages.outgoing.order(:id).to_a
    expect(sent.first.content).to include('orçamento oficial')
    expect(sent.last.content).to include('É interessante para você fazer esse investimento agora?')
    expect(sent.map { |m| m.additional_attributes['cevico_ia_agent'] }.uniq).to eq(['atendente_agendamento'])
    expect(conversation.messages.where(message_type: :activity).last.content).to include('Orçamento automático ENVIADO')
    expect(quote.reload).to be_sent
    expect(conversation.reload.additional_attributes.dig('cevico_orcamento_auto', 'status')).to eq('enviado')
  end

  it 'falhou: avisa a instabilidade do fornecedor e abre tarefa urgente para gerar na mão', :aggregate_failures do
    allow(Crm::KitQuote::AutoBuild).to receive(:new).and_return(
      instance_double(Crm::KitQuote::AutoBuild,
                      call: Crm::KitQuote::AutoBuild::Result.new(status: :fornecedor_fora, motivo: 'nenhum fornecedor trouxe kit completo'))
    )

    described_class.perform_now(conversation.id, 'atendente_agendamento')

    expect(conversation.messages.outgoing.last.content).to include('instabilidade no sistema do fornecedor', 'alguns minutos')
    task = account.tasks.where(contact: contact).last
    expect(task.title).to include('Orçamento automático não saiu')
    expect(conversation.reload.additional_attributes.dig('cevico_orcamento_auto', 'status')).to eq('falhou')
  end

  it 'marca "gerando" e não deixa disparar duas vezes' do
    described_class.enqueue!(conversation, 'atendente_agendamento')
    expect(described_class.running?(conversation.reload)).to be(true)
  end

  describe '⏱️ timer: monta na hora e só manda quando a espera completa' do
    let(:quote) do
      Crm::Quote.create!(account: account, contact: contact, price: 12_880, kind: 'micro', payload: { 'opcao' => { 'placas' => 7 } }).tap do |q|
        q.files.attach(io: StringIO.new('%PDF-1'), filename: 'Proposta-Marcos.pdf', content_type: 'application/pdf')
      end
    end

    before do
      allow(Crm::KitQuote::AutoBuild).to receive(:new).and_return(
        instance_double(Crm::KitQuote::AutoBuild, call: Crm::KitQuote::AutoBuild::Result.new(status: :pronto, quote: quote))
      )
    end

    it 'pronto antes da hora: guarda, agenda o envio e nada sai para o cliente ainda', :aggregate_failures do
      described_class.enqueue!(conversation, 'atendente_agendamento') # espera padrão 180 s

      expect { described_class.perform_now(conversation.id, 'atendente_agendamento') }
        .to have_enqueued_job(described_class).with(conversation.id, 'atendente_agendamento', quote.id)
      expect(conversation.messages.outgoing).to be_empty
      expect(conversation.reload.additional_attributes.dig('cevico_orcamento_auto', 'status')).to eq('pronto')
      expect(described_class.running?(conversation)).to be(true)
      expect(quote.reload.sent_at).to be_nil
    end

    it 'na hora: manda o orçamento e a pergunta de fechamento', :aggregate_failures do
      described_class.enqueue!(conversation, 'atendente_agendamento')
      described_class.perform_now(conversation.id, 'atendente_agendamento')

      travel 3.minutes do
        described_class.perform_now(conversation.id, 'atendente_agendamento', quote.id)
      end

      expect(conversation.messages.outgoing.order(:id).last.content).to include('É interessante para você fazer esse investimento agora?')
      expect(quote.reload.sent_at).to be_present
    end

    it 'não manda se a equipe já enviou outro orçamento nesse meio tempo' do
      described_class.enqueue!(conversation, 'atendente_agendamento')
      described_class.perform_now(conversation.id, 'atendente_agendamento')
      Crm::Quote.create!(account: account, contact: contact, price: 13_000, kind: 'micro', payload: {}, sent_at: 1.minute.from_now)

      travel 3.minutes do
        described_class.perform_now(conversation.id, 'atendente_agendamento', quote.id)
      end

      expect(conversation.messages.outgoing).to be_empty
    end

    it 'espera 0 na configuração = manda assim que fica pronto' do
      setting = CrmSetting.find_or_create_by!(account: account)
      setting.update!(ai_config: { 'agents' => { 'atendente_agendamento' => { 'orcamento_espera_segundos' => 0 } } })
      described_class.enqueue!(conversation, 'atendente_agendamento')
      described_class.perform_now(conversation.id, 'atendente_agendamento')

      expect(quote.reload.sent_at).to be_present
    end
  end
end
