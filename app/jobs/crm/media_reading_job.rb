# 👂🖼️ item 204: lê na hora os áudios/imagens de uma mensagem do paciente
# (Crm::MediaReadingService), para a equipe ver o texto embaixo do anexo e o
# Atendente já encontrar tudo lido quando o job dele rodar (6 s depois).
# Disparado pelo CrmListener nas caixas atendidas pelos Atendentes do WhatsApp.
#
# 🔁 item 340 (13/10): o arquivo do WhatsApp sobe para o armazenamento DEPOIS
# do aviso da mensagem, e esta fila (a da IA) está sempre livre — o job
# chegava antes do arquivo e o áudio ficava "falhou" para sempre. Agora, se a
# falha é passageira (arquivo ainda subindo, rede, Gemini ocupado), o job volta
# sozinho em 3 s, 6 s e 12 s; só depois disso o anexo fica como falhou.
class Crm::MediaReadingJob < ApplicationJob
  queue_as :ai # 🚦 Rodada 6 (RESIL-1): fila da IA, cápsula própria (SIDEKIQ_AI_CONCURRENCY, config/sidekiq.yml)

  RETRY_WAITS = [3, 6, 12].freeze

  def perform(message_id, round = 0) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    message = Message.find_by(id: message_id)
    return if message.blank? || !message.incoming?
    return unless Crm::MediaReadingService.configured?(message.account)

    again = false
    message.attachments.each do |attachment|
      next unless Crm::MediaReadingService.readable?(attachment)

      # nas voltas (round > 0) não precisa esperar os 20 s entre tentativas
      Crm::MediaReadingService.new(attachment).perform(retry_now: round.positive?)
      again ||= Crm::MediaReadingService.retriable?(attachment.reload, retry_now: true)
    end
    return unless again && round < RETRY_WAITS.size

    self.class.set(wait: RETRY_WAITS[round].seconds).perform_later(message_id, round + 1)
  end
end
