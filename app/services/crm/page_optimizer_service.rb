# 🧠 SUGESTÕES DA IA para OTIMIZAR uma página (item 329, 05/10 — "precisamos
# inclusive poder otimizar a página"). Só roda quando alguém aperta o botão
# na tela Resultados de tráfego.
#
# Recebe a página (textos como estão no ar), os números dela no período e os
# diagnósticos automáticos (Cevico::PageInsights) e devolve um diagnóstico
# curto + até 5 mudanças concretas, cada uma com o PEDIDO PRONTO para colar no
# chat do ambiente de montagem (onde a IA construtora aplica e a pessoa confere).
#
# Usa a config do Construtor de Páginas (mesma chave, modelo e interruptor em
# Automações → Agentes de IA). A IA só sugere: nada muda na página sozinho.
class Crm::PageOptimizerService
  include Crm::AiAgentConfig

  AGENT_KEY = 'pagebuilder'.freeze
  MAX_PAGE_CHARS = 14_000

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      diagnostico: { type: 'string', description: 'Leitura da página em 2 a 3 frases: onde o funil vaza e por quê' },
      sugestoes: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            titulo: { type: 'string', description: 'A mudança em poucas palavras' },
            por_que: { type: 'string', description: 'O número ou trecho da página que justifica' },
            pedido: { type: 'string', description: 'Instrução pronta para o ambiente de montagem, no imperativo, citando a seção e o texto novo' }
          },
          required: %w[titulo por_que pedido],
          additionalProperties: false
        }
      }
    },
    required: %w[diagnostico sugestoes],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é analista de conversão das páginas da CEVICO — CUIDADOS OCULARES,
    clínica oftalmológica (cirurgia refrativa, catarata, ceratocone, lentes
    fácicas). O objetivo de cada página é levar o paciente a clicar no botão
    do WhatsApp e conversar com a equipe.

    Você recebe: os textos da página como estão no ar, os números do período
    (visitas → cliques no WhatsApp → leads na caixa → agendaram → cirurgias),
    até onde as pessoas leem e os diagnósticos automáticos já feitos.

    Devolva um diagnóstico curto e de 3 a 5 mudanças CONCRETAS, da que mais
    deve aumentar a conversão para a que menos. Cada mudança traz:
    - titulo: a mudança em poucas palavras;
    - por_que: o número ou o trecho da página que justifica (cite-o);
    - pedido: a instrução pronta para a IA construtora aplicar — diga a seção
      e escreva o texto novo entre aspas.

    Regras:
    - Baseie-se só no que recebeu. Com pouca visita, diga que ainda é cedo e
      sugira o que testar, sem afirmar certeza.
    - Nunca prometa resultado de cirurgia, nunca invente dado clínico, preço,
      depoimento ou número.
    - Não sugira colocar preço na página: o valor é conversado no atendimento.
    - Não cite nome de médico. A autoridade é da equipe cirúrgica especializada
      e da estrutura de alta tecnologia.
    - Português do Brasil, simples e direto, sem jargão de marketing.
  PROMPT

  def initialize(page:, row:, insights:, period:)
    @page = page
    @account = page.account
    @row = row || {}
    @insights = Array(insights)
    @period = period
  end

  def call # rubocop:disable Metrics/MethodLength
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Construtor de Páginas está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?

    message = client.messages.create(
      model: model,
      max_tokens: 4096,
      system_: cached_system(SYSTEM_PROMPT + OPERATIONAL_GUARDRAIL),
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: briefing }]
    )
    record_usage(message)
    parsed = parse_structured_response(message)
    return parsed if parsed[:error]

    { diagnostico: parsed['diagnostico'].to_s, sugestoes: Array(parsed['sugestoes']).first(5), generated_at: Time.current.iso8601 }
  rescue Anthropic::Errors::AuthenticationError
    { error: 'Chave da API inválida. Confira em CRM → Integrações → IA.' }
  rescue Anthropic::Errors::RateLimitError
    { error: 'Limite de uso da IA atingido. Tente novamente em instantes.' }
  rescue JSON::ParserError, TypeError
    { error: 'A IA devolveu um formato inesperado. Tente de novo.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::PageOptimizer] #{e.class}: #{e.message}"
    { error: 'Não consegui gerar as sugestões agora. Tente de novo em instantes.' }
  end

  private

  def briefing
    [
      "PÁGINA: #{@page.title} (/#{@page.slug}) — #{@page.status == 'published' ? 'publicada' : 'rascunho'}",
      "Título para o Google: #{@page.meta_title.presence || '(vazio)'}",
      "Descrição para o Google: #{@page.meta_description.presence || '(vazia)'}",
      "Palavras-chave: #{@page.seo_keywords.presence || '(nenhuma)'}",
      "Botão principal: #{@page.cta_label.presence || '(padrão)'}",
      '', "NÚMEROS (#{@period}):", numbers, '', 'DIAGNÓSTICOS AUTOMÁTICOS:', findings, '', 'TEXTOS DA PÁGINA:', page_text
    ].join("\n")
  end

  def numbers
    scroll = @row[:scroll].presence
    lines = ["#{@row[:views].to_i} visitas → #{@row[:cta].to_i} cliques no WhatsApp → #{@row[:leads].to_i} leads na caixa → " \
             "#{@row[:booked].to_i} agendaram → #{@row[:conversions].to_i} cirurgias"]
    lines << "Leitura: #{scroll.map { |mark, n| "#{mark}% da página = #{n}" }.join(' · ')}" if scroll
    (@row[:sources] || {}).each do |source, b|
      lines << "#{Cevico::TrafficSource::SOURCES[source] || source}: #{b[:views]} visitas, #{b[:cta]} cliques, #{b[:leads]} leads"
    end
    lines.join("\n")
  end

  def findings
    return '(nenhum — sem volume ou sem problema detectado)' if @insights.empty?

    @insights.map { |i| "- #{i[:title]}: #{i[:evidence]}" }.join("\n")
  end

  # os textos como o visitante lê: seções do construtor ou o HTML próprio sem as tags
  def page_text
    text = if @page.sections.present?
             @page.sections.map.with_index(1) { |section, i| "[Seção #{i}] #{section_text(section)}" }.join("\n")
           else
             ActionController::Base.helpers.strip_tags(@page.custom_html.presence || @page.body.to_s)
           end
    text.to_s.gsub(/[ \t]+/, ' ').gsub(/\n{3,}/, "\n\n").strip[0, MAX_PAGE_CHARS].presence || '(página sem texto)'
  end

  def section_text(section) # rubocop:disable Metrics/CyclomaticComplexity
    strings = []
    collect = lambda do |value|
      case value
      when String then strings << value.strip if value.length > 2 && !value.match?(%r{\A(#\h{3,8}|https?://|/)})
      when Array then value.each { |v| collect.call(v) }
      when Hash then value.each_value { |v| collect.call(v) }
      end
    end
    collect.call(section)
    strings.uniq.join(' | ')
  end
end
