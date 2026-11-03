# 📣 item 381: o PLANO DE REATIVAÇÃO EM FATIAS (Marketing → Campanhas →
# Reativação → "Plano de envio"). Leitura para o time; configurar, ativar,
# pausar e rodar agora = quem edita campanhas.
class Api::V1::Accounts::Crm::ReactivationPlansController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action -> { require_access('crm.campanhas', :edit) }, only: %i[update activate pause run_now]
  before_action :mother, only: %i[activate pause run_now]

  def show
    render json: Crm::ReactivationPlan.payload(Current.account)
  end

  # salva a configuração (cria a mãe como rascunho na 1ª vez; não muda o status)
  def update
    Crm::ReactivationPlan.upsert!(Current.account, plan_params, user: Current.user)
    render json: Crm::ReactivationPlan.payload(Current.account)
  rescue ArgumentError => e
    render_could_not_create_error(e.message)
  end

  # prévia sem salvar: fatias, tamanho de cada uma, dias estimados
  def simulate
    cfg = Crm::ReactivationPlan.normalize(plan_params)
    mother = Crm::ReactivationPlan.find(Current.account) || Crm::Campaign.new(account: Current.account)
    render json: Crm::ReactivationPlan.simulate(mother, cfg)
  end

  def activate
    cfg = Crm::ReactivationPlan.config(@mother)
    if cfg['slices'].none? { |s| s['share'].positive? && s['templates'].any? }
      return render_could_not_create_error('Defina pelo menos uma fatia com porcentagem e modelo aprovado')
    end
    return render_could_not_create_error('As porcentagens das fatias precisam somar 100') unless cfg['slices'].sum { |s| s['share'] } == 100

    @mother.update!(status: :processing, started_at: @mother.started_at || Time.current, finished_at: nil)
    render json: Crm::ReactivationPlan.payload(Current.account)
  end

  def pause
    return render_could_not_create_error('O plano não está ativo') unless @mother.processing?

    @mother.update!(status: :paused)
    render json: Crm::ReactivationPlan.payload(Current.account)
  end

  # manda a fatia de UMA hora agora (ignora janela/dia útil; respeita teto e regras)
  def run_now
    return render_could_not_create_error('Ative o plano antes de rodar') unless @mother.processing?

    sent = Crm::ReactivationPlan.run!(@mother, force: true)
    render json: Crm::ReactivationPlan.payload(Current.account).merge(sent_now: sent)
  end

  private

  def mother
    @mother = Crm::ReactivationPlan.find(Current.account)
    render_could_not_create_error('Salve o plano antes') if @mother.nil?
  end

  def plan_params
    params.require(:plan).permit(
      :daily_cap, :hour_from, :hour_to, :weekdays_only, :inbox_daily_cap, :route_by_origin, :default_inbox_id,
      :max_open_conversations, :quiet_hours, :skip_future_appointment, :min_age_days, :order,
      slices: [:key, :stage_id, :share, { templates: {} }]
    ).to_h
  end
end
