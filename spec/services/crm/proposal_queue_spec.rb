require 'rails_helper'

# 📄 11/11/2026 (LIFE): quem está na coluna do funil, para escolher de quem é a proposta.
RSpec.describe Crm::ProposalQueue do
  let(:account) { create(:account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life', position: 0) }
  let!(:novos) { Crm::Stage.create!(pipeline: pipeline, name: 'Novos Contatos', position: 0) }
  let!(:a_fazer) do
    Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento a fazer', position: 1,
                       settings: { 'prazo' => { 'modo' => 'horas', 'horas' => 24, 'tarefa' => 'Montar e enviar o orçamento' } })
  end

  def card(name, stage, moved_at)
    contact = create(:contact, account: account, name: name)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage).update_columns(stage_moved_at: moved_at) # rubocop:disable Rails/SkipsModelValidations
    contact
  end

  it 'conta sem funil devolve tudo vazio' do
    expect(described_class.new(create(:account)).call).to eq(stages: [], stage_id: nil, people: [], selected: nil)
  end

  it 'abre na primeira coluna com compromisso e gente; mais antigo primeiro; traz o resumo do cliente', :aggregate_failures do
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'ficha_cliente' => { 'campos' => [{ 'chave' => 'conta',
                                                                                                             'rotulo' => 'Conta de luz' }] } })
    card('Novo da Silva', novos, 3.hours.ago)
    ivan = card('Ivan Coral', a_fazer, 2.days.ago)
    card('Marina Teles', a_fazer, 1.day.ago)
    Crm::ClientSummary.write!(ivan, { 'conta' => 'R$ 300' }, by: 'Fernando')

    result = described_class.new(account).call

    expect(result[:stage_id]).to eq(a_fazer.id)
    expect(result[:stages].map { |s| [s[:name], s[:count]] }).to eq([['Novos Contatos', 1], ['Orçamento a fazer', 2]])
    expect(result[:people].pluck(:name)).to eq(['Ivan Coral', 'Marina Teles'])
    expect(result[:people].first).to include(contact_id: ivan.id, summary: [{ label: 'Conta de luz', value: 'R$ 300' }])
    expect(result[:people].first[:stage_due_at]).to be_present
    expect(result[:selected]).to be_nil
  end

  it 'troca de coluna quando pedem e devolve o cliente escolhido (mesmo fora da coluna)', :aggregate_failures do
    novo = card('Novo da Silva', novos, 3.hours.ago)
    card('Ivan Coral', a_fazer, 2.days.ago)
    solto = create(:contact, account: account, name: 'Sem Cartão')

    result = described_class.new(account, stage_id: novos.id, contact_id: novo.id).call
    expect(result[:stage_id]).to eq(novos.id)
    expect(result[:people].pluck(:name)).to eq(['Novo da Silva'])
    expect(result[:selected]).to include(contact_id: novo.id, name: 'Novo da Silva')
    expect(result[:selected][:stage]).to include(name: 'Novos Contatos')

    expect(described_class.new(account, contact_id: solto.id).call[:selected]).to include(name: 'Sem Cartão', stage: nil, card_id: nil)
    de_fora = create(:contact, name: 'De outra empresa')
    expect(described_class.new(account, contact_id: de_fora.id).call[:selected]).to be_nil
  end
end
