# Tabela de preços OFICIAL (decisão 17/07): um lugar só para preço atual
# e preço promocional de cada procedimento/produto. Alimenta o Espaço do
# Paciente/Cliente (orçamento de indicação) e os prompts dos agentes de IA.
# Fica em crm_settings.agenda_config['price_table'] (admin edita em
# Configurações → Tabela de preços). Sem tabela salva, valem os padrões
# do SEGMENTO (config/segmentos/<id>.yml → precos) — no preset clínica,
# os MESMOS valores que os prompts sempre usaram.
class Cevico::PriceList
  def self.default_items
    Segmento.precos_padrao.map do |item|
      item.transform_keys(&:to_s).slice('group', 'name', 'price', 'promo_price')
    end
  end

  def self.items(account)
    table = CrmSetting.find_by(account: account)&.agenda_config&.dig('price_table', 'items')
    list = table.presence || default_items
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
    list = items(account)
    return '- Nenhum preço cadastrado ainda (Configurações → Tabela de preços). Não cite valores.' if list.blank?

    list.group_by { |i| i['group'] }.map do |group, group_items|
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
