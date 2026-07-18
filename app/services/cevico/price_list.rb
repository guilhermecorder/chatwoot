# Tabela de preços OFICIAL da clínica (decisão 17/07): um lugar só para
# preço atual e preço promocional de cada procedimento. Alimenta o Espaço
# do Paciente (orçamento de indicação) e os prompts dos agentes de IA.
# Fica em crm_settings.agenda_config['price_table'] (admin edita em
# Configurações → Tabela de preços). Sem tabela salva, valem os padrões
# abaixo — os MESMOS valores que os prompts sempre usaram.
class Cevico::PriceList
  DEFAULT_ITEMS = [
    { 'group' => 'Refrativa (2 olhos)', 'name' => 'PRK',                   'price' => 4900 },
    { 'group' => 'Refrativa (2 olhos)', 'name' => 'Lasik',                 'price' => 5700 },
    { 'group' => 'Catarata (por olho)', 'name' => 'Nacional',              'price' => 2800 },
    { 'group' => 'Catarata (por olho)', 'name' => 'Mono Rayner',           'price' => 3200 },
    { 'group' => 'Catarata (por olho)', 'name' => 'Tórica monofocal',      'price' => 5600 },
    { 'group' => 'Catarata (por olho)', 'name' => 'Foco estendido',        'price' => 5690 },
    { 'group' => 'Catarata (por olho)', 'name' => 'Trifocal',              'price' => 8490 },
    { 'group' => 'Catarata (por olho)', 'name' => 'Galaxy',                'price' => 14_990 },
    { 'group' => 'Fácica',              'name' => 'Artisan',               'price' => 11_900 }
  ].freeze

  def self.items(account)
    table = CrmSetting.find_by(account: account)&.agenda_config&.dig('price_table', 'items')
    list = table.presence || DEFAULT_ITEMS
    list.map { |item| item.slice('group', 'name', 'price', 'promo_price') }
  end

  # preço que vale hoje: promocional (se houver) senão o cheio
  def self.effective_price(item)
    item['promo_price'].presence || item['price']
  end

  # "name" (sem distinção de caixa/acento) → preço vigente, para telas
  def self.price_by_name(account)
    items(account).each_with_object({}) do |item, map|
      map[normalize(item['name'])] = effective_price(item).to_f
    end
  end

  # bloco de texto para os PROMPTS dos agentes (Atendente IA / Analista):
  # uma linha por grupo, com promoção explícita quando existir
  def self.prompt_block(account)
    items(account).group_by { |i| i['group'] }.map do |group, group_items|
      lines = group_items.map do |item|
        price = format_money(item['price'])
        if item['promo_price'].present?
          "#{item['name']} R$ #{format_money(item['promo_price'])} (promoção; preço normal R$ #{price})"
        else
          "#{item['name']} R$ #{price}"
        end
      end
      "- #{group}: #{lines.join(' · ')}."
    end.join("\n")
  end

  def self.format_money(value)
    value.to_i.to_s.gsub(/(\d)(?=(\d{3})+$)/, '\\1.')
  end

  def self.normalize(name)
    I18n.transliterate(name.to_s).downcase.strip
  end
end
