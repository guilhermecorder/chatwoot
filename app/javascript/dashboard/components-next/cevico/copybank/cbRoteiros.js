// ✍️ 18/11/2026 (Guilherme: "quero ter a liberdade e quero ter a referência"):
// os MODELOS DE ROTEIRO da aba Escrever. Cada modelo é uma lista de partes
// na ordem, com o que a parte faz e uma frase-molde com [lacunas]. Servem de
// duas formas: como campos para preencher ("Com modelo") ou só como
// referência ao lado do texto livre.
//
// Modelo novo que der certo entra aqui (e em TRACKING/modelos, fora do
// sistema). `exemplo` só aparece na clínica: é fala real de um vídeo da casa.

export const MODELOS = [
  {
    key: 'explosivo',
    nome: 'Roteiro explosivo',
    sub: '5 blocos · vídeo de 40 a 75 s',
    icon: 'i-lucide-flame',
    color: '#ea580c',
    origem: 'Do seu PDF "Roteiro explosivo"',
    partes: [
      {
        key: 'titulo',
        nome: 'Título com gatilho',
        tempo: '0–3 s',
        faz: 'Faz a pessoa parar. Número, promessa de lista e, logo na primeira frase, para quem é.',
        molde:
          'Se você [situação do público], essas [número] coisas vão acontecer com você.',
        dica: 'Na tela, o título escrito. No som, a frase dita com energia.',
        linhas: 2,
      },
      {
        key: 'misterio',
        nome: 'Intensificador do mistério',
        tempo: '3–6 s',
        faz: 'Segura até o fim: avisa que o item mais forte está no final.',
        molde: 'E a última [consequência forte].',
        linhas: 2,
      },
      {
        key: 'posicionamento',
        nome: 'Posicionamento',
        tempo: '6–12 s',
        faz: 'Dá o motivo para seguir esta pessoa: nome, credencial e a promessa do perfil.',
        molde:
          'Eu sou [nome], [credencial], e estou aqui pra te ajudar a [desejo do público] sem [objeção]. Então já dá o like e me segue pra mais dicas.',
        linhas: 3,
      },
      {
        key: 'conteudo',
        nome: 'Conteúdo notável',
        tempo: '12–55 s',
        faz: 'Entrega o que o título prometeu, em lista numerada. Cada item tem o fato, por que importa e uma imagem do dia a dia. O mais forte fica por último e é anunciado.',
        molde:
          'A primeira é [fato]. Isso importa porque [motivo]. É como [imagem do dia a dia].\nA segunda é [fato]…\nE a última, que na minha opinião é a mais [forte], é [fato].',
        linhas: 9,
      },
      {
        key: 'chamado',
        nome: 'Chamado',
        tempo: '55–70 s',
        faz: 'Transforma atenção em seguidor e alcance, com dois pedidos.',
        molde:
          'Então eu te peço duas coisas. A primeira é seguir esse perfil, pois no próximo vídeo eu vou [promessa]. A outra é compartilhar esse vídeo com quem [situação], pois [benefício para a pessoa].',
        linhas: 4,
      },
    ],
  },
  {
    key: 'especialista',
    nome: 'Especialista explica',
    sub: '10 partes · vídeo de uns 2 min',
    icon: 'i-lucide-user-round-check',
    color: '#2563eb',
    origem: 'Mapeado do vídeo "Livre dos óculos" (nov/2026)',
    partes: [
      {
        key: 'gancho',
        nome: 'Gancho',
        tempo: '0–7 s',
        faz: 'Promessa com contradição: uns não podem uma coisa, mas mesmo assim chegam ao resultado.',
        molde:
          'Descubra por que algumas pessoas não podem [X], mas mesmo assim podem [resultado desejado].',
        exemplo:
          'Descubra por que algumas pessoas não podem fazer a cirurgia refrativa, mas mesmo assim podem ficar livres dos óculos.',
        dica: 'É a parte que muda no teste: mesma fala, 5 a 7 aberturas visuais.',
        linhas: 2,
      },
      {
        key: 'autoridade',
        nome: 'Autoridade',
        tempo: '7–15 s',
        faz: 'Quem fala, com nome e registro.',
        molde:
          'Eu sou [nome], [profissão], e estou aqui para te ajudar a entender [assunto].',
        exemplo:
          'Eu sou o Doutor Henrique Gemelli, cirurgião oftalmologista, e estou aqui para te ajudar a entender quais são as cirurgias que corrigem o grau da visão.',
        linhas: 2,
      },
      {
        key: 'objetivo',
        nome: 'Objetivo',
        tempo: '15–20 s',
        faz: 'O compromisso de quem fala.',
        molde: 'Meu objetivo é [resultado] sem [o medo do público].',
        exemplo:
          'Meu objetivo é devolver a sua independência dos óculos sem arriscar a sua saúde.',
        linhas: 2,
      },
      {
        key: 'micro',
        nome: 'Curtir e seguir',
        tempo: '20–23 s',
        faz: 'Um pedido pequeno, cedo.',
        molde:
          'Então já curte esse vídeo e segue o perfil para entender melhor.',
        linhas: 1,
      },
      {
        key: 'contexto',
        nome: 'Contexto novo',
        tempo: '23–39 s',
        faz: 'Mostra que existe uma saída que a pessoa não conhecia.',
        molde:
          'Com a evolução de [área], surgiram outras formas de [resultado]. Por isso hoje a maioria das pessoas pode [resultado].',
        exemplo:
          'Com a evolução da tecnologia, surgiram outros tipos de cirurgia além da cirurgia refrativa. Por isso hoje em dia a grande maioria das pessoas pode ficar livre dos óculos.',
        linhas: 3,
      },
      {
        key: 'lista',
        nome: 'Lista dos 3',
        tempo: '39–58 s',
        faz: 'Quem não pode: três características. É onde a pessoa se reconhece.',
        molde:
          '[X] não é indicado para quem tem uma destas três características. 1. [característica]. 2. [característica]. 3. [característica].',
        exemplo:
          'A cirurgia refrativa não é segura nem eficaz para pessoas com uma dessas três características. 1. Ter idade acima dos 55 anos. 2. Ter grau muito alto. 3. Ter problema na córnea.',
        linhas: 4,
      },
      {
        key: 'virada',
        nome: 'Virada',
        tempo: '58–64 s',
        faz: 'A boa notícia.',
        molde:
          'A boa notícia é que existem outras [soluções] que também resolvem.',
        exemplo:
          'A boa notícia é que ainda existem outras tecnologias cirúrgicas que também podem resolver o problema.',
        linhas: 2,
      },
      {
        key: 'solucoes',
        nome: 'As soluções',
        tempo: '64–104 s',
        faz: 'Duas soluções, cada uma com uma imagem que mostra como é. Fecha dizendo que o resultado é possível.',
        molde:
          'A primeira é [solução 1]: [como funciona, em uma frase]. É uma excelente opção para quem [perfil].\nA segunda é [solução 2]: [como funciona]. Ou seja, [resultado] é totalmente possível.',
        linhas: 6,
      },
      {
        key: 'reforco',
        nome: 'Reforço',
        tempo: '104–110 s',
        faz: 'Repete o objetivo antes de pedir.',
        molde: 'Como eu falei antes, meu grande objetivo é [resultado].',
        linhas: 2,
      },
      {
        key: 'chamada',
        nome: 'Chamada dupla',
        tempo: '110–138 s',
        faz: 'Primeiro compartilhar; depois o passo pelo WhatsApp.',
        molde:
          'Por isso eu te peço duas coisas. A primeira é compartilhar esse vídeo com quem tem [característica]. A outra, se você já tem interesse: o primeiro passo é [ação] pelo WhatsApp.',
        linhas: 4,
      },
    ],
  },
  {
    key: 'gho',
    nome: 'Gancho, história, oferta',
    sub: '3 partes · anúncio ou post',
    icon: 'i-lucide-anchor',
    color: '#7c3aed',
    origem: 'O padrão da aba Criar, sem os passos',
    partes: [
      {
        key: 'gancho',
        nome: 'Gancho',
        tempo: 'abertura',
        faz: 'A primeira frase: faz a pessoa parar de rolar.',
        molde:
          '[Uma frase que fala com quem é o público e abre uma curiosidade.]',
        linhas: 2,
      },
      {
        key: 'historia',
        nome: 'História',
        tempo: 'corpo',
        faz: 'O corpo: o problema, a virada e a prova, numa linha só de raciocínio.',
        molde:
          '[O que a pessoa vive hoje.] [O que muda.] [Por que dá para acreditar.]',
        linhas: 8,
      },
      {
        key: 'oferta',
        nome: 'Oferta',
        tempo: 'fim',
        faz: 'O pedido: um passo pequeno e claro.',
        molde: '[O que fazer agora] pelo WhatsApp.',
        linhas: 2,
      },
    ],
  },
];

export const MODELO = Object.fromEntries(MODELOS.map(m => [m.key, m]));

// fala em vídeo: perto de 150 palavras por minuto
export const PALAVRAS_POR_SEGUNDO = 2.5;
export const contarPalavras = texto =>
  String(texto || '')
    .trim()
    .split(/\s+/)
    .filter(Boolean).length;

// 📚 a Biblioteca do negócio (pesquisas e materiais), por empresa
export const bibliotecaDe = empresa => {
  const nome = String(empresa?.nome || '').toLowerCase();
  const ramo = String(empresa?.ramo || '').toLowerCase();
  let pasta = '';
  if (nome.includes('life')) pasta = 'life';
  else if (ramo.includes('tica') || nome.includes('tica')) pasta = 'otica';
  else if (empresa?.clinica !== false) pasta = 'cevico';
  return pasta ? `https://guilhermecorder.com.br/biblioteca/${pasta}/` : '';
};
