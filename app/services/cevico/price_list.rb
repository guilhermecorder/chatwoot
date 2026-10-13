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

  # 🔢 Rodada 5 (#401): a unidade do preço é CAMPO da linha, não mais só um
  # pedaço do texto do grupo (renomear "Catarata (por olho)" para "Catarata"
  # apagava a unidade). As 4 opções da tela → como a IA lê no roteiro.
  UNITS = {
    'por_olho' => 'por olho',
    'dois_olhos' => 'pelos dois olhos',
    'por_sessao' => 'por sessão',
    'unico' => '(valor único)'
  }.freeze

  # o texto do grupo já diz a unidade? (aí não repete na linha)
  UNIT_IN_GROUP = {
    'por_olho' => /por olho/i,
    'dois_olhos' => /(2|dois|ambos os) olhos/i,
    'por_sessao' => /por sess[ãa]o/i,
    'unico' => /valor [úu]nico/i
  }.freeze

  def self.items(account)
    table = CrmSetting.find_by(account: account)&.agenda_config&.dig('price_table', 'items')
    list = table.presence || DEFAULT_ITEMS
    list.map do |item|
      row = item.slice('group', 'name', 'price', 'promo_price')
      # promoção R$ 0 (ou maior que o preço) não vale — some da tela e da IA
      row['promo_price'] = valid_promo(row['price'], row['promo_price'])
      row['unit'] = unit_for(item)
      row
    end
  end

  # unidade da linha: a escolhida na tela; sem escolha, a que o texto do grupo
  # diz. Lente fácica (Artisan) é SEMPRE por olho, escolha o que escolher.
  def self.unit_for(item)
    text = "#{item['group']} #{item['name']}"
    return 'por_olho' if text.match?(PER_EYE_GROUPS)

    unit = item['unit'].to_s
    return unit if UNITS.key?(unit)

    UNIT_IN_GROUP.find { |_key, regex| item['group'].to_s.match?(regex) }&.first
  end

  # promoção só vale se for MAIOR que zero e MENOR que o preço normal
  def self.valid_promo(price, promo)
    return nil if promo.blank?

    value = promo.to_f
    value.positive? && value < price.to_f ? promo : nil
  end

  # linha com preço de verdade (R$ 0 ou vazio nunca chega ao paciente)
  def self.priced?(item)
    item['price'].to_f.positive?
  end

  # 🔢 Rodada 5 (#401): limpa UMA linha vinda da tela (Configurações → Tabela
  # de preços). Devolve [linha, nil], [nil, nil] (linha sem nome, ignorada) ou
  # [nil, "Nome: o que falta"] quando a linha não pode ser gravada:
  # - sem preço (vazio, R$ 0 ou negativo);
  # - sem unidade (nem escolhida, nem dita no texto do grupo);
  # - grupo e unidade se contradizem ("Catarata (por olho)" + "dois olhos") —
  #   o prompt sairia com as duas, a mesma confusão do item 295.
  def self.sanitize_row(raw)
    raw = raw.to_h.with_indifferent_access
    name = raw[:name].to_s.strip[0, 80]
    return [nil, nil] if name.blank?

    price = money(raw[:price])
    return [nil, "#{name}: falta o preço (maior que zero)"] unless price&.positive?

    row = build_row(raw, name, price)
    problem = unit_problem(row['group'], row['unit'])
    return [nil, "#{name}: #{problem}"] if problem

    [row.compact, nil]
  end

  def self.build_row(raw, name, price)
    group = raw[:group].to_s.strip[0, 80].presence || 'Outros'
    row = { 'group' => group, 'name' => name, 'price' => price, 'promo_price' => valid_promo(price, money(raw[:promo_price])) }
    row.merge('unit' => unit_for(row.merge('unit' => raw[:unit])))
  end

  # o que está errado na unidade da linha (texto para a equipe) ou nil
  def self.unit_problem(group, unit)
    return 'escolha a unidade (por olho, dois olhos, por sessão ou único)' unless UNITS.key?(unit.to_s)

    other = group_unit_conflict(group, unit)
    return nil unless other

    "o grupo diz \"#{UNITS[other].delete('()')}\" e a unidade escolhida é \"#{UNITS[unit].delete('()')}\" — deixe os dois iguais"
  end

  # o texto do grupo fala de OUTRA unidade? devolve essa outra (ou nil)
  def self.group_unit_conflict(group, unit)
    said = UNIT_IN_GROUP.select { |_key, regex| group.to_s.match?(regex) }.keys
    return nil if said.empty? || said.include?(unit.to_s)

    said.first
  end

  # número vindo da tela → reais com 2 casas (nil quando vazio ou inválido)
  def self.money(value)
    return nil if value.blank?

    # Rodada 6 (#260): regra única do dinheiro — "8.490" é R$ 8.490 (o to_f dava R$ 8,49)
    number = Cevico::Money.parse(value)
    number&.finite? ? number : nil
  end

  # preço que vale hoje: promocional (se houver e for válido) senão o cheio
  def self.effective_price(item)
    valid_promo(item['price'], item['promo_price']) || item['price']
  end

  # "name" (sem distinção de caixa/acento) → preço vigente, para telas
  def self.price_by_name(account)
    items(account).select { |item| priced?(item) }.each_with_object({}) do |item, map|
      map[normalize(item['name'])] = effective_price(item).to_f
    end
  end

  # bloco de texto para os PROMPTS dos agentes (Atendente IA / Analista):
  # uma linha por grupo, com promoção explícita quando existir e a unidade
  # (por olho / dois olhos / por sessão / valor único). Linha sem preço
  # (R$ 0 ou vazia) fica de fora até o admin preencher.
  def self.prompt_block(account)
    items(account).select { |i| priced?(i) }.group_by { |i| group_label(i['group']) }.map do |group, group_items|
      lines = group_items.map do |item|
        unit = unit_suffix(item, group)
        price = "#{format_money(item['price'])}#{unit}"
        if item['promo_price'].present?
          "#{item['name']} R$ #{format_money(item['promo_price'])}#{unit} (promoção; preço normal R$ #{price})"
        else
          "#{item['name']} R$ #{price}"
        end
      end
      "- #{group}: #{lines.join(' · ')}."
    end.push("- #{PER_EYE_RULE}").join("\n")
  end

  # " por olho" depois do valor — vazio quando o nome do grupo já diz isso
  def self.unit_suffix(item, group)
    unit = item['unit'].to_s
    return '' unless UNITS.key?(unit)
    return '' if group.to_s.match?(UNIT_IN_GROUP[unit])

    " #{UNITS[unit]}"
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
