# 🪝 item 397: a IA do Banco de Ganchos. Duas tarefas:
#   :ganchos → escolhido o TIPO de gancho (categoria) e o tema, preenche os
#              modelos do banco para a CEVICO (o time escolhe um e segue);
#   :copy    → com o gancho escolhido + a estrutura de história + a oferta,
#              escreve o corpo no padrão GANCHO → HISTÓRIA → OFERTA, com
#              reganchos (ganchos contextualizados) ao longo da copy.
# Usa a configuração do agente COPYWRITER (mesma chave, mesmo liga/desliga).
class Crm::CopyBankGenerator
  include Crm::AiAgentConfig

  AGENT_KEY = 'copywriter'.freeze

  TEMAS = {
    'refrativa' => 'cirurgia refrativa a laser (tirar o óculos/lente de contato: miopia, astigmatismo, hipermetropia; PRK e LASIK)',
    'catarata' => 'cirurgia de catarata (troca do cristalino por lente intraocular; lentes monofocal, tórica, foco estendido, trifocal)',
    'avaliacao' => 'a avaliação oftalmológica completa da CEVICO (o primeiro passo antes de qualquer cirurgia)',
    'geral' => 'saúde dos olhos e a CEVICO como clínica'
  }.freeze

  FORMATOS = {
    'reels' => 'roteiro de REELS (fala do apresentador; frases curtas, ditas em voz alta)',
    'carrossel' => 'CARROSSEL (um pensamento por cartão; cada cartão termina puxando o próximo)',
    'anuncio' => 'texto de ANÚNCIO (Meta), direto e escaneável',
    'post' => 'LEGENDA de post (gancho na 1ª linha, corpo escaneável, CTA no fim)'
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o redator de criativos da CEVICO — CUIDADOS OCULARES, clínica
    oftalmológica em São Paulo (unidades Av. Paulista e Tatuapé). Escreve
    no padrão GANCHO → HISTÓRIA → OFERTA (hook, story, offer).

    Voz: português do Brasil falado, simples, acolhedor, específico. Sem
    jargão médico sem tradução. Valores da marca: tecnologia de ponta,
    acolhimento humano e clareza.

    REGRAS DO CFM (obrigatórias): nunca prometer ou garantir resultado;
    nada de "antes e depois" de paciente; nada de superlativo ("o melhor",
    "o único", "o mais moderno"); nada de sensacionalismo ou medo exagerado;
    não inventar números (nota, quantidade de cirurgias, porcentagens).
    Fatos que PODEM ser usados: avaliação completa por 150 reais com os
    exames da avaliação inclusos; unidades Paulista e Tatuapé; a equipe
    explica cada etapa; atendimento pelo WhatsApp.

    Ao usar um MODELO de gancho, mantenha a estrutura (é ela que prende) e
    troque as [lacunas] por conteúdo concreto do tema. Responda só no
    formato estruturado pedido.
  PROMPT

  GANCHOS_SCHEMA = {
    type: 'object', additionalProperties: false, required: %w[ganchos],
    properties: {
      ganchos: {
        type: 'array',
        items: {
          type: 'object', additionalProperties: false, required: %w[modelo_id texto],
          properties: { modelo_id: { type: 'integer' }, texto: { type: 'string' } }
        }
      }
    }
  }.freeze

  COPY_SCHEMA = {
    type: 'object', additionalProperties: false, required: %w[gancho historia oferta],
    properties: {
      gancho: { type: 'string' },
      historia: { type: 'string' },
      oferta: { type: 'string' },
      reganchos_usados: { type: 'array', items: { type: 'string' } }
    }
  }.freeze

  def initialize(account, opts = {})
    @account = account
    @opts = opts
    @tema = TEMAS.key?(opts[:tema]) ? opts[:tema] : 'refrativa'
    @formato = FORMATOS.key?(opts[:formato]) ? opts[:formato] : 'reels'
  end

  # modelos = [{ id, texto, exemplo }]
  def ganchos(modelos)
    return { error: 'Nenhum modelo de gancho para preencher.' } if modelos.blank?

    lista = modelos.map { |m| "##{m[:id]}: #{m[:texto]}" }.join("\n")
    ask(GANCHOS_SCHEMA, 4096, <<~MSG)
      TEMA: #{TEMAS[@tema]}
      #{extra_block}
      Preencha CADA modelo abaixo para o tema, um gancho por modelo
      (devolva o modelo_id). O gancho é a primeira frase do vídeo/anúncio:
      curto, concreto, que faça a pessoa parar de rolar.

      MODELOS:
      #{lista}
    MSG
  end

  # partes = { gancho:, historia_modelo:, historia:, oferta:, reganchos: [..] }
  def copy(partes)
    return { error: 'Escolha um gancho primeiro.' } if partes[:gancho].blank?

    ask(COPY_SCHEMA, 6000, <<~MSG)
      TEMA: #{TEMAS[@tema]}
      FORMATO: #{FORMATOS[@formato]}
      #{extra_block}
      GANCHO escolhido (mantenha, só ajuste o mínimo se ferir alguma regra):
      #{partes[:gancho]}

      HISTÓRIA — estrutura a seguir: #{partes[:historia_modelo].presence || 'livre'}
      #{partes[:historia].present? ? "Rascunho do time (aproveite e melhore):\n#{partes[:historia]}" : ''}

      OFERTA — CTA escolhido (adapte ao tema, sem perder a essência):
      #{partes[:oferta].presence || 'Convite leve para chamar no WhatsApp.'}

      #{reganchos_block(partes[:reganchos])}
      Devolva gancho, historia (o corpo, com quebras de linha) e oferta.
    MSG
  end

  private

  def extra_block
    notas = @opts[:notas].to_s.strip
    notas.present? ? "OBSERVAÇÕES DO TIME: #{notas[0, 1500]}" : ''
  end

  def reganchos_block(list)
    list = Array(list).map(&:to_s).compact_blank
    return '' if list.empty?

    'REGANCHOS: insira na HISTÓRIA, nos pontos de virada, ganchos de reconexão contextualizados ao tema ' \
      "(adapte estas frases, uma por trecho, sem exagerar): #{list.join(' | ')}. Liste em reganchos_usados como ficaram."
  end

  def ask(schema, max_tokens, content)
    error = config_error
    return error if error

    message = client.messages.create(
      model: model, max_tokens: max_tokens, system_: cached_system,
      output_config: output_config_for({ type: 'json_schema', schema: schema }),
      messages: [{ role: 'user', content: content }]
    )
    record_usage(message)
    parse_structured_response(message)
  rescue Anthropic::Errors::APIError => e
    { error: "Erro na IA: #{e.message}" }
  rescue JSON::ParserError, TypeError
    { error: 'A IA devolveu um formato inesperado. Tente de novo.' }
  rescue StandardError => e
    Rails.logger.error "[CopyBank] #{e.class}: #{e.message}"
    { error: "Não consegui gerar agora (#{e.class.name.demodulize}). Tente de novo em instantes." }
  end

  def config_error
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Copywriter está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?

    nil
  end

  # o prompt do Copywriter (se o admin personalizou) NÃO vale aqui: este
  # gerador tem o seu, sempre com a trava de leitura no fim
  def system_prompt
    SYSTEM_PROMPT + OPERATIONAL_GUARDRAIL
  end
end
