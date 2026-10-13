# 💸 #444 (13/10): corrige o HISTÓRICO do "Gasto da IA" do Sonnet 5.
#
# Até o conserto, cada chamada do Sonnet 5 era gravada com o preço errado
# (US$ 3 / US$ 15 por milhão) em vez do preço de lista (US$ 2 / US$ 10). O custo
# fica guardado linha a linha em crm_ai_usages e nunca é recalculado, então o
# passado continua ~50% maior no Gasto da IA, no CAC/Financeiro e no mapa.
#
# Como funciona (seguro para rodar quantas vezes quiser):
# - só olha linhas do Sonnet 5;
# - refaz a conta de cada linha com os tokens guardados e o preço VELHO;
#   só mexe se o custo gravado bater com essa conta (= prova de que é preço velho);
# - troca pelo custo com o preço NOVO (dá exatamente 2/3 do valor antigo).
# Depois de corrigida, a linha não bate mais com o preço velho — rodar de novo
# não mexe nela. Linhas que não batem com nenhuma conta (ex.: 23–25/09, antes
# de existirem as colunas de cache) ficam como estão e aparecem no resumo.
#
# Não roda sozinho: só pela rake `cevico:ai_usage_reprice` com DRY=0.
class Crm::AiUsageReprice
  MODEL = 'claude-sonnet-5'.freeze
  OLD_PRICE = [3.0, 15.0].freeze # preço errado que estava no código até 13/10
  TOLERANCE = 0.000002 # o custo é gravado com 6 casas; folga de arredondamento

  def initialize(account_id: nil)
    @account_id = account_id
  end

  def scope
    rel = Crm::AiUsage.where(model: MODEL).where('cost_usd > 0')
    @account_id ? rel.where(account_id: @account_id) : rel
  end

  # linhas gravadas com o preço velho (as que seriam corrigidas)
  def stale
    scope.where("ABS(cost_usd - #{cost_sql(*OLD_PRICE)}) <= #{TOLERANCE}")
  end

  # linhas que já estão com o preço novo
  def current
    scope.where("ABS(cost_usd - #{cost_sql(*new_price)}) <= #{TOLERANCE}")
  end

  def summary
    stale_rel = stale
    {
      total: scope.count,
      stale: stale_rel.count,
      current: current.count,
      stale_cost_usd: stale_rel.sum(:cost_usd).to_f.round(2),
      new_cost_usd: stale_rel.sum(Arel.sql("ROUND(#{cost_sql(*new_price)}, 6)")).to_f.round(2),
      first_at: stale_rel.minimum(:created_at),
      last_at: stale_rel.maximum(:created_at)
    }.tap { |s| s[:unmatched] = s[:total] - s[:stale] - s[:current] }
  end

  # aplica a correção; devolve quantas linhas mudaram
  # (update_all de propósito: um só UPDATE no banco, só troca o custo; o modelo
  # não tem regra de validação sobre cost_usd)
  def apply!
    stale.update_all("cost_usd = ROUND(#{cost_sql(*new_price)}, 6), updated_at = NOW()") # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def new_price
    Crm::AiAgentConfig::PRICING.fetch(MODEL)
  end

  # mesma conta do record_usage (Crm::AiAgentConfig), em SQL:
  # entrada nova + gravação no cache 2x + leitura do cache 10% + saída
  def cost_sql(price_in, price_out)
    pin = format('%.6f', price_in)
    pout = format('%.6f', price_out)
    write = format('%.6f', Crm::AiAgentConfig::CACHE_WRITE_FACTOR)
    read = format('%.6f', Crm::AiAgentConfig::CACHE_READ_FACTOR)
    "(((input_tokens - cache_read_tokens - cache_write_tokens) * #{pin} + " \
      "cache_write_tokens * #{pin} * #{write} + cache_read_tokens * #{pin} * #{read} + " \
      "output_tokens * #{pout}) / 1000000.0)"
  end
end
