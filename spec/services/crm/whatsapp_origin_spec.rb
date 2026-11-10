require 'rails_helper'

# 🧭 10/11/2026 (LIFE): de onde veio a conversa, pela primeira mensagem do cliente.
RSpec.describe Crm::WhatsappOrigin do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ivan', phone_number: '+5519999990001') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:origens) do
    [
      { 'pagina' => 'placa-solar-piracicaba', 'canal' => 'google_busca',
        'frases' => ['Oi! Quanto eu economizo na minha conta de luz?', 'Oi! Minha conta de luz é de uns R$ * Quanto eu economizo?'] },
      { 'pagina' => 'conta-de-luz', 'canal' => 'meta_anuncio',
        'frases' => ['Oi! Vi o anúncio da Life. Quanto eu economizo?',
                     'Oi! Minha conta de luz é de uns R$ * Vi o anúncio da Life. Quanto eu economizo?'] },
      { 'pagina' => 'quantas-placas-solares-preciso', 'canal' => 'google_busca', 'frases' => ['Oi! Quantas placas eu preciso?'] }
    ]
  end

  before { CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'origens_site' => origens }) }

  def chega(texto)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: texto)
    described_class.new(conversation: conversation, text: texto).call
  end

  it 'reconhece a mensagem pronta da página (com acento, pontuação e saudação diferentes)', :aggregate_failures do
    expect(chega('Olá, quantas placas eu preciso')).to eq('site')
    expect(conversation.reload.additional_attributes['origem_whatsapp']).to include('tipo' => 'site', 'pagina' => 'quantas-placas-solares-preciso')
    expect(conversation.label_list).to include('origem-site')
    expect(conversation.messages.activity.last.content).to include('página quantas-placas-solares-preciso')
    expect(contact.reload.additional_attributes['canal_origem']).to include('key' => 'google_busca')
  end

  it 'a calculadora (valor no meio) e a frase mais comprida vencem', :aggregate_failures do
    expect(described_class.match_page(account, 'Oi! Minha conta de luz é de uns R$ 600. Quanto eu economizo?')['pagina'])
      .to eq('placa-solar-piracicaba')
    expect(described_class.match_page(account, 'Oi! Minha conta de luz é de uns R$ 450. Vi o anúncio da Life. Quanto eu economizo?')['pagina'])
      .to eq('conta-de-luz')
    expect(described_class.match_page(account, 'quanto custa?')).to be_nil
  end

  it 'anúncio da Meta e formulário vêm antes do texto', :aggregate_failures do
    conversation.update!(additional_attributes: { 'meta_ads' => { 'source_id' => '1', 'headline' => 'E se o governo proibir?' } })
    expect(chega('Olá! Posso ter mais informações sobre isso?')).to eq('anuncio')
    expect(conversation.reload.label_list).to include('origem-anuncio')
    expect(contact.reload.additional_attributes['canal_origem']).to be_nil

    outra = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account),
                                  additional_attributes: { 'meta_lead_id' => '99' })
    create(:message, account: account, inbox: inbox, conversation: outra, message_type: :incoming, content: 'Pode sim')
    expect(described_class.new(conversation: outra, text: 'Pode sim').call).to eq('formulario')
  end

  it 'texto livre = direto; só a primeira mensagem decide; conta sem lista não faz nada', :aggregate_failures do
    expect(chega('Gostaria de um orçamento para uma casa que estou construindo')).to eq('direto')
    expect(conversation.reload.label_list).to include('origem-direto')
    expect(chega('Oi! Quantas placas eu preciso?')).to be_nil
    expect(conversation.reload.additional_attributes.dig('origem_whatsapp', 'tipo')).to eq('direto')

    CrmSetting.find_by(account: account).update!(ai_config: {})
    nova = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: nova, message_type: :incoming, content: 'oi')
    expect(described_class.new(conversation: nova, text: 'oi').call).to be_nil
    expect(nova.reload.label_list).to be_empty
  end

  it 'não sobrescreve o "como chegou" que a equipe já informou' do
    contact.update!(additional_attributes: { 'canal_origem' => { 'key' => 'indicacao', 'por' => 'Fernando' } })
    chega('Oi! Quantas placas eu preciso?')
    expect(contact.reload.additional_attributes['canal_origem']['key']).to eq('indicacao')
  end

  it 'carga das conversas antigas: usa a 1ª mensagem mesmo com várias depois', :aggregate_failures do
    3.times { |i| create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: "msg #{i}") }
    expect(described_class.new(conversation: conversation, text: 'Oi! Quantas placas eu preciso?').call).to be_nil
    expect(described_class.new(conversation: conversation, text: 'Oi! Quantas placas eu preciso?', historico: true).call).to eq('site')
  end
end
