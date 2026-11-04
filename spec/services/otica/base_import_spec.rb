require 'rails_helper'

# 👓 Importação da base do SavWin: celular normalizado, segmento pela data da
# última compra (e multifocal), contato + etiqueta + card no funil de
# pós-venda, sem duplicar quando roda de novo.
RSpec.describe Otica::BaseImport do
  let(:account) { create(:account) }
  let(:csv) { File.read(Rails.root.join('spec/fixtures/otica/savwin_clientes_amostra.csv')) }
  let(:today) { Date.new(2026, 11, 4) }
  let!(:pipeline) do
    Crm::Pipeline.create!(account_id: account.id, name: 'Pós-venda e relacionamento', position: 1).tap do |p|
      ['Retirou o óculos', 'Base: compra recente', '6 meses (segundo óculos)', 'Multifocal há mais de 18 meses',
       '1 ano ou parcelas acabaram (nova oferta)', 'Nova oferta em conversa', 'Comprou de novo'].each_with_index do |name, i|
        p.stages.create!(name: name, color: '#1E7A4C', position: i)
      end
    end
  end

  def stage(name)
    pipeline.stages.find_by(name: name)
  end

  def card_of(phone)
    Crm::Contact.find_by(contact_id: account.contacts.find_by(phone_number: phone).id, pipeline_id: pipeline.id)
  end

  describe '.normalize_phone' do
    it 'aceita os formatos do SavWin e devolve E.164; fixo e inválido viram nil', :aggregate_failures do
      expect(described_class.normalize_phone('(11) 99876-1001')).to eq('+5511998761001')
      expect(described_class.normalize_phone('+55 11 99876-1001')).to eq('+5511998761001')
      expect(described_class.normalize_phone('011 99876-1001')).to eq('+5511998761001')
      expect(described_class.normalize_phone('(11) 9876-1005')).to eq('+5511998761005') # celular antigo de 8 dígitos ganha o 9
      expect(described_class.normalize_phone('(11) 3333-4444')).to be_nil
      expect(described_class.normalize_phone('')).to be_nil
      expect(described_class.normalize_phone('123')).to be_nil
    end
  end

  describe '.parse_date / .parse_amount' do
    it 'lê datas e valores no formato brasileiro', :aggregate_failures do
      expect(described_class.parse_date('20/09/2026')).to eq(Date.new(2026, 9, 20))
      expect(described_class.parse_date('2026-09-20 10:30')).to eq(Date.new(2026, 9, 20))
      expect(described_class.parse_date('20/09/26')).to eq(Date.new(2026, 9, 20))
      expect(described_class.parse_date('')).to be_nil
      expect(described_class.parse_amount('R$ 1.550,00')).to eq(1550.0)
      expect(described_class.parse_amount('399,00')).to eq(399.0)
      expect(described_class.parse_amount('1550.5')).to eq(1550.5)
      expect(described_class.parse_amount('')).to be_nil
    end
  end

  it 'em ensaio só conta, sem gravar nada', :aggregate_failures do
    importer = described_class.new(account, csv, dry: true, today: today).call

    expect(importer.result[:segmentos]).to include('s0' => 6, 's2' => 5, 's1' => 8, 's3' => 5, 'fora' => 3, 's4' => 6)
    expect(importer.report[:clientes]).to eq(27)
    expect(importer.report[:sem_celular]).to eq(2)
    expect(importer.report[:repetidas]).to eq(1)
    expect(importer.report[:sem_data]).to eq(1)
    expect(account.contacts.count).to eq(0)
    expect(Crm::Contact.where(pipeline_id: pipeline.id).count).to eq(0)
  end

  it 'cria contatos, etiquetas e cards por segmento', :aggregate_failures do
    importer = described_class.new(account, csv, today: today).call

    expect(importer.report[:contatos_criados]).to eq(27)
    expect(importer.report[:cards_criados]).to eq(24)
    expect(Crm::Contact.where(pipeline_id: pipeline.id).count).to eq(24)
    expect(Label.where(account_id: account.id).pluck(:title)).to include('base_s1', 'base_s3', 'base_s4', 'base_fora')
    expect(CustomAttributeDefinition.where(account_id: account.id, attribute_model: 'contact_attribute').pluck(:attribute_key))
      .to include('ultima_compra', 'tipo_lente', 'segmento_base')

    ana = account.contacts.find_by(phone_number: '+5511998761001')
    expect(ana.name).to eq('Ana Beatriz Souza')
    expect(ana.custom_attributes).to include('ultima_compra' => '2026-09-20', 'valor_ultima_compra' => 399.0, 'segmento_base' => 's0',
                                             'vendedora' => 'Valdira', 'nascimento' => '1978-03-12', 'origem_base' => 'savwin')
    expect(card_of('+5511998761001').stage).to eq(stage('Base: compra recente'))

    bruno = account.contacts.find_by(phone_number: '+5511998761002')
    expect(bruno.label_list).to contain_exactly('base_s0', 'base_s4') # aniversário em 05/11

    expect(card_of('+5511998761006').stage).to eq(stage('6 meses (segundo óculos)'))      # Fernanda, 6 meses
    expect(card_of('+5511998761011').stage).to eq(stage('1 ano ou parcelas acabaram (nova oferta)')) # Karen, 12 meses
    expect(card_of('+5511998761017').stage).to eq(stage('Multifocal há mais de 18 meses')) # Quitéria, multifocal há 18 meses
    expect(card_of('+5511998761021').stage).to eq(stage('1 ano ou parcelas acabaram (nova oferta)')) # Úrsula, multifocal há 14 meses
    expect(card_of('+5511998761020').stage).to eq(stage('Multifocal há mais de 18 meses')) # Tiago, Varilux há 34 meses
    expect(card_of('+5511998761020').stage_moved_at.to_date).to eq(Date.new(2024, 1, 1))

    wagner = account.contacts.find_by(phone_number: '+5511998761023')
    expect(wagner.label_list).to eq(['base_fora'])
    expect(card_of('+5511998761023')).to be_nil

    beatriz = account.contacts.find_by(phone_number: '+5511998761026')
    expect(beatriz.custom_attributes['ultima_compra']).to eq('2026-08-22') # fica a venda mais recente
    expect(account.contacts.find_by(phone_number: '+5511998761005').name).to eq('Eliane Prado')
  end

  it 'rodar de novo não duplica e respeita card em coluna viva', :aggregate_failures do
    described_class.new(account, csv, today: today).call
    card_of('+5511998761006').update!(stage_id: stage('Nova oferta em conversa').id)

    importer = described_class.new(account, csv, today: today).call

    expect(account.contacts.count).to eq(27)
    expect(Crm::Contact.where(pipeline_id: pipeline.id).count).to eq(24)
    expect(importer.report[:contatos_criados]).to eq(0)
    expect(importer.report[:cards_criados]).to eq(0)
    expect(importer.report[:cards_mantidos]).to eq(1)
    expect(card_of('+5511998761006').stage).to eq(stage('Nova oferta em conversa'))
  end

  it 'move o card quando o cliente muda de segmento numa exportação nova' do
    described_class.new(account, csv, today: today).call
    importer = described_class.new(account, csv, today: Date.new(2027, 6, 1)).call # 7 meses depois

    expect(importer.report[:cards_movidos]).to be_positive
    expect(card_of('+5511998761001').stage).to eq(stage('6 meses (segundo óculos)')) # Ana: 20/09/2026 → 8 meses
    expect(account.contacts.find_by(phone_number: '+5511998761001').label_list).to eq(['base_s2'])
  end

  it 'avisa quando falta a coluna do celular' do
    importer = described_class.new(account, "Nome;Data\nAna;20/09/2026\n", today: today).call

    expect(importer.result[:problemas].first).to include('telefone/celular')
    expect(account.contacts.count).to eq(0)
  end

  it 'avisa quando o funil de pós-venda não existe' do
    pipeline.destroy!
    importer = described_class.new(account, csv, today: today).call

    expect(importer.report[:sem_funil]).to eq(24)
    expect(importer.report_lines.join).to include('cevico:otica:preparar')
  end
end
