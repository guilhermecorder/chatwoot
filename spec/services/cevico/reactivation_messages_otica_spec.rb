require 'rails_helper'

# 👓 03/11: a Reativação lê o arquivo do RAMO da empresa — a ótica reativa a
# base do SavWin (config/otica/reativacao_base.yml), a clínica segue com o
# original de fim de ano.
RSpec.describe Cevico::ReactivationMessages do
  let(:account) { create(:account) }

  it 'usa o arquivo da ótica quando o ramo é ótica, apontando o funil de pós-venda', :aggregate_failures do
    Cevico::Company.save!(account, 'segment' => 'otica', 'name' => 'Sua Ótica')
    pipeline = Crm::Pipeline.create!(account_id: account.id, name: 'Pós-venda e relacionamento', position: 1)
    stage = pipeline.stages.create!(name: 'Multifocal há mais de 18 meses', color: '#7C3AED', position: 0)
    Crm::Pipeline.create!(account_id: account.id, name: 'Aquisição', position: 0)

    payload = described_class.payload(account)

    expect(payload[:campanha]['titulo']).to eq('Reativação da base (SavWin)')
    expect(payload[:frentes].map { |f| f['key'] }).to eq(['padrao'])
    expect(payload[:publicos].map { |p| p[:key] }).to eq(%w[multifocal segundo renovar])
    expect(payload[:publicos].first[:funil]).to include(stage_id: stage.id)
    expect(payload[:totais][:mensagens]).to eq(6)
    expect(described_class.find_message('otica_base_renovar_a', account)).to be_present
    expect(described_class.find_message('otica_base_renovar_a')).to be_nil
  end

  it 'segue com o arquivo da clínica para quem não é ótica' do
    payload = described_class.payload(account)

    expect(payload[:campanha]['titulo']).to eq('Reativação de fim de ano')
    expect(payload[:publicos].map { |p| p[:key] }).to include('nao_fechou')
  end
end
