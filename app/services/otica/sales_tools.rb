# 💬 VENDA PELO WHATSAPP (08/11/2026, 2ª etapa da ideia do Henrique): depois
# que a cliente se viu de óculos (prova virtual), o agente conduz o resto da
# venda pela conversa, com três ferramentas desta classe (só ramo ótica):
#
#   mostrar_lentes       consultoria de lentes: lista as lentes da loja (preço
#                        CHEIO, pra quem é, o que resolve) e ENVIA a imagem
#                        explicativa de cada uma, quando cadastrada;
#   conferir_desconto    a negociação: a cliente diz quanto cabe → o sistema
#                        confere contra o desconto máximo de cada produto
#                        (nunca mostrado ao modelo) e devolve aprovado ou a
#                        melhor contraproposta. AO VIVO manda na hora o balão
#                        "me dá um instante…" e espera ~30 s antes de devolver,
#                        para a resposta chegar como quem conferiu de verdade;
#   registrar_fechamento o "sim": abre a TAREFA para a Val (Meu Painel) com
#                        armação, lente, valor e forma de pagamento, e devolve
#                        a chave Pix / o link de pagamento da loja para o agente
#                        enviar. O comprovante que chegar depois é imagem tipo
#                        "comprovante": o agente abre tarefa (abrir_tarefa).
#
# Config da loja (CrmSetting.ai_config['otica_venda'], tela Produtos → Venda
# pelo WhatsApp): pix_key, payment_link, default_discount_pct.
# Em SOMBRA nada é enviado, nada espera e nenhuma tarefa nasce: tudo `simulado`.
class Otica::SalesTools
  NAMES = %w[pedir_fotos mostrar_lentes conferir_desconto registrar_fechamento status_do_pedido].freeze
  # 🪞 08/11: o pedido da foto (uma só: "quanto mais fácil, melhor") sai com o cartão-exemplo da loja (Produtos → Venda pelo WhatsApp)
  DEFAULT_PHOTO_GUIDE = 'Me manda uma foto sua, assim fica bem parecido: de frente pra uma janela, com a luz do dia no rosto, ' \
                        'celular com o braço esticado na altura dos olhos, sem óculos e sem boné, só você na foto.'.freeze
  # as 3 de venda são dos atendentes de aquisição; o status do pedido é de todos (o pós-compra vive dele)
  SALES_KEYS = %w[atendente_agendamento atendente_pos atendente_visagista].freeze
  CONFIG_KEY = 'otica_venda'.freeze
  MAX_LENSES = 3
  MAX_CHECKS_PER_DAY = 3
  # a espera "conferindo no sistema" (ao vivo): o balão sai antes, a resposta depois
  CHECK_WAIT = 25
  CHECK_TEXT = 'Me dá um instante que eu vou conferir aqui no sistema a possibilidade pra você. Me dá uns 30 segundos.'.freeze
  STAMP_KEY = 'cevico_venda'.freeze
  PAYMENT_METHODS = %w[pix link na_loja].freeze

  def self.config(account)
    (CrmSetting.find_by(account: account)&.ai_config&.dig(CONFIG_KEY) || {}).to_h
  end

  def self.save_config!(account, attrs) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    setting = CrmSetting.find_or_create_by!(account: account)
    cfg = (setting.ai_config || {}).dup
    current = (cfg[CONFIG_KEY] || {}).to_h
    current['pix_key'] = attrs['pix_key'].to_s.strip[0, 120] if attrs.key?('pix_key')
    current['payment_link'] = attrs['payment_link'].to_s.strip[0, 300] if attrs.key?('payment_link')
    current['default_discount_pct'] = attrs['default_discount_pct'].to_s.tr(',', '.').to_f.clamp(0, 90).round(2) if attrs.key?('default_discount_pct')
    # 🪞 08/11: balões que saem ANTES das imagens da prova virtual (vazio = texto padrão)
    current['aviso_prova'] = attrs['aviso_prova'].to_s.strip[0, 400] if attrs.key?('aviso_prova')
    current['aviso_parecidas'] = attrs['aviso_parecidas'].to_s.strip[0, 400] if attrs.key?('aviso_parecidas')
    current['orientacao_foto'] = attrs['orientacao_foto'].to_s.strip[0, 600] if attrs.key?('orientacao_foto')
    if attrs.key?('selo_tom')
      tone = attrs['selo_tom'].to_s
      current['selo_tom'] = Otica::TryOnCard::TONES.key?(tone) ? tone : Otica::TryOnCard::DEFAULT_TONE
    end
    cfg[CONFIG_KEY] = current
    setting.update!(ai_config: cfg)
    current
  end

  def self.definitions(agent_key = nil)
    list = agent_key.nil? || SALES_KEYS.include?(agent_key.to_s) ? sales_definitions : []
    list + [status_definition]
  end

  # 📦 08/11: "já ficou pronto?" — o pedido do cliente, etapa por etapa
  def self.status_definition
    {
      name: 'status_do_pedido',
      description: 'ACOMPANHAMENTO DO PEDIDO: devolve a situação do óculos do cliente desta conversa (O.S.): etapa (lentes ' \
                   'pedidas ao laboratório, em produção, PRONTO para retirar, entregue), previsão do laboratório, prazo ' \
                   'prometido, desde quando está pronto e o que falta pagar. Use quando o cliente perguntar "já ficou ' \
                   'pronto?", "quando fica pronto?", "chegou minha lente?". Se estiver pronto, ofereça marcar a retirada ' \
                   '(HORÁRIOS PARA RETIRADA DO ÓCULOS). Sem pedido no cadastro: pergunte o nome completo e passe para a equipe.',
      input_schema: { type: 'object', properties: {}, additionalProperties: false }
    }
  end

  def self.sales_definitions # rubocop:disable Metrics/MethodLength
    [
      {
        name: 'pedir_fotos',
        description: 'PEDIDO DA FOTO PARA A PROVA VIRTUAL: envia à cliente, nesta conversa, a sugestão de como tirar a foto ' \
                     '(com o cartão-exemplo da loja, se houver). Use UMA vez, no momento em que ela aceita ver armações no rosto ' \
                     'dela (ou logo ao convidar). Depois do ok=true você não repete a orientação: só espera a foto. Qualquer ' \
                     'foto boa serve; vale sempre a última que ela mandar.',
        input_schema: { type: 'object', properties: {}, additionalProperties: false }
      },
      {
        name: 'mostrar_lentes',
        description: 'CONSULTORIA DE LENTES: devolve as lentes que a loja trabalha (nome, pra quem é, o que resolve, valor ' \
                     'CHEIO) e ENVIA à cliente, nesta conversa, a imagem explicativa de cada lente que tiver imagem (até 3). ' \
                     'Use quando a cliente perguntar quais lentes existem, qual a diferença, ou quando ela gostou da armação e ' \
                     'é hora de escolher a lente. Informe a rotina dela (tela, rua, leitura, perto e longe, grau alto) para ' \
                     'ordenar as mais indicadas. As imagens chegam antes da sua fala: comente em palavras simples e pergunte ' \
                     'qual faz mais sentido pra rotina dela.',
        input_schema: {
          type: 'object',
          properties: {
            rotina: { type: 'string', description: 'A rotina da cliente em poucas palavras: "tela o dia todo", "perto e longe", ' \
                                                   '"dirige à noite", "grau alto", "leitura"' },
            quantidade: { type: 'integer', minimum: 1, maximum: MAX_LENSES, description: 'Quantas lentes mostrar (padrão 3)' }
          },
          additionalProperties: false
        }
      },
      {
        name: 'conferir_desconto',
        description: 'NEGOCIAÇÃO: só depois de a cliente pedir desconto ou dizer quanto cabe no orçamento dela. Informe a ' \
                     'armação, a lente e o valor que ela disse. O sistema confere contra a política da loja e devolve ' \
                     'aprovado=true (feche nesse valor) ou aprovado=false com melhor_valor (a contraproposta: ofereça esse ' \
                     'valor, nunca menos). AO VIVO o sistema já envia o balão "me dá um instante que vou conferir" e espera ' \
                     'uns 30 segundos antes de devolver: você só escreve a resposta ("Boa notícia: conferi aqui e, fechando ' \
                     'hoje, consigo R$ X. Dá pra você fazer esse investimento?"). Nunca invente desconto fora desta ferramenta.',
        input_schema: {
          type: 'object',
          properties: {
            armacao_id: { type: 'integer', description: 'id da armação escolhida (da prova virtual ou de mostrar_lentes)' },
            lente_id: { type: 'integer', description: 'id da lente escolhida (de mostrar_lentes)' },
            valor_pedido: { type: 'number', description: 'O valor que a cliente disse que cabe (R$). Se ela só pediu desconto ' \
                                                         'sem dizer valor, pergunte "quanto cabe pra você?" antes de usar.' }
          },
          required: %w[armacao_id lente_id valor_pedido],
          additionalProperties: false
        }
      },
      {
        name: 'registrar_fechamento',
        description: 'FECHAMENTO: quando a cliente disse SIM ao valor e escolheu como pagar. Abre a tarefa para a equipe da ' \
                     'loja (separar armação, lente e acompanhar o pagamento) e devolve o que você deve enviar: a chave Pix ou ' \
                     'o link de pagamento parcelado da loja, ou a orientação para pagar na loja. Peça o comprovante em seguida; ' \
                     'quando ele chegar (imagem "comprovante"), use abrir_tarefa com urgência normal.',
        input_schema: {
          type: 'object',
          properties: {
            armacao_id: { type: 'integer' },
            lente_id: { type: 'integer' },
            valor: { type: 'number', description: 'Valor fechado (R$): o cheio ou o aprovado por conferir_desconto' },
            forma_pagamento: { type: 'string', enum: PAYMENT_METHODS, description: 'pix | link (cartão parcelado) | na_loja' },
            observacao: { type: 'string', description: 'Receita em mãos? exame marcado? qualquer combinado em 1 frase' }
          },
          required: %w[valor forma_pagamento],
          additionalProperties: false
        }
      }
    ]
  end

  # simulation = Testar agente: sem a espera de 30 s e sem tarefa real no fechamento
  def initialize(conversation:, agent_key:, live:, simulation: false)
    @conversation = conversation
    @account = conversation.account
    @agent_key = agent_key.to_s
    @live = live == true
    @simulation = simulation == true
  end

  # devolve [outcome (tool_result), resumo (para a ação)]
  def call(name, args)
    case name
    when 'pedir_fotos' then pedir_fotos
    when 'mostrar_lentes' then mostrar_lentes(args)
    when 'conferir_desconto' then conferir_desconto(args)
    when 'registrar_fechamento' then registrar_fechamento(args)
    when 'status_do_pedido' then status_do_pedido
    else [{ ok: false, motivo: "Ferramenta desconhecida: #{name}" }, 'desconhecida']
    end
  end

  # ── pedido da foto (cartão-exemplo + orientação) ──────────────────────────
  def pedir_fotos # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    cfg = self.class.config(@account)
    text = Otica::TextSpacing.space(cfg['orientacao_foto'].presence || DEFAULT_PHOTO_GUIDE)
    example = CrmSetting.find_by(account: @account)&.otica_photo_example
    # já pediu hoje nesta conversa (o agente às vezes chama de novo no "topo!"): não repete, só espera
    if @live && @conversation.messages.where(message_type: :outgoing).where('created_at > ?', Otica::TZ.now.beginning_of_day)
                             .where("additional_attributes ? 'cevico_pedir_fotos'").exists?
      return [{ ok: true, repetido: true, aviso: 'A orientação JÁ tinha sido enviada hoje: não repita nada, só espere a foto.' }, 'já enviada hoje']
    end

    unless @live
      return [{ ok: true, simulado: true, com_exemplo: example&.attached? == true,
                aviso: 'SIMULAÇÃO: ao vivo a cliente receberia a sugestão de como tirar a foto. Agora só espere a foto.' },
              'simulado']
    end

    if example&.attached?
      message = @conversation.messages.new(account_id: @account.id, inbox_id: @conversation.inbox_id, message_type: :outgoing,
                                           content: text, additional_attributes: { 'cevico_ia_agent' => @agent_key, 'cevico_pedir_fotos' => true })
      message.attachments.build(account_id: @account.id, file_type: :image,
                                file: { io: StringIO.new(example.blob.open(&:read)), filename: 'como-tirar-as-fotos.jpg',
                                        content_type: example.content_type.presence || 'image/jpeg' })
      message.save!
    else
      @conversation.messages.create!(account_id: @account.id, inbox_id: @conversation.inbox_id, message_type: :outgoing, content: text,
                                     additional_attributes: { 'cevico_ia_agent' => @agent_key, 'cevico_pedir_fotos' => true })
    end
    [{ ok: true, com_exemplo: example&.attached? == true,
       aviso: 'A orientação JÁ FOI ENVIADA à cliente (com o cartão-exemplo, se a loja tem um). Não repita a orientação: escreva no ' \
              'máximo 1 linha ou nada, e espere a foto.' },
     "orientação enviada#{' + cartão-exemplo' if example&.attached?}"]
  end

  # ── consultoria de lentes ─────────────────────────────────────────────────
  def mostrar_lentes(args) # rubocop:disable Metrics/AbcSize
    quantidade = (args['quantidade'].presence || MAX_LENSES).to_i.clamp(1, MAX_LENSES)
    lenses = ordered_lenses(args['rotina'].to_s)
    return [{ ok: false, motivo: 'A loja ainda não tem lentes cadastradas com valor. Diga que vai explicar as lentes na loja.' }, 'sem lentes'] if lenses.empty?

    chosen = lenses.first(quantidade)
    sent = 0
    if @live
      with_photo = chosen.select { |l| l.photo.attached? }
      with_photo.each_with_index do |lens, index|
        send_image!(lens, "#{lens.name}: #{lens.pitch.presence || Otica::Product::LENS_TYPES[lens.lens_type]}", index + 1, with_photo.size)
        sent += 1
      end
    end
    listed = chosen.map { |l| describe_lens(l) }
    outcome = { ok: true, simulado: !@live, lentes: listed, imagens_enviadas: sent,
                aviso: if @live
                         "#{sent} imagem(ns) de lente JÁ FORAM ENVIADAS à cliente (as que têm imagem). Explique em palavras simples " \
                         'pra quem é cada lente e pergunte qual faz mais sentido pra rotina dela. Os valores são o preço CHEIO: ' \
                         'é o único que você passa, salvo conferir_desconto.'
                       else
                         'SIMULAÇÃO (sombra/teste): nenhuma imagem foi enviada. Ao vivo, as lentes com imagem seriam enviadas. ' \
                         'Comente como se tivessem chegado.'
                       end }
    [outcome, "#{chosen.size} lente(s)#{" · #{sent} imagem(ns)" if @live}: #{chosen.map(&:name).join(', ')}"]
  end

  # ── negociação ────────────────────────────────────────────────────────────
  def conferir_desconto(args) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    frame = product(args['armacao_id'])
    lens = product(args['lente_id'])
    return [{ ok: false, motivo: 'Armação ou lente não encontrada (use os ids de mostrar_lentes / prova virtual).' }, 'produto não encontrado'] if frame.nil? || lens.nil?

    asked = args['valor_pedido'].to_f.round(2)
    return [{ ok: false, motivo: 'Informe o valor que a cliente disse que cabe (valor_pedido maior que zero).' }, 'sem valor'] unless asked.positive?

    checks = checks_today
    if checks >= MAX_CHECKS_PER_DAY
      return [{ ok: false, motivo: "Já foram #{checks} conferências hoje nesta conversa. Mantenha a última proposta e convide para a loja." },
              'limite de conferências']
    end

    default_pct = self.class.config(@account)['default_discount_pct'].to_f
    full = (frame.price + lens.price).round(2)
    floor = (frame.floor_price(default_pct) + lens.floor_price(default_pct)).round(2)
    # a contraproposta sai redonda (de 10 em 10, nunca abaixo do piso)
    best = (floor / 10.0).ceil * 10.0
    best = full if best > full

    if @live
      send_text!(CHECK_TEXT)
      activity_note!("💬 Negociação (#{stamp}): cliente pediu R$ #{money(asked)} · cheio R$ #{money(full)} · " \
                     "#{asked >= floor ? 'APROVADO' : "contraproposta R$ #{money(best)}"}")
      sleep CHECK_WAIT unless @simulation
    end

    base = { ok: true, simulado: !@live, preco_cheio: full, valor_pedido: asked, armacao: frame.name, lente: lens.name }
    if asked >= floor
      value = [asked, full].min
      [base.merge(aprovado: true, valor_fechamento: value,
                  aviso: "APROVADO: feche em R$ #{money(value)} se ela comprar hoje. Diga que conferiu no sistema, que tem uma boa " \
                         'notícia, o valor, e feche com "Dá pra você fazer esse investimento?". Depois pare de falar e espere.'),
       "pediu R$ #{money(asked)} → aprovado R$ #{money(value)}"]
    else
      [base.merge(aprovado: false, melhor_valor: best,
                  aviso: "NÃO dá em R$ #{money(asked)}. O melhor que a loja consegue hoje é R$ #{money(best)} (cheio R$ #{money(full)}). " \
                         'Diga que conferiu, que esse é o máximo que liberaram, e pergunte se dá pra fechar nesse valor hoje. ' \
                         'Nunca ofereça menos do que isso.'),
       "pediu R$ #{money(asked)} → contraproposta R$ #{money(best)}"]
    end
  end

  # ── fechamento ────────────────────────────────────────────────────────────
  def registrar_fechamento(args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    value = args['valor'].to_f.round(2)
    method = args['forma_pagamento'].to_s
    return [{ ok: false, motivo: 'Informe o valor fechado e a forma de pagamento (pix, link ou na_loja).' }, 'dados faltando'] unless value.positive? && PAYMENT_METHODS.include?(method)

    frame = product(args['armacao_id'])
    lens = product(args['lente_id'])
    cfg = self.class.config(@account)
    payment = payment_instructions(method, cfg)
    detalhes = ["Armação: #{frame&.name || 'a definir'}", "Lente: #{lens&.name || 'a definir'}", "Valor fechado: R$ #{money(value)}",
                "Pagamento: #{method.tr('_', ' ')}", args['observacao'].to_s.presence].compact.join(' · ')

    unless @live && !@simulation
      return [{ ok: true, simulado: true, pagamento: payment,
                aviso: 'SIMULAÇÃO: a tarefa para a equipe NÃO foi aberta. Ao vivo seria. Envie as orientações de pagamento como se fosse real.' },
              "simulado: #{detalhes.truncate(100)}"]
    end

    result = Crm::HandoffTask.open!(account: @account, contact: @conversation.contact, conversation: @conversation, agent_key: @agent_key,
                                    motivo: "Venda fechada pelo WhatsApp: R$ #{money(value)} (#{method.tr('_', ' ')})",
                                    detalhes: detalhes, urgencia: 'normal')
    stamp_conversation!(frame, lens, value, method)
    activity_note!("🛍️ Fechamento (#{stamp}): #{detalhes}")
    [{ ok: true, simulado: false, tarefa_id: result[:task]&.id, pagamento: payment,
       aviso: 'Tarefa aberta para a equipe da loja. Envie as orientações de pagamento abaixo em 1 balão e peça o comprovante por ' \
              'aqui. Quando o comprovante chegar, use abrir_tarefa (normal) dizendo "comprovante recebido".' },
     "R$ #{money(value)} · #{method.tr('_', ' ')} · tarefa #{result[:task]&.id}"]
  rescue StandardError => e
    Rails.logger.error "[Otica::SalesTools#registrar_fechamento] #{e.class}: #{e.message}"
    [{ ok: false, motivo: 'Não consegui registrar o fechamento agora. Diga que a equipe confirma por aqui em instantes e marque chamar_humano.' },
     "erro: #{e.message.truncate(80)}"]
  end

  # ── 📦 acompanhamento do pedido ──────────────────────────────────────────
  def status_do_pedido
    contact = @conversation.contact
    orders = Otica::Order.where(account_id: @account.id, contact_id: contact&.id).includes(:lab_orders).order(:sold_on, :id).to_a
    return [{ ok: false, motivo: 'Nenhum pedido (O.S.) no cadastro deste cliente. Pergunte o nome completo e passe para a equipe (abrir_tarefa).' }, 'sem pedido'] if orders.empty?

    watch = Otica::OrderWatch.new(@account)
    open_orders = orders.select(&:open?)
    shown = (open_orders.presence || orders.last(1))
    [{ ok: true, pedidos: shown.map { |o| { os: o.number, status: o.status, resumo: watch.describe(o), pronto: o.status == 'pronta' } },
       aviso: 'Responda em palavras simples (sem o número da O.S., salvo se o cliente pedir). Pronto → ofereça marcar a retirada. ' \
              'Em produção → diga a previsão e que avisa por aqui quando ficar pronto. Nunca prometa data que não está no resumo.' },
     "#{shown.size} pedido(s): #{shown.map { |o| "#{o.label} #{o.status}" }.join(', ')}"]
  end

  private

  def product(id)
    return nil if id.blank?

    Otica::Product.where(account_id: @account.id).active.find_by(id: id.to_i)
  end

  # lentes ativas com valor; a rotina da cliente puxa as mais indicadas para cima
  def ordered_lenses(rotina)
    lenses = Otica::Product.where(account_id: @account.id, kind: 'lente').active.priced.with_attached_photo.to_a
    text = rotina.to_s.downcase
    lenses.sort_by do |l|
      hay = [l.name, l.lens_type, l.lens_material, l.lens_treatment, l.pitch, l.notes].join(' ').downcase
      score = 0
      score += 3 if text.match?(/perto e longe|longe e perto|multifocal|progressiv/) && l.lens_type == 'multifocal'
      score += 3 if text.match?(/tela|computador|celular/) && hay.match?(/azul|blue|digital|tela/)
      score += 2 if text.match?(/dirig|noite|rua/) && hay.match?(/antirreflexo|ar |fotossens|transitions/)
      score += 2 if text.match?(/grau alto|grau forte|lente grossa/) && hay.match?(/1\.6|1\.67|1\.74|fina|alto/)
      score += 1 if l.photo.attached?
      [-score, l.price, l.id]
    end
  end

  def describe_lens(lens)
    { id: lens.id, lente: lens.name, tipo: Otica::Product::LENS_TYPES[lens.lens_type], material: lens.lens_material.presence,
      tratamento: lens.lens_treatment.presence, pra_quem: lens.pitch.presence, valor_cheio: lens.price,
      prazo_dias: (lens.lab_days.positive? ? lens.lab_days : nil), tem_imagem: lens.photo.attached? }.compact
  end

  def payment_instructions(method, cfg)
    case method
    when 'pix'
      cfg['pix_key'].present? ? { tipo: 'pix', chave_pix: cfg['pix_key'], texto: "Chave Pix da loja: #{cfg['pix_key']}. Depois do Pix, me manda o comprovante por aqui?" } \
                              : { tipo: 'pix', texto: 'A loja ainda não tem chave Pix cadastrada: diga que a equipe envia a chave por aqui em instantes.' }
    when 'link'
      cfg['payment_link'].present? ? { tipo: 'link', link: cfg['payment_link'], texto: "Link para pagar no cartão, parcelado: #{cfg['payment_link']}. Me avisa quando concluir?" } \
                                   : { tipo: 'link', texto: 'A loja ainda não tem link de pagamento: diga que a equipe envia o link por aqui em instantes.' }
    else
      { tipo: 'na_loja', texto: 'Pagamento na loja, na hora de confirmar a armação e a lente.' }
    end
  end

  def checks_today
    @conversation.messages.where(message_type: :outgoing).where('created_at > ?', Otica::TZ.now.beginning_of_day)
                 .where(content: [CHECK_TEXT, Otica::TextSpacing.space(CHECK_TEXT)]).count
  end

  def send_text!(text)
    text = Otica::TextSpacing.space(text) # 💬 linha em branco entre as frases
    @conversation.messages.create!(account_id: @account.id, inbox_id: @conversation.inbox_id, message_type: :outgoing, content: text,
                                   additional_attributes: { 'cevico_ia_agent' => @agent_key })
  end

  def send_image!(lens, caption, index, total)
    ext = lens.photo.content_type.to_s.include?('jpeg') ? 'jpg' : 'png'
    # anexo ANTES do save (mensagem sem anexo dispara o envio na hora e sai só o texto)
    message = @conversation.messages.new(
      account_id: @account.id, inbox_id: @conversation.inbox_id, message_type: :outgoing,
      content: (total > 1 ? "Lente #{index} de #{total}. #{caption}" : caption).truncate(900),
      additional_attributes: { 'cevico_ia_agent' => @agent_key, STAMP_KEY => { 'lente_id' => lens.id } }
    )
    message.attachments.build(account_id: @account.id, file_type: :image,
                              file: { io: StringIO.new(lens.photo.blob.open(&:read)), filename: "lente-#{lens.id}.#{ext}",
                                      content_type: lens.photo.content_type.presence || 'image/png' })
    message.save!
    message
  end

  def stamp_conversation!(frame, lens, value, method)
    attrs = (@conversation.additional_attributes || {}).dup
    attrs[STAMP_KEY] = { 'fechado_em' => Time.current.iso8601, 'armacao_id' => frame&.id, 'lente_id' => lens&.id,
                         'valor' => value, 'forma' => method }
    @conversation.update!(additional_attributes: attrs)
  end

  def activity_note!(content)
    @conversation.messages.create!(account_id: @account.id, inbox_id: @conversation.inbox_id, message_type: :activity, private: true, content: content)
  rescue StandardError => e
    Rails.logger.warn "[Otica::SalesTools] nota: #{e.message}"
  end

  def money(value)
    format('%.2f', value.to_f).tr('.', ',')
  end

  def stamp
    Otica::TZ.now.strftime('%d/%m %H:%M')
  end
end
