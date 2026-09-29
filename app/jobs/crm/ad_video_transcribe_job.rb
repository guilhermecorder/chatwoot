# 🎬 Transcreve os vídeos dos anúncios (Central de Criativos v2.1, item 181).
# Um vídeo por execução; `enqueue_pending` enfileira os que ainda não têm
# transcrição (até LIMIT por vez), chamado depois de cada carga da Meta e
# pelo botão "Transcrever vídeos" da tela.
class Crm::AdVideoTranscribeJob < ApplicationJob
  queue_as :low
  LIMIT = 25
  # item 286: "na fila"/"transcrevendo" há mais que isso = travou (deploy no meio, fila caiu) → tenta de novo
  STUCK_AFTER = 20.minutes
  # nunca pediu, falhou, travou, ou foi pulado por um motivo passageiro (faltava a chave do Gemini)
  PENDING_SQL = <<~SQL.squish.freeze
    coalesce(creative -> 'transcript' ->> 'status', '') IN ('', 'failed')
    OR (creative -> 'transcript' ->> 'status' IN ('queued', 'processing')
        AND coalesce(creative -> 'transcript' ->> 'status_at', '1970-01-01') < :stuck)
    OR (creative -> 'transcript' ->> 'status' = 'skipped'
        AND (creative -> 'transcript' ->> 'retry' = 'true' OR creative -> 'transcript' ->> 'error' LIKE 'Configure a chave%'))
  SQL

  def self.pending_for(account, limit: LIMIT)
    Crm::AdCreative.where(account_id: account.id)
                   .where("format = 'video' OR coalesce(creative ->> 'video_id', '') <> ''")
                   .where(PENDING_SQL, stuck: STUCK_AFTER.ago.iso8601)
                   .order(synced_at: :desc).limit(limit)
  end

  # item 293: vídeo enviado pela pessoa que ficou parado (transcrição falhou no
  # meio) não fica ocupando espaço — some depois de 24 horas
  STALE_UPLOAD = 24.hours

  def self.purge_stale_uploads
    ActiveStorage::Attachment.where(record_type: 'Crm::AdCreative', name: 'video_upload')
                             .where(created_at: ...STALE_UPLOAD.ago).find_each(&:purge)
  rescue StandardError => e
    Rails.logger.warn("[CEVICO criativos] limpeza dos vídeos enviados falhou: #{e.message}")
  end

  def self.enqueue_pending(account, limit: LIMIT)
    purge_stale_uploads
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
