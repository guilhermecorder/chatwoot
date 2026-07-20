// Conteúdo do ambiente PESSOAS: diagnóstico DISC v2 (28 itens — escolha +
// escalas 0-10, mais dados), teste dos 4 TEMPERAMENTOS (24 perguntas
// equilibradas), Roda da Vida e a ficha estratégica de hábitos/crenças
// (técnicas de coaching e planejamento de vida). Correlação clássica:
// D=Colérico · I=Sanguíneo · S=Fleumático · C=Melancólico.

// ── DISC v2: 16 situações de escolha + 12 afirmações em escala 0-10 ──
export const DISC_QUESTIONS = [
  {
    q: 'Numa segunda-feira cheia de trabalho, eu…',
    options: [
      { dim: 'd', text: 'Ataco logo o problema mais difícil do dia' },
      { dim: 'i', text: 'Puxo a energia do time pra cima antes de tudo' },
      { dim: 's', text: 'Sigo minha rotina com calma, um passo de cada vez' },
      { dim: 'c', text: 'Organizo a lista e planejo a ordem certa das tarefas' },
    ],
  },
  {
    q: 'Quando aparece um problema novo e urgente…',
    options: [
      { dim: 'd', text: 'Decido rápido — errar corrigindo é melhor que parar' },
      { dim: 'i', text: 'Chamo alguém pra pensar junto conversando' },
      { dim: 's', text: 'Mantenho a calma e resolvo sem alarde' },
      { dim: 'c', text: 'Entendo a causa a fundo antes de agir' },
    ],
  },
  {
    q: 'No trabalho em equipe, meu papel natural é…',
    options: [
      { dim: 'd', text: 'Puxar a frente e cobrar o resultado' },
      { dim: 'i', text: 'Animar, conectar as pessoas e vender a ideia' },
      { dim: 's', text: 'Dar apoio constante e segurar a rotina' },
      { dim: 'c', text: 'Cuidar da qualidade e dos detalhes' },
    ],
  },
  {
    q: 'O que mais me incomoda no dia a dia é…',
    options: [
      { dim: 'd', text: 'Lentidão e falta de decisão' },
      { dim: 'i', text: 'Ambiente frio, sem conversa e sem reconhecimento' },
      { dim: 's', text: 'Mudança brusca sem aviso' },
      { dim: 'c', text: 'Trabalho malfeito e desorganizado' },
    ],
  },
  {
    q: 'Quando recebo uma meta desafiadora…',
    options: [
      { dim: 'd', text: 'Aceito o desafio na hora — gosto de vencer' },
      { dim: 'i', text: 'Empolgo o time: juntos a gente chega lá' },
      { dim: 's', text: 'Prefiro entender o caminho antes de acelerar' },
      { dim: 'c', text: 'Quebro a meta em etapas e crio um plano' },
    ],
  },
  {
    q: 'Sob pressão, eu costumo…',
    options: [
      { dim: 'd', text: 'Ficar mais duro e direto do que o normal' },
      { dim: 'i', text: 'Falar demais e me dispersar' },
      { dim: 's', text: 'Me fechar e evitar o conflito' },
      { dim: 'c', text: 'Ficar perfeccionista e crítico demais' },
    ],
  },
  {
    q: 'O elogio que mais gosto de receber é…',
    options: [
      { dim: 'd', text: '“Você resolve como ninguém”' },
      { dim: 'i', text: '“Você contagia todo mundo”' },
      { dim: 's', text: '“Com você a gente pode contar sempre”' },
      { dim: 'c', text: '“Seu trabalho é impecável”' },
    ],
  },
  {
    q: 'Numa conversa difícil com um paciente/cliente…',
    options: [
      { dim: 'd', text: 'Vou direto ao ponto e proponho a solução' },
      { dim: 'i', text: 'Quebro o gelo e conquisto a pessoa primeiro' },
      { dim: 's', text: 'Escuto com paciência até a pessoa desabafar' },
      { dim: 'c', text: 'Explico com dados e precisão o que aconteceu' },
    ],
  },
  {
    q: 'Meu ritmo natural de trabalho é…',
    options: [
      { dim: 'd', text: 'Rápido e intenso — gosto de volume' },
      { dim: 'i', text: 'Em ondas: quando empolga, rende muito' },
      { dim: 's', text: 'Constante: o mesmo bom ritmo o dia inteiro' },
      { dim: 'c', text: 'Cuidadoso: prefiro certo a rápido' },
    ],
  },
  {
    q: 'Nas decisões, eu me guio mais por…',
    options: [
      { dim: 'd', text: 'Resultado: o que traz retorno mais rápido' },
      { dim: 'i', text: 'Pessoas: o que anima e engaja o grupo' },
      { dim: 's', text: 'Harmonia: o que mantém todos bem' },
      { dim: 'c', text: 'Lógica: o que os dados mostram' },
    ],
  },
  {
    q: 'Mudanças no trabalho me deixam…',
    options: [
      { dim: 'd', text: 'Animado se me derem o comando delas' },
      { dim: 'i', text: 'Curioso — novidade é combustível' },
      { dim: 's', text: 'Desconfortável no início; preciso de tempo' },
      { dim: 'c', text: 'Questionador: quero entender o porquê' },
    ],
  },
  {
    q: 'No fim do dia, me sinto realizado quando…',
    options: [
      { dim: 'd', text: 'Bati a meta e superei alguém (nem que seja eu de ontem)' },
      { dim: 'i', text: 'Fiz conexões e o clima ficou leve' },
      { dim: 's', text: 'Entreguei tudo com tranquilidade, sem incêndios' },
      { dim: 'c', text: 'Entreguei um trabalho do qual me orgulho nos detalhes' },
    ],
  },
  {
    q: 'Quando alguém discorda de mim…',
    options: [
      { dim: 'd', text: 'Defendo meu ponto com firmeza — gosto do embate' },
      { dim: 'i', text: 'Tento conquistar a pessoa pro meu lado' },
      { dim: 's', text: 'Procuro o meio-termo que acomode os dois' },
      { dim: 'c', text: 'Trago fatos e deixo os dados decidirem' },
    ],
  },
  {
    q: 'Se o sistema/processo falha, minha primeira reação é…',
    options: [
      { dim: 'd', text: 'Resolver na marra e seguir — depois vemos o processo' },
      { dim: 'i', text: 'Avisar todo mundo e mobilizar ajuda' },
      { dim: 's', text: 'Seguir o plano B combinado, sem pânico' },
      { dim: 'c', text: 'Investigar a causa raiz pra nunca mais repetir' },
    ],
  },
  {
    q: 'Nas conversas em grupo, eu geralmente…',
    options: [
      { dim: 'd', text: 'Conduzo: trago pauta e fecho encaminhamentos' },
      { dim: 'i', text: 'Falo bastante e puxo os assuntos' },
      { dim: 's', text: 'Escuto mais do que falo' },
      { dim: 'c', text: 'Só falo quando tenho algo preciso a dizer' },
    ],
  },
  {
    q: 'O risco, pra mim, é…',
    options: [
      { dim: 'd', text: 'Parte do jogo — quem não arrisca não ganha' },
      { dim: 'i', text: 'Empolgante quando a ideia é boa' },
      { dim: 's', text: 'Algo a evitar — prefiro o caminho seguro' },
      { dim: 'c', text: 'Algo a calcular friamente antes' },
    ],
  },
];

