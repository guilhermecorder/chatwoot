# 🧪 item 383: a cada 2 minutos, manda a próxima leva de cada segmento que
# está enviando (Crm::SegmentSender.tick! decide se a leva venceu, se está
# dentro da janela e do teto, e trava por segmento: uma leva longa nunca é
# atropelada pela seguinte nem pelo botão da tela).
class Crm::SegmentDripJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(segment_id = nil, force: false, limit: nil)
    scope = Crm::Segment.sending
    scope = Crm::Segment.where(id: segment_id) if segment_id
    scope.find_each do |segment|
      Crm::SegmentSender.tick!(segment, force: force, limit: limit)
    rescue StandardError => e
      Rails.logger.error "[Crm::SegmentDripJob] segmento #{segment.id}: #{e.message}"
      Crm::SegmentSender.skip(segment, "erro: #{e.message.to_s.first(120)}")
    end
    Crm::CronHealth.ran!('segmentos') if defined?(Crm::CronHealth)
  end
end
