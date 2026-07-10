class Api::V1::Accounts::Crm::RetroLabelsController < Api::V1::Accounts::BaseController
  # POST preview — quantas conversas/contatos seriam etiquetados
  def preview
    return render_could_not_create_error('Informe o texto de busca') if params[:term].blank?

    scope = Crm::RetroLabelJob.matching_scope(Current.account, params[:term], options_params)
    conversation_ids = scope.distinct.limit(50_000).pluck(:conversation_id).compact.uniq

    sample = Current.account.conversations.where(id: conversation_ids.first(5)).includes(:contact).map do |c|
      { id: c.display_id, contact_name: c.contact&.name }
    end

    render json: {
      conversations: conversation_ids.size,
      contacts: Current.account.conversations.where(id: conversation_ids).distinct.count(:contact_id),
      sample: sample
    }
  end

  # POST apply — dispara o job em segundo plano
  def apply
    return render_could_not_create_error('Informe o texto de busca') if params[:term].blank?
    if params[:label].blank? && params[:target_stage_id].blank?
      return render_could_not_create_error('Escolha uma etiqueta e/ou uma coluna do CRM')
    end

    Crm::RetroLabelJob.perform_later(
      Current.account.id,
      params[:term].to_s,
      params[:label].to_s,
      options_params.merge('apply_to_contact' => params[:apply_to_contact] != false)
    )
    render json: { status: 'queued' }
  end

  private

  def options_params
    {
      'period_from' => params[:period_from].presence,
      'period_to' => params[:period_to].presence,
      'target_stage_id' => params[:target_stage_id].presence
    }.compact
  end
end
