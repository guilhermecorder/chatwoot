# Agente de CORREÇÃO do Ambiente de Montagem (item 112 Fase 1): recebe a
# página ATUAL + uma instrução do time ("deixa o título mais direto",
# "FAQ por último", "seção 3 dourada com brilho") e devolve a página
# INTEIRA atualizada no mesmo formato do Construtor — mais uma resposta
# curta pro chat (o que mudou + sugestões, ex.: fotos por seção).
# Compartilha a config do Construtor (modelo/esforço/teto/referências).
class Crm::PageEditorService
  include Crm::AiAgentConfig

  AGENT_KEY = 'pagebuilder'.freeze

  EDIT_SCHEMA = {
    type: 'object',
    properties: Crm::CopywriterSchemas::PAGE_SCHEMA[:properties].merge(
      reply: { type: 'string',
               description: 'Resposta CURTA ao autor no chat (pt-BR): o que você mudou e, quando fizer sentido, sugestões práticas — ex.: que foto cairia bem em qual seção' }
    ),
    required: Crm::CopywriterSchemas::PAGE_SCHEMA[:required] + %w[reply],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o construtor de páginas da CEVICO — CUIDADOS OCULARES em MODO
    CORREÇÃO: recebe a página ATUAL (JSON) e uma instrução de ajuste da
    equipe, e devolve a página COMPLETA atualizada.

    Regras:
    - Mude SOMENTE o que a instrução pedir. Todo o resto (textos, ordem,
      efeitos, cores, imagens das seções) volta IDÊNTICO ao recebido.
    - Pode reordenar, criar e remover seções quando a instrução pedir.
    - Cores: hexadecimal #RRGGBB, com parcimônia (paleta da casa:
      #0F5FA6 azul, #D4AF37 dourado, #10B981 verde, #7C3AED roxo).
    - image_url: mantenha os caminhos recebidos; só troque/atribua se a
      instrução indicar uma imagem LISTADA no contexto. NUNCA invente URL.
    - FOTOS ANEXADAS NO CHAT: você as VÊ neste pedido, numeradas, cada uma
      com seu caminho. Olhe o conteúdo de cada foto e escolha a seção onde
      ela comunica melhor (ou a seção que a instrução pedir), preenchendo
      image_url com o caminho EXATO listado. No "reply", conte onde colocou
      cada foto e por quê.
    - Nunca prometa resultado de cirurgia nem invente dados clínicos,
      preços ou depoimentos.
    - "reply": 1-3 frases em pt-BR contando o que mudou; quando couber,
      sugira fotos concretas por seção (a equipe adora saber o que
      fotografar).
  PROMPT

  # images (112 Fase 2): caminhos /rails/active_storage/... já subidos pelo
  # chat — viram blocos de IMAGEM na chamada (o agente enxerga as fotos)
  def initialize(account:, page:, instruction:, images: [])
    @account = account
    @page = page
    @instruction = instruction
    @images = Array(images)
  end

  def call
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Construtor de Páginas está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?
    return { error: 'Escreva o que você quer mudar.' } if @instruction.blank?

    message = client.messages.create(
      model: model,
      max_tokens: max_tokens_config || 30_000,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: EDIT_SCHEMA }),
      messages: [{ role: 'user', content: user_content }]
    )
    record_usage(message)
    parse_structured_response(message)
  rescue Anthropic::Errors::APIError => e
    { error: "Erro na IA: #{e.message}" }
  rescue JSON::ParserError, TypeError
    { error: 'A IA devolveu um formato inesperado. Tente de novo.' }
  rescue StandardError => e
    Rails.logger.error "[PageEditor] #{e.class}: #{e.message}"
    { error: "Não consegui ajustar agora (#{e.class.name.demodulize}). Tente de novo em instantes." }
  end

  private

  def current_page_json
    {
      title: @page.title, subtitle: @page.subtitle, emoji: @page.emoji,
      meta_title: @page.meta_title, meta_description: @page.meta_description,
      cta_label: @page.cta_label, sections: @page.sections || []
    }.to_json
  end

  def build_input
    <<~INPUT
      PÁGINA ATUAL (JSON):
      #{current_page_json}
      #{style_refs_block}#{attached_photos_block}
      INSTRUÇÃO DA EQUIPE (aplicar agora):
      #{@instruction}
    INPUT
  end

  # ── 112 Fase 2: fotos com visão ──
  # Sem foto: entrada segue sendo texto puro (idêntico à Fase 1).
  # Com fotos: vira lista de blocos — "Foto N — caminho" + a imagem em
  # base64 — e o texto da página por último. O agente VÊ cada foto e sabe
  # o caminho exato pra pôr no image_url da seção escolhida.
  def user_content
    blocks = photo_blocks
    return build_input if blocks.empty?

    blocks + [{ type: 'text', text: build_input }]
  end

  def photo_blocks
    resolved_photos.flat_map.with_index do |photo, idx|
      [{ type: 'text', text: "Foto #{idx + 1} — caminho: #{photo[:path]}" },
       { type: 'image', source: { type: 'base64', media_type: photo[:media_type], data: Base64.strict_encode64(photo[:data]) } }]
    end
  end

  def attached_photos_block
    photos = resolved_photos
    return '' if photos.empty?

    list = photos.map.with_index { |photo, idx| "Foto #{idx + 1}: #{photo[:path]}" }.join("\n")
    "\nFOTOS ANEXADAS PELA EQUIPE (as imagens acima, na mesma ordem — use o caminho EXATO no image_url da seção escolhida):\n#{list}\n"
  end

  def resolved_photos
    @resolved_photos ||= @images.filter_map do |path|
      blob = blob_from_path(path)
      next if blob.nil? || !blob.content_type.to_s.start_with?('image/')

      data, media_type = photo_payload(blob)
      next if data.blank? || data.bytesize > 5.megabytes # limite de imagem da API

      { path: path, data: data, media_type: media_type }
    end.first(3)
  end

  def blob_from_path(path)
    signed_id = path[%r{/rails/active_storage/blobs/(?:redirect/|proxy/)?([^/]+)}, 1]
    signed_id && ActiveStorage::Blob.find_signed(signed_id)
  rescue StandardError
    nil
  end

  # foto grande → versão reduzida só pra IA olhar (a página continua usando
  # a original); se a redução falhar, tenta a original mesmo
  def photo_payload(blob)
    if blob.byte_size > 3.megabytes && blob.variable?
      variant = blob.variant(resize_to_limit: [1600, 1600], format: :jpeg, saver: { quality: 85 }).processed
      [variant.download, 'image/jpeg']
    else
      [blob.download, blob.content_type]
    end
  rescue StandardError => e
    Rails.logger.warn "[PageEditor] foto #{blob.id} sem versão reduzida (#{e.class}), usando original"
    [blob.download, blob.content_type]
  end
end