// afirmações em escala (0 = nada a ver comigo · 10 = sou eu demais)
export const DISC_SCALES = [
  { dim: 'd', text: 'Assumo o comando naturalmente quando ninguém assume.' },
  { dim: 'd', text: 'Fico impaciente com reuniões longas e conversa em círculo.' },
  { dim: 'd', text: 'Competir me dá energia — até comigo mesmo.' },
  { dim: 'i', text: 'Faço amizade fácil, até na fila do café.' },
  { dim: 'i', text: 'Preciso de gente por perto pra render bem.' },
  { dim: 'i', text: 'Convencer alguém de uma ideia me dá prazer.' },
  { dim: 's', text: 'Prefiro rotina previsível a surpresa, mesmo boa.' },
  { dim: 's', text: 'As pessoas me procuram pra desabafar.' },
  { dim: 's', text: 'Termino o que começo, mesmo sem ninguém cobrando.' },
  { dim: 'c', text: 'Erro de detalhe me incomoda mais do que deveria.' },
  { dim: 'c', text: 'Prefiro dados a opiniões.' },
  { dim: 'c', text: 'Reviso mais de uma vez antes de entregar qualquer coisa.' },
];

// ── Teste dos 4 TEMPERAMENTOS (vida pessoal, não só trabalho) ──
// 24 perguntas EQUILIBRADAS: cada uma tem exatamente 1 opção por
// temperamento (Colérico=d · Sanguíneo=i · Fleumático=s · Melancólico=c),
// cobrindo os eixos clássicos — energia social, reação emocional, ritmo,
// relacionamentos, organização e vida interior.
export const TEMPERAMENT_QUESTIONS = [
  {
    q: 'Numa festa em que conheço pouca gente, eu…',
    options: [
      { dim: 'd', text: 'Vou direto falar com quem me interessa' },
      { dim: 'i', text: 'Em 10 minutos conheço metade da festa' },
      { dim: 's', text: 'Fico com quem já conheço, numa boa' },
      { dim: 'c', text: 'Observo bastante antes de me soltar' },
    ],
  },
  {
    q: 'Quando me irrito de verdade…',
    options: [
      { dim: 'd', text: 'Explodo na hora e passa rápido' },
      { dim: 'i', text: 'Desabafo falando com alguém' },
      { dim: 's', text: 'Engulo e fico quieto (às vezes demais)' },
      { dim: 'c', text: 'Guardo, remoo e lembro por muito tempo' },
    ],
  },
  {
    q: 'Meus fins de semana ideais…',
    options: [
      { dim: 'd', text: 'Atividade, desafio, movimento — parado eu enferrujo' },
      { dim: 'i', text: 'Gente, festa, novidade' },
      { dim: 's', text: 'Casa, família, paz e um bom sofá' },
      { dim: 'c', text: 'Um bom livro/filme e tempo pra mim' },
    ],
  },
  {
    q: 'Nos relacionamentos, sou mais…',
    options: [
      { dim: 'd', text: 'Protetor e resolutivo — cuido resolvendo' },
      { dim: 'i', text: 'Carinhoso e expressivo — falo e demonstro' },
      { dim: 's', text: 'Leal e constante — estou sempre lá' },
      { dim: 'c', text: 'Profundo e seletivo — poucos e verdadeiros' },
    ],
  },
  {
    q: 'Meu jeito com dinheiro…',
    options: [
      { dim: 'd', text: 'Invisto agressivo: dinheiro parado me incomoda' },
      { dim: 'i', text: 'Gasto com experiências — viver é agora' },
      { dim: 's', text: 'Guardo pra segurança da família' },
      { dim: 'c', text: 'Planilho tudo e decido friamente' },
    ],
  },
  {
    q: 'Quando erro feio…',
    options: [
      { dim: 'd', text: 'Assumo, corrijo e sigo — sem drama' },
      { dim: 'i', text: 'Peço desculpa com o coração e conto pra todo mundo' },
      { dim: 's', text: 'Fico mal por dentro, mas sigo em frente quieto' },
      { dim: 'c', text: 'Me cobro por dias — o erro fica ecoando' },
    ],
  },
  {
    q: 'A crítica que mais dói em mim é…',
    options: [
      { dim: 'd', text: '“Você é fraco/incompetente”' },
      { dim: 'i', text: '“Ninguém gosta de você”' },
      { dim: 's', text: '“Você decepcionou quem confiava”' },
      { dim: 'c', text: '“Seu trabalho está errado”' },
    ],
  },
  {
    q: 'Meu humor no dia a dia…',
    options: [
      { dim: 'd', text: 'Intenso: quando quero algo, o mundo percebe' },
      { dim: 'i', text: 'Pra cima: rio fácil e contagio' },
      { dim: 's', text: 'Estável: quase nada me tira do sério' },
      { dim: 'c', text: 'Varia com a qualidade do meu dia interior' },
    ],
  },
  {
    q: 'Na hora de decidir algo importante da vida…',
    options: [
      { dim: 'd', text: 'Decido rápido e ajusto no caminho' },
      { dim: 'i', text: 'Converso com todo mundo que amo' },
      { dim: 's', text: 'Deixo maturar com calma, sem pressa' },
      { dim: 'c', text: 'Faço listas de prós e contras (às vezes demais)' },
    ],
  },
  {
    q: 'O que me tira o sono…',
    options: [
      { dim: 'd', text: 'Sentir que estou perdendo/ficando pra trás' },
      { dim: 'i', text: 'Conflito com alguém que gosto' },
      { dim: 's', text: 'Mudanças grandes chegando' },
      { dim: 'c', text: 'Coisas malresolvidas e imperfeitas' },
    ],
  },
  {
    q: 'Meu superpoder emocional é…',
    options: [
      { dim: 'd', text: 'Coragem: encaro o que os outros evitam' },
      { dim: 'i', text: 'Alegria: levanto o astral de qualquer ambiente' },
      { dim: 's', text: 'Paz: acalmo as pessoas só de estar perto' },
      { dim: 'c', text: 'Profundidade: enxergo o que ninguém viu' },
    ],
  },
  {
    q: 'Minha sombra (o lado que preciso vigiar) é…',
    options: [
      { dim: 'd', text: 'Atropelar sentimentos pra chegar no objetivo' },
      { dim: 'i', text: 'Prometer demais e me perder na desordem' },
      { dim: 's', text: 'Aceitar tudo calado e acumular mágoa' },
      { dim: 'c', text: 'Pessimismo e crítica dura comigo e com os outros' },
    ],
  },
  {
    q: 'Numa fila ou espera longa, eu…',
    options: [
      { dim: 'd', text: 'Fico impaciente e procuro um jeito de acelerar' },
      { dim: 'i', text: 'Puxo papo com quem estiver do lado' },
      { dim: 's', text: 'Espero numa boa — pressa não me domina' },
      { dim: 'c', text: 'Uso o tempo pra pensar e observar tudo' },
    ],
  },
  {
    q: 'Com horários e compromissos…',
    options: [
      { dim: 'd', text: 'Agenda cheia: encaixo mais do que cabe' },
      { dim: 'i', text: 'Me atraso às vezes — me empolgo no caminho' },
      { dim: 's', text: 'Chego no horário, sem correria' },
      { dim: 'c', text: 'Chego antes — atrasar me angustia' },
    ],
  },
  {
    q: 'Minhas amizades são…',
    options: [
      { dim: 'd', text: 'Parcerias: gente que caminha e constrói junto' },
      { dim: 'i', text: 'Muitas! Faço amigo em qualquer lugar' },
      { dim: 's', text: 'Antigas e leais — amizade de anos' },
      { dim: 'c', text: 'Raras e profundas — poucos entram de verdade' },
    ],
  },
  {
    q: 'Quando alguém me magoa…',
    options: [
      { dim: 'd', text: 'Confronto na hora e depois viro a página' },
      { dim: 'i', text: 'Perdoo rápido — quase esqueço' },
      { dim: 's', text: 'Digo que está tudo bem (mesmo sem estar)' },
      { dim: 'c', text: 'Perdoo, mas não esqueço' },
    ],
  },
  {
    q: 'Meu espaço (quarto, mesa, carro) costuma ser…',
    options: [
      { dim: 'd', text: 'Funcional: o que importa é servir ao objetivo' },
      { dim: 'i', text: 'Uma bagunça criativa que só eu entendo' },
      { dim: 's', text: 'Confortável, do jeitinho de sempre' },
      { dim: 'c', text: 'Organizado: cada coisa no seu lugar' },
    ],
  },
  {
    q: 'De férias, meu estilo é…',
    options: [
      { dim: 'd', text: 'Roteiro intenso: aproveitar o máximo possível' },
      { dim: 'i', text: 'Conhecer gente nova e viver histórias' },
      { dim: 's', text: 'Descansar DE VERDADE, sem plano nenhum' },
      { dim: 'c', text: 'Viagem planejada nos detalhes, sem surpresa' },
    ],
  },
  {
    q: 'Diante de uma injustiça…',
    options: [
      { dim: 'd', text: 'Enfrento na hora, custe o que custar' },
      { dim: 'i', text: 'Falo, mobilizo, chamo atenção pro caso' },
      { dim: 's', text: 'Me abalo, mas evito virar briga' },
      { dim: 'c', text: 'Sofro por dentro e analiso de todos os lados' },
    ],
  },
  {
    q: 'Quando conto uma história…',
    options: [
      { dim: 'd', text: 'Resumo: começo, fim e o que importa' },
      { dim: 'i', text: 'Dramatizo, enfeito e faço rir' },
      { dim: 's', text: 'Conto com calma, se me perguntarem' },
      { dim: 'c', text: 'Detalho com precisão — do jeito que foi' },
    ],
  },
  {
    q: 'Minha energia recarrega quando…',
    options: [
      { dim: 'd', text: 'Estou vencendo um desafio' },
      { dim: 'i', text: 'Estou cercado de gente que amo' },
      { dim: 's', text: 'Estou em casa, em paz, sem cobrança' },
      { dim: 'c', text: 'Estou sozinho, no meu mundo' },
    ],
  },
  {
    q: 'Sobre sonhos e projetos pessoais…',
    options: [
      { dim: 'd', text: 'Meta ambiciosa com prazo — e vou com tudo' },
      { dim: 'i', text: 'Tenho mil ideias e começo várias ao mesmo tempo' },
      { dim: 's', text: 'Passos pequenos e seguros, sem me arriscar' },
      { dim: 'c', text: 'Só começo com o plano perfeito na cabeça' },
    ],
  },
  {
    q: 'Nas discussões em família…',
    options: [
      { dim: 'd', text: 'Quero resolver logo e seguir em frente' },
      { dim: 'i', text: 'Quero fazer as pazes rápido — não aguento clima ruim' },
      { dim: 's', text: 'Cedo pra ter paz, mesmo tendo razão' },
      { dim: 'c', text: 'Preciso entender quem errou e por quê' },
    ],
  },
  {
    q: 'O que eu mais valorizo em alguém…',
    options: [
      { dim: 'd', text: 'Coragem e palavra: fala e cumpre' },
      { dim: 'i', text: 'Alegria e presença: estar junto de verdade' },
      { dim: 's', text: 'Constância: quem fica nos dias difíceis' },
      { dim: 'c', text: 'Profundidade: conversa que vai além do raso' },
    ],
  },
];

