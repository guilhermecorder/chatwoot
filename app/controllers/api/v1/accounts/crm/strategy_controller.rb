# Painel Estratégico CEVICO (só admin): a empresa por pilares — cada um com
# responsáveis, semáforo de saúde, nota de desempenho e as estratégias/ações
# corretivas (dono, prazo, andamento). Os 3 pilares combinados nascem
# prontos na primeira visita.
class Api::V1::Accounts::Crm::StrategyController < Api::V1::Accounts::BaseController
  before_action :require_administrator

  def show
    CevicoPillar.seed_defaults!(account)
    render json: board_json
  end

  def create_pillar
    pillar = account.cevico_pillars.create!(
      pillar_params.merge(position: (account.cevico_pillars.maximum(:position) || -1) + 1)
    )
    render json: pillar_json(pillar)
  end

  def update_pillar
    pillar = account.cevico_pillars.find(params[:pillar_id])
    pillar.update!(pillar_params)
    render json: pillar_json(pillar)
  end

  def delete_pillar
    account.cevico_pillars.find(params[:pillar_id]).destroy!
    head :ok
  end

  def create_item
    pillar = account.cevico_pillars.find(params[:pillar_id])
    item = pillar.strategies.create!(
      item_params.merge(account: account,
                        position: (pillar.strategies.maximum(:position) || -1) + 1)
    )
    render json: item_json(item)
  end

  def update_item
    item = account.cevico_strategies.find(params[:item_id])
    item.update!(item_params)
    render json: item_json(item)
  end

  def delete_item
    account.cevico_strategies.find(params[:item_id]).destroy!
    head :ok
  end

  private

  def require_administrator
    return if Current.account_user.administrator?

    render json: { error: 'O Painel Estratégico é só para administradores.' }, status: :forbidden
  end

  def account
    Current.account
  end

  def pillar_params
    permitted = params.permit(:name, :subtitle, :emoji, :color, :status, :health_note, owner_ids: [])
    permitted[:owner_ids] = Array(permitted[:owner_ids]).map(&:to_i) if params.key?(:owner_ids)
    permitted
  end

  def item_params
    params.permit(:kind, :title, :description, :status, :owner_id, :due_on)
  end

  def board_json
    pillars = account.cevico_pillars.order(:position, :id).includes(:strategies)
    { pillars: pillars.map { |p| pillar_json(p) } }
  end

  def pillar_json(pillar)
    {
      id: pillar.id,
      name: pillar.name,
      subtitle: pillar.subtitle,
      emoji: pillar.emoji,
      color: pillar.color,
      status: pillar.status,
      health_note: pillar.health_note,
      owner_ids: Array(pillar.owner_ids).map(&:to_i),
      items: pillar.strategies.sort_by { |s| [s.position, s.id] }.map { |s| item_json(s) }
    }
  end

  def item_json(item)
    {
      id: item.id,
      pillar_id: item.pillar_id,
      kind: item.kind,
      title: item.title,
      description: item.description,
      status: item.status,
      owner_id: item.owner_id,
      due_on: item.due_on
    }
  end
end
