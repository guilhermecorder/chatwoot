# 🎬 Transcreve os vídeos dos anúncios (Central de Criativos v2.1, item 181).
# Um vídeo por execução; `enqueue_pending` enfileira os que ainda não têm
# transcrição (até LIMIT por vez), chamado depois de cada carga da Meta e
# pelo botão "Transcrever vídeos" da tela.
class Crm::AdVideoTranscribeJob < ApplicationJob
  queue_as :low
  LIMIT = 25

  def self.pending_for(account, limit: LIMIT)
    Crm::AdCreative.where(account_id: account.id, format: 'video')
                   .where("coalesce(creative -> 'transcript' ->> 'status', '') NOT IN ('done', 'processing', 'skipped')")
                   .order(synced_at: :desc).limit(limit)
  end

  def self.enqueue_pending(account, limit: LIMIT)
    ids = pending_for(account, limit: limit).pluck(:id)
    ids.each { |id| perform_later(id) }
    ids.size
  end

  def perform(creative_id)
    creative = Crm::AdCreative.find_by(id: creative_id)
    return unless creative

    Crm::AdVideoTranscriptionService.new(creative).perform
  end
end