export const DISC_PROFILES = {
  d: {
    letter: 'D',
    name: 'Dominância',
    temperament: 'Colérico',
    color: '#DC2626',
    grad: 'linear-gradient(135deg, #B91C1C, #F87171)',
    icon: 'i-lucide-flame',
    headline: 'Direto, decidido e movido a resultado.',
    strengths: ['Iniciativa e coragem pra decidir', 'Velocidade de execução', 'Foco total no resultado', 'Não foge de conversa difícil'],
    watchouts: ['Impaciência com ritmos diferentes', 'Pode atropelar pessoas no caminho', 'Delegar pouco ("eu faço mais rápido")'],
    communication: 'Seja direto e objetivo: comece pelo resultado, mostre o impacto e dê autonomia. Rodeios e reuniões longas o desligam.',
  },
  i: {
    letter: 'I',
    name: 'Influência',
    temperament: 'Sanguíneo',
    color: '#D97706',
    grad: 'linear-gradient(135deg, #D97706, #FBBF24)',
    icon: 'i-lucide-sun',
    headline: 'Comunicativo, entusiasmado e movido a pessoas.',
    strengths: ['Carisma que abre portas', 'Otimismo contagiante', 'Vende ideias com facilidade', 'Cria relacionamento rápido'],
    watchouts: ['Dispersão nos detalhes e prazos', 'Promete mais do que cabe na agenda', 'Precisa de reconhecimento constante'],
    communication: 'Comece pela pessoa, não pela tarefa. Reconheça em público, dê espaço pra falar e transforme metas em desafios divertidos.',
  },
  s: {
    letter: 'S',
    name: 'Estabilidade',
    temperament: 'Fleumático',
    color: '#047857',
    grad: 'linear-gradient(135deg, #047857, #34D399)',
    icon: 'i-lucide-anchor',
    headline: 'Calmo, leal e constante — o porto seguro do time.',
    strengths: ['Consistência dia após dia', 'Escuta de verdade', 'Paciência com gente e processo', 'Lealdade ao time'],
    watchouts: ['Resistência a mudanças bruscas', 'Dificuldade de dizer não', 'Evita conflito mesmo quando necessário'],
    communication: 'Dê segurança e contexto: explique o porquê da mudança com antecedência, pergunte a opinião em particular e valorize a constância.',
  },
  c: {
    letter: 'C',
    name: 'Conformidade',
    temperament: 'Melancólico',
    color: '#1D4ED8',
    grad: 'linear-gradient(135deg, #1E40AF, #60A5FA)',
    icon: 'i-lucide-ruler',
    headline: 'Analítico, preciso e movido a qualidade.',
    strengths: ['Precisão e atenção ao detalhe', 'Planejamento de verdade', 'Padrão alto de qualidade', 'Enxerga riscos antes de todos'],
    watchouts: ['Perfeccionismo que atrasa entregas', 'Crítica dura (consigo e com os outros)', 'Paralisia por análise'],
    communication: 'Traga dados, clareza e tempo: explique critérios, evite cobrança em cima da hora e reconheça a qualidade do trabalho — não só a velocidade.',
  },
};

