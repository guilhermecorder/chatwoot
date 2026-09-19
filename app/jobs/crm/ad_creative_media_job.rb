# Guarda no NOSSO armazenamento (Active Storage) a miniatura de cada anúncio
# da Central de Criativos (item 174). A URL que a Meta dá expira em horas e
# o anúncio pode ser apagado lá; a cópia aqui não depende de nada disso.
# Roda depois de cada carga; pega até LIMIT criativos sem miniatura por vez;
# a falha de um anúncio não derruba os outros (tenta de novo na próxima).
class Crm::AdCreativeMediaJob < ApplicationJob
  queue_as :low
  LIMIT = 300
  MAX_SIZE = 8.megabytes

  def perform(account_id, limit = LIMIT)
    account = Account.find(account_id)
    pending = Crm::AdCreative.where(account_id: account.id).where.missing(:thumbnail_attachment).order(:id).limit(limit)
    saved = 0
    pending.each do |creative|
      saved += 1 if store(creative)
    end
    Rails.logger.info "[CEVICO criativos] conta=#{account.id} miniaturas guardadas=#{saved}/#{pending.size}"
    saved
  end

  private

  def store(creative)
    url = creative.meta_thumbnail_url
    return false if url.blank?

    file = Down.download(url, max_size: MAX_SIZE, open_timeout: 15, read_timeout: 30)
    content_type = file.respond_to?(:content_type) ? file.content_type.to_s : ''
    return false unless content_type.start_with?('image/')

    creative.thumbnail.attach(io: file, filename: "anuncio-#{creative.ad_id}#{extension_for(content_type)}", content_type: content_type)
    true
  rescue StandardError => e
    Rails.logger.warn "[CEVICO criativos] miniatura do anúncio #{creative.ad_id} falhou: #{e.message}"
    false
  ensure
    file&.close! if file.respond_to?(:close!)
  end

  def extension_for(content_type)
    { 'image/jpeg' => '.jpg', 'image/png' => '.png', 'image/webp' => '.webp', 'image/gif' => '.gif' }[content_type] || ''
  end
end
