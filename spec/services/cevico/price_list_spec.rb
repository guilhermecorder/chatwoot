require 'rails_helper'

# 🔢 Rodada 5 da auditoria — "Números certos" (achado #401): a Tabela de
# preços aceitava procedimento sem preço (virava "R$ 0") e promoção R$ 0, e
# isso ia para o prompt do Atendente IA e para o Espaço do Paciente. A
# unidade (por olho × dois olhos) vivia só no texto do grupo.
RSpec.describe Cevico::PriceList do
  let(:account) { create(:account) }

  def save_table(items)
    settings = CrmSetting.find_or_create_by!(account: account)
    settings.update!(agenda_config: { 'price_table' => { 'items' => items } })
  end

  describe '.prompt_block' do
    it 'deixa de fora a linha já salva com R$ 0 (até o admin preencher)', :aggregate_failures do
      save_table([{ 'group' => 'Exames', 'name' => 'Topografia', 'price' => 0.0 },
                  { 'group' => 'Exames', 'name' => 'Paquimetria', 'price' => 250 }])

      block = described_class.prompt_block(account)
      expect(block).not_to include('Topografia')
      expect(block).not_to include('R$ 0')
      expect(block).to include('Paquimetria R$ 250')
    end

    it 'ignora promoção R$ 0 ou maior que o preço (não vira preço oficial)', :aggregate_failures do
      save_table([{ 'group' => 'Catarata (por olho)', 'name' => 'Trifocal', 'price' => 8490, 'promo_price' => 0.0 },
                  { 'group' => 'Catarata (por olho)', 'name' => 'Galaxy', 'price' => 14_990, 'promo_price' => 20_000 }])

      block = described_class.prompt_block(account)
      expect(block).to include('Trifocal R$ 8.490')
      expect(block).to include('Galaxy R$ 14.990')
      expect(block).not_to include('promoção')
    end

    it 'mantém a promoção válida com a unidade nos dois valores' do
      save_table([{ 'group' => 'Catarata', 'name' => 'Trifocal', 'price' => 8490, 'promo_price' => 7990, 'unit' => 'por_olho' }])

      expect(described_class.prompt_block(account))
        .to include('Trifocal R$ 7.990 por olho (promoção; preço normal R$ 8.490 por olho)')
    end

    it 'imprime a unidade do CAMPO mesmo com o grupo renomeado sem ela', :aggregate_failures do
      save_table([{ 'group' => 'Catarata', 'name' => 'Trifocal', 'price' => 8490, 'unit' => 'por_olho' },
                  { 'group' => 'Refrativa', 'name' => 'Lasik', 'price' => 5700, 'unit' => 'dois_olhos' },
                  { 'group' => 'Exames', 'name' => 'Laser', 'price' => 900, 'unit' => 'por_sessao' },
                  { 'group' => 'Exames', 'name' => 'Mapeamento', 'price' => 300, 'unit' => 'unico' }])

      block = described_class.prompt_block(account)
      expect(block).to include('Trifocal R$ 8.490 por olho')
      expect(block).to include('Lasik R$ 5.700 pelos dois olhos')
      expect(block).to include('Laser R$ 900 por sessão')
      expect(block).to include('Mapeamento R$ 300 (valor único)')
    end

    it 'não repete a unidade quando o nome do grupo já diz' do
      save_table([{ 'group' => 'Refrativa (2 olhos)', 'name' => 'PRK', 'price' => 4900, 'unit' => 'dois_olhos' }])

      expect(described_class.prompt_block(account)).to include('- Refrativa (2 olhos): PRK R$ 4.900.')
    end
  end

  describe '.items' do
    it 'deduz a unidade de tabelas antigas pelo texto do grupo e força fácica por olho', :aggregate_failures do
      save_table([{ 'group' => 'Refrativa (2 olhos)', 'name' => 'PRK', 'price' => 4900 },
                  { 'group' => 'Outros', 'name' => 'Artisan', 'price' => 11_900, 'unit' => 'dois_olhos' },
                  { 'group' => 'Outros', 'name' => 'Consulta', 'price' => 400 }])

      units = described_class.items(account).to_h { |i| [i['name'], i['unit']] }
      expect(units).to eq('PRK' => 'dois_olhos', 'Artisan' => 'por_olho', 'Consulta' => nil)
    end

    it 'devolve a tabela padrão com unidade em todas as linhas' do
      expect(described_class.items(account).pluck('unit')).to all(be_present)
    end

    it 'esconde da tela a promoção inválida (R$ 0)' do
      save_table([{ 'group' => 'Catarata', 'name' => 'Trifocal', 'price' => 8490, 'promo_price' => 0.0 }])

      expect(described_class.items(account).first['promo_price']).to be_nil
    end
  end

  describe '.effective_price / .price_by_name' do
    it 'promoção R$ 0 não vale como preço e linha sem preço some', :aggregate_failures do
      save_table([{ 'group' => 'Catarata', 'name' => 'Trifocal', 'price' => 8490, 'promo_price' => 0.0 },
                  { 'group' => 'Exames', 'name' => 'Topografia', 'price' => 0 }])

      expect(described_class.effective_price('price' => 8490, 'promo_price' => 0.0)).to eq(8490)
      expect(described_class.price_by_name(account)).to eq('trifocal' => 8490.0)
    end
  end

  describe '.sanitize_row' do
    it 'recusa linha com nome e sem preço (ou R$ 0) devolvendo o nome e o motivo', :aggregate_failures do
      expect(described_class.sanitize_row({ name: 'Topografia', price: '', unit: 'unico' }))
        .to eq([nil, 'Topografia: falta o preço (maior que zero)'])
      expect(described_class.sanitize_row({ name: 'Topografia', price: 0 }).last).to start_with('Topografia: falta o preço')
      expect(described_class.sanitize_row({ name: 'Topografia', price: -5 }).last).to start_with('Topografia: falta o preço')
    end

    it 'ignora linha sem nome' do
      expect(described_class.sanitize_row({ name: ' ', price: 10 })).to eq([nil, nil])
    end

    it 'zera promoção R$ 0 ou maior que o preço e guarda a unidade válida', :aggregate_failures do
      row, = described_class.sanitize_row({ group: 'Catarata', name: 'Trifocal', price: 8490, promo_price: 0, unit: 'por_olho' })
      expect(row).to eq('group' => 'Catarata', 'name' => 'Trifocal', 'price' => 8490.0, 'unit' => 'por_olho')

      row, = described_class.sanitize_row({ group: 'Catarata (por olho)', name: 'Galaxy', price: 100, promo_price: 150, unit: 'inventada' })
      expect(row).to eq('group' => 'Catarata (por olho)', 'name' => 'Galaxy', 'price' => 100.0, 'unit' => 'por_olho')
    end

    it 'recusa linha sem unidade (nem escolhida, nem dita no grupo)', :aggregate_failures do
      expect(described_class.sanitize_row({ group: 'Outros', name: 'Consulta', price: 400 }))
        .to eq([nil, 'Consulta: escolha a unidade (por olho, dois olhos, por sessão ou único)'])
      expect(described_class.sanitize_row({ name: 'Consulta', price: 400, unit: 'inventada' }).first).to be_nil
    end

    # revisão do grupo: "Catarata (por olho)" + "dois olhos" saía no prompt
    # como "Catarata (por olho): Trifocal R$ 8.490 pelos dois olhos"
    it 'recusa grupo e unidade em contradição', :aggregate_failures do
      row, problem = described_class.sanitize_row({ group: 'Catarata (por olho)', name: 'Trifocal', price: 8490, unit: 'dois_olhos' })
      expect(row).to be_nil
      expect(problem).to eq('Trifocal: o grupo diz "por olho" e a unidade escolhida é "pelos dois olhos" — deixe os dois iguais')

      expect(described_class.sanitize_row({ group: 'Refrativa (2 olhos)', name: 'PRK', price: 4900, unit: 'por_olho' }).last)
        .to include('o grupo diz "pelos dois olhos"')
      # fácica é sempre por olho: grupo dizendo "2 olhos" precisa ser corrigido
      expect(described_class.sanitize_row({ group: 'Fácica (2 olhos)', name: 'Artisan', price: 11_900 }).first).to be_nil
      expect(described_class.sanitize_row({ group: 'Catarata (por olho)', name: 'Trifocal', price: 8490, unit: 'por_olho' }).last)
        .to be_nil
    end
  end
end
