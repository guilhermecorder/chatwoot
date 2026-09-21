# 🕐 Janela "ao vivo" de um agente (rodada 193, extraída na 195 para o Agente
# de Ligação usar a mesma regra dos atendentes do WhatsApp):
#   live_days   = dias da semana 0..6 em que fica ao vivo (vazio = todos)
#   hours_start / hours_end = "HH:MM" (vazios = o dia inteiro;
#                             start > end = vira a noite, ex.: 20:00 → 06:00)
# Fora da janela o agente continua em SOMBRA, aprendendo.
module Crm::AgentWindow
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  module_function

  def within?(cfg, now = TZ.now) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = (cfg || {}).to_h
    days = Array(cfg['live_days']).map(&:to_i)
    return false if days.any? && days.exclude?(now.wday)

    start_at = cfg['hours_start'].to_s.presence
    end_at = cfg['hours_end'].to_s.presence
    return true if start_at.blank? || end_at.blank?

    hm = now.strftime('%H:%M')
    start_at <= end_at ? hm.between?(start_at, end_at) : (hm >= start_at || hm <= end_at)
  end
end