// combinações fortes (dominante + secundário) — leitura de time
export const DISC_DUOS = {
  di: 'Executor carismático: decide rápido E leva o time junto — ótimo pra frentes novas.',
  id: 'Vendedor nato com garra: conquista a pessoa e fecha — ideal pro comercial.',
  ds: 'Líder firme e constante: cobra resultado sem perder a estabilidade.',
  sd: 'Força tranquila: segura a rotina e assume o comando quando precisa.',
  dc: 'Estrategista de execução: decide rápido com base em dados.',
  cd: 'Perfeccionista que entrega: qualidade alta com senso de urgência.',
  is: 'Coração do time: acolhe, anima e mantém todo mundo unido.',
  si: 'Anfitrião leal: atendimento caloroso e constante — pacientes amam.',
  ic: 'Comunicador preciso: explica o complexo de um jeito leve.',
  ci: 'Especialista didático: domina o detalhe e sabe apresentar.',
  sc: 'Guardião do processo: rotina impecável, zero drama.',
  cs: 'Qualidade em silêncio: entrega perfeita, todo santo dia.',
};

// ── Roda da Vida: 8 áreas coloridas (avaliação 0-10 + reflexão) ──
export const WHEEL_AREAS = [
  { key: 'carreira', label: 'Carreira', color: '#F59E0B', ask: 'Seu trabalho hoje te aproxima de quem você quer ser?' },
  { key: 'financeiro', label: 'Financeiro', color: '#EF4444', ask: 'Seu dinheiro trabalha pra você ou você só trabalha por ele?' },
  { key: 'espiritual', label: 'Espiritual', color: '#8B5CF6', ask: 'Sua fé/propósito tem espaço de verdade na sua semana?' },
  { key: 'fisico', label: 'Físico', color: '#F43F5E', ask: 'Seu corpo hoje sustenta os seus sonhos de amanhã?' },
  { key: 'intelectual', label: 'Intelectual', color: '#0EA5E9', ask: 'O que você aprendeu de novo nos últimos 30 dias?' },
  { key: 'familia', label: 'Família', color: '#10B981', ask: 'As pessoas que você ama SENTEM que são prioridade?' },
  { key: 'social', label: 'Social', color: '#3B82F6', ask: 'Suas amizades te elevam ou só te distraem?' },
  { key: 'emocional', label: 'Lazer & Emoções', color: '#14B8A6', ask: 'Você tem descansado de um jeito que renova?' },
];

