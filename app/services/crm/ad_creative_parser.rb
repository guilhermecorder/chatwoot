# Lê o objeto `creative` da Meta e tira dele o que a Central de Criativos
# mostra: gancho (title), corpo (body), CTA, descrição, miniatura, vídeo e —
# no criativo dinâmico — as listas de ganchos/corpos/CTAs (asset_feed_spec).
module Crm::AdCreativeParser
  module_function

  CTA_LABELS = {
    'WHATSAPP_MESSAGE' => 'Enviar mensagem (WhatsApp)', 'MESSAGE_PAGE' => 'Enviar mensagem', 'LEARN_MORE' => 'Saiba mais',
    'CONTACT_US' => 'Fale conosco', 'GET_QUOTE' => 'Pedir orçamento', 'SIGN_UP' => 'Cadastre-se', 'APPLY_NOW' => 'Inscreva-se',
    'CALL_NOW' => 'Ligar agora', 'GET_OFFER' => 'Ver oferta', 'SHOP_NOW' => 'Comprar', 'ORDER_NOW' => 'Pedir agora',
    'SUBSCRIBE' => 'Assinar', 'WATCH_MORE' => 'Assistir', 'BOOK_NOW' => 'Agendar', 'DOWNLOAD' => 'Baixar',
    'SEND_MESSAGE' => 'Enviar mensagem', 'NO_BUTTON' => 'Sem botão', 'INSTAGRAM_MESSAGE' => 'Mensagem (Instagram)'
  }.freeze

  def cta_label(type)
    return 'Sem botão' if type.blank?

    CTA_LABELS[type.to_s] || type.to_s.tr('_', ' ').capitalize
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def format_for(creative)
    feed = creative['asset_feed_spec'] || {}
    story = creative['object_story_spec'] || {}
    return 'dynamic' if feed.present? && (Array(feed['bodies']).size > 1 || Array(feed['titles']).size > 1 ||
                                          Array(feed['videos']).size > 1 || Array(feed['images']).size > 1)
    return 'carousel' if Array(story.dig('link_data', 'child_attachments')).size > 1
    return 'video' if creative['video_id'].present? || story['video_data'].present? || Array(feed['videos']).any?
    return 'image' if creative['image_url'].present? || creative['image_hash'].present? ||
                      story.dig('link_data', 'picture').present? || Array(feed['images']).any?

    'other'
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/AbcSize
  def parse(creative)
    feed = creative['asset_feed_spec'] || {}
    video = creative.dig('object_story_spec', 'video_data') || {}
    link = creative.dig('object_story_spec', 'link_data') || {}
    titles = texts(feed['titles'])
    bodies = texts(feed['bodies'])
    descriptions = texts(feed['descriptions'])
    ctas = Array(feed['call_to_action_types']).map(&:to_s)
    {
      'title' => first_present(creative['title'], video['title'], link['name'], titles.first),
      'body' => first_present(creative['body'], video['message'], link['message'], bodies.first),
      'cta_type' => first_present(creative['call_to_action_type'], video.dig('call_to_action', 'type'),
                                  link.dig('call_to_action', 'type'), ctas.first),
      'description' => first_present(link['description'], descriptions.first),
      'thumbnail_url' => first_present(creative['thumbnail_url'], video['image_url'], link['picture'], creative['image_url']),
      'image_url' => first_present(creative['image_url'], video['image_url'], link['picture']),
      'video_id' => first_present(creative['video_id'], video['video_id'], Array(feed['videos']).first&.dig('video_id')),
      'permalink' => creative['instagram_permalink_url'],
      'titles' => titles, 'bodies' => bodies, 'ctas' => ctas, 'descriptions' => descriptions
    }.compact
  end
  # rubocop:enable Metrics/AbcSize

  def texts(list)
    Array(list).filter_map { |item| item.is_a?(Hash) ? item['text'].presence : item.to_s.presence }
  end

  def first_present(*values)
    values.find(&:present?)
  end
end
