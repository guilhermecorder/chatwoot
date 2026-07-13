# Carimba a origem de anúncio (CTWA — click-to-WhatsApp) no contato e na
# conversa a partir do "referral" que a Meta manda na primeira mensagem.
#
# Regra: PRIMEIRO TOQUE — se o contato já tem meta_ads gravado, não sobrescreve
# (o anúncio que trouxe a pessoa é o que vale para atribuição de venda).
# Na conversa, grava sempre que a conversa ainda não tiver (cada conversa pode
# ter vindo de um anúncio diferente).
class Crm::AdAttributionService
  def initialize(contact:, referral:, conversation: nil, captured_at: nil)
    @contact = contact
    @conversation = conversation
    @referral = (referral || {}).deep_stringify_keys
    @captured_at = captured_at
  end

  def call
    return if @referral['source_id'].blank? && @referral['ctwa_clid'].blank?

    stamp(@conversation) if @conversation
    stamp(@contact) if @contact
  end

  private

  def attribution_data
    @attribution_data ||= {
      'source_id' => @referral['source_id'],
      'source_type' => @referral['source_type'],
      'source_url' => @referral['source_url'],
      'headline' => @referral['headline'],
      'body' => @referral['body'].to_s.truncate(300).presence,
      'media_type' => @referral['media_type'],
      'thumbnail_url' => @referral['image_url'] || @referral['thumbnail_url'] || @referral['video_url'],
      'ctwa_clid' => @referral['ctwa_clid'],
      'captured_at' => (@captured_at || Time.current).iso8601
    }.compact
  end

  def stamp(record)
    attrs = record.additional_attributes || {}
    return if attrs['meta_ads'].present? # primeiro toque vence

    record.update!(additional_attributes: attrs.merge('meta_ads' => attribution_data))
  rescue StandardError => e
    Rails.logger.error "[Crm::AdAttribution] #{record.class}##{record.id}: #{e.message}"
  end
end
