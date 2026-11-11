# 📨 item 391 (11/11): criar mensagem modelo do WhatsApp daqui do sistema e
# pedir a aprovação à Meta nos números escolhidos (Configurações → Modelos →
# "Criar modelo"). Só administrador: o modelo aprovado vira mensagem cobrada e
# fala em nome da clínica. A conta mora em Crm::WhatsappTemplateCreator.
class Api::V1::Accounts::Crm::WhatsappTemplatesController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action :require_administrator!

  # POST /api/v1/accounts/:id/crm/whatsapp_templates
  #   { inbox_ids: [1, 2], name:, category: MARKETING|UTILITY, header:, body:, footer:, buttons: [..], examples: [..] }
  def create
    inboxes = Current.account.inboxes.where(id: Array(params[:inbox_ids]).map(&:to_i)).includes(:channel)
    result = Crm::WhatsappTemplateCreator.new(Current.account, template_params).call(inboxes)
    render json: result, status: result[:errors].any? ? :unprocessable_entity : :ok
  end

  private

  def template_params
    params.permit(:name, :category, :language, :header, :body, :footer, buttons: [], examples: []).to_h
  end
end
