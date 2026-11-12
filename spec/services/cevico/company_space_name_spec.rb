require 'rails_helper'

# 🏠 11/11/2026 (LIFE): o nome do ambiente da pessoa sai do vocabulário da empresa —
# "Espaço do Paciente" na clínica (nada muda), "Central do cliente" no ramo 'outro' (LIFE).
RSpec.describe Cevico::Company do
  let(:account) { create(:account) }

  it 'clínica sem configuração continua com "Espaço do Paciente"', :aggregate_failures do
    company = described_class.for(account)
    expect(company.word(:espaco)).to eq('Espaço do Paciente')
    expect(company.fill('Abrir {{o_espaco}}')).to eq('Abrir o Espaço do Paciente')
    expect(company.fill('{{Paciente_plural}} ({{Espaco}})')).to eq('Pacientes (Espaço do Paciente)')
  end

  it 'ramo "outro" (LIFE) chama de "Central do cliente", com o artigo certo nas frases', :aggregate_failures do
    described_class.save!(account, name: 'Life Energia Solar', segment: 'outro')
    company = described_class.for(account)
    expect(company.word(:espaco)).to eq('Central do cliente')
    expect(company.fill('Abrir {{o_espaco}}')).to eq('Abrir a Central do cliente')
    expect(company.fill('sem sair d{{o_espaco}}')).to eq('sem sair da Central do cliente')
    expect(company.fill('{{Paciente_plural}} ({{Espaco}})')).to eq('Clientes (Central do cliente)')
    expect(company.to_h[:vocabulary]).to include('espaco' => 'Central do cliente', 'o_espaco' => 'a Central do cliente')
  end

  it 'o administrador pode trocar o nome pela tela da empresa' do
    described_class.save!(account, segment: 'outro', vocabulary: { 'espaco' => 'Ficha do cliente', 'o_espaco' => 'a Ficha do cliente' })
    expect(described_class.for(account).fill('Abrir {{o_espaco}}')).to eq('Abrir a Ficha do cliente')
  end

  it 'o catálogo de acessos mostra o nome da empresa no nó de sempre' do
    described_class.save!(account, segment: 'outro')
    node = Cevico::AccessCatalog.node('pacientes')
    expect(described_class.for(account).fill(node['label'])).to eq('Clientes (Central do cliente)')
  end
end
