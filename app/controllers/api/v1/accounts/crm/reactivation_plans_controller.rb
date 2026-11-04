# 📣 item 381: o PLANO DE REATIVAÇÃO EM FATIAS (Marketing → Campanhas →
# Reativação → "Plano de envio"). Leitura para o time; configurar, ativar,
# pausar e rodar agora = quem edita campanhas.
class Api::V1::Accounts::Crm::ReactivationPlansController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action -> { require_access('crm.campanhas', :edit) }, only: %i[update activate pause run_now send_batch]
  before_action :mother, only: %i[activate pause run_now send_batch preview_next queue batches]

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
  # 🎛️ item 382: no modo de aprovação manual, prepara o lote e devolve a prévia
  def run_now
    return render_could_not_create_error('Ative o plano antes de rodar') unless @mother.processing?

    sent = Crm::ReactivationPlan.run!(@mother, force: true)
    render json: Crm::ReactivationPlan.payload(Current.account).merge(sent_now: sent)
  end

  # 🎛️ item 382: a próxima fatia, pessoa por pessoa, SEM mandar (force=1 ignora a janela)
  def preview_next
    batch = Crm::ReactivationBatch.plan(@mother, force: params[:force].to_s == '1')
    render json: batch.slice(:skip, :quota, :remaining_today, :warnings)
                      .merge(today: batch[:today]&.iso8601, rows: Array(batch[:rows]).map { |r| r.except(:tpl) },
                             approval: batch[:cfg]['approval'], test_mode: batch[:cfg]['test_mode'])
  end

  # 🎛️ item 382: manda EXATAMENTE as pessoas aprovadas na tela (ids), agora
  def send_batch
    return render_could_not_create_error('Ative o plano antes de aprovar um lote') unless @mother.processing?

    ids = Array(params[:contact_ids]).map(&:to_i).reject(&:zero?)
    return render_could_not_create_error('Escolha pelo menos uma pessoa') if ids.empty?

    sent = Crm::ReactivationPlan.run!(@mother, force: true, approved_ids: ids)
    render json: Crm::ReactivationPlan.payload(Current.account).merge(sent_now: sent)
  end

  # 🎛️ item 382: a fila inteira projetada dia a dia (lote 1 = hoje…)
  def queue
    render json: Crm::ReactivationBatch.queue(@mother, days: params.fetch(:days, 30).to_i.clamp(1, 90),
                                                       detail_days: params.fetch(:detail_days, 3).to_i.clamp(0, 10))
  end

  # 🎛️ item 382: os lotes que já saíram, com o status de entrega de cada pessoa
  def batches
    render json: { batches: Crm::ReactivationBatch.batches(@mother, days: params.fetch(:days, 14).to_i.clamp(1, 90)) }
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
      :approval, :test_mode, test_phones: [], slices: [:key, :stage_id, :share, { templates: {} }]
    ).to_h
  end
end
