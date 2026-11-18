require 'rails_helper'

# 🧭 18/11/2026 (LIFE): etapa da venda de UM cliente + botões da equipe ("formas do Fernando apertar um botão").
RSpec.describe Crm::SaleSteps do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Marlene') }

  before do
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'ficha_cliente' => { 'campos' => [
                                                              { 'chave' => 'forma_pagamento', 'rotulo' => 'Forma de pagamento',
                                                                'etiqueta' => 'quer-fechar' },
                                                              { 'chave' => 'cpf', 'rotulo' => 'CPF do responsável' }
                                                            ] } })
  end

  def reached
    described_class.for(contact.reload)[:steps].select { |s| s[:reached] }.pluck(:key)
  end

  it 'mostra as 10 etapas e quais a equipe marca à mão', :aggregate_failures do
    data = described_class.for(contact)

    expect(data[:steps].pluck(:key)).to eq(%w[leads sondagem conta enviado investimento pagamento credito proposta fechado instalado])
    expect(data[:steps].select { |s| s[:markable] }.pluck(:key)).to eq(%w[investimento pagamento credito proposta fechado instalado])
    expect(data[:current]).to eq('leads')
    expect(data[:payments].pluck(:key)).to eq(%w[cartao financiamento a_vista])
  end

  it 'marcar põe a etiqueta da etapa no contato e a pessoa anda na jornada', :aggregate_failures do
    expect(described_class.mark!(contact, 'investimento', by: 'Fernando')).to be(true)
    expect(contact.reload.label_list).to include('investimento-possivel')
    expect(described_class.for(contact)[:current]).to eq('investimento')

    described_class.mark!(contact, 'proposta', by: 'Fernando')
    expect(contact.reload.label_list).to include('proposta-de-fechamento')
    expect(reached.last).to eq('proposta')
  end

  it 'forma de pagamento vai para a ficha: financiamento para no pagamento, cartão passa direto pelo crédito', :aggregate_failures do
    described_class.mark!(contact, 'pagamento', by: 'Fernando', payment: 'financiamento')
    data = described_class.for(contact.reload)
    expect(data[:payment]).to eq('financiamento')
    expect(data[:current]).to eq('pagamento')
    expect(contact.label_list).to include('quer-fechar')

    described_class.mark!(contact, 'credito', by: 'Fernando')
    expect(described_class.for(contact.reload)[:current]).to eq('credito')

    outro = create(:contact, account: account, name: 'Regis')
    described_class.mark!(outro, 'pagamento', by: 'Fernando', payment: 'cartao')
    expect(described_class.for(outro.reload)[:current]).to eq('credito')
  end

  it 'desfazer tira a marcação', :aggregate_failures do
    described_class.mark!(contact, 'fechado', by: 'Fernando')
    expect(described_class.for(contact.reload)[:current]).to eq('fechado')

    described_class.unmark!(contact, 'fechado', by: 'Fernando')
    expect(contact.reload.label_list).not_to include('contrato-fechado')
    expect(described_class.for(contact)[:current]).to eq('leads')

    described_class.mark!(contact, 'pagamento', by: 'Fernando', payment: 'a_vista')
    described_class.unmark!(contact, 'pagamento', by: 'Fernando')
    expect(described_class.for(contact.reload)[:payment]).to be_nil
  end

  it 'não marca etapa que o sistema registra sozinho nem forma de pagamento fora da lista', :aggregate_failures do
    expect(described_class.mark!(contact, 'enviado', by: 'Fernando')).to be(false)
    expect(described_class.mark!(contact, 'pagamento', by: 'Fernando', payment: 'fiado')).to be(false)
    expect(contact.reload.label_list).to be_empty
  end
end
