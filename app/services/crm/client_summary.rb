# 📝 RESUMO DO CLIENTE (11/11/2026 · LIFE, pedido do Guilherme): "quando a pessoa der aquela
# informação de 'a conta é R$ 300, mas quero 2 ar-condicionados', isso precisa estar nas
# informações captadas… um resumo escrito do cliente, tanto na Central do cliente quanto no card".
#
# O que é: uma FICHA curta por cliente, com os campos que a empresa escolheu (conta de luz,
# consumo que vai aumentar, telhado…). Quem preenche: o atendente de IA, na hora em que o cliente
# conta (ferramenta `anotar_cliente` do Crm::ResponderTools), ou uma pessoa, pela Central do
# cliente. Onde aparece: Central do cliente, cartão do funil e tarefas do Meu Painel.
#
# Campo com 'etiqueta' vira ETIQUETA no contato quando é preenchido (e sai quando é apagado) —
# ex.: "consumo-vai-aumentar", para filtrar e acompanhar na gestão.
#
# Configuração (por conta, sem migration) em crm_settings.ai_config['ficha_cliente']:
#   { 'campos' => [{ 'chave' => 'conta', 'rotulo' => 'Conta de luz', 'quando' => 'quanto paga por mês' },
#                  { 'chave' => 'consumo_futuro', 'rotulo' => 'Vai aumentar o consumo',
#                    'quando' => 'ar-condicionado, piscina…', 'etiqueta' => 'consumo-vai-aumentar' }] }
# Conta sem campos = recurso desligado (a clínica não muda).
#
# Os valores ficam em contacts.additional_attributes['ficha_cliente']:
#   { 'conta' => { 'valor' => 'R$ 300', 'em' => '2026-11-11T…', 'por' => 'Fernando' }, … }
class Crm::ClientSummary
  CONFIG_KEY = 'ficha_cliente'.freeze
  ATTR_KEY = 'ficha_cliente'.freeze
  MAX_FIELDS = 12
  MAX_VALUE = 200

  # campos que a conta escolheu, já limpos: [{ 'chave', 'rotulo', 'quando', 'etiqueta' }]
  def self.fields(account)
    raw = CrmSetting.find_by(account: account)&.ai_config&.dig(CONFIG_KEY, 'campos')
    list = Array(raw).first(MAX_FIELDS).filter_map { |item| field(item) }
    list.uniq { |f| f['chave'] }
  end

  def self.field(item)
    return nil unless item.respond_to?(:to_h)

    row = item.to_h.transform_keys(&:to_s)
    key = slug(row['chave'])
    label = row['rotulo'].to_s.squish[0, 40]
    return nil if key.blank? || label.blank?

    { 'chave' => key, 'rotulo' => label, 'quando' => row['quando'].to_s.squish[0, 200],
      'etiqueta' => slug(row['etiqueta'], '-').presence }.compact
  end

  def self.slug(text, sep = '_')
    text.to_s.strip.downcase.gsub(/[^a-z0-9_-]/, sep).squeeze(sep)[0, 40]
  end

  def self.enabled?(account)
    fields(account).any?
  end

  # o que vai para a tela: todos os campos da conta, com o que já foi anotado
  def self.for(contact, fields: nil)
    fields ||= self.fields(contact.account)
    saved = (contact.additional_attributes || {})[ATTR_KEY].to_h
    rows = fields.map do |f|
      entry = saved[f['chave']].to_h
      { key: f['chave'], label: f['rotulo'], hint: f['quando'], value: entry['valor'].to_s.presence, at: entry['em'], by: entry['por'] }
    end
    { enabled: fields.any?, fields: rows, filled: rows.count { |r| r[:value] } }
  end

  # só o que está preenchido, em linhas curtas: [{ label:, value: }] (cartão do funil, tarefas)
  def self.lines(contact, fields:)
    return [] if fields.empty?

    self.for(contact, fields: fields)[:fields].select { |r| r[:value] }.map { |r| { label: r[:label], value: r[:value] } }
  end

  # grava os campos recebidos ({ 'conta' => 'R$ 300', … }); valor vazio apaga o campo.
  # Devolve as chaves que mudaram. `by` = nome de quem anotou.
  def self.write!(contact, values, by:)
    fields = self.fields(contact.account).index_by { |f| f['chave'] }
    incoming = clean_values(values, fields.keys)
    changed = []
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      ficha = attrs[ATTR_KEY].to_h
      changed = incoming.reject { |key, value| ficha.dig(key, 'valor').to_s == value }.keys
      changed.each { |key| put(ficha, key, incoming[key], by) }
      attrs.merge(ATTR_KEY => ficha)
    end
    sync_labels!(contact, fields.values_at(*changed), incoming)
    changed
  end

  # só os campos da conta, com o texto aparado
  def self.clean_values(values, keys)
    values.to_h.transform_keys(&:to_s).slice(*keys).transform_values { |v| v.to_s.squish[0, MAX_VALUE] }
  end

  def self.put(ficha, key, value, by)
    return ficha.delete(key) if value.blank?

    ficha[key] = { 'valor' => value, 'em' => Time.current.iso8601, 'por' => by.to_s[0, 60] }
  end

  # campo com etiqueta: preenchido → o contato ganha a etiqueta; apagado → perde
  def self.sync_labels!(contact, fields, incoming)
    fields.each do |field|
      label = field['etiqueta']
      next if label.blank?

      if incoming[field['chave']].present?
        contact.account.labels.find_or_create_by!(title: label)
        contact.add_labels([label])
      else
        contact.update_labels(contact.label_list - [label])
      end
    end
  end
end
