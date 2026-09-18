# Avisos que entram no Radar sem vir da auditoria de IA (ligação perdida,
# resposta "não vou" da jornada). Cada tipo sabe dizer se ainda vale.
module Crm::RadarExtraAlerts
  HANDLERS = {
    Crm::Calls::RadarAlert::KIND => Crm::Calls::RadarAlert,
    Crm::Journey::RadarAlert::KIND => Crm::Journey::RadarAlert
  }.freeze

  module_function

  def handler_for(alert)
    HANDLERS[alert['kind'].to_s]
  end

  def extra?(alert)
    handler_for(alert).present?
  end

  def still_open?(account, alert)
    handler = handler_for(alert)
    handler.present? && handler.still_open?(account, alert)
  end
end
