require 'rails_helper'

RSpec.describe Crm::TextSpacing do
  it 'põe uma linha em branco entre as frases', :aggregate_failures do
    expect(described_class.space('Recebi, obrigado! Vou montar o seu orçamento. Te mando segunda de manhã.'))
      .to eq("Recebi, obrigado!\n\nVou montar o seu orçamento.\n\nTe mando segunda de manhã.")
    expect(described_class.space('Agora só falta uma coisa. Consegue me mandar a foto?'))
      .to eq("Agora só falta uma coisa.\n\nConsegue me mandar a foto?")
  end

  it 'não quebra número, endereço, reticência no meio nem texto já espaçado', :aggregate_failures do
    expect(described_class.space('A conta de R$ 1.250 cai bastante.')).to eq('A conta de R$ 1.250 cai bastante.')
    expect(described_class.space('Fica na Av. Dr. Morato, 233.')).to eq('Fica na Av. Dr. Morato, 233.')
    expect(described_class.space('Então... vamos ver.')).to eq('Então... vamos ver.')
    expect(described_class.space("Oi!\n\nTudo bem?")).to eq("Oi!\n\nTudo bem?")
  end

  it 'só liga na conta com texto_espacado' do
    account = create(:account)
    expect(described_class.for_account(account, 'Oi! Tudo bem?')).to eq('Oi! Tudo bem?')
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'texto_espacado' => true })
    expect(described_class.for_account(account, 'Oi! Tudo bem?')).to eq("Oi!\n\nTudo bem?")
  end
end
