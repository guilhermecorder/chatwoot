# 🆚 COMPARATIVO DE CAIXAS (item 413, 24/11): cada caixa de entrada lado a lado,
# pela TURMA que chegou por ela no período (Crm::InboxComparison). Mesmo acesso
# do Dashboard CRM (nó relatorios.crm); dinheiro (gasto de anúncio, custo por
# lead, custo da IA) só para administrador, como lá.
#   GET crm/inbox_comparison?preset=…&compare=previous|month|pick&compare_month=AAAA-MM
#   GET crm/inbox_comparison/lines?…  📈 item 418: as linhas por caixa, campanha e criativo
#     (Crm::InboxLines; pedido à parte para não pesar o comparativo; sem dinheiro)
#   📍 item 419 — MARCOS DE TESTE (a caixa comparada com ela mesma):
#   GET  crm/inbox_comparison/marks          os marcos da conta (Crm::AttendanceMilestones)
#   POST crm/inbox_comparison/mark|unmark    anota / apaga um marco (só administrador)
#   …?preset=mark&mark=<id>                  o período vira "do marco até agora" e a base de
#                                            comparação, o mesmo tempo logo antes do marco
class Api::V1::Accounts::Crm::InboxComparisonsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  CACHE_TTL = 5.minutes

  def show
    since, until_at = standard_period_range || custom_period_range
    compare = period_comparison(since, until_at)
    admin = Current.account_user&.administrator? == true
    key = ['cevico_inbox_comparison', Current.account.id, since.to_i, until_at.to_i, compare.cache_key, admin]
    payload = Rails.cache.fetch(key, expires_in: CACHE_TTL) do
      Crm::InboxComparison.new(account: Current.account, since: since, until_at: until_at, compare: compare,
                               invest: admin ? invest_for(since, until_at) : nil).call
    end
    render json: payload
  end

  def lines
    since, until_at = standard_period_range || custom_period_range
    compare = period_comparison(since, until_at)
    marks = Crm::AttendanceMilestones.list(Current.account)
    key = ['cevico_inbox_lines', Current.account.id, since.to_i, until_at.to_i, compare.cache_key, marks_digest(marks)]
    payload = Rails.cache.fetch(key, expires_in: CACHE_TTL) do
      Crm::InboxLines.new(account: Current.account, since: since, until_at: until_at, compare: compare, marks: marks).call
    end
    render json: payload
  end

  # 📍 item 419: os marcos de teste (lista para todos que veem o relatório)
  def marks
    render json: marks_payload
  end

  def mark # rubocop:disable Metrics/AbcSize
    return render json: { error: 'Só o administrador anota um marco.' }, status: :forbidden unless admin?

    title = params[:title].to_s.strip
    at = params[:at].present? ? Crm::AttendanceMilestones.parse(params[:at]) : Time.current
    error = mark_error(title, at)
    return render json: { error: error }, status: :unprocessable_entity if error

    inbox_ids = Current.account.inboxes.where(id: Array(params[:inbox_ids]).map(&:to_i)).pluck(:id)
    Crm::AttendanceMilestones.add!(Current.account, title: title, note: params[:note], at: at.iso8601, by: Current.user&.name, inbox_ids: inbox_ids)
    render json: marks_payload
  end

  def unmark
    return render json: { error: 'Só o administrador apaga um marco.' }, status: :forbidden unless admin?

    Crm::AttendanceMilestones.remove!(Current.account, params[:id])
    render json: marks_payload
  end

  private

  def admin?
    Current.account_user&.administrator? == true
  end

  def marks_digest(marks)
    Digest::MD5.hexdigest(marks.map { |m| [m['id'], m['at'], m['inbox_ids']] }.to_json)
  end

  def mark_error(title, at)
    return 'Dê um nome ao marco.' if title.blank?

    'Data do marco inválida (não pode ser no futuro).' if at.nil? || at > 1.minute.from_now
  end

  # o marco mais novo primeiro; `horas` = há quanto tempo foi (a tela avisa quando ainda é cedo para ler)
  def marks_payload
    names = Current.account.inboxes.pluck(:id, :name).to_h
    { marcos: Crm::AttendanceMilestones.list(Current.account).filter_map { |m| mark_row(m, names) }, pode_marcar: admin? }
  end

  def mark_row(mark, names)
    at = Crm::AttendanceMilestones.parse(mark['at'])
    return if at.nil?

    ids = Array(mark['inbox_ids']).map(&:to_i)
    { id: mark['id'], titulo: mark['title'], nota: mark['note'], por: mark['by'], em: at.iso8601,
      quando: at.in_time_zone(Crm::ResolvesPeriod::PERIOD_TZ).strftime('%d/%m/%Y %Hh%M'),
      horas: ((Time.current - at) / 3600.0).round(1), inbox_ids: ids, caixas: names.values_at(*ids).compact }
  end

  # o gasto dos anúncios do período, com o MESMO cache do Dashboard CRM
  def invest_for(since, until_at) # rubocop:disable Metrics/AbcSize
    meta = Rails.cache.fetch(['cevico_meta_spend', Current.account.id, since.to_date.iso8601, until_at.to_date.iso8601],
                             expires_in: 10.minutes) do
      Crm::MetaInsightsService.new(account: Current.account, since_date: since.to_date, until_date: until_at.to_date).call
    end
    config = investments_config
    {
      meta_total: meta[:spend].to_f.positive? ? meta[:spend].to_f : nil,
      meta_note: meta[:error].presence || (meta[:configured] ? nil : 'Meta Ads não configurado em Integrações'),
      google: config.values.any? { |cfg| cfg['mode'] == 'google_auto' } ? google_cost(since, until_at) : nil,
      config: config
    }
  end

  def google_cost(since, until_at)
    Rails.cache.fetch(['cevico_google_cost', Current.account.id, since.to_date.iso8601, until_at.to_date.iso8601],
                      expires_in: 10.minutes) do
      Crm::GoogleAdCostService.new(account: Current.account, since_date: since.to_date, until_date: until_at.to_date).call
    end
  end

  # config por caixa no formato novo {mode, monthly}; número puro = legado manual
  def investments_config
    raw = CrmSetting.find_by(account: Current.account)&.agenda_config&.dig('inbox_investments') || {}
    raw.transform_values { |value| value.is_a?(Hash) ? value : { 'mode' => 'manual', 'monthly' => value.to_f } }
  end
end
