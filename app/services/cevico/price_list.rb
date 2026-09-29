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
    { 'group' => 'Fácica (por olho)',   'name' => 'Artisan',               'price' => 11_900 }
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
    items(account).group_by { |i| group_label(i['group']) }.map do |group, group_items|
      lines = group_items.map do |item|
        price = format_money(item['price'])
        if item['promo_price'].present?
          "#{item['name']} R$ #{format_money(item['promo_price'])} (promoção; preço normal R$ #{price})"
        else
          "#{item['name']} R$ #{price}"
        end
      end
      "- #{group}: #{lines.join(' · ')}."
    end.push("- #{PER_EYE_RULE}").join("\n")
  end

  # 🚨 item 295 (29/09, produção: o Atendente disse que os R$ 11.900 da lente
  # fácica eram "para os dois olhos"): o grupo "Fácica" era o único da tabela
  # sem dizer se o valor é por olho. Lente fácica é SEMPRE por olho — mesmo que
  # a tabela salva pela clínica não diga.
  PER_EYE_GROUPS = /f[áa]cica|artisan/i

  def self.group_label(group)
    name = group.to_s
    return name unless name.match?(PER_EYE_GROUPS)
    return name if name.match?(/por olho/i)

    "#{name.sub(/\s*\(.*\)\s*\z/, '')} (por olho)"
  end

  # regra fixa que acompanha a tabela em todo roteiro (não depende do texto editado na tela)
  PER_EYE_RULE = 'ATENÇÃO — LENTE FÁCICA (Artisan): o valor é POR OLHO (cada olho é uma cirurgia). Ao passar o ' \
                 'orçamento diga sempre "por olho". NUNCA diga que o valor vale para os dois olhos. Se o paciente ' \
                 'perguntar o total dos dois olhos, é o dobro do valor por olho. Só a refrativa (PRK/Lasik) tem ' \
                 'valor para os dois olhos; catarata e lente fácica são por olho.'.freeze

  def self.format_money(value)
    value.to_i.to_s.gsub(/(\d)(?=(\d{3})+$)/, '\\1.')
  end

  def self.normalize(name)
    I18n.transliterate(name.to_s).downcase.strip
  end
end
