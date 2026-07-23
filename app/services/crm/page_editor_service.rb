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
    - Nunca prometa resultado de cirurgia nem invente dados clínicos,
      preços ou depoimentos.
    - "reply": 1-3 frases em pt-BR contando o que mudou; quando couber,
      sugira fotos concretas por seção (a equipe adora saber o que
      fotografar).
  PROMPT

  def initialize(account:, page:, instruction:)
    @account = account
    @page = page
    @instruction = instruction
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
      messages: [{ role: 'user', content: build_input }]
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
      #{style_refs_block}
      INSTRUÇÃO DA EQUIPE (aplicar agora):
      #{@instruction}
    INPUT
  end
end
