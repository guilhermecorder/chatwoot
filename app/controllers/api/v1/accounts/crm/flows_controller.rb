# 🗺️ MAPA DE FLUXOS (item 170): fluxogramas dos agentes/automações com o
# estado ao vivo da conta. Área "Automações" (admin ou atendente com a
# concessão). index = lista inteira; show = um fluxo (refresh a cada 60 s).
class Api::V1::Accounts::Crm::FlowsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:automations) }

  def index
    render json: {
      flows: Crm::FlowMap::Registry.all(Current.account),
      groups: Crm::FlowMap::Registry.groups
    }
  end

  def show
    flow = Crm::FlowMap::Registry.find(Current.account, params[:key])
    return render json: { error: 'Fluxo não encontrado.' }, status: :not_found unless flow

    render json: flow
  end
end
