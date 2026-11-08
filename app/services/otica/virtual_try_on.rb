# 🪞 PROVA VIRTUAL PELO WHATSAPP (08/11/2026, ideia do Henrique): a cliente
# manda uma foto → o sistema já leu o rosto (Otica::FaceReading, dentro da
# leitura de imagem que roda em toda foto) → o agente chama a ferramenta
# `experimentar_armacoes` → este serviço escolhe as armações do estoque que
# combinam com o rosto (Otica::Visagismo), gera a foto dela com cada uma
# (Otica::TryOnImage) e ENVIA as imagens na conversa, cada uma com a legenda
# da armação. O agente só recebe o resumo (o que foi enviado) e escreve os
# balões de texto depois — as fotos chegam antes da fala, como quem manda a
# foto e comenta.
#
# Travas (todas aqui, nunca no modelo):
# - só ramo ÓTICA, só conversa com foto utilizável (1 pessoa adulta, de frente, nítida);
# - no máximo MAX_PER_CALL armações por chamada e MAX_CALLS_PER_DAY chamadas
#   por conversa por dia (a cliente pode pedir "outra" uma vez; depois é na loja);
# - teto de imagens por dia na conta (ai_config['visagismo_daily_cap'], padrão 150)
#   para o gasto nunca fugir;
# - em SOMBRA/simulador nada é gerado nem enviado: devolve `simulado` com a escolha;
# - a foto da cliente só vai ao Gemini para gerar a imagem (não é guardada em
#   lugar nenhum além da própria conversa, como qualquer anexo do WhatsApp).
class Otica::VirtualTryOn
  MAX_PER_CALL = 3
  MAX_CALLS_PER_DAY = 2
  DEFAULT_DAILY_CAP = 150
  CAP_KEY = 'visagismo_daily_cap'.freeze
  STAMP_KEY = 'cevico_visagismo'.freeze
  LOOKBACK_MESSAGES = 30

  attr_reader :account

  def initialize(account:, conversation: nil, live: false, agent_key: nil)
    @account = account
    @conversation = conversation
    @live = live == true
    @agent_key = agent_key.to_s
  end

  def self.otica?(account)
    Cevico::Company.for(account).segment == 'otica'
  rescue StandardError
    false
  end

  # armações que podem entrar na prova: ativas, com foto, marcadas e com saldo
  def self.candidates(account)
    Otica::Product.where(account_id: account.id).active.where(kind: %w[armacao solar], try_on: true)
                  .where('quantity > 0').with_attached_photo.select { |p| p.photo.attached? }
  end

  def self.daily_cap(account)
    value = CrmSetting.find_by(account: account)&.ai_config&.dig(CAP_KEY).to_i
    (value.positive? ? value : DEFAULT_DAILY_CAP).clamp(1, 5000)
  end

  def self.generated_today(account)
    Crm::AiUsage.where(account: account, agent_key: Otica::TryOnImage::AGENT_KEY)
                .where('created_at > ?', Otica::TZ.now.beginning_of_day).count
  end

  # ── a foto da cliente nesta conversa ──────────────────────────────────────
  # a selfie mais recente já lida (tipo selfie + bloco rosto)
  def selfie_attachment
    return nil if @conversation.nil?

    messages = @conversation.messages.where(message_type: :incoming).includes(:attachments)
                            .reorder(created_at: :desc).limit(LOOKBACK_MESSAGES)
    messages.flat_map { |m| m.attachments.select { |a| a.file_type.to_s == 'image' && a.file.attached? } }
            .sort_by(&:created_at).reverse
            .find { |a| media(a)['tipo'] == 'selfie' && media(a)['rosto'].is_a?(Hash) }
  end

  def media(attachment)
    attachment.meta&.[]('cevico_media') || {}
  end

  # ── chamada do agente ─────────────────────────────────────────────────────
  # devolve o Hash que vai ao modelo como tool_result
  def run(quantidade: 2, preferencia: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return refuse('A prova virtual só existe no ramo ótica.') unless self.class.otica?(account)

    attachment = selfie_attachment
    return refuse('Ainda não há foto do rosto da cliente nesta conversa. Peça uma foto de frente, com boa luz, só ela na foto.') if attachment.nil?

    rosto = media(attachment)['rosto']
    ok, motivo = Otica::FaceReading.usable(rosto)
    return refuse("A foto recebida não serve para a prova virtual: #{motivo}.") unless ok

    quantidade = quantidade.to_i.clamp(1, MAX_PER_CALL)
    products = self.class.candidates(account)
    return refuse('Nenhuma armação do estoque está pronta para a prova virtual (precisa de foto e saldo). Convide para a loja.') if products.empty?

    chosen = Otica::Visagismo.recommend(products, face_shape: rosto['formato'], preference: preferencia, limit: quantidade)
    base = { rosto: rosto['formato'], rosto_label: Otica::Visagismo.face_label(rosto['formato']),
             visagismo: Otica::Visagismo.explain(rosto['formato']) }

    unless @live
      return base.merge(ok: true, simulado: true,
                        aviso: 'SIMULAÇÃO (sombra/teste): nenhuma imagem foi gerada nem enviada. Ao vivo, estas armações ' \
                               'seriam enviadas como fotos da cliente usando cada uma. Comente como se as fotos tivessem chegado.',
                        armacoes: chosen.map { |p| describe(p) })
    end

    calls = calls_today
    return refuse("A cliente já recebeu #{calls} prova(s) virtual(is) hoje (limite #{MAX_CALLS_PER_DAY}). Convide para ver o resto na loja.") if calls >= MAX_CALLS_PER_DAY

    cap = self.class.daily_cap(account)
    used = self.class.generated_today(account)
    return refuse('O limite diário de imagens da loja foi atingido. Convide para ver as armações na loja.') if used >= cap

    chosen = chosen.first([cap - used, quantidade].min)
    return refuse('Configure a chave do Gemini em Integrações → IA.') unless Otica::TryOnImage.configured?(account)

    selfie_bytes = attachment.file.blob.open(&:read)
    selfie_mime = mime_of(attachment.file, 'image/jpeg')
    sent = []
    failures = []
    chosen.each_with_index do |product, index|
      image = Otica::TryOnImage.new(account).generate(selfie: selfie_bytes, selfie_mime: selfie_mime,
                                                     frame: product.photo.blob.open(&:read), frame_mime: mime_of(product.photo, 'image/png'),
                                                     product: product)
      send_image!(product, image, index + 1, chosen.size, attachment)
      sent << describe(product)
    rescue Otica::TryOnImage::Error, ActiveStorage::FileNotFoundError => e
      Rails.logger.warn("[Otica::VirtualTryOn] armação #{product.id} falhou: #{e.class}: #{e.message}")
      failures << product.name
    end

    if sent.empty?
      return refuse('Não consegui gerar as imagens agora (falha do serviço de imagem). Diga que vai separar as opções e mostrar ' \
                    'na loja; não prometa a foto.')
    end

    base.merge(ok: true, enviadas: sent.size, armacoes: sent, falhas: failures,
               aviso: 'As fotos JÁ FORAM ENVIADAS à cliente nesta conversa (uma por armação, com legenda). Agora comente em 1 ou 2 ' \
                      'balões: diga por que essas armações combinam com o rosto dela (sem termo técnico), lembre que é uma simulação por ' \
                      'computador e convide para experimentar na loja. Não repita os nomes das armações (já estão nas legendas).')
  end

  # ── teste pela tela de Produtos (equipe) ─────────────────────────────────
  # selfie: bytes; product_ids: escolha manual (vazio = automática). Gera e
  # devolve as imagens em base64, sem enviar a ninguém e sem gravar a foto.
  def preview(selfie:, selfie_mime:, product_ids: [], quantidade: 2, preferencia: nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    rosto = read_face(selfie, selfie_mime)
    ok, motivo = Otica::FaceReading.usable(rosto)
    products = self.class.candidates(account)
    chosen = if product_ids.present?
               ids = Array(product_ids).map(&:to_i)
               products.select { |p| ids.include?(p.id) }.first(MAX_PER_CALL)
             else
               Otica::Visagismo.recommend(products, face_shape: rosto&.[]('formato') || 'oval', preference: preferencia,
                                                    limit: quantidade.to_i.clamp(1, MAX_PER_CALL))
             end
    result = { rosto: rosto, utilizavel: ok, motivo: motivo, visagismo: (rosto ? Otica::Visagismo.explain(rosto['formato']) : nil),
               prontas: products.size, imagens: [] }
    return result if !ok && product_ids.blank?
    return result.merge(motivo: 'Nenhuma armação pronta para a prova virtual (precisa de foto, saldo e a marca "prova virtual").') if chosen.empty?

    chosen.each do |product|
      image = Otica::TryOnImage.new(account).generate(selfie: selfie, selfie_mime: selfie_mime,
                                                     frame: product.photo.blob.open(&:read), frame_mime: mime_of(product.photo, 'image/png'),
                                                     product: product)
      result[:imagens] << { produto: describe(product), product_id: product.id, model: image[:model],
                            data_url: "data:#{image[:mime]};base64,#{Base64.strict_encode64(image[:bytes])}" }
    rescue Otica::TryOnImage::Error => e
      result[:imagens] << { produto: describe(product), product_id: product.id, erro: e.message.truncate(200) }
    end
    result
  end

  private

  # lê o rosto de uma foto solta (prévia da tela) com o mesmo prompt da leitura de imagem
  def read_face(bytes, mime)
    api_key = Crm::MediaReadingService.api_key_for(account)
    raise Otica::TryOnImage::Error, 'Configure a chave do Gemini em Integrações → IA.' if api_key.blank?

    body = { contents: [{ parts: [{ text: Otica::FaceReading::IMAGE_PROMPT },
                                  { inline_data: { mime_type: mime, data: Base64.strict_encode64(bytes) } }] }],
             generationConfig: { temperature: 0.1, response_mime_type: 'application/json' } }
    response, = Crm::GeminiModels.post(account: account, api_key: api_key, body: body.to_json, timeout: 90)
    raise Otica::TryOnImage::Error.new("Gemini respondeu #{response.code} na leitura do rosto.", response.code) unless response.success?

    text = response.parsed_response.dig('candidates', 0, 'content', 'parts', 0, 'text').to_s.gsub(/```(?:json)?/i, '').strip
    parsed = JSON.parse(text[(text.index('{') || 0)..(text.rindex('}') || -1)])
    parsed['tipo'].to_s == 'selfie' ? Otica::FaceReading.normalize(parsed['rosto']) : nil
  rescue JSON::ParserError
    nil
  end

  def describe(product)
    { id: product.id, armacao: product.name, formato: Otica::Visagismo.frame_label(product.frame_shape),
      cor: product.color, valor: product.price, observacao: product.visagismo_notes.presence }.compact
  end

  def mime_of(attached, fallback)
    type = attached.content_type.to_s
    type.present? && type != 'application/octet-stream' ? type : fallback
  end

  # quantas chamadas da prova virtual esta conversa já teve hoje (pelo carimbo das mensagens enviadas)
  def calls_today
    @conversation.messages.where(message_type: :outgoing).where('created_at > ?', Otica::TZ.now.beginning_of_day)
                 .where("additional_attributes ? '#{STAMP_KEY}'")
                 .pluck(Arel.sql("additional_attributes -> '#{STAMP_KEY}' ->> 'lote'")).uniq.size
  end

  # a foto gerada vira mensagem da loja na conversa (sai pelo WhatsApp como imagem com legenda)
  def send_image!(product, image, index, total, selfie_attachment)
    ext = image[:mime].to_s.include?('jpeg') ? 'jpg' : 'png'
    caption = "Opção #{index} de #{total}: #{product.name}"
    # ⚠️ 08/11: o anexo entra ANTES do save. Se a mensagem nasce sem anexo, o Message dispara o
    # SendReplyJob na hora e o WhatsApp recebe só a legenda em texto (foi o que chegou pro Henrique).
    message = @conversation.messages.new(
      account_id: account.id, inbox_id: @conversation.inbox_id, message_type: :outgoing, content: caption,
      additional_attributes: { 'cevico_ia_agent' => @agent_key.presence || Otica::TryOnImage::AGENT_KEY,
                               STAMP_KEY => { 'lote' => @lote ||= SecureRandom.hex(4), 'product_id' => product.id,
                                              'selfie_attachment_id' => selfie_attachment.id, 'model' => image[:model] } }
    )
    message.attachments.build(account_id: account.id, file_type: :image,
                              file: { io: StringIO.new(image[:bytes]), filename: "prova-virtual-#{product.id}.#{ext}", content_type: image[:mime] })
    message.save!
    message
  end

  def refuse(motivo)
    { ok: false, motivo: motivo }
  end
end
