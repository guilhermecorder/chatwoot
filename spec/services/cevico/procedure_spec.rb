require 'rails_helper'

# 🎯 item 371: o procedimento vira um nome fixo para viajar na conversão
RSpec.describe Cevico::Procedure do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Novos') }

  it 'normaliza as grafias que o sistema guarda', :aggregate_failures do
    expect(described_class.normalize('Refrativa PRK')).to eq('prk')
    expect(described_class.normalize('FEMTO LASIK OD')).to eq('lasik')
    expect(described_class.normalize('FACECTOMIA + LIO TRIFOCAL')).to eq('catarata_trifocal')
    expect(described_class.normalize('Catarata mono Rayner')).to eq('catarata_monofocal')
    expect(described_class.normalize('Facectomia OE')).to eq('catarata')
    expect(described_class.normalize('Lente fácica Artisan')).to eq('lente_facica')
    expect(described_class.normalize('refrativa')).to eq('refrativa')
    expect(described_class.normalize('consulta')).to be_nil
    expect(described_class.normalize(nil)).to be_nil
  end

  it 'a etiqueta exigida pela automação vence tudo' do
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, procedure_of_interest: 'Catarata')

    expect(described_class.of_contact(contact, pipeline: pipeline, label: 'refrativa')).to eq(%w[refrativa etiqueta_exigida])
  end

  it 'sem etiqueta exigida, vale o card; depois a cirurgia do Oftalmofácil; depois a página' do
    expect(described_class.of_contact(contact, pipeline: pipeline)).to eq([nil, nil])

    contact.update!(additional_attributes: { 'page_ads' => { 'slug' => 'trifocal', 'title' => 'Catarata trifocal' } })
    expect(described_class.of_contact(contact, pipeline: pipeline)).to eq(%w[catarata_trifocal pagina])

    Crm::OftalmofacilSurgery.create!(account: account, contact_id: contact.id, item_token: 'x1', status_kind: 'agendada',
                                     procedure_name: 'PRK OD', procedure_type: 'Cirurgia')
    expect(described_class.of_contact(contact, pipeline: pipeline)).to eq(%w[prk oftalmofacil])

    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, procedure_of_interest: 'Lasik')
    expect(described_class.of_contact(contact, pipeline: pipeline)).to eq(%w[lasik card])
  end
end
