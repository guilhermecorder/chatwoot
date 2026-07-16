# Agente COPYWRITER: escreve conteúdo em várias MODALIDADES — página por
# seções (Construtor v2), carrossel, roteiro de reels, post e anúncio —
# a partir de um briefing (e, quando escolhido, dos insights reais de um
# formulário). Aceita ESTRUTURAS validadas de copywriting (kishōtenketsu,
# storytelling, jornada do herói, notícia, P&R, diálogo) e as REFERÊNCIAS
# próprias do Guilherme salvas na config do agente.
class Crm::CopywriterService
  include Crm::AiAgentConfig

  AGENT_KEY = 'copywriter'.freeze

  MODALITIES = %w[pagina carrossel reels post anuncio].freeze

  # estruturas narrativas validadas ("como usar" vai pro prompt)
  STRUCTURES = {
    'auto' => 'Escolha você a melhor estrutura para o objetivo e o formato.',
    'kishotenketsu' => 'Kishōtenketsu (4 atos, sem conflito forçado): Ki = apresenta a cena/situação do paciente; ' \
                       'Shō = desenvolve e aprofunda; Ten = a VIRADA inesperada que muda a perspectiva; ' \
                       'Ketsu = conclusão que amarra tudo. Ótima para conteúdo que prende sem parecer venda.',
    'storytelling' => 'Storytelling clássico: personagem concreto (um paciente típico) + situação real + obstáculo + ' \
                      'transformação + moral que conecta com o leitor. Sensorial e específico, nada genérico.',
    'jornada_heroi' => 'Jornada do Herói (condensada): mundo comum (a vida com óculos/condição) → chamado (a possibilidade ' \
                       'de mudar) → medos e provações (objeções) → mentor (a clínica/médico) → transformação → retorno ' \
                       'com a visão nova. O PACIENTE é o herói; a CEVICO é o mentor.',
    'noticia' => 'Estrutura de notícia (pirâmide invertida): lead forte com a informação mais importante nas 2 primeiras ' \
                 'linhas, depois os detalhes em ordem decrescente de relevância, citações/dados no meio, serviço no final.',
    'perguntas_respostas' => 'Perguntas e Respostas: as dúvidas REAIS do público (use os insights quando houver), na ordem ' \
                             'da jornada de decisão, respostas curtas e francas — a última pergunta leva naturalmente ao CTA.',
    'dialogo' => 'Diálogo: conversa realista entre duas pessoas (ex.: paciente e amiga que já operou, ou paciente e médico) ' \
                 '— as objeções aparecem na fala de um e são resolvidas na resposta do outro. Natural, sem parecer roteiro ' \
                 'de propaganda.'
  }.freeze

  SECTION_SCHEMA = Crm::CopywriterSchemas::SECTION_SCHEMA
  CONTENT_SCHEMA = Crm::CopywriterSchemas::CONTENT_SCHEMA
  OUTPUT_SCHEMA = Crm::CopywriterSchemas::PAGE_SCHEMA

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o copywriter sênior da CEVICO — CUIDADOS OCULARES, clínica
    oftalmológica premium (azul marinho e dourado). Procedimentos e valores
    oficiais: Refrativa PRK/Lasik R$ 5.000 · Catarata (lente Nacional
    R$ 2.800 | Mono Rayner R$ 3.200 | Tórica monofocal R$ 5.600 | Foco
    estendido R$ 5.690 | Trifocal R$ 8.490 | Galaxy R$ 14.990) · Artisan
    R$ 11.900. Só cite valor se o briefing pedir.

    Sua missão: escrever PÁGINAS por seções que conectam com o paciente e
    o levam a chamar a clínica no WhatsApp.

    Técnicas obrigatórias:
    - Falar a língua do paciente (nada de jargão médico sem tradução).
    - Quebrar objeções (medo, preço, "será que funciona pra mim?") com
      empatia e prova, nunca com pressão.
    - Títulos curtos e concretos; parágrafos de 2-3 frases; uma ideia por
      seção; terminar guiando para o CTA.
    - SEO: usar naturalmente os termos que o público pesquisa (catarata,
      cirurgia refrativa, lasik, prk, lente intraocular...).
    - NUNCA prometer resultado garantido nem dar diagnóstico; a página
      informa e convida para a avaliação.

    Tipos de seção: hero (faixa de destaque — o TOPO da página já mostra
    título e subtítulo, então NUNCA comece com hero repetindo o título;
    use no meio, para uma virada de conversa), texto, beneficios (cards), passos
    (passo a passo), faq (perguntas frequentes), depoimento (use SOMENTE
    depoimentos fornecidos no briefing — nunca invente), visao
    (experiência interativa de como a pessoa enxerga antes/depois da
    correção — use quando o assunto envolver grau/miopia/astigmatismo/
    catarata) e cta (chamada final).
    Efeitos disponíveis por seção: nenhum, liquido, foco, movimento,
    miopia, astigmatismo, brilho. Use com parcimônia (2-3 seções com
    efeito por página); "miopia"/"astigmatismo" só em seções que falam da
    condição; "brilho" para o fechamento premium.

    Quando receber INSIGHTS DO PÚBLICO (dores/desejos/objeções reais de
    formulários), escreva a copy em cima deles — são ouro.
    Escreva em português do Brasil.
  PROMPT

  # opts: category / form / modality / structure
  def initialize(account:, briefing:, **opts)
    @account = account
    @briefing = briefing
    @category = opts[:category] || 'captacao'
    @form = opts[:form]
    @modality = MODALITIES.include?(opts[:modality]) ? opts[:modality] : 'pagina'
    @structure = STRUCTURES.key?(opts[:structure]) ? opts[:structure] : 'auto'
  end

  def call
    error = config_error
    return error if error

    schema = @modality == 'pagina' ? OUTPUT_SCHEMA : CONTENT_SCHEMA
    message = client.messages.create(
      model: model,
      max_tokens: 8192,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: schema }),
      messages: [{ role: 'user', content: build_briefing }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    JSON.parse(text)
  rescue Anthropic::Errors::APIError => e
    { error: "Erro na IA: #{e.message}" }
  rescue JSON::ParserError
    { error: 'A IA devolveu um formato inesperado. Tente de novo.' }
  end

  private

  def config_error
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Copywriter está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?
    return { error: 'Escreva um briefing para o copywriter.' } if @briefing.blank?

    nil
  end

  MODALITY_BRIEF = {
    'pagina' => 'Escreva uma PÁGINA por seções (formato estruturado combinado).',
    'carrossel' => 'Escreva um CARROSSEL para redes sociais: 6-10 cards, card 1 = gancho forte, um pensamento ' \
                   'por card, último card = CTA. Frases curtas (o card é lido em 2s).',
    'reels' => 'Escreva um ROTEIRO DE REELS (30-60s): cena a cena com marcação de tempo, fala do apresentador + ' \
               'sugestão do que aparece na tela; os 3 primeiros segundos seguram a pessoa.',
    'post' => 'Escreva um POST/DESCRIÇÃO para redes sociais: gancho na primeira linha, corpo escaneável, CTA no fim.',
    'anuncio' => 'Escreva um ANÚNCIO (Meta/Google): 3 variações — cada bloco com headline (rotulo) e texto ' \
                 'principal + CTA. Direto, específico, sem promessa de resultado médico.'
  }.freeze

  def build_briefing
    parts = []
    parts << "FORMATO PEDIDO: #{MODALITY_BRIEF[@modality]}"
    parts << "ESTRUTURA NARRATIVA: #{STRUCTURES[@structure]}"
    parts << "ETAPA DA JORNADA: #{CevicoPage::CATEGORIES[@category] || @category}" if @modality == 'pagina'
    parts << "BRIEFING:\n#{@briefing}"
    parts << references_block if references_block
    parts << insights_block if insights_block
    parts.join("\n\n")
  end

  def references_block
    refs = agent_config['references'].to_s.strip
    return nil if refs.blank?

    "REFERÊNCIAS E ESTRUTURAS DA CASA (siga o estilo delas):\n#{refs}"
  end

  def insights_block
    insight = @form&.ai_insight
    return nil if insight.blank?

    <<~BLOCK
      INSIGHTS DO PÚBLICO (respostas reais do formulário "#{@form.name}"):
      Resumo: #{insight['resumo']}
      Dores: #{Array(insight['dores']).join(' · ')}
      Desejos: #{Array(insight['desejos']).join(' · ')}
      Objeções: #{Array(insight['objecoes']).join(' · ')}
    BLOCK
  end
end
