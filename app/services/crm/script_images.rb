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
# A mensagem leva o carimbo MEDIA_STAMP: a trava de "já respondi esta
# mensagem" (Crm::ResponderAgentJob.already_replied?) ignora a imagem, senão os
# balões de texto que vêm logo depois seriam barrados.
class Crm::ScriptImages
  MEDIA_STAMP = 'cevico_ia_midia'.freeze
  MAX_IMAGES = 12
  # 1 envio + 1 reenvio quando o cliente diz que não chegou (como a prova virtual da ótica)
  MAX_SENDS = 2
  CONTENT_TYPES = { '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg', '.png' => 'image/png', '.webp' => 'image/webp' }.freeze
  PUBLIC_ROOT = Rails.public_path

  def self.for(account)
    raw = Array(CrmSetting.find_by(account: account)&.ai_config&.dig('imagens_roteiro'))
    raw.first(MAX_IMAGES).filter_map { |entry| normalize(entry) }
  end

  def self.normalize(entry)
    e = entry.to_h.transform_keys(&:to_s)
    key = e['chave'].to_s.strip.downcase.gsub(/[^a-z0-9_-]/, '_').squeeze('_')[0, 40]
    path = file_path(e['arquivo'])
    return if key.blank? || path.nil?

    { 'chave' => key, 'quando' => e['quando'].to_s.strip[0, 200], 'legenda' => e['legenda'].to_s.strip[0, 900],
      'faz_pergunta' => e['faz_pergunta'] != false, 'caminho' => path }
  end

  # só arquivos de imagem dentro de public/ (nada de ../ para fora dela)
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
  # Chatwoot): quando o envio ao WhatsApp roda, a imagem já está lá
  def self.send!(conversation, image, agent_key)
    path = image['caminho']
    message = conversation.messages.new(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
      content: image['legenda'].presence,
      additional_attributes: { 'cevico_ia_agent' => agent_key, MEDIA_STAMP => { 'chave' => image['chave'] } }
    )
    message.attachments.new(account_id: conversation.account_id, file_type: :image,
                            file: { io: StringIO.new(File.binread(path)), filename: File.basename(path),
                                    content_type: CONTENT_TYPES[File.extname(path).downcase] })
    message.save!
    message
  end
end
