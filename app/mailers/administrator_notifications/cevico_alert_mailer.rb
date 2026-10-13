# 🚨 E-mail de ROBÔ PARADO para os administradores da conta (auditoria
# 10/2026, achado #217). Enviado pelo vigia (Crm::CronWatchdogJob) quando um
# robô CEVICO não roda nos horários dele ou termina em erro 2× seguidas.
# Usa o SMTP da instalação (sem SMTP_ADDRESS configurado, não envia nada —
# a tarefa 🔴 e o aviso no Meu Painel continuam valendo).
class AdministratorNotifications::CevicoAlertMailer < AdministratorNotifications::BaseMailer
  def robo_parado(problem)
    subject = "#{problem[:kind] == 'erro' ? 'Robô com erro' : 'Robô parado'}: #{problem[:label]}"
    action_url = "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{Current.account.id}/inicio"
    meta = {
      'label' => problem[:label],
      'situacao' => problem[:kind] == 'erro' ? 'está terminando as rodadas com erro' : 'parou de rodar',
      'mensagem' => problem[:message],
      'account_name' => Current.account.name
    }
    send_notification(subject, action_url: action_url, meta: meta)
  end
end
