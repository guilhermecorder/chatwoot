require 'rails_helper'

# 🧹 16/11/2026 (LIFE): a trava final do "sem diminutivo e sem frase passiva" antes de o texto ir para o cliente.
RSpec.describe Crm::PlainWords do
  it 'tira o diminutivo, do jeito que a IA escreveu no dia em que a regra entrou', :aggregate_failures do
    expect(described_class.clean('Vou confirmar certinho com o Anderson, nosso engenheiro.'))
      .to eq('Vou confirmar com o Anderson, nosso engenheiro.')
    expect(described_class.clean('Ficou tudo certinho? Me dá um minutinho que eu volto.'))
      .to eq('Ficou tudo certo? Me dá um minuto que eu volto.')
    expect(described_class.clean('É rapidinho e sem custo. Rapidinho mesmo.')).to eq('É rápido e sem custo. Rápido mesmo.')
    expect(described_class.clean('Segunda de manhã eu já te mando ele certinho.')).to eq('Segunda de manhã eu já te mando ele.')
  end

  it 'tira a frase passiva e mantém o resto do balão', :aggregate_failures do
    expect(described_class.clean("Sem problema, Adriana!\n\nFica à vontade pra analisar com calma. Qualquer dúvida que surgir é só me chamar aqui."))
      .to eq("Sem problema, Adriana!\n\nFica à vontade pra analisar com calma.")
    expect(described_class.clean('Qualquer dúvida que surgir é só me chamar aqui.')).to eq('')
    expect(described_class.clean('Se ficou alguma dúvida, me fala. Quer garantir agora?')).to eq('Quer garantir agora?')
  end

  it 'não mexe no que não é diminutivo' do
    expect(described_class.clean('Você pensa em instalar qualquer coisa que aumente a conta?'))
      .to eq('Você pensa em instalar qualquer coisa que aumente a conta?')
    text = "O caminho é simples, e a linha da CPFL fica com a gente.\n\nSozinho o sistema não zera a conta. Quer seguir?"
    expect(described_class.clean(text)).to eq(text)
  end

  it 'liga por conta (ai_config sem_diminutivo)', :aggregate_failures do
    account = create(:account)
    expect(described_class.enabled?(account)).to be(false)
    CrmSetting.create!(account: account, ai_config: { 'sem_diminutivo' => true })
    expect(described_class.enabled?(account)).to be(true)
  end
end
