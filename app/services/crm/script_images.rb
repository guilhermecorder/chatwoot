# 🖼️ IMAGENS DO ROTEIRO (08/11/2026 · LIFE, pedido do Fernando): o atendente
# manda uma imagem pronta da empresa num ponto da conversa — a primeira é a
# "O seu TELHADO se parece com qual das opções?" (4 telhados numerados), que
# vai junto da pergunta de sondagem e o cliente responde só com o número.
#
# Mesmo mecanismo do envio de imagens da ótica (mensagem de saída com anexo na
# conversa → a caixa do WhatsApp entrega), mas genérico: as imagens vêm da
# conta, em ai_config['imagens_roteiro']:
#   [{ 'chave' => 'telhados', 'quando' => 'na pergunta do tipo de telhado',
#      'arquivo' => 'brand-assets/life/roteiro/telhados.jpg',   # dentro de public/
#      'legenda' => 'O seu telhado se parece com qual destas opções? ...' }]
# 'faz_pergunta' => false (08/11 noite · print do Google para quem desconfia): a
# legenda NÃO pergunta nada — é prova; a IA segue a conversa no balão depois dela.
# Sem lista (ou arquivo inexistente), a ferramenta nem aparece para a IA.
#
# 🔊 09/11 (LIFE, pedido do Guilherme): a MESMA lista aceita ÁUDIO pronto (.ogg/.opus/
# .mp3/.m4a) — 1º caso: o áudio do Fernando apresentando a Life, para quem já vai
# receber o orçamento. 'tipo' sai da extensão ('imagem' | 'audio'); a IA chama
# enviar_audio em vez de enviar_imagem. O WhatsApp não aceita legenda em áudio:
# a legenda vira um balão de texto logo ANTES do áudio (mesmo carimbo).
#
# 🛟 09/11 'gatilho' (pedido do Guilherme: a foto dos telhados tem de ir "exatamente
# naquele momento"): palavras/regex. Se a IA esquecer a ferramenta e perguntar em
# texto (ex.: "telha, laje ou metálico?"), Crm::ResponderAgentJob#send_replies
# troca esse balão pela imagem com a legenda — uma vez por conversa.
#
# A mensagem leva o carimbo MEDIA_STAMP: a trava de "já respondi esta
# mensagem" (Crm::ResponderAgentJob.already_replied?) ignora a imagem, senão os
# balões de texto que vêm logo depois seriam barrados.
class Crm::ScriptImages
  MEDIA_STAMP = 'cevico_ia_midia'.freeze
  MAX_IMAGES = 12
  # 1 envio + 1 reenvio quando o cliente diz que não chegou (como a prova virtual da ótica)
  MAX_SENDS = 2
  IMAGE_TYPES = { '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg', '.png' => 'image/png', '.webp' => 'image/webp' }.freeze
  AUDIO_TYPES = { '.ogg' => 'audio/ogg', '.opus' => 'audio/ogg', '.mp3' => 'audio/mpeg', '.m4a' => 'audio/mp4' }.freeze
  CONTENT_TYPES = IMAGE_TYPES.merge(AUDIO_TYPES).freeze
  PUBLIC_ROOT = Rails.public_path

  def self.for(account)
    raw = Array(CrmSetting.find_by(account: account)&.ai_config&.dig('imagens_roteiro'))
    raw.first(MAX_IMAGES).filter_map { |entry| normalize(entry) }
  end

  def self.normalize(entry) # rubocop:disable Metrics/AbcSize
    e = entry.to_h.transform_keys(&:to_s)
    key = e['chave'].to_s.strip.downcase.gsub(/[^a-z0-9_-]/, '_').squeeze('_')[0, 40]
    path = file_path(e['arquivo'])
    return if key.blank? || path.nil?

    { 'chave' => key, 'quando' => e['quando'].to_s.strip[0, 200], 'legenda' => e['legenda'].to_s.strip[0, 900],
      'faz_pergunta' => e['faz_pergunta'] != false, 'caminho' => path,
      'tipo' => AUDIO_TYPES.key?(File.extname(path.to_s).downcase) ? 'audio' : 'imagem',
      'gatilho' => e['gatilho'].to_s.strip[0, 300] }
  end

  def self.images(account)
    self.for(account).select { |i| i['tipo'] == 'imagem' }
  end

  def self.audios(account)
    self.for(account).select { |i| i['tipo'] == 'audio' }
  end

  # 🛟 a IA perguntou em TEXTO o que a imagem devia perguntar? Devolve a mídia cujo
  # 'gatilho' casa com o balão (sem acento, sem maiúscula), ainda não enviada nesta
  # conversa e só quando o balão é pergunta (termina com "?"): "Telha, anotado!" não dispara.
  def self.triggered_by(conversation, text, medias = nil) # rubocop:disable Metrics/CyclomaticComplexity
    plain = I18n.transliterate(text.to_s).downcase
    return if plain.exclude?('?')

    (medias || self.for(conversation.account)).find do |m|
      next false if m['gatilho'].blank? || m['tipo'] != 'imagem'

      re = trigger_regexp(m['gatilho'])
      re.present? && plain.match?(re) && sent_count(conversation, m['chave']).zero?
    end
  end

  def self.trigger_regexp(gatilho)
    Regexp.new(I18n.transliterate(gatilho.to_s).downcase, Regexp::IGNORECASE)
  rescue RegexpError
    nil
  end

  # só arquivos de imagem/áudio dentro de public/ (nada de ../ para fora dela)
  def self.file_path(relative)
    rel = relative.to_s.strip.delete_prefix('/')
    return if rel.blank? || CONTENT_TYPES[File.extname(rel).downcase].nil?

    full = PUBLIC_ROOT.join(rel).expand_path
    return unless full.to_s.start_with?("#{PUBLIC_ROOT.expand_path}/") && full.file?

    full
  end

  # quantas vezes a imagem desta chave já foi mandada nesta conversa
  def self.sent_count(conversation, key)
    conversation.messages.where(message_type: :outgoing)
                .where("additional_attributes -> '#{MEDIA_STAMP}' ->> 'chave' = ?", key).count
  end

  # cria a mensagem de saída COM o anexo já preso (como o MessageBuilder do
  # Chatwoot): quando o envio ao WhatsApp roda, a mídia já está lá.
  # Áudio: a legenda vai num balão de texto ANTES (o WhatsApp não aceita legenda em áudio).
  def self.send!(conversation, media, agent_key) # rubocop:disable Metrics/AbcSize
    path = media['caminho']
    audio = media['tipo'] == 'audio'
    attrs = { 'cevico_ia_agent' => agent_key, MEDIA_STAMP => { 'chave' => media['chave'], 'tipo' => media['tipo'] } }
    if audio && media['legenda'].present?
      conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                    message_type: :outgoing, content: media['legenda'],
                                    additional_attributes: attrs.merge(MEDIA_STAMP => attrs[MEDIA_STAMP].merge('legenda' => true)))
    end
    message = conversation.messages.new(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
      content: audio ? nil : media['legenda'].presence, additional_attributes: attrs
    )
    message.attachments.new(account_id: conversation.account_id, file_type: audio ? :audio : :image,
                            file: { io: StringIO.new(File.binread(path)), filename: File.basename(path),
                                    content_type: CONTENT_TYPES[File.extname(path).downcase], identify: false })
    message.save!
    message
  end
end
