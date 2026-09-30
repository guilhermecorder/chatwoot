# 💸 item 303 (30/09/2026): TARIFAS da API oficial do WhatsApp.
#
# A Meta cobra por mensagem ENTREGUE, pela categoria (marketing, utilidade,
# autenticação e, a partir de 01/10/2026, serviço = as respostas livres do robô
# e da equipe). O status de cada mensagem diz se foi cobrada e em qual
# categoria, mas NÃO diz o valor — o valor vem desta tabela, que o admin pode
# corrigir na tela Gasto do WhatsApp quando a Meta atualizar (trimestral).
#
# Valores lidos em 30/09/2026 em whatsappbusiness.com/products/platform-pricing
# (mercado Brasil). 'service' era R$ 0 e passa a valer o preço de utilidade em
# 01/10/2026 (doc "Pricing for non-template messages").
class Crm::WhatsappPricing
  CATEGORIES = %w[marketing utility authentication service].freeze
  DEFAULTS = {
    'BRL' => { 'marketing' => 0.3217, 'utility' => 0.035, 'authentication' => 0.035, 'service' => 0.035 },
    'USD' => { 'marketing' => 0.0625, 'utility' => 0.0068, 'authentication' => 0.0068, 'service' => 0.0068 }
  }.freeze
  SETTING_KEY = 'whatsapp_pricing'.freeze
  # data em que a resposta dentro das 24h deixa de ser grátis
  SERVICE_CHARGED_FROM = Date.new(2026, 10, 1)

  class << self
    # tarifas vigentes da conta: o que o admin salvou vence o padrão
    def rates(account)
      saved = stored(account)
      currency = DEFAULTS.key?(saved['currency'].to_s) ? saved['currency'].to_s : 'BRL'
      base = DEFAULTS[currency]
      out = { 'currency' => currency, 'edited' => saved.present? }
      CATEGORIES.each do |cat|
        v = saved[cat]
        out[cat] = v.present? ? v.to_f.round(4) : base[cat]
      end
      out
    end

    # salva só o que veio válido; vazio = volta ao padrão
    def save(account, attrs)
      entry = sanitize(attrs)
      settings = CrmSetting.find_or_create_by!(account: account)
      cfg = settings.ai_config || {}
      entry.present? ? cfg[SETTING_KEY] = entry : cfg.delete(SETTING_KEY)
      settings.update!(ai_config: cfg)
      rates(account)
    end

    # expressão SQL (por linha, sem SUM — o cesto soma) do custo de UMA
    # mensagem pelo que a Meta marcou nela (cevico_wa_billing): cobrada →
    # tarifa da categoria; grátis → 0.
    # october: true = simula a regra de 01/10 (resposta na janela também paga).
    def cost_sql(rates, october: false)
      billing = "messages.additional_attributes -> 'cevico_wa_billing'"
      by_category = CATEGORIES.map { |cat| "WHEN '#{cat}' THEN #{format('%.4f', rates[cat].to_f)}" }.join(' ')
      rate = "(CASE #{billing} ->> 'category' #{by_category} ELSE 0 END)"
      charged = if october
                  "(#{billing} ->> 'type') IN ('regular', 'free_customer_service')"
                else
                  "(#{billing} ->> 'type') = 'regular'"
                end
      "(CASE WHEN #{charged} THEN #{rate} ELSE 0 END)"
    end

    private

    # aceita "0,35" ou "0.35"; ignora vazio e negativo
    def sanitize(attrs)
      attrs = (attrs || {}).to_h.stringify_keys
      entry = {}
      currency = attrs['currency'].to_s.upcase
      entry['currency'] = currency if DEFAULTS.key?(currency)
      CATEGORIES.each do |cat|
        v = attrs[cat].to_s.tr(',', '.')
        entry[cat] = v.to_f.round(4) if v.present? && v.to_f >= 0
      end
      entry
    end

    def stored(account)
      CrmSetting.find_by(account: account)&.ai_config&.dig(SETTING_KEY) || {}
    end
  end
end
