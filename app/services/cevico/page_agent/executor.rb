# 🖐️ O "fazer" das recomendações de PÁGINA (item 353) é sempre à mão — a IA
# construtora aplica no ambiente de montagem e a pessoa confere — por isso o
# executor só devolve o passo a passo; "Fiz à mão" é o que liga o antes × depois.
module Cevico::PageAgent::Executor
  module_function

  LABELS = {
    'cta_baixo' => 'Muita visita, pouco clique', 'leitura_curta' => 'Saem antes da metade', 'le_e_nao_clica' => 'Leem e não clicam',
    'protocolo_perdido' => 'Clicam e não chegam na caixa', 'lead_nao_agenda' => 'Lead não agenda', 'anuncio_sem_retorno' => 'Visita paga sem lead',
    'origem_destaque' => 'Origem que converte mais', 'sem_visita' => 'Publicada e sem visita', 'campea' => 'Página campeã',
    'seo_titulo' => 'Título do Google', 'seo_descricao' => 'Descrição do Google', 'seo_palavras' => 'Palavras-chave',
    'seo_sem_organico' => 'Sem Google orgânico', 'gsc_ctr_baixo' => 'Aparece e não clicam', 'gsc_quase_topo' => 'Quase na 1ª página',
    'gsc_termo_sem_pagina' => 'Termo sem página'
  }.freeze
  BUILDER = ['Abrir a montagem da página (botão "Abrir a montagem") e colar o pedido no chat do Construtor.',
             'Conferir a página, republicar e marcar "Fiz à mão" para o antes × depois começar a contar.'].freeze

  def steps_for(action) # rubocop:disable Metrics/MethodLength
    case action.kind
    when 'seo'
      ['Abrir Marketing → Páginas → a página → SEO (título, descrição e palavras-chave).', "Aplicar: #{action.suggestion}",
       'Republicar e marcar "Fiz à mão" — o Google leva de 1 a 3 semanas para mostrar o novo texto.']
    when 'content'
      if action.level == 'termo'
        ['Criar a página nova no Construtor (Marketing → Páginas → Nova) com o termo no título.',
         'Publicar, apontar o botão para a página de venda e marcar "Fiz à mão".']
      else
        [BUILDER[0], "Pedido: #{action.suggestion}", BUILDER[1]]
      end
    when 'quality'
      ['Ler as conversas dos leads desta página (Conversas → filtro por origem).', 'Alinhar a promessa da página com o Roteiro do atendimento.',
       'Marcar "Fiz à mão".']
    when 'traffic'
      ['Rever de onde a visita vem: anúncio, palavras-chave e público apontados para esta página.', "O que fazer: #{action.suggestion}",
       'Marcar "Fiz à mão" quando ajustar.']
    when 'watch'
      ['Só acompanhar: use a estrutura desta página como modelo nas outras.']
    else
      [BUILDER[0], "Pedido: #{action.suggestion}", BUILDER[1]]
    end
  end
end
