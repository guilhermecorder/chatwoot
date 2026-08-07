# Régua de período PADRÃO dos dashboards CEVICO (06/08):
#   Hoje | Ontem | Últimos 7 dias | Este mês | Este ano | Personalizado
#
# Uso no controller:
#   include Crm::ResolvesPeriod
#   since, until_at = standard_period_range || resolve_range_legada
#
# Devolve nil para presets fora do padrão — assim cada tela mantém seus
# atalhos antigos funcionando enquanto migra para a régua única.
module Crm
  module ResolvesPeriod
    PERIOD_TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

    def standard_period_range
      now = PERIOD_TZ.now
      case params[:preset].presence
      when 'today'     then [now.beginning_of_day, now.end_of_day]
      when 'yesterday' then [now.yesterday.beginning_of_day, now.yesterday.end_of_day]
      when 'last7'     then [(now - 6.days).beginning_of_day, now.end_of_day]
      when 'month'     then [now.beginning_of_month, now.end_of_day]
      when 'year'      then [now.beginning_of_year, now.end_of_day]
      when 'custom'    then custom_period_range(now)
      end
    end

    def custom_period_range(now = PERIOD_TZ.now)
      from = safe_period_parse(params[:from])&.beginning_of_day
      to = safe_period_parse(params[:to])&.end_of_day
      from ||= now.beginning_of_month
      to ||= now.end_of_day
      to = from.end_of_day if to < from
      [from, to]
    end

    def safe_period_parse(value)
      PERIOD_TZ.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