// horizontes de objetivos (do sonho grande ao AGORA)
export const HORIZONS = [
  { key: 'h20', label: '20 anos' },
  { key: 'h10', label: '10 anos' },
  { key: 'h5', label: '5 anos' },
  { key: 'h3', label: '3 anos' },
  { key: 'h1', label: '1 ano' },
  { key: 'm3', label: '3 meses' },
  { key: 'm1', label: '1 mês' },
  { key: 'w1', label: '1 semana' },
  { key: 'd1', label: '1 dia' },
  { key: 'now', label: 'Agora' },
];

// ficha estratégica do hábito/crença (perguntas de ressignificação)
export const HABIT_QUESTIONS = [
  { key: 'learned_from', label: 'Com quem você aprendeu isso?' },
  { key: 'authority', label: 'Essa pessoa era uma autoridade no assunto? A forma de pensar dela nessa área merece ser levada a sério?' },
  { key: 'absurd', label: 'O que é um ABSURDO em relação a esse tema?' },
  { key: 'god_view', label: 'O que Deus pensa sobre isso?' },
  { key: 'replacement', label: 'Pelo que você vai trocar? (o novo hábito/crença)' },
];
export const HABIT_PRICES = [
  { key: 'price_physical', label: 'Preço físico' },
  { key: 'price_emotional', label: 'Preço emocional' },
  { key: 'price_financial', label: 'Preço financeiro' },
  { key: 'price_relational', label: 'Preço nos relacionamentos' },
];

export function computeDisc(answers) {
  const scores = { d: 0, i: 0, s: 0, c: 0 };
  answers.forEach(a => {
    if (typeof a === 'string' && scores[a] !== undefined) scores[a] += 10;
    else if (a && scores[a.dim] !== undefined) scores[a.dim] += Number(a.value) || 0;
  });
  return scores;
}

export function discPercentages(scores) {
  const total = Object.values(scores).reduce((a, b) => a + b, 0) || 1;
  const pct = {};
  Object.keys(scores).forEach(k => {
    pct[k] = Math.round((scores[k] / total) * 100);
  });
  return pct;
}

export function discRanking(scores) {
  return Object.keys(scores).sort((a, b) => scores[b] - scores[a]);
}
