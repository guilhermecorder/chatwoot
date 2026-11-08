require 'rails_helper'

# 💬 08/11: o texto da ótica no WhatsApp sai espaçado, uma linha em branco entre as frases
RSpec.describe Otica::TextSpacing do
  it 'pula uma linha depois de ponto, interrogação e exclamação; não quebra número nem "Dr."', :aggregate_failures do
    expect(described_class.space('Recebi sua foto! Já estou montando. Em alguns segundos te mando. Quer ver?'))
      .to eq("Recebi sua foto!\n\nJá estou montando.\n\nEm alguns segundos te mando.\n\nQuer ver?")
    expect(described_class.space('Fica R$ 1.250 em até 10x. Dá pra você?')).to eq("Fica R$ 1.250 em até 10x.\n\nDá pra você?")
    expect(described_class.space('Fala com a Dra. Fabi no sábado.')).to eq('Fala com a Dra. Fabi no sábado.')
    expect(described_class.space("Oi!\n\n\n\nTudo bem? \"Ótimo\".")).to eq("Oi!\n\nTudo bem?\n\n\"Ótimo\".")
    expect(described_class.space('uma frase só')).to eq('uma frase só')
  end

  it 'só no ramo ótica', :aggregate_failures do
    account = create(:account)
    Cevico::Company.save!(account, 'segment' => 'clinica')
    expect(described_class.for_account(account, 'Oi. Tudo bem?')).to eq('Oi. Tudo bem?')
    Cevico::Company.save!(account, 'segment' => 'otica')
    expect(described_class.for_account(account, 'Oi. Tudo bem?')).to eq("Oi.\n\nTudo bem?")
  end
end
