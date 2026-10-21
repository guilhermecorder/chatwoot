# 🔐 Auditoria 10/2026 (achado #307): dado SENSÍVEL do paciente só para quem
# tem a porta certa — a mesma regra que o Espaço do Médico já usa
# (agenda_config.clinical_access, ver ClinicalNotesController), agora
# reaproveitada por quem só precisa LER:
#   - respostas de formulário (dado de saúde, LGPD): admin, médicos marcados
#     (doctor_user_ids) e a equipe só com team_view ligado;
#   - dinheiro do paciente (valor de fechamento, forma de pagamento, valor do
#     card): admin ou quem tem o nó "financeiro" (ver) no catálogo de acessos.
module Crm::ClinicalAccessGate
  extend ActiveSupport::Concern

  private

  def clinical_access_config
    @clinical_access_config ||= (CrmSetting.find_by(account: Current.account)&.agenda_config || {})['clinical_access'] || {}
  end

  def clinical_access_view?
    return true if Current.account_user&.administrator?
    return true if Array(clinical_access_config['doctor_user_ids']).map(&:to_i).include?(Current.user.id)

    clinical_access_config['team_view'] == true
  end

  def money_visible?
    Current.account_user&.administrator? || cevico_can?('financeiro', :view)
  end
end
