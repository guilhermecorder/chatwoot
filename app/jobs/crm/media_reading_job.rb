# 👂🖼️ item 204: lê na hora os áudios/imagens de uma mensagem do paciente
# (Crm::MediaReadingService), para a equipe ver o texto embaixo do anexo e o
# Atendente já encontrar tudo lido quando o job dele rodar (6 s depois).
# Disparado pelo CrmListener nas caixas atendidas pelos Atendentes do WhatsApp.
class Crm::MediaReadingJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank? || !message.incoming?
    return unless Crm::MediaReadingService.configured?(message.account)

    message.attachments.each do |attachment|
      next unless Crm::MediaReadingService.readable?(attachment)

      Crm::MediaReadingService.new(attachment).perform
    end
  end
end
