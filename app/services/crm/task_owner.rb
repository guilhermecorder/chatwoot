# Responsável automático das tarefas (pedido 20/07): cada atendente cuida
# de algumas colunas do CRM. Tarefa criada por robô (Secretário, automações,
# Atendente IA) nasce NO NOME de quem cuida da coluna onde o paciente está —
# o aviso dourado do Meu Painel chega para a pessoa certa, não para ninguém.
#
# Ordem de decisão:
#   1. coluna atual do paciente no CRM → settings.task_owner_id da coluna;
#   2. sem coluna/da coluna sem dono → responsáveis da conferência
#      (agenda_config.attendance_owners: consulta/cirurgia);
#   3. nada configurado → sem responsável (como era antes).
class Crm::TaskOwner
  def self.resolve(account, contact: nil, task_type: nil)
    user_id = stage_owner_id(account, contact) || fallback_owner_id(account, task_type)
    account.users.find_by(id: user_id) if user_id.present?
  end

  def self.stage_owner_id(account, contact)
    return nil if contact.blank?

    record = Crm::Contact.joins(:pipeline)
                         .where(crm_pipelines: { account_id: account.id }, contact_id: contact.id)
                         .order(updated_at: :desc).first
    record&.stage&.settings&.[]('task_owner_id').presence&.to_i
  end

  def self.fallback_owner_id(account, task_type)
    owners = CrmSetting.find_by(account: account)&.agenda_config&.dig('attendance_owners') || {}
    key = { 'consulta' => 'consulta_user_id', 'cirurgia' => 'cirurgia_user_id' }[task_type.to_s]
    owners[key].presence&.to_i if key
  end
end
