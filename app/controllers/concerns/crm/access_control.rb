# Controle de acesso granular do CRM CEVICO (decisão 17/07).
#
# Regra: administrador SEMPRE passa. Atendente só passa numa área sensível se
# o admin CONCEDEU aquela área a ele (allow-list). Sem concessão = negado —
# "travar tudo no admin, admin concede acesso personalizado".
#
# As concessões ficam em crm_settings.agent_permissions['grants'] =
#   { "<user_id>" => ["reports", "campaigns", ...] }
# (o campo agent_permissions já existia guardando a lista de BLOQUEIO usada só
# pelo menu do frontend; aqui usamos uma sub-chave 'grants' separada, sem mexer
# no legado — assim o backend passa a valer de verdade, por API também.)
#
# IMPORTANTE: só endpoints SENSÍVEIS usam isto. As telas do dia a dia do
# atendente (conversas, board do CRM, agenda) continuam abertas — ninguém é
# trancado fora do próprio trabalho.
module Crm::AccessControl
  extend ActiveSupport::Concern

  # áreas concedíveis (o admin marca quais o atendente pode acessar)
  CAPABILITIES = %w[reports campaigns automations data_tools settings finance strategy goals pages].freeze

  private

  def require_capability(capability)
    return if crm_can?(capability)

    render json: { error: 'Você não tem acesso a esta área. Peça a um administrador.' }, status: :forbidden
  end

  # admin estrito (não delegável) — para ações como conceder acessos
  def require_administrator!
    return if Current.account_user.administrator?

    render json: { error: 'Apenas administradores.' }, status: :forbidden
  end

  def crm_can?(capability)
    return true if Current.account_user.administrator?

    crm_granted_capabilities.include?(capability.to_s)
  end

  def crm_granted_capabilities
    @crm_granted_capabilities ||= begin
      perms = CrmSetting.find_by(account: Current.account)&.agent_permissions || {}
      Array(perms.dig('grants', Current.user.id.to_s)).map(&:to_s)
    end
  end
end
