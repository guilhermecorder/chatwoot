# Agente CONSTRUTOR DE PÁGINAS: recebe uma COPY PRONTA (escrita pelo
# Copywriter, pelo Guilherme ou por qualquer pessoa do time) e MONTA a
# página no Construtor v2 — distribui o texto em seções, escolhe os
# efeitos visuais e gera o SEO. Ele NÃO reescreve a copy: no máximo
# lapida transições para o texto caber no formato de cada seção.
class Crm::PageBuilderService
  include Crm::AiAgentConfig

  AGENT_KEY = 'pagebuilder'.freeze

  # a saída é o mesmo formato de página do Copywriter (seções do v2)
  OUTPUT_SCHEMA = Crm::CopywriterService::OUTPUT_SCHEMA

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o construtor de páginas da CEVICO — CUIDADOS OCULARES, clínica
    oftalmológica premium (azul marinho e dourado). Você recebe uma COPY
    PRONTA e monta a página por seções.

    Regras:
    - RESPEITE a copy recebida: não reescreva o conteúdo nem mude o tom.
      Só ajuste transições mínimas quando o texto precisar caber no
      formato de uma seção (ex.: transformar uma lista em cards).
    - Distribua o conteúdo nos tipos de seção: texto, beneficios (cards),
      passos (passo a passo), faq (perguntas frequentes), depoimento
      (SOMENTE se a copy trouxer um), visao (experiência interativa de
      visão — use quando a copy falar de grau/miopia/astigmatismo/
      catarata), hero (faixa de destaque no MEIO da página — nunca a
      primeira seção repetindo o título) e cta (chamada final).
    - Efeitos por seção: nenhum, liquido, foco, movimento, miopia,
      astigmatismo, brilho. Use 2-3 efeitos por página; "miopia"/
      "astigmatismo" só em seções sobre a condição; "brilho" no
      fechamento premium.
    - Gere título da página, subtítulo, emoji, meta_title/meta_description
      (SEO com os termos que o público pesquisa) e o texto do CTA a partir
      da própria copy.
    - A copy pode vir com INSTRUÇÕES DE MONTAGEM embutidas (blocos "não
      renderizar", notas para o agente, pedidos de layout, placeholders
      de foto como [FOTO: ...], [IMAGEM: ...]). Use essas instruções como
      orientação e NUNCA as copie para o texto das seções — o paciente só
      vê o conteúdo final. Placeholders de imagem: descarte (as fotos são
      adicionadas depois no editor).
    - Escreva em português do Brasil.
  PROMPT

  def initialize(account:, copy:, category: 'captacao')
    @account = account
    @copy = copy
    @category = category
  end

  def call
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Construtor de Páginas está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?
    return { error: 'Cole a copy que o construtor deve montar.' } if @copy.blank?

    message = client.messages.create(
      model: model,
      # páginas longas (copy grande) + esforço de raciocínio dividem o
      # MESMO teto de tokens — 8192 truncava o JSON no meio e a página
      # saía vazia (caso real 23/07, landing de catarata trifocal).
      # Construtor PRO: o admin pode escolher o teto na tela do agente.
      max_tokens: max_tokens_config || 30_000,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: build_input }]
    )
    record_usage(message)
    parse_structured_response(message)
  rescue Anthropic::Errors::APIError => e
    { error: "Erro na IA: #{e.message}" }
  rescue JSON::ParserError, TypeError
    { error: 'A IA devolveu um formato inesperado. Tente de novo.' }
  rescue StandardError => e
    Rails.logger.error "[PageBuilder] #{e.class}: #{e.message}"
    { error: "Não consegui montar agora (#{e.class.name.demodulize}). Tente de novo em instantes." }
  end

  private

  def build_input
    <<~INPUT
      ETAPA DA JORNADA: #{CevicoPage::CATEGORIES[@category] || @category}
      #{style_refs_block}
      COPY PRONTA (montar a página com este conteúdo):
      #{@copy}
    INPUT
  end
end
