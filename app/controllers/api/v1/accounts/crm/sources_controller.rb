# 🏷️ FONTES DE PACIENTES (item 322, só admin): o cadastro das fontes (cada uma
# com o seu ambiente: funis e caixas), o retrato do carimbo e o botão que
# carimba o passado (prévia antes de gravar).
class Api::V1::Accounts::Crm::SourcesController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action :require_administrator!
  before_action :set_source, only: [:update]

  def index
    render json: Crm::SourceOverview.new(Current.account).call
  end

  # POST /crm/sources — fonte nova (sempre parceira; a da casa é uma só)
  def create
    source = Crm::Source.new(account: Current.account, kind: 'partner', key: unique_key(params[:name]),
                             position: Crm::Source.where(account_id: Current.account.id).maximum(:position).to_i + 1)
    save_and_render(source)
  end

  def update
    save_and_render(@source)
  end

  # POST /crm/sources/backfill — { apply: false } mostra o que seria carimbado;
  # { apply: true } grava. Só toca em registro sem carimbo.
  def backfill
    apply = ActiveModel::Type::Boolean.new.cast(params[:apply]) == true
    result = apply ? Crm::SourceBackfill.run!(Current.account) : Crm::SourceBackfill.preview(Current.account)
    render json: { applied: apply, result: result, pending: Crm::SourceBackfill.pending(Current.account) }
  end

  private

  def set_source
    @source = Crm::Source.find_by!(account_id: Current.account.id, id: params[:id])
  end

  def save_and_render(source) # rubocop:disable Metrics/AbcSize
    source.name = params[:name].to_s.strip if params.key?(:name)
    source.color = params[:color].to_s[/\A#\h{6}\z/] if params.key?(:color)
    assign_environment(source)
    return render json: { error: source.errors.full_messages.to_sentence }, status: :unprocessable_entity unless source.save

    # o funil mudou de dono → cards e entradas dele acompanham
    Crm::SourceBackfill.restamp_funnels!(Current.account)
    render json: Crm::SourceOverview.new(Current.account).call
  end

  # funis e caixas da fonte. A da casa não escolhe (fica com o resto); a do
  # Oftalmofácil continua escolhendo no card do OftalmoFácil em Integrações.
  def assign_environment(source) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return if source.own? || source.legacy_partner?

    taken = Crm::Source.where(account_id: Current.account.id).where.not(id: source.id).reject(&:own?)
    if params.key?(:pipeline_ids)
      # o funil principal da casa (o de entrada dos leads e dos indicadores) nunca muda de dono
      free = Current.account.crm_pipelines.pluck(:id) - taken.flat_map(&:pipeline_ids) - Crm::Sources.main_pipeline_ids(Current.account)
      source.config = source.config.merge('pipeline_ids' => Array(params[:pipeline_ids]).map(&:to_i) & free)
    end
    return unless params.key?(:inbox_ids)

    free = Current.account.inboxes.pluck(:id) - taken.flat_map(&:inbox_ids)
    source.config = source.config.merge('inbox_ids' => Array(params[:inbox_ids]).map(&:to_i) & free)
  end

  def unique_key(name)
    base = name.to_s.parameterize(separator: '_')[0, 30].presence || 'fonte'
    key = base
    n = 1
    key = "#{base}_#{n += 1}" while Crm::Source.exists?(account_id: Current.account.id, key: key)
    key
  end
end
