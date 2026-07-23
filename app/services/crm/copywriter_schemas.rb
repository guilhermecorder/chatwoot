# Schemas de saída estruturada do Copywriter e do Construtor de Páginas
# (formato das páginas por seções do Construtor v2 e dos conteúdos de
# redes sociais do Estúdio).
module Crm::CopywriterSchemas
  SECTION_SCHEMA = {
    type: 'object',
    properties: {
      type: { type: 'string', enum: CevicoPage::SECTION_TYPES },
      effect: { type: 'string', enum: CevicoPage::SECTION_EFFECTS },
      title: { type: 'string', description: 'Título da seção (vazio quando não precisar)' },
      text: { type: 'string', description: 'Texto corrido da seção (parágrafos separados por linha em branco)' },
      color: { type: 'string',
               description: 'Cor de fundo suave da seção em hexadecimal #RRGGBB (use com parcimônia — 2-3 seções por página; string vazia = sem cor). Paleta da casa: #0F5FA6 azul, #D4AF37 dourado, #10B981 verde, #7C3AED roxo' },
      image_url: { type: 'string',
                   description: 'SOMENTE um caminho de imagem listado no contexto como disponível (começa com /rails/active_storage/) ou string vazia — NUNCA invente URL de imagem' },
      items: {
        type: 'array',
        description: 'Itens da seção (benefícios/passos/FAQ: title = item ou pergunta, text = explicação ou resposta)',
        items: {
          type: 'object',
          properties: { title: { type: 'string' }, text: { type: 'string' } },
          required: %w[title text],
          additionalProperties: false
        }
      }
    },
    required: %w[type effect title text color image_url items],
    additionalProperties: false
  }.freeze

  # conteúdo (carrossel/reels/post/anúncio): blocos = cards/cenas/variações
  CONTENT_SCHEMA = {
    type: 'object',
    properties: {
      titulo: { type: 'string', description: 'Título/gancho principal do conteúdo' },
      blocos: {
        type: 'array',
        description: 'Carrossel: um bloco por card (rotulo = "Card 1"...). Reels: um bloco por cena ' \
                     '(rotulo = "Cena 1 — 0-3s"...). Anúncio: um bloco por variação. Post: um bloco único com o texto.',
        items: {
          type: 'object',
          properties: { rotulo: { type: 'string' }, texto: { type: 'string' } },
          required: %w[rotulo texto],
          additionalProperties: false
        }
      },
      legenda: { type: 'string', description: 'Legenda pronta para publicar (vazio se não se aplicar)' },
      hashtags: { type: 'string', description: 'Hashtags sugeridas separadas por espaço (vazio se não se aplicar)' }
    },
    required: %w[titulo blocos legenda hashtags],
    additionalProperties: false
  }.freeze

  PAGE_SCHEMA = {
    type: 'object',
    properties: {
      title: { type: 'string', description: 'Título da página (H1)' },
      subtitle: { type: 'string', description: 'Subtítulo do hero, 1-2 frases' },
      emoji: { type: 'string', description: 'Um emoji que representa o assunto' },
      meta_title: { type: 'string', description: 'Título para o Google (até ~60 caracteres, com a cidade quando fizer sentido)' },
      meta_description: { type: 'string', description: 'Descrição para o Google (1-2 frases que convidam ao clique)' },
      cta_label: { type: 'string', description: 'Texto do botão de WhatsApp' },
      sections: { type: 'array', items: SECTION_SCHEMA, description: 'As seções da página, na ordem de leitura' }
    },
    required: %w[title subtitle emoji meta_title meta_description cta_label sections],
    additionalProperties: false
  }.freeze
end
