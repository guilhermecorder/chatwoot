# Transcrição em segundo plano (fila low): a gravação chega e o card já
# aparece; a transcrição completa o card minutos depois.
class Crm::Calls::TranscriptionJob < ApplicationJob
  queue_as :low

  def perform(call_id)
    call = Crm::Call.find_by(id: call_id)
    return unless call

    Crm::Calls::TranscriptionService.new(call).perform
  end
end
