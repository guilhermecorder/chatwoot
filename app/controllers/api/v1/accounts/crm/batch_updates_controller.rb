# Tratamento de dados → "Mover e etiquetar em lote": prévia + aplicação
# em segundo plano (Crm::BatchUpdateJob). Admin-only — mexe na base inteira.
class Api::V1::Accounts::Crm::BatchUpdatesController < Api::V1::Accounts::BaseController
  before_action :check_admin

  # POST preview — quantos cards seriam afetados + amostra
  def preview
    return render_could_not_create_error('Escolha pelo menos um filtro') if filter_params.empty?

    scope = Crm::BatchUpdateJob.matching_cards(Current.account, filter_params)
    sample = scope.limit(5).includes(:contact, :stage).map do |card|
      { name: card.contact&.name, stage: card.stage&.name, value: card.value }
    end

    render json: { cards: scope.count, sample: sample }
  end

  # POST apply — dispara o job em segundo plano
  def apply
    return render_could_not_create_error('Escolha pelo menos um filtro (coluna, valor, caixa ou etiqueta)') if filter_params.empty?
    if params[:target_stage_id].blank? && params[:add_label].blank?
      return render_could_not_create_error('Escolha uma coluna de destino e/ou uma etiqueta para adicionar')
    end

    Crm::BatchUpdateJob.perform_later(
      Current.account.id,
      filter_params,
      { 'target_stage_id' => params[:target_stage_id].presence,
        'add_label' => params[:add_label].presence }.compact
    )
    render json: { status: 'queued' }
  end

  private

  def filter_params
    {
      'stage_id' => params[:stage_id].presence,
      'value_filter' => params[:value_filter].presence,
      'inbox_id' => params[:inbox_id].presence,
      'label' => params[:label].presence
    }.compact
  end

  def check_admin
    return if Current.account_user.administrator?

    render json: { error: 'Apenas administradores podem usar o tratamento em lote.' }, status: :forbidden
  end
end
