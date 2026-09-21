# 🕘 Histórico do Roteiro CEVICO e dos passos dos agentes (rodada 191, só
# admin): lista as últimas fotos e "Voltar para esta" (que tira uma foto do
# estado atual antes de escrever a antiga de volta).
class Api::V1::Accounts::Crm::ScriptVersionsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action :require_administrator!

  LIMIT = 30

  # GET /crm/script_versions[?kind=script|stage&agent_key=]
  def index
    scope = Crm::ScriptVersion.where(account: Current.account)
    scope = scope.where(kind: params[:kind].to_s) if Crm::ScriptVersion::KINDS.include?(params[:kind].to_s)
    scope = scope.where(agent_key: params[:agent_key].to_s) if params[:agent_key].present?
    render json: { versions: scope.includes(:created_by).recent.limit(LIMIT).map(&:to_payload) }
  end

  # POST /crm/script_versions/:id/restore
  def restore
    version = Crm::ScriptVersion.where(account: Current.account).find(params[:id])
    version.restore!(by: Current.user)
    payload = { ok: true, version: version.to_payload, kind: version.kind, agent_key: version.agent_key }
    if version.kind == 'stage'
      payload[:prompt] = Crm::CevicoScript.stage_prompt(Current.account, version.agent_key)
    else
      payload[:script] = Crm::CevicoScript.sections(Current.account)
      payload[:script_updated_at] = Crm::CevicoScript.updated_at(Current.account)
    end
    render json: payload
  end
end
