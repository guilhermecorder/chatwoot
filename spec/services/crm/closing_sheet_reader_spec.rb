require 'rails_helper'
require 'zlib'

# 📄 Rodada 5 da auditoria (#192): na planilha de fechamento (.xlsx), a célula
# de TEXTO "5.000" virava R$ 5,00 (Float('5.000') = 5.0) — card e receita
# 1000× menores. Monta um .xlsx de verdade (zip sem compressão, feito aqui
# mesmo) e lê pelo caminho real do leitor.
RSpec.describe Crm::ClosingSheetReader do
  let(:ns) { 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"' }
  let(:ns_r) { 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"' }
  let(:rels) do
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
      '<Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'
  end
  let(:workbook) { %(<workbook #{ns} #{ns_r}><sheets><sheet name="Julho" sheetId="1" r:id="rId1"/></sheets></workbook>) }

  # zip "stored" mínimo: o binário unzip da imagem lê sem problema
  def build_zip(entries)
    body = ''.b
    central = ''.b
    entries.each do |name, data|
      data = data.b
      sizes = [Zlib.crc32(data), data.bytesize, data.bytesize, name.bytesize]
      offset = body.bytesize
      body << [0x04034b50, 20, 0, 0, 0, 0, *sizes, 0].pack('VvvvvvVVVvv') << name << data
      central << [0x02014b50, 20, 20, 0, 0, 0, 0, *sizes, 0, 0, 0, 0, 0, offset].pack('VvvvvvvVVVvvvvvVV') << name
    end
    body + central + [0x06054b50, 0, 0, entries.size, entries.size, central.bytesize, body.bytesize, 0].pack('VvvvvVVv')
  end

  def cell(ref, value, texto:)
    texto ? %(<c r="#{ref}" t="s"><v>#{value}</v></c>) : %(<c r="#{ref}"><v>#{value}</v></c>)
  end

  # linhas: [[nome, valor, tipo]] — tipo :texto (célula de texto) ou :numero (célula numérica crua)
  def xlsx_with(linhas)
    textos = ['Paciente', 'valor total'] + linhas.flat_map { |nome, valor, tipo| tipo == :texto ? [nome, valor] : [nome] }
    rows = linhas.each_with_index.map { |linha, i| row_xml(linha, i + 2, textos) }
    header = %(<row r="1">#{cell('A1', 0, texto: true)}#{cell('B1', 1, texto: true)}</row>)
    sheet = %(<worksheet #{ns}><sheetData>#{header}#{rows.join}</sheetData></worksheet>)
    shared = %(<sst #{ns}>#{textos.map { |t| "<si><t>#{t}</t></si>" }.join}</sst>)
    write_xlsx('xl/workbook.xml' => workbook, 'xl/_rels/workbook.xml.rels' => rels,
               'xl/sharedStrings.xml' => shared, 'xl/worksheets/sheet1.xml' => sheet)
  end

  def row_xml((nome, valor, tipo), numero, textos)
    texto = tipo == :texto
    valor = textos.index(valor) if texto
    %(<row r="#{numero}">#{cell("A#{numero}", textos.index(nome), texto: true)}#{cell("B#{numero}", valor, texto: texto)}</row>)
  end

  def write_xlsx(entries)
    file = Tempfile.new(['fechamento', '.xlsx'])
    file.binmode
    file.write(build_zip(entries))
    file.close
    file
  end

  it 'célula de texto "5.000" vira R$ 5.000,00 (antes virava R$ 5,00)' do
    file = xlsx_with([['Maria Souza', '5.000', :texto]])
    rows = described_class.new(file.path).parse[:rows]
    expect(rows.map { |r| r[:value] }).to eq([5000.0])
  ensure
    file&.unlink
  end

  it 'lê texto em formato brasileiro e número cru do Excel lado a lado', :aggregate_failures do
    file = xlsx_with([
                       ['Ana', 'R$ 12.500,00', :texto],
                       ['Bia', '3900,5', :texto],
                       ['Caio', '3900', :numero],
                       ['Davi', '24187.8', :numero],
                       ['Eva', 'à combinar', :texto]
                     ])
    parsed = described_class.new(file.path).parse
    expect(parsed[:rows].to_h { |r| [r[:name], r[:value]] }).to eq('Ana' => 12_500.0, 'Bia' => 3900.5, 'Caio' => 3900.0, 'Davi' => 24_187.8)
    expect(parsed[:skipped][:sem_valor]).to eq(1)
  ensure
    file&.unlink
  end

  it 'célula NUMÉRICA com 3 casas (fórmula) não vira milhar: 162.375 continua 162,375' do
    file = xlsx_with([['Fábio', '162.375', :numero], ['Gil', '5.000', :texto]])
    rows = described_class.new(file.path).parse[:rows]
    expect(rows.to_h { |r| [r[:name], r[:value]] }).to eq('Fábio' => 162.375.round(2), 'Gil' => 5000.0)
  ensure
    file&.unlink
  end

  it 'anotação depois do número é ignorada; texto com dois números fica sem valor', :aggregate_failures do
    file = xlsx_with([
                       ['Hugo', '5.000,00 (pago)', :texto],
                       ['Iris', '$ 5.000', :texto],
                       ['Júlia', 'R $ 5.000', :texto],
                       ['Leo', '2x 2.500,00', :texto]
                     ])
    parsed = described_class.new(file.path).parse
    expect(parsed[:rows].to_h { |r| [r[:name], r[:value]] }).to eq('Hugo' => 5000.0, 'Iris' => 5000.0, 'Júlia' => 5000.0)
    expect(parsed[:skipped][:sem_valor]).to eq(1)
  ensure
    file&.unlink
  end
end
