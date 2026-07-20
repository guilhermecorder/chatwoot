# Planejamento de conteúdos (workflow de marketing): cards de conteúdo
# andando pelo fluxo ideia → copy → produção → revisão → publicado.
# Time inteiro cria e move; excluir é do admin.
class Api::V1::Accounts::Crm::ContentItemsController < Api::V1::Accounts::BaseController
  def index
    # arquivados (coluna oculta do item 95) ficam fora do board
    items = Current.account.cevico_content_items.where(archived_at: nil).order(:position, :id)
    render json: { items: items.map { |i| item_json(i) } }
  end

  # item 95: RENOVAR o ambiente — publicados vão pra coluna oculta
  def archive_published
    count = Current.account.cevico_content_items
                   .where(stage: 'publicado', archived_at: nil)
                   .update_all(archived_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    render json: { archived: count }
  end

  def create
    item = Current.account.cevico_content_items.create!(
      item_params.merge(position: next_position(item_params[:stage] || 'ideia'))
    )
    render json: item_json(item), status: :created
  end

  def update
    item = Current.account.cevico_content_items.find(params[:id])
    item.update!(item_params)
    render json: item_json(item)
  end

  def destroy
    return render json: { error: 'Só administradores excluem conteúdos.' }, status: :forbidden unless Current.account_user.administrator?

    Current.account.cevico_content_items.find(params[:id]).destroy!
    head :no_content
  end

  private

  def next_position(stage)
    (Current.account.cevico_content_items.where(stage: stage).maximum(:position) || -1) + 1
  end

  def item_params
    # Envelope obrigatório: a rota da API tem defaults { format: 'json' } e o
    # path param sobrescreveria um :format solto no corpo da requisição.
    params.require(:content_item).permit(:title, :format, :stage, :owner_id, :due_on, :notes, :position)
  end

  def item_json(item)
    {
      id: item.id,
      title: item.title,
      format: item.format,
      stage: item.stage,
      owner_id: item.owner_id,
      due_on: item.due_on,
      notes: item.notes,
      position: item.position,
      updated_at: item.updated_at
    }
  end
end
