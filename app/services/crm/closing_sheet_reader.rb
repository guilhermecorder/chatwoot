# 📄 LEITOR DA PLANILHA DE FECHAMENTO (item 132): entende o .xlsx do
# fechamento comercial da clínica — uma ABA POR MÊS, cabeçalho
# Status | Data | Paciente | Procedimento | Olho | valor total — e devolve
# as cirurgias válidas (status Ativa, com paciente e valor), com a DATA REAL
# em cada linha (aceita '01/07/2026 17:00' e número serial do Excel).
# Sem gem nova: .xlsx é zip + XML → binário `unzip` da imagem (chamado com
# array de argumentos, sem shell) + Nokogiri, que já está no projeto.
class Crm::ClosingSheetReader
  M = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'.freeze
  R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'.freeze
  EXCEL_EPOCH = Date.new(1899, 12, 30)
  MAX_ROWS_TOTAL = 20_000

  HEADER_ALIASES = {
    'status' => :status,
    'data' => :date,
    'paciente' => :name,
    'nome' => :name,
    'telefone' => :phone,
    'celular' => :phone,
    'whatsapp' => :phone,
    'fone' => :phone,
    'procedimento' => :procedure,
    'valor total' => :value,
    'valor' => :value
  }.freeze

  # Célula NUMÉRICA do Excel (sem t="s"): o XML traz o número cru com ponto
  # decimal ("162.375" = 162,375). Marcamos para o valor NÃO passar pela
  # regra brasileira do milhar, que leria 162.375 como 162 mil (Rodada 5).
  NumberCell = Class.new(String)

  def initialize(io_path)
    @path = io_path
  end

  # => { rows: [{name, date, procedure, value, sheet}], sheets: N,
  #      skipped: {duplicada: n, sem_valor: n, sem_nome: n} }
  def parse
    rows = []
    skipped = Hash.new(0)
    sheets_read = 0

    shared = shared_strings
    sheet_files.each do |sheet_name, file|
      xml = read_entry(file)
      next if xml.blank?

      sheet_rows = parse_sheet(Nokogiri::XML(xml), shared)
      header = find_header(sheet_rows)
      next unless header

      sheets_read += 1
      columns, header_index = header
      sheet_rows[(header_index + 1)..].to_a.each do |cells|
        break if rows.size >= MAX_ROWS_TOTAL

        row = extract_row(cells, columns, sheet_name)
        case row
        when Hash then rows << row
        when Symbol then skipped[row] += 1
        end
      end
    end

    { rows: rows, sheets: sheets_read, skipped: skipped }
  end

  private

  # extrai UMA entrada do zip com o binário `unzip` (array de argumentos —
  # nome de arquivo nunca passa por shell)
  def read_entry(name)
    IO.popen(['unzip', '-p', @path.to_s, name], 'rb', &:read).presence
  rescue StandardError
    nil
  end

  def shared_strings
    xml = read_entry('xl/sharedStrings.xml')
    return [] if xml.blank?

    doc = Nokogiri::XML(xml)
    doc.xpath('//m:si', 'm' => M).map { |si| si.xpath('.//m:t', 'm' => M).map(&:text).join }
  end

  # nome da aba → caminho do arquivo dentro do zip (via rels do workbook)
  def sheet_files
    workbook_xml = read_entry('xl/workbook.xml')
    rels_xml = read_entry('xl/_rels/workbook.xml.rels')
    return [] if workbook_xml.blank? || rels_xml.blank?

    workbook = Nokogiri::XML(workbook_xml)
    rel_map = Nokogiri::XML(rels_xml).css('Relationship').to_h { |rel| [rel['Id'], rel['Target']] }

    workbook.xpath('//m:sheet', 'm' => M).filter_map do |sheet|
      target = rel_map[sheet.attribute_with_ns('id', R)&.value]
      next unless target

      [sheet['name'], "xl/#{target.delete_prefix('/').delete_prefix('xl/')}"]
    end
  end

  # cada linha vira { 'A' => valor, 'B' => valor, ... }
  def parse_sheet(doc, shared)
    doc.xpath('//m:sheetData/m:row', 'm' => M).map do |row|
      row.xpath('m:c', 'm' => M).each_with_object({}) do |cell, h|
        value = cell_value(cell, shared)
        next if value.nil?

        col = cell['r'].to_s.gsub(/\d/, '')
        h[col] = value
      end
    end
  end

  # texto compartilhado (t="s") → o texto; célula numérica → NumberCell
  def cell_value(cell, shared)
    value = cell.at_xpath('m:v', 'm' => M)&.text
    return nil if value.nil?
    return shared[value.to_i].to_s if cell['t'] == 's'
    return NumberCell.new(value) if cell['t'].nil? || cell['t'] == 'n'

    value
  end

  # acha a linha de cabeçalho e mapeia coluna → campo
  def find_header(sheet_rows)
    sheet_rows.first(10).each_with_index do |cells, index|
      mapped = cells.filter_map do |col, raw|
        field = HEADER_ALIASES[raw.to_s.strip.downcase]
        [col, field] if field
      end.to_h
      return [mapped, index] if mapped.values.include?(:name) && mapped.values.include?(:value)
    end
    nil
  end

  def extract_row(cells, columns, sheet_name)
    fields = columns.each_with_object({}) { |(col, field), h| h[field] ||= cells[col] }
    name = fields[:name].to_s.strip
    return :sem_nome if name.blank? # linha de totais/vazia

    skip = status_skip(fields[:status])
    return skip if skip

    value = parse_value(fields[:value])
    return :sem_valor unless value.positive?

    {
      name: name,
      phone: parse_phone(fields[:phone]),
      date: parse_date(fields[:date]),
      procedure: fields[:procedure].to_s.strip.presence,
      value: value,
      sheet: sheet_name
    }
  end

  def status_skip(raw)
    status = raw.to_s.strip.downcase
    return :duplicada if status.include?('duplicad')
    return :cancelada if status.include?('cancelad')

    nil
  end

  # coluna Telefone/Celular/WhatsApp (opcional — pedido 01/09: casar pelo
  # telefone). Célula numérica do Excel pode vir '11987654321.0' ou em
  # notação científica — normaliza pra só dígitos antes de devolver.
  def parse_phone(raw)
    str = raw.to_s.strip
    return nil if str.blank?

    str = format('%.0f', Float(str)) if str.match?(/\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/) && str.match?(/[.eE]/)
    digits = str.gsub(/\D/, '')
    digits.length >= 8 ? digits : nil
  rescue ArgumentError
    digits = str.gsub(/\D/, '')
    digits.length >= 8 ? digits : nil
  end

  # Célula NUMÉRICA vem crua do XML ('3900', '24187.8', '162.375') e é lida
  # como número de verdade, com ponto decimal. Célula de TEXTO pode vir
  # "R$ 3.900,00" ou "5.000": achado #192, antes Float('5.000') dava 5.0
  # (R$ 5,00) — agora a regra única do Cevico::Money lê 5000,00.
  # Anotação depois do número ("5.000,00 (pago)") é ignorada; se o texto
  # tiver dois números ("2x 2.500,00"), a linha fica "sem valor" em vez de
  # entrar com valor errado (decisão segura; o Guilherme pode rever).
  def parse_value(raw)
    value = raw.is_a?(NumberCell) ? Float(raw, exception: false) : Cevico::Money.parse_with_note(raw)
    Cevico::Money.parse(value) || 0.0
  end

  # '01/07/2026 17:00' | '01/07/2026' | serial do Excel (46202.33)
  def parse_date(raw)
    str = raw.to_s.strip
    return nil if str.blank?

    if str.match?(%r{^\d{1,2}/\d{1,2}/\d{4}})
      Date.strptime(str.split(' ').first, '%d/%m/%Y').iso8601
    elsif str.match?(/^\d+(\.\d+)?$/)
      (EXCEL_EPOCH + str.to_f.floor).iso8601
    end
  rescue Date::Error
    nil
  end
end
