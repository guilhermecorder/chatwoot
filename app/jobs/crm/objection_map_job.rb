# Gera o Mapa de Objeções sob demanda (botão do admin em Ferramentas de
# Fechamento). Usa a config do agente Consultor Comercial.
class Crm::ObjectionMapJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find(account_id)
    result = Crm::ObjectionMapService.new(account).call
    Rails.logger.info "[Crm::ObjectionMap] account=#{account_id} #{result.inspect}"
  end
end
