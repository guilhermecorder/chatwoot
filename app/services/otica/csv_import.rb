# Importação dos produtos exportados do SavWin (CSV). Colunas (cabeçalho,
# sem distinção de caixa/acento; separador ; ou ,): codigo, grife, modelo,
# cor, tamanho, custo, preco, saldo (+ opcionais tipo, linha, codigo_barras,
# ncm, descricao). Produto achado pelo código (sku) é ATUALIZADO; sem
# código ou código novo = criado. Linha sem grife/modelo/descrição = pulada.
require 'csv'

class Otica::CsvImport
  COLUMNS = {
    'codigo' => :sku, 'cod' => :sku, 'sku' => :sku, 'referencia' => :sku,
    'grife' => :brand, 'marca' => :brand,
    'linha' => :line,
    'modelo' => :model,
    'cor' => :color,
    'tamanho' => :size, 'tam' => :size,
    'custo' => :cost, 'preco_custo' => :cost, 'custo_unitario' => :cost,
    'preco' => :list_price, 'preco_venda' => :list_price, 'venda' => :list_price,
    'saldo' => :quantity, 'estoque' => :quantity, 'quantidade' => :quantity, 'qtd' => :quantity,
    'tipo' => :kind,
    'codigo_barras' => :barcode, 'ean' => :barcode, 'barras' => :barcode,
    'ncm' => :ncm,
    'descricao' => :name, 'nome' => :name, 'produto' => :name
  }.freeze
  KIND_WORDS = {
    'armacao' => 'armacao', 'armacoes' => 'armacao', 'oculos' => 'armacao', 'receituario' => 'armacao',
    'solar' => 'solar', 'sol' => 'solar',
    'lente' => 'lente', 'lentes' => 'lente', 'lente_grau' => 'lente',
    'lente_contato' => 'lente_contato', 'contato' => 'lente_contato', 'lc' => 'lente_contato',
    'servico' => 'servico', 'servicos' => 'servico',
    'outro' => 'outro', 'outros' => 'outro', 'acessorio' => 'outro', 'acessorios' => 'outro'
  }.freeze
  MAX_ROWS = 5000

  attr_reader :created, :updated, :skipped, :errors

  def initialize(account, csv_text)
    @account = account
    @csv_text = csv_text.to_s.sub('﻿', '')
    @created = 0
    @updated = 0
    @skipped = 0
    @errors = []
  end

  def call # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows = parse
    return self if rows.nil?

    header = rows.shift
    mapping = header_mapping(header)
    if mapping.values.exclude?(:brand) && mapping.values.exclude?(:model) && mapping.values.exclude?(:name)
      @errors << 'Não achei as colunas (precisa de grife/modelo ou descrição). Confira o cabeçalho.'
      return self
    end

    rows.first(MAX_ROWS).each_with_index do |row, i|
      line = i + 2
      next if row.compact.all?(&:blank?)

      attrs = attributes_for(row, mapping)
      if attrs[:brand].blank? && attrs[:model].blank? && attrs[:name].blank?
        @skipped += 1
        next
      end
      save_row(attrs, line)
    end
    self
  end

  def result
    { created: @created, updated: @updated, skipped: @skipped, errors: @errors.first(50) }
  end

  private

  def parse
    sep = @csv_text.lines.first.to_s.count(';') >= @csv_text.lines.first.to_s.count(',') ? ';' : ','
    CSV.parse(@csv_text, col_sep: sep, liberal_parsing: true)
  rescue CSV::MalformedCSVError => e
    @errors << "Arquivo CSV inválido: #{e.message}"
    nil
  end

  def header_mapping(header)
    header.to_a.each_with_index.to_h do |name, idx|
      key = I18n.transliterate(name.to_s).downcase.strip.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
      [idx, COLUMNS[key]]
    end.compact
  end

  def attributes_for(row, mapping) # rubocop:disable Metrics/CyclomaticComplexity
    attrs = {}
    mapping.each do |idx, field|
      value = row[idx].to_s.strip
      next if value.blank?

      attrs[field] = case field
                     when :cost, :list_price then Cevico::Money.parse(value) || 0.0
                     when :quantity then value.gsub(/\D/, '').to_i
                     when :kind then KIND_WORDS[I18n.transliterate(value).downcase.gsub(/[^a-z]+/, '_')] || 'outro'
                     else value[0, 120]
                     end
    end
    attrs[:kind] ||= guess_kind(attrs)
    attrs
  end

  # sem coluna tipo: lente quando a descrição/linha fala em lente; senão armação
  def guess_kind(attrs)
    text = I18n.transliterate("#{attrs[:name]} #{attrs[:model]} #{attrs[:line]} #{attrs[:brand]}").downcase
    return 'lente_contato' if text.include?('contato')
    return 'lente' if text.include?('lente')
    return 'solar' if text.match?(/\bsol\b|solar/)

    'armacao'
  end

  def save_row(attrs, line)
    product = attrs[:sku].present? ? @account.otica_products.find_by(sku: attrs[:sku]) : nil
    if product
      product.assign_attributes(attrs.except(:kind))
      saved = product.save
      @updated += 1 if saved
    else
      product = @account.otica_products.new(attrs)
      saved = product.save
      @created += 1 if saved
    end
    @errors << "linha #{line}: #{product.errors.full_messages.first}" unless saved
  rescue StandardError => e
    @errors << "linha #{line}: #{e.message[0, 120]}"
  end
end
