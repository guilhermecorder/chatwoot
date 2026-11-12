require 'rails_helper'

# 📨 Envio do orçamento pelo WhatsApp + cartão e ficha atualizados na hora de gerar (LIFE, 12/11).
RSpec.describe Crm::KitQuote::Delivery do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)) }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5519999990000') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:quote) do
    Crm::Quote.create!(account: account, contact: contact, price: 12_880, kind: 'micro',
                       payload: { 'opcao' => { 'placas' => 8, 'potencia_kwp' => 5.04 }, 'proposta' => {
                         'validade_dias' => 7,
                         'investimento' => { 'cartao' => '6x sem juros ou até 20x no cartão (favor nos consultar)',
                                             'financiamento' => [{ 'parcelas' => 36, 'valor' => 640 }, { 'parcelas' => 60, 'valor' => 520 }] }
                       } }).tap do |q|
      q.files.attach(io: StringIO.new('%PDF-1'), filename: 'Proposta-Ana.pdf', content_type: 'application/pdf')
      q.files.attach(io: StringIO.new('%PDF-1'), filename: 'Justificativa-Ana.pdf', content_type: 'application/pdf')
      q.files.attach(io: StringIO.new('jpg'), filename: 'Resumo-Ana.jpg', content_type: 'image/jpeg')
    end
  end

  it 'janela aberta: manda a proposta (o resumo fica para o follow-up) e a pergunta de fechamento; marca enviada', :aggregate_failures do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'pode mandar')

    expect(described_class.new(quote).call).to eq(:enviado)

    sent = conversation.messages.outgoing.order(:id).to_a
    expect(sent.first.content).to include('Pronto, Ana!')
    expect(sent.flat_map { |m| m.attachments.map { |a| a.file.filename.to_s } }).to eq(%w[Proposta-Ana.pdf])
    expect(sent.last.content).to include('25 a 40 dias', 'É interessante para você fazer esse investimento agora?')
    expect(quote.reload).to be_sent
    expect(contact.reload.label_list).to include('orcamento-enviado')
  end

  it 'sem conversa no WhatsApp não manda nada' do
    conversation.destroy!
    expect(described_class.new(quote).call).to eq(:sem_conversa)
  end

  it 'monta a linha da ficha com valor, kit, cartão, financiamento e validade' do
    text = Crm::KitQuote::CardUpdate.new(quote).summary_text
    expect(text).to eq("R$ 12.880 · micro inversor, 8 placas, 5,04 kWp · cartão: 6x sem juros ou até 20x no cartão · " \
                       "financiamento em até 60x de R$ 520 (sujeito a aprovação) · vale até #{(quote.created_at.in_time_zone('America/Sao_Paulo') + 7.days).strftime('%d/%m')}")
  end
end
