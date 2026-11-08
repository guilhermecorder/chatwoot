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
# - no máximo MAX_PER_CALL armações por chamada e MAX_IMAGES_PER_DAY imagens
#   por CLIENTE por dia (todas as conversas dela); depois é na loja;
# - 08/11 (Guilherme): a cliente recebe um AVISO na hora ("recebi sua foto, já
#   estou aplicando o visagismo…") antes das imagens; cada legenda traz o MOTIVO
#   curto; `parecida_com` manda 3 do mesmo estilo em 3 faixas (top de linha /
#   custo-benefício / mais acessível) com o valor da armação; vale sempre a ÚLTIMA
#   foto boa que ela mandou; o cartão é ANTES (a foto dela) e DEPOIS (com a armação);
# - teto de imagens por dia na conta (ai_config['visagismo_daily_cap'], padrão 150)
#   para o gasto nunca fugir;
# - em SOMBRA/simulador nada é gerado nem enviado: devolve `simulado` com a escolha;
# - a foto da cliente só vai ao Gemini para gerar a imagem (não é guardada em
#   lugar nenhum além da própria conversa, como qualquer anexo do WhatsApp).
class Otica::VirtualTryOn # rubocop:disable Metrics/ClassLength
  MAX_PER_CALL = 3
  MAX_IMAGES_PER_DAY = 12
  AVISO_KEY = 'cevico_visagismo_aviso'.freeze
  # {opcoes} vira "2 opções" / "uma opção" (quantas vão sair agora)
  DEFAULT_AVISO = 'Recebi sua foto! Já estou aplicando as técnicas de visagismo no seu rosto pra escolher as armações ' \
                  'que mais combinam com você. Em alguns segundos te mando {opcoes} pra você comparar.'.freeze
  # {faixas} só aparece quando saem as 3 (top de linha, custo-benefício, mais acessível)
  DEFAULT_AVISO_PARECIDAS = 'Boa escolha! Vou te mandar {opcoes} nesse mesmo estilo pra você comparar{faixas}. Só um instante.'.freeze
  FAIXAS_TEXTO = ': uma top de linha, uma de melhor custo-benefício e uma mais acessível'.freeze
  TIERS = { 'top' => 'Top de linha', 'custo_beneficio' => 'Melhor custo-benefício', 'acessivel' => 'Mais acessível' }.freeze
  # 08/11 (Guilherme: "enviou duplicado"): o agente chamou a prova 2 vezes na MESMA resposta e cada chamada mandou
  # aviso + imagem. Agora: uma prova por mensagem da cliente (a 2ª chamada sem mensagem nova dela é recusada) e trava
  # por conversa enquanto uma prova está sendo montada (2 chamadas ao mesmo tempo).
  RECENT_WINDOW = 5.minutes
  LOCK_TTL = 180
  JA_ENVIADAS = 'As fotos da prova virtual ACABARAM de ser enviadas a ela nesta resposta. Não chame a ferramenta de novo agora: ' \
                'só comente e feche com uma pergunta. Para mais opções, espere ela responder.'.freeze
  DEFAULT_AVISO_MAIS = 'Boa! Vou te mandar mais {opcoes} no seu rosto pra você comparar. Em alguns segundos chegam.'.freeze
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
  # selfies já lidas (tipo selfie + bloco rosto), a mais recente primeiro
  def selfies # rubocop:disable Metrics/CyclomaticComplexity
    return [] if @conversation.nil?

    messages = @conversation.messages.where(message_type: :incoming).includes(:attachments)
                            .reorder(created_at: :desc).limit(LOOKBACK_MESSAGES)
    messages.flat_map { |m| m.attachments.select { |a| a.file_type.to_s == 'image' && a.file.attached? } }
            .sort_by(&:created_at).reverse
            .select { |a| media(a)['tipo'] == 'selfie' && media(a)['rosto'].is_a?(Hash) }
  end

  # a selfie mais recente (compatibilidade com a tela e os testes)
  def selfie_attachment
    selfies.first
  end

  # [foto da prova, rosto dela, foto da prova]: a última selfie utilizável; sem nenhuma, a última recebida
  def pick_selfie
    all = selfies
    return [nil, nil, {}] if all.empty?

    usable = all.select { |a| Otica::FaceReading.usable(media(a)['rosto']).first }
    return [all.first, media(all.first)['rosto'], {}] if usable.empty?

    # 🪞 08/11 (Guilherme: "quanto mais fácil, melhor"): UMA foto. Vale sempre a ÚLTIMA foto boa que ela
    # mandou (de frente ou de 3/4); o formato do rosto é lido nela mesma. O cartão é ANTES e DEPOIS dessa foto.
    photo = usable.first
    [photo, media(photo)['rosto'], photo]
  end

  def media(attachment)
    attachment.meta&.[]('cevico_media') || {}
  end

  # ── chamada do agente ─────────────────────────────────────────────────────
  # devolve o Hash que vai ao modelo como tool_result.
  # parecida_com: id da armação que a cliente gostou → 3 do mesmo estilo em faixas de valor
  def run(quantidade: 2, preferencia: nil, parecida_com: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return refuse('A prova virtual só existe no ramo ótica.') unless self.class.otica?(account)

    attachment, rosto, = pick_selfie
    return refuse('Ainda não há foto do rosto da cliente nesta conversa. Peça uma foto de frente, com boa luz, só ela na foto.') if attachment.nil?

    ok, motivo = Otica::FaceReading.usable(rosto)
    return refuse("A foto recebida não serve para a prova virtual: #{motivo}.") unless ok

    products = self.class.candidates(account)
    return refuse('Nenhuma armação do estoque está pronta para a prova virtual (precisa de foto e saldo). Convide para a loja.') if products.empty?

    already = sent_product_ids
    tiers = {}
    if parecida_com.present?
      ref = products.find { |p| p.id == parecida_com.to_i } || Otica::Product.find_by(account_id: account.id, id: parecida_com.to_i)
      return refuse('Não achei essa armação. Use o id devolvido na prova anterior.') if ref.nil?

      quantidade = (quantidade.presence || 3).to_i.clamp(1, MAX_PER_CALL)
      others = products.select { |p| p.id != ref.id && p.kind == ref.kind && already.exclude?(p.id) }
      pool = others.select { |p| p.frame_shape.to_s == ref.frame_shape.to_s }
      pool = others if pool.empty?
      if pool.empty?
        return refuse("Não há outras armações prontas parecidas com \"#{ref.name}\". Diga que essa é a escolha certa e siga para as lentes.")
      end

      chosen, tiers = pick_tiers(pool, quantidade)
      tiers = {} if chosen.size < 2 # faixa só faz sentido comparando (1 parecida sai sem "top de linha")
    else
      quantidade = (quantidade.presence || 2).to_i.clamp(1, MAX_PER_CALL)
      pool = products.reject { |p| already.include?(p.id) }
      pool = products if pool.empty?
      chosen = Otica::Visagismo.recommend(pool, face_shape: rosto['formato'], preference: preferencia, limit: quantidade)
    end

    base = { rosto: rosto['formato'], rosto_label: Otica::Visagismo.face_label(rosto['formato']),
             foto_usada: (media(attachment).dig('rosto', 'angulo') == 'tres_quartos' ? 'de 3/4' : 'de frente'),
             visagismo: Otica::Visagismo.explain(rosto['formato']), parecidas: parecida_com.present? }

    unless @live
      return base.merge(ok: true, simulado: true,
                        aviso: 'SIMULAÇÃO (sombra/teste): nenhuma imagem foi gerada nem enviada. Ao vivo, estas armações ' \
                               'seriam enviadas como fotos da cliente usando cada uma. Comente como se as fotos tivessem chegado.',
                        armacoes: chosen.map { |p| describe(p, rosto, tiers[p.id]) })
    end

    return refuse(JA_ENVIADAS) if just_sent?

    @lock_key = "otica:prova_virtual:#{@conversation.id}"
    unless Redis::Alfred.set(@lock_key, Time.current.to_i, nx: true, ex: LOCK_TTL)
      @lock_key = nil
      return refuse(JA_ENVIADAS)
    end

    today = images_today
    if today >= MAX_IMAGES_PER_DAY
      return refuse("A cliente já recebeu #{today} imagens da prova virtual hoje (limite #{MAX_IMAGES_PER_DAY}). " \
                    'Diga que o resto fica para ver na loja e convide.')
    end

    cap = self.class.daily_cap(account)
    used = self.class.generated_today(account)
    return refuse('O limite diário de imagens da loja foi atingido. Convide para ver as armações na loja.') if used >= cap

    chosen = chosen.first([cap - used, MAX_IMAGES_PER_DAY - today, quantidade].min)
    return refuse('Configure a chave do Gemini em Integrações → IA.') unless Otica::TryOnImage.configured?(account)

    send_aviso!(parecida_com.present?, again: selfie_used_before?(attachment), count: chosen.size)
    before = { bytes: attachment.file.blob.open(&:read), mime: mime_of(attachment.file, 'image/jpeg') }
    logo = brand_logo
    sent = []
    failures = []
    chosen.each_with_index do |product, index|
      # 🪞 08/11: ANTES (a foto dela, sem óculos) | DEPOIS (a mesma foto com a armação) → UM cartão com a marca
      after = Otica::TryOnImage.new(account).generate(selfie: before[:bytes], selfie_mime: before[:mime],
                                                      frame: product.photo.blob.open(&:read),
                                                      frame_mime: mime_of(product.photo, 'image/png'), product: product)
      card = Otica::TryOnCard.compose(images: [before, after], logo: logo, tom: brand_tone)
      send_image!(product, card.merge(model: after[:model]), index + 1, chosen.size, attachment,
                  caption: caption_for(product, index + 1, chosen.size, rosto, tiers[product.id]))
      sent << describe(product, rosto, tiers[product.id]).merge(opcao: index + 1)
    rescue Otica::TryOnImage::Error, ActiveStorage::FileNotFoundError, MiniMagick::Error => e
      Rails.logger.warn("[Otica::VirtualTryOn] armação #{product.id} falhou: #{e.class}: #{e.message}")
      failures << product.name
    end

    if sent.empty?
      return refuse('Não consegui gerar as imagens agora (falha do serviço de imagem). Diga que vai separar as opções e mostrar ' \
                    'na loja; não prometa a foto.')
    end

    # 08/11 (Guilherme): a pergunta que faz ela se ver com o óculos
    pergunta = case sent.size
               when 1 then 'Você já se imagina usando esse?'
               when 2 then 'Qual dos dois você já se imagina usando?'
               else "Qual desses #{sent.size} você já se imagina usando?"
               end
    base.merge(ok: true, enviadas: sent.size, armacoes: sent, falhas: failures, imagens_hoje: today + sent.size,
               aviso: 'As fotos JÁ FORAM ENVIADAS à cliente nesta conversa (uma por armação, com legenda e o motivo). Agora escreva ' \
                      "1 balão curto, sem repetir os nomes nem os motivos (já estão nas legendas), e FECHE com a pergunta: \"#{pergunta}\" " \
                      '(lembre em meia frase que é uma simulação por computador). NÃO chame experimentar_armacoes de novo nesta resposta.')
  ensure
    Redis::Alfred.delete(@lock_key) if @lock_key
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

    logo = brand_logo
    chosen.each do |product|
      image = Otica::TryOnImage.new(account).generate(selfie: selfie, selfie_mime: selfie_mime,
                                                     frame: product.photo.blob.open(&:read), frame_mime: mime_of(product.photo, 'image/png'),
                                                     product: product)
      card = Otica::TryOnCard.compose(images: [{ bytes: selfie, mime: selfie_mime }, image], logo: logo, tom: brand_tone)
      result[:imagens] << { produto: describe(product), product_id: product.id, model: image[:model],
                            data_url: "data:#{card[:mime]};base64,#{Base64.strict_encode64(card[:bytes])}" }
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

  def describe(product, rosto = nil, tier = nil)
    { id: product.id, armacao: product.name, formato: Otica::Visagismo.frame_label(product.frame_shape),
      cor: product.color, valor: product.price, faixa: (tier ? TIERS[tier] : nil),
      motivo: (rosto ? Otica::Visagismo.reason(rosto['formato'], product.frame_shape) : nil),
      observacao: product.visagismo_notes.presence }.compact
  end

  # tom do selo de vidro (branco = logo verde; verde = logo branco), escolhido em Produtos → Venda pelo WhatsApp
  def brand_tone
    Otica::SalesTools.config(account)['selo_tom'].presence || Otica::TryOnCard::DEFAULT_TONE
  end

  # a marca da loja (PNG transparente em Produtos → Venda pelo WhatsApp); nil = cartão sem marca
  def brand_logo
    logo = CrmSetting.find_by(account: account)&.otica_logo
    logo&.attached? ? logo.blob.open(&:read) : nil
  rescue StandardError
    nil
  end

  # 3 faixas de valor: a mais cara (top de linha), a do meio (custo-benefício) e a mais barata (acessível)
  def pick_tiers(pool, quantidade)
    sorted = pool.sort_by { |p| [-p.price, p.id] }
    picks = { 'top' => sorted.first, 'acessivel' => sorted.last, 'custo_beneficio' => sorted[sorted.size / 2] }
    chosen = []
    tiers = {}
    %w[top custo_beneficio acessivel].each do |tier|
      p = picks[tier]
      next if p.nil? || chosen.include?(p) || chosen.size >= quantidade

      chosen << p
      tiers[p.id] = tier
    end
    [chosen, tiers]
  end

  # legenda da foto: "Opção 1 de 2 · HB Switch (retangular): no seu rosto oval, a retangular dá definição…"
  # nas faixas: "Top de linha · R$ 450 · HB Switch (retangular): …"
  def caption_for(product, index, total, rosto, tier)
    head = tier ? "#{TIERS[tier]} · #{money(product.price)}" : "Opção #{index} de #{total}"
    shape = product.frame_shape.present? ? " (#{Otica::Visagismo.frame_label(product.frame_shape)})" : ''
    "#{head} · #{product.name}#{shape}: #{Otica::Visagismo.reason(rosto['formato'], product.frame_shape)}.".truncate(600)
  end

  # "R$ 450" ou "R$ 450,50"
  def money(value)
    v = value.to_f
    v == v.to_i ? "R$ #{v.to_i}" : "R$ #{format('%.2f', v).tr('.', ',')}"
  end

  # imagens que ESTA CLIENTE já recebeu hoje (todas as conversas dela), pelo carimbo das mensagens
  def images_today
    scope = Message.where(account_id: account.id, message_type: :outgoing).where('created_at > ?', Otica::TZ.now.beginning_of_day)
                   .where("additional_attributes ? '#{STAMP_KEY}'")
    contact_id = @conversation.contact_id
    scope = if contact_id
              scope.where(conversation_id: Conversation.where(account_id: account.id, contact_id: contact_id).select(:id))
            else
              scope.where(conversation_id: @conversation.id)
            end
    scope.count
  end

  # armações já mostradas nesta conversa hoje (para "outra" trazer novas)
  def sent_product_ids
    @conversation.messages.where(message_type: :outgoing).where('created_at > ?', Otica::TZ.now.beginning_of_day)
                 .where("additional_attributes ? '#{STAMP_KEY}'")
                 .pluck(Arel.sql("additional_attributes -> '#{STAMP_KEY}' ->> 'product_id'")).map(&:to_i)
  end

  # já saiu imagem de prova depois da última mensagem da cliente (e há pouco)? então esta chamada é repetida
  # (falha do Gemini não conta: o aviso sai mas nenhuma imagem; chamadas simultâneas ficam com a trava)
  def just_sent?
    last_lot = @conversation.messages.where(message_type: :outgoing).where('created_at > ?', RECENT_WINDOW.ago)
                            .where("additional_attributes ? '#{STAMP_KEY}'")
                            .maximum(:created_at)
    return false if last_lot.nil?

    last_from_her = @conversation.messages.where(message_type: :incoming).maximum(:created_at)
    last_from_her.nil? || last_lot >= last_from_her
  end

  # esta foto já foi usada numa prova antes? (aí o aviso não diz "recebi sua foto")
  def selfie_used_before?(attachment)
    @conversation.messages.where(message_type: :outgoing).where("additional_attributes ? '#{STAMP_KEY}'")
                 .exists?(["(additional_attributes -> '#{STAMP_KEY}' ->> 'selfie_attachment_id')::bigint = ?", attachment.id])
  end

  # o balão de "recebi sua foto, já estou montando" sai ANTES das imagens (texto editável em Produtos → Venda pelo WhatsApp);
  # se a foto já foi usada antes, sai "já estou montando mais uma opção"
  def send_aviso!(parecidas, again: false, count: 2) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = Otica::SalesTools.config(account)
    text = if parecidas
             cfg['aviso_parecidas'].presence || DEFAULT_AVISO_PARECIDAS
           elsif again
             DEFAULT_AVISO_MAIS
           else
             cfg['aviso_prova'].presence || DEFAULT_AVISO
           end
    # "te mando 2 opções" / "mais uma opção": a cliente já sabe quantas vêm
    text = text.gsub('{opcoes}', count == 1 ? 'uma opção' : "#{count} opções").gsub('{faixas}', count == 3 ? FAIXAS_TEXTO : '')
    text = Otica::TextSpacing.space(text)
    @conversation.messages.create!(account_id: account.id, inbox_id: @conversation.inbox_id, message_type: :outgoing, content: text,
                                   additional_attributes: { 'cevico_ia_agent' => @agent_key.presence || Otica::TryOnImage::AGENT_KEY,
                                                            AVISO_KEY => true })
  end

  def mime_of(attached, fallback)
    type = attached.content_type.to_s
    type.present? && type != 'application/octet-stream' ? type : fallback
  end

  # a foto gerada vira mensagem da loja na conversa (sai pelo WhatsApp como imagem com legenda)
  def send_image!(product, image, index, total, selfie_attachment, caption: nil) # rubocop:disable Metrics/ParameterLists
    ext = image[:mime].to_s.include?('jpeg') ? 'jpg' : 'png'
    caption ||= "Opção #{index} de #{total}: #{product.name}"
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
