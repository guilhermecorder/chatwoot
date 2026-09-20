# Filtros da lista/CSV de chamadas (item 176): situação, direção, quem cuidou,
# atendente, caixa, paciente, busca por nome/telefone e período (preset da
# régua padrão ou since/until). Devolve um scope de Crm::Call.
class Crm::Calls::ListFilter
  include Crm::ResolvesPeriod

  NOT_ANSWERED = %i[missed rejected failed canceled].freeze

  attr_reader :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  def scope
    base = Crm::Call.where(account_id: @account.id)
    apply_period(apply_search(apply_ids(apply_kind(base))))
  end

  private

  def apply_kind(scope)
    scope = scope.where(status: params[:status]) if Crm::Call.statuses.key?(params[:status].to_s)
    scope = scope.where(status: NOT_ANSWERED) if params[:status].to_s == 'not_answered'
    scope = scope.where(direction: params[:direction]) if Crm::Call.directions.key?(params[:direction].to_s)
    apply_handler(scope)
  end

  def apply_handler(scope)
    return scope unless %w[human ai].include?(params[:handled_by].to_s)

    scope.where(handled_by: params[:handled_by])
  end

  def apply_ids(scope)
    %i[user_id contact_id inbox_id].each do |key|
      scope = scope.where(key => params[key]) if params[key].present?
    end
    scope
  end

  def apply_search(scope)
    term = params[:q].to_s.strip
    term.length >= 2 ? scope.search(term) : scope
  end

  def apply_period(scope)
    range = list_range
    range ? scope.in_period(*range) : scope
  end

  def list_range
    preset_range = standard_period_range
    return preset_range if preset_range

    since = safe_period_parse(params[:since])
    until_at = list_until
    return nil if since.nil? && until_at.nil?

    [since || Time.zone.at(0), until_at || PERIOD_TZ.now.end_of_day]
  end

  # "até" só com a data (sem hora) = o dia inteiro
  def list_until
    until_at = safe_period_parse(params[:until])
    return until_at if until_at.nil? || params[:until].to_s.length > 10

    until_at.end_of_day
  end
end
