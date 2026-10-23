# 🧾 Lê o XML da NF-e de COMPRA (o arquivo que o fornecedor manda) e devolve
# a nota + itens, casando cada item com um produto da loja pelo código de
# barras (cEAN/cEANTrib) ou pelo código do fornecedor (cProd = sku). Não
# grava nada: a tela confere e manda gravar (Otica::Purchases.create!).
class Otica::NfeXmlImport
  def initialize(account, xml_text)
    @account = account
    @xml_text = xml_text.to_s
  end

  def call # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    doc = Nokogiri::XML(@xml_text)
    doc.remove_namespaces!
    inf = doc.at_xpath('//infNFe')
    raise ArgumentError, 'Não achei uma NF-e nesse arquivo (falta o bloco infNFe).' if inf.nil?

    key = inf['Id'].to_s.delete_prefix('NFe')
    ide = inf.at_xpath('ide')
    emit = inf.at_xpath('emit')
    issued = ide&.at_xpath('dhEmi')&.text.presence || ide&.at_xpath('dEmi')&.text
    purchase = {
      supplier_name: emit&.at_xpath('xNome')&.text.to_s.strip,
      supplier_cnpj: emit&.at_xpath('CNPJ')&.text.to_s.strip,
      number: ide&.at_xpath('nNF')&.text.to_s.strip,
      series: ide&.at_xpath('serie')&.text.to_s.strip,
      access_key: key,
      issued_on: (Date.parse(issued.to_s) rescue nil)&.iso8601, # rubocop:disable Style/RescueModifier
      total: inf.at_xpath('total/ICMSTot/vNF')&.text.to_f.round(2)
    }
    items = inf.xpath('det').map do |det|
      prod = det.at_xpath('prod')
      ean = [prod.at_xpath('cEAN')&.text, prod.at_xpath('cEANTrib')&.text].map { |e| e.to_s.strip }.find { |e| e.match?(/\A\d{8,14}\z/) }
      code = prod.at_xpath('cProd')&.text.to_s.strip
      product = match_product(ean, code)
      qty = prod.at_xpath('qCom')&.text.to_f
      unit = prod.at_xpath('vUnCom')&.text.to_f
      { description: prod.at_xpath('xProd')&.text.to_s.strip[0, 200], ean: ean.to_s, ncm: prod.at_xpath('NCM')&.text.to_s.strip,
        code: code[0, 60], quantity: [qty.round, 1].max, unit_cost: unit.round(2), total: (qty * unit).round(2),
        product_id: product&.id, product_name: product&.name }
    end
    { purchase: purchase, items: items }
  rescue Nokogiri::XML::SyntaxError => e
    raise ArgumentError, "XML inválido: #{e.message[0, 120]}"
  end

  private

  def match_product(ean, code)
    scope = @account.otica_products
    (ean.present? && scope.find_by(barcode: ean)) || (code.present? && scope.find_by(sku: code)) || nil
  end
end
