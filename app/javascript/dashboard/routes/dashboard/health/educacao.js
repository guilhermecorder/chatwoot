// EDUCAÇÃO DO PROGRAMA (rodada 36) — pedido dele 28/09: "um ambiente de
// educação com as principais informações e as principais dúvidas sobre
// todos os pilares do programa; fácil de entender os princípios e
// fundamentos, como funcionam as alimentações, o objetivo, a metodologia
// de 24 semanas".
//
// FONTES: planilha Warrior_Shredding_24_Semanas_Ciclos_Separados.xlsx
// (ciclos, fichas, métodos, descansos, progressões), o seed da dieta
// (db/seeds/hub_warrior.rb: 12 kcal/lb, 0,8 g/lb, jejum 4–6 h, refeed,
// growth phase) e os princípios gerais do método, escritos em palavras
// próprias. Não é texto do material original. Tudo aqui é conteúdo
// estático e editável — cada pilar tem: resumo (em 1 minuto), números,
// princípios (cards), dúvidas (acordeão) e atalhos pras telas do HUB.

export const PILLARS = [
  // ═══════════════════════════════════════════════════════════════════
  {
    key: 'programa',
    ico: 'i-lucide-compass',
    label: 'O programa',
    sub: 'objetivo, pra quem é e o que esperar',
    resumo: [
      'O Warrior Shredding é um programa de 24 semanas pra perder gordura MANTENDO (ou ganhando) força e músculo. O resultado buscado é um físico enxuto, forte e proporcional — não só "pesar menos".',
      'Ele se apoia em três pilares que trabalham juntos: treino de força curto e pesado 3 vezes por semana, alimentação com jejum e déficit calórico moderado, e um estilo de vida que sustenta os dois (sono, caminhada, rotina).',
      'A regra de ouro: fazer o básico bem feito por muito tempo. Cargas subindo devagar, calorias sob controle, semana após semana — é a constância que muda o corpo, não a intensidade de um dia.',
    ],
    numeros: [
      { l: 'Duração', v: '24 semanas', s: '3 ciclos de 8 semanas', ico: 'i-lucide-calendar-range' },
      { l: 'Treinos', v: '3 por semana', s: 'seg · qua · sex, 45–60 min', ico: 'i-lucide-dumbbell' },
      { l: 'Perda esperada', v: '0,5–1% do peso', s: 'por semana, sem perder força', ico: 'i-lucide-trending-down' },
    ],
    principios: [
      { ico: 'i-lucide-target', t: 'Objetivo: definir, não só emagrecer', d: 'Perder gordura enquanto a força sobe. Se as cargas continuam subindo e a cintura diminui, o programa está funcionando — mesmo que a balança oscile.' },
      { ico: 'i-lucide-layers', t: 'Três pilares, um sistema', d: 'Treino (estímulo pra manter/ganhar músculo), alimentação (déficit pra queimar gordura) e estilo de vida (sono, passos, rotina). Tirar um deles enfraquece os outros dois.' },
      { ico: 'i-lucide-scale', t: 'Força é o termômetro', d: 'Num déficit calórico, o sinal de que você não está perdendo músculo é a força se mantendo ou subindo. Por isso cada treino tem uma meta clara de carga e repetições.' },
      { ico: 'i-lucide-hourglass', t: 'Menos é mais', d: 'Poucos exercícios, poucas séries, muito descanso entre elas e carga pesada. Sessões curtas que você consegue repetir por meses, sem esgotar o corpo em déficit.' },
      { ico: 'i-lucide-users', t: 'Pra quem é', d: 'Pra quem já treina há algum tempo e quer secar sem virar "magro sem forma". Iniciante absoluto também pode, mas as primeiras semanas servem pra aprender os movimentos e achar as cargas.' },
      { ico: 'i-lucide-heart', t: 'Pra vida toda', d: 'Depois das 24 semanas o método continua: alterna fases de definição e fases de ganho (Growth Phase), sempre com o mesmo estilo de treino e alimentação.' },
    ],
    faq: [
      { q: 'Qual é o objetivo real do programa?', a: 'Chegar a um percentual de gordura baixo (em torno de 8–12% pra homens) preservando a massa muscular e a força. O foco é a composição corporal — peso na balança é só um dos indicadores.' },
      { q: 'Quanto tempo até ver resultado?', a: 'Cintura e roupas costumam mudar nas primeiras 3–4 semanas. O corpo "seco" aparece mais claramente entre as semanas 8 e 16. As 24 semanas completas foram desenhadas pra transformar um físico médio em um físico definido.' },
      { q: 'Preciso seguir os três pilares?', a: 'Sim. Treinar sem controlar comida não seca; comer pouco sem treinar pesado perde músculo junto; os dois sem dormir e sem se mover no dia a dia travam. O programa é o conjunto.' },
      { q: 'E se eu já for magro e quiser ganhar?', a: 'Aí a fase certa é a Growth Phase (calorias acima da manutenção, ~15 kcal por libra de peso). O treino é o mesmo; muda só a comida. Ver o pilar Alimentação.' },
      { q: 'Posso treinar mais que 3 vezes por semana?', a: 'Não com pesos. O programa funciona porque cada treino é pesado e o corpo se recupera nos dias entre eles. Nos outros dias, caminhada, boxe leve ou mobilidade. Ver o pilar Cardio e movimento.' },
    ],
    hub: [
      { label: 'Meu Painel', route: 'hub_health_painel', ico: 'i-lucide-gauge' },
      { label: 'Treino', route: 'hub_health', ico: 'i-lucide-dumbbell' },
      { label: 'Dieta', route: 'hub_health_dieta', ico: 'i-lucide-utensils' },
    ],
  },

  // ═══════════════════════════════════════════════════════════════════
  {
    key: 'metodo',
    ico: 'i-lucide-route',
    label: 'As 24 semanas',
    sub: '3 ciclos de 8 semanas · treinos A, B e C',
    resumo: [
      'O programa principal é dividido em 3 ciclos independentes de 8 semanas: Ciclo 1 (Base), Ciclo 2 (ênfase em peitoral) e Ciclo 3 (ênfase em ombros). Cada ciclo tem três treinos — A, B e C — feitos na segunda, quarta e sexta.',
      'Dentro de um ciclo os exercícios não mudam: você repete os mesmos movimentos por 8 semanas pra conseguir progredir de carga neles. Mudar exercício toda semana impede de medir progresso.',
      'Existe ainda a Rotina Bônus (Strength & Fullness), um bloco alternativo de 8 semanas com mais volume, pra ser alternado com a rotina principal depois de um ciclo — ela não substitui o programa.',
    ],
    numeros: [
      { l: 'Ciclo 1', v: 'Semanas 1–8', s: 'Fase 1 — Base', ico: 'i-lucide-flag' },
      { l: 'Ciclo 2', v: 'Semanas 9–16', s: 'Fase 2 — Peitoral', ico: 'i-lucide-flag' },
      { l: 'Ciclo 3', v: 'Semanas 17–24', s: 'Fase 3 — Ombros', ico: 'i-lucide-flag' },
    ],
    principios: [
      { ico: 'i-lucide-repeat', t: 'Mesmos exercícios por 8 semanas', d: 'Repetição é o que permite comparar hoje com a semana passada e subir a carga. Só troque um exercício se houver dor ou falta de equipamento — e aí mantenha o substituto até o fim do ciclo.' },
      { ico: 'i-lucide-calendar-check', t: 'A · B · C em dias fixos', d: 'Treino A na segunda (peito e braços), B na quarta (pernas e abdômen), C na sexta (ombros, costas e tríceps). Um dia de descanso entre cada um. Se perder um dia, faça o próximo treino da sequência no próximo dia livre — não pule o treino.' },
      { ico: 'i-lucide-list-ordered', t: 'Cada ciclo muda a ênfase', d: 'Ciclo 1 constrói a base de força nos movimentos principais. Ciclo 2 troca alguns movimentos pra dar mais trabalho ao peitoral. Ciclo 3 prioriza ombros e traz agachamento frontal e desenvolvimento sentado.' },
      { ico: 'i-lucide-shuffle', t: 'Rotina Bônus: quando usar', d: 'Depois de fechar um ciclo de 8 semanas, é possível fazer 8 semanas da Rotina Bônus (peitoral superior e ombros, pirâmides e mais volume) e voltar. É opcional e serve pra variar o estímulo, não pra encurtar o programa.' },
      { ico: 'i-lucide-pencil-ruler', t: 'Semana 1 é calibração', d: 'Nos primeiros treinos você ainda não sabe a carga certa. Comece conservador, anote tudo, e use a segunda semana pra ajustar. O motor do HUB já sugere o próximo alvo a partir do que você fez.' },
      { ico: 'i-lucide-flag-triangle-right', t: 'Ao terminar as 24 semanas', d: 'Reavalie medidas e fotos. Se ainda há gordura a perder, mais um ciclo de definição; se chegou onde queria, entre em Growth Phase pra ganhar músculo por 8–12 semanas.' },
    ],
    faq: [
      { q: 'Por que 8 semanas por ciclo?', a: 'É o tempo em que dá pra progredir de carga de forma consistente antes do corpo se adaptar ao mesmo estímulo. Menos que isso não dá pra medir progresso; mais que isso o ganho desacelera.' },
      { q: 'Perdi um treino da semana. E agora?', a: 'Faça o treino perdido no próximo dia disponível e continue a sequência A → B → C. A semana pode "escorregar" um pouco; o que não pode é pular um treino inteiro.' },
      { q: 'Posso mudar a ordem dos treinos?', a: 'A ordem A → B → C existe pra distribuir os grupos musculares com descanso entre eles. Trocar o dia da semana é tranquilo; trocar a ordem (ex.: fazer C antes de B) evita-se, mas é melhor do que não treinar.' },
      { q: 'Como sei em que semana estou?', a: 'O HUB conta a partir da data de início configurada no programa (aba Treino). Meu Painel mostra "Semana N de 8 · Ciclo X" e qual treino é o próximo; o mapa acima marca a semana em laranja.' },
      { q: 'Quando entra a Rotina Bônus?', a: 'Só depois de um ciclo completo de 8 semanas, e por 8 semanas. Não é obrigatória — muita gente faz os 3 ciclos direto e usa a Bônus depois das 24 semanas.' },
      { q: 'E se eu viajar por uma semana?', a: 'Retome de onde parou; o ciclo simplesmente fica uma semana mais longo. Não tente "compensar" com treinos extras — o corpo não recupera duas cargas pesadas em dias seguidos.' },
    ],
    hub: [
      { label: 'Treino da semana', route: 'hub_health', ico: 'i-lucide-dumbbell' },
      { label: 'Rotina', route: 'hub_health_rotina', ico: 'i-lucide-calendar-range' },
    ],
  },

  // ═══════════════════════════════════════════════════════════════════
  {
    key: 'treino',
    ico: 'i-lucide-dumbbell',
    label: 'Treino',
    sub: 'métodos, aquecimento, descanso e progressão',
    resumo: [
      'O treino é curto e pesado: 4 ou 5 exercícios por sessão, com poucas séries e descansos longos. O método principal é o RPT (Pirâmide Reversa): a primeira série é a mais pesada, e a carga cai cerca de 10% a cada série seguinte.',
      'Exercícios menores (elevação lateral, crucifixo inverso) usam Rest-Pause: uma série de ativação seguida de 3 mini-séries com a mesma carga e pausas de 10–20 segundos. Na Rotina Bônus entra a Pirâmide padrão (12/10/8/6 com a mesma carga).',
      'Progredir é a única meta de cada treino: quando você bate o topo da faixa de repetições em todas as séries, sobe a carga no próximo treino. O HUB acompanha isso série por série e diz o alvo do dia.',
    ],
    numeros: [
      { l: 'Descanso RPT', v: '3 min', s: 'nos principais · 2 min nos menores', ico: 'i-lucide-timer' },
      { l: 'Queda por série', v: '−10%', s: 'da carga, série a série', ico: 'i-lucide-arrow-down-right' },
      { l: 'Salto de carga', v: '+2,3 kg', s: 'ao bater o topo das faixas', ico: 'i-lucide-arrow-up-right' },
    ],
    principios: [
      { ico: 'i-lucide-triangle', t: 'RPT — Pirâmide Reversa', d: 'Você faz a série mais pesada primeiro, quando está descansado e forte. Depois tira ~10% da carga e faz 1–2 repetições a mais. Exemplo: 80 kg × 6, 72 kg × 7, 65 kg × 8. Cada série vai até 1 repetição antes da falha.' },
      { ico: 'i-lucide-pause', t: 'Rest-Pause', d: 'Série de ativação (12–15 reps), pausa de 10–20 s, mini-série de 4–6 reps com a MESMA carga, e repete por 3 minis. Ótimo pra ombros e costas superiores com pouco tempo. Sobe a carga quando fechar 15 + 6/6/6.' },
      { ico: 'i-lucide-align-vertical-justify-end', t: 'Pirâmide padrão (Bônus)', d: 'Quatro séries de 12, 10, 8 e 6 reps com a MESMA carga, descansando 30–60 s. A progressão é de descanso: reduza de 60 até 30 s; quando chegar em 30 s, suba a carga e volte a 60 s.' },
      { ico: 'i-lucide-flame', t: 'Aquecimento inteligente', d: 'Só no primeiro exercício pesado do dia: 2–3 séries leves subindo a carga (ex.: 6 leve, 4 médio, 2 quase pesado). Nos exercícios seguintes você já está aquecido. Aquecer demais rouba força da série principal.' },
      { ico: 'i-lucide-timer', t: 'Descansar é parte do treino', d: 'Nos compostos pesados (supino, desenvolvimento, barra fixa, agachamento) descanse 3 minutos entre séries; nos menores, 2. Descanso curto = menos carga = menos estímulo. Use o cronômetro da sessão.' },
      { ico: 'i-lucide-trending-up', t: 'Regra de progressão', d: 'Bateu o topo da faixa em TODAS as séries (ex.: 6/7/8)? No próximo treino suba ~2,3 kg (5 lb) na barra ou por halter. Não bateu? Repita a carga e tente mais 1 rep onde faltou. Na barra fixa, +1,1 kg por treino se cumpriu 6/6.' },
      { ico: 'i-lucide-git-branch', t: 'Independent Set Loading (Bônus)', d: 'Nas séries exatas 5/6/8 da Rotina Bônus, cada série progride sozinha: suba primeiro a 3ª, depois a 2ª, por último a 1ª. Assim a carga sobe sem travar por causa da série mais pesada.' },
      { ico: 'i-lucide-shield-alert', t: 'Técnica antes de carga', d: 'Rep válida é amplitude completa e controle na descida. Se precisou trapacear pra fechar a série, a carga não subiu de verdade — anote a rep real. Dor articular = troca de exercício, não de ego.' },
    ],
    faq: [
      { q: 'Como escolho a carga da primeira série?', a: 'Um peso com que você consiga o mínimo da faixa (ex.: 6 reps em 5–6) com esforço alto, guardando 1 rep. Se fez mais que o máximo, a carga estava leve: suba no próximo treino. Nas primeiras semanas isso é normal.' },
      { q: 'O que fazer se não consigo subir a carga há 3 treinos?', a: 'Primeiro confira sono, comida e descanso entre séries. Depois tente subir só a última série (independent set) ou trocar o salto de 2,3 kg por 1 kg. Se o platô continua em vários exercícios, é sinal de déficit calórico grande demais ou falta de sono.' },
      { q: 'Vou até a falha?', a: 'Não. Cada série termina 1 repetição antes da falha (tecnicamente ainda faria mais uma com boa forma). Ir até a falha em déficit calórico esgota sem trazer ganho extra e atrapalha o treino seguinte.' },
      { q: 'Posso adicionar exercícios?', a: 'O programa é enxuto de propósito. Se quiser, um exercício extra leve de abdômen ou panturrilha no fim está ok. Adicionar mais peito/braço só rouba recuperação. Na aba Treino dá pra registrar "extras" sem mexer na ficha.' },
      { q: 'Quanto tempo dura o treino?', a: 'Entre 45 e 60 minutos, contando descansos de 3 minutos. Se está passando de 75, provavelmente há exercícios extras ou conversa demais entre séries.' },
      { q: 'Como trocar um exercício que dói?', a: 'Troque por um movimento do mesmo padrão: supino inclinado com barra → com halteres; agachamento búlgaro → leg press unilateral; barra fixa → puxada na polia. Mantenha a troca até o fim do ciclo pra conseguir progredir nela.' },
      { q: 'Pernas só uma vez por semana é suficiente?', a: 'No objetivo de definição, sim. O Treino B é pesado (búlgaro, RDL, extensora) e as pernas também trabalham na caminhada diária. Quem quer mais volume de perna pode usar a Rotina Bônus, que tem búlgaro na sexta também.' },
      { q: 'O que são as etiquetas "Ativação" e "Mini" na sessão?', a: 'São as séries do Rest-Pause: Ativação é a série longa (12–15), Mini 1/2/3 são as mini-séries de 4–6 com pausa de 10–20 s. Todas com a mesma carga.' },
    ],
    hub: [
      { label: 'Treino de hoje', route: 'hub_health', ico: 'i-lucide-dumbbell' },
      { label: 'Análises de força', route: 'hub_health_dash', ico: 'i-lucide-area-chart' },
    ],
  },

  // ═══════════════════════════════════════════════════════════════════
  {
    key: 'alimentacao',
    ico: 'i-lucide-utensils',
    label: 'Alimentação',
    sub: 'jejum, calorias, macros, refeed e growth phase',
    resumo: [
      'A alimentação segue jejum intermitente: você fica 4 a 6 horas sem comer depois de acordar (água, café preto e chá liberados) e concentra as calorias em 2 ou 3 refeições — uma menor na quebra do jejum e a maior à noite.',
      'Na fase de definição (cutting) as calorias são cerca de 12 kcal por libra de peso corporal (≈ 26 kcal por kg), com proteína em 0,8 g por libra (≈ 1,8 g por kg). Pra 93 kg isso dá 2.460 kcal e 164 g de proteína; o restante se divide entre carboidrato e gordura.',
      'Uma vez por semana há o refeed: +600 kcal em carboidratos no dia de treino, pra repor glicogênio e manter o metabolismo e a força. Depois de 2–3 meses de cutting, entra uma Growth Phase de ~4 semanas a 15 kcal/lb pra ganhar músculo e "descansar" da dieta.',
    ],
    numeros: [
      { l: 'Jejum', v: '4–6 h', s: 'após acordar · água e café', ico: 'i-lucide-moon' },
      { l: 'Cutting', v: '12 kcal/lb', s: '≈ 26 kcal por kg', ico: 'i-lucide-flame' },
      { l: 'Proteína', v: '0,8 g/lb', s: '≈ 1,8 g por kg', ico: 'i-lucide-beef' },
      { l: 'Refeed', v: '+600 kcal', s: 'carbo · 1× por semana', ico: 'i-lucide-refresh-cw' },
    ],
    principios: [
      { ico: 'i-lucide-moon', t: 'Jejum: por que funciona', d: 'Adiar a primeira refeição corta o "beliscar" da manhã, deixa mais calorias pra refeições grandes e satisfatórias, e melhora o foco. Não é mágica metabólica: o que emagrece é o déficit — o jejum só torna o déficit fácil de manter.' },
      { ico: 'i-lucide-calculator', t: 'Calorias: a conta do cutting', d: 'Peso em libras × 12 (ou peso em kg × 26). Isso fica ~20–25% abaixo da manutenção — o suficiente pra perder 0,5–1% do peso por semana sem derrubar a força. Reajuste a cada 3–4 kg perdidos.' },
      { ico: 'i-lucide-beef', t: 'Proteína é prioridade', d: '0,8 g por libra (≈ 1,8 g/kg), distribuída nas refeições. É o que protege o músculo no déficit. Fontes: carne, frango, peixe, ovos, iogurte grego, whey. Bata a proteína primeiro, depois encaixe o resto.' },
      { ico: 'i-lucide-pie-chart', t: 'Carbo e gordura: o restante', d: 'Depois da proteína, o resto das calorias vai pra gordura (~25–30%) e carboidrato (o que sobrar, ~40%). Pra 2.460 kcal: ~90 g de gordura e ~246 g de carbo. Carbo maior no dia de treino, menor nos outros, se quiser refinar.' },
      { ico: 'i-lucide-utensils', t: 'Massive Meal Option', d: 'Quebra o jejum com uma refeição menor (~30% das calorias), faz a refeição grande à noite (~50%) e, se couber, um lanche noturno (~20%). Jantar grande = saciedade, sono melhor e vida social sem culpa.' },
      { ico: 'i-lucide-refresh-cw', t: 'Refeed semanal', d: 'Um dia por semana (de preferência dia de treino pesado), some +600 kcal só de carboidrato: arroz, batata, pão, frutas. Não é dia do lixo — proteína e gordura seguem iguais. Serve pra repor energia e manter os hormônios da queima em dia.' },
      { ico: 'i-lucide-sprout', t: 'Growth Phase', d: 'Depois de 8–12 semanas de cutting, 4 semanas a 15 kcal/lb (pra 93 kg: ~3.075 kcal). Você ganha força, enche o músculo e reseta a cabeça. Depois volta ao cutting mais forte. Ganho de peso de até 1–2 kg é esperado e é em parte glicogênio e água.' },
      { ico: 'i-lucide-glass-water', t: 'Água, café e o que não conta', d: 'No jejum: água à vontade, café preto, chá sem açúcar, água com gás. Adoçante é tolerado. Leite, açúcar, suco e qualquer caloria quebram o jejum — e mais importante, contam no total do dia.' },
    ],
    faq: [
      { q: 'Como calculo as minhas calorias?', a: 'Cutting: peso em kg × 26 (ou em libras × 12). Manutenção: ×33 (15 kcal/lb). Growth Phase: ×33 a ×35. Exemplo com 93 kg: cutting 2.460 kcal, growth ~3.075. Reajuste a cada 3–4 kg. A aba Dieta do HUB já mostra as metas atuais.' },
      { q: 'Sinto fome de manhã. O jejum é obrigatório?', a: 'A fome da manhã passa em 1–2 semanas de adaptação; café preto e água ajudam muito. Se mesmo assim não funcionar, o que importa é o total de calorias e proteína do dia — o jejum é a ferramenta, não o objetivo.' },
      { q: 'Quantas refeições preciso fazer?', a: 'Duas ou três. Menos refeições = refeições maiores e mais satisfatórias. Cinco ou seis refeições pequenas em cutting costumam deixar fome o dia inteiro.' },
      { q: 'Posso treinar em jejum?', a: 'Sim, e muita gente prefere. Café antes ajuda. Se treinar à tarde ou à noite, treine depois da primeira refeição. O importante é a refeição grande vir depois do treino no mesmo dia.' },
      { q: 'O que como no refeed?', a: 'Carboidratos limpos: arroz, batata, batata-doce, aveia, pão, massas, frutas, mel. Mantenha proteína igual e gordura baixa nesse dia. +600 kcal de carbo ≈ 150 g de carboidrato a mais.' },
      { q: 'Posso beber álcool?', a: 'Com moderação e contando: cerveja e drinks têm calorias que entram no total do dia. Um jeito comum é usar o dia do refeed pra isso, trocando parte do carbo. Álcool em excesso derruba o sono e a recuperação — ou seja, o treino seguinte.' },
      { q: 'Preciso pesar comida?', a: 'Nas primeiras 2–3 semanas, sim — é assim que se aprende o tamanho real das porções. Depois dá pra estimar e pesar só quando o progresso trava. Proteína é a primeira coisa a conferir.' },
      { q: 'A balança parou. O que ajusto?', a: 'Espere 2 semanas de estagnação real (média semanal, não um dia). Depois: confira se a proteína está certa, corte 150–200 kcal (de carbo ou gordura) ou adicione 2–3 mil passos por dia. Nunca corte proteína. Se a força também caiu, é hora de uma semana de manutenção.' },
      { q: 'Suplementos são necessários?', a: 'Não. Whey é só proteína prática; creatina (3–5 g/dia) ajuda a força e é segura; cafeína ajuda no jejum e no treino. Queimadores e afins não substituem déficit.' },
      { q: 'E nos fins de semana e eventos?', a: 'Mantenha o jejum e coma a refeição grande no evento. Se estourar as calorias, compense de leve nos dois dias seguintes (−200 kcal), não com jejum prolongado nem treino extra. Consistência da semana vale mais que um dia perfeito.' },
    ],
    hub: [
      { label: 'Dieta e metas', route: 'hub_health_dieta', ico: 'i-lucide-utensils' },
      { label: 'Corpo e peso', route: 'hub_health_corpo', ico: 'i-lucide-ruler' },
    ],
  },

  // ═══════════════════════════════════════════════════════════════════
  {
    key: 'cardio',
    ico: 'i-lucide-heart-pulse',
    label: 'Cardio e movimento',
    sub: 'caminhada, boxe e os dias sem pesos',
    resumo: [
      'No Warrior Shredding o cardio é coadjuvante: quem faz o corpo secar é o déficit calórico. O movimento diário serve pra aumentar o gasto sem cansar o corpo pro treino de força.',
      'A ferramenta principal é a caminhada: 8 a 12 mil passos por dia, todos os dias. É de baixo impacto, não interfere na recuperação e pode ser feita em jejum, ouvindo algo, resolvendo coisas.',
      'Cardio intenso (corrida, HIIT, boxe forte) é opcional e limitado: 1 a 2 vezes por semana, curto, nos dias sem pesos ou bem depois do treino. Mais que isso costuma derrubar a força e aumentar a fome.',
    ],
    numeros: [
      { l: 'Passos', v: '8–12 mil', s: 'por dia, todos os dias', ico: 'i-lucide-footprints' },
      { l: 'Cardio intenso', v: '1–2×', s: 'por semana, 15–25 min', ico: 'i-lucide-zap' },
      { l: 'Dias de pesos', v: 'sem cardio', s: 'ou só caminhada leve', ico: 'i-lucide-ban' },
    ],
    principios: [
      { ico: 'i-lucide-footprints', t: 'Caminhar é a base', d: 'Caminhada é o cardio que não cobra nada do corpo: queima 300–500 kcal em uma hora, não gera fome e ainda ajuda no sono. Priorize passos antes de pensar em corrida.' },
      { ico: 'i-lucide-swords', t: 'Boxe como cardio inteligente', d: 'Rounds de saco, sombra e sequências são cardio divertido e técnico. Use nos dias sem pesos (terça, quinta, sábado), 20–30 min, intensidade moderada. Os planos de luta e sequências estão na aba Boxe.' },
      { ico: 'i-lucide-zap', t: 'HIIT: pouco e raro', d: 'Tiros curtos (8–10 × 20–30 s) uma ou duas vezes por semana, longe do treino de pernas. Em déficit, HIIT demais aumenta cortisol e fome e tira força do treino seguinte.' },
      { ico: 'i-lucide-ban', t: 'Não use cardio pra "compensar"', d: 'Comeu demais? Ajuste a comida dos dias seguintes. Cardio punitivo cria um ciclo de fome e exagero. O déficit se constrói na cozinha; o cardio só soma um pouco.' },
      { ico: 'i-lucide-calendar', t: 'Semana típica', d: 'Seg pesos A · Ter caminhada ou boxe · Qua pesos B · Qui caminhada ou boxe · Sex pesos C · Sáb caminhada longa ou boxe · Dom descanso ativo. Passos todos os dias.' },
    ],
    faq: [
      { q: 'Cardio em jejum queima mais gordura?', a: 'Um pouco mais durante a sessão, mas no total do dia dá o mesmo. A vantagem real é prática: caminhar de manhã em jejum encaixa bem na rotina e tira a fome.' },
      { q: 'Posso fazer cardio no mesmo dia dos pesos?', a: 'Caminhada sim, a qualquer hora. Cardio intenso, só depois do treino de pesos e curto, ou de preferência em outro dia. Nunca antes dos pesos — rouba a força das séries principais.' },
      { q: 'Boxe conta como treino de força?', a: 'Não. Boxe é habilidade e condicionamento. Ele não substitui os treinos A, B, C. Some os dois: pesos nos 3 dias fixos, boxe nos outros.' },
      { q: 'Preciso de esteira ou bike?', a: 'Não. Passos ao ar livre resolvem. Se quiser variar, bike ou remo em intensidade leve por 20–30 min são boas opções pra dias de chuva.' },
      { q: 'Quantas calorias o cardio queima?', a: 'Menos do que parece: 30 min de corrida moderada ≈ 300 kcal; 1 h de caminhada ≈ 300–400 kcal. Por isso o cardio é complemento e a dieta é a base.' },
    ],
    hub: [
      { label: 'Cardio', route: 'hub_health_cardio', ico: 'i-lucide-heart-pulse' },
      { label: 'Boxe', route: 'hub_health_boxe', ico: 'i-lucide-swords' },
    ],
  },

  // ═══════════════════════════════════════════════════════════════════
  {
    key: 'corpo',
    ico: 'i-lucide-ruler',
    label: 'Corpo e medidas',
    sub: 'como medir progresso de verdade',
    resumo: [
      'O peso na balança é só um dos sinais e é o mais barulhento: varia com água, sal, carboidrato e intestino. Por isso o programa acompanha a MÉDIA semanal do peso, a cintura na altura do umbigo e as medidas dos músculos.',
      'A meta de perda é 0,5 a 1% do peso corporal por semana (pra 93 kg: 450 g a 900 g). Mais rápido que isso custa músculo e força; mais lento indica que as calorias precisam de ajuste.',
      'Fotos a cada 4 semanas, na mesma luz e posição, mostram o que nem a fita nem a balança pegam. O HUB guarda peso, medidas e gera a "Transformação" (início × agora).',
    ],
    numeros: [
      { l: 'Pesagem', v: 'diária', s: 'em jejum, após o banheiro · use a média', ico: 'i-lucide-scale' },
      { l: 'Medidas', v: 'a cada 2 sem', s: 'cintura umbigo · peito · braço · coxa', ico: 'i-lucide-ruler' },
      { l: 'Fotos', v: 'a cada 4 sem', s: 'mesma luz, mesma pose', ico: 'i-lucide-camera' },
    ],
    principios: [
      { ico: 'i-lucide-scale', t: 'Peso: olhe a média, não o dia', d: 'Pese-se de manhã, em jejum, depois do banheiro. Compare a média desta semana com a da semana passada. Uma oscilação de 1–2 kg em um dia é água — não é gordura ganha nem perdida.' },
      { ico: 'i-lucide-circle-dashed', t: 'Cintura é o melhor indicador', d: 'Fita na altura do umbigo, relaxado, sem apertar. Cintura caindo com força mantida = gordura indo embora. Se a cintura cai e o peso não, você está trocando gordura por músculo — ótimo.' },
      { ico: 'i-lucide-ruler', t: 'Medidas dos músculos', d: 'Peito, ombros, braço, antebraço, coxa e panturrilha, sempre no mesmo ponto e sem contrair (ou sempre contraído). Em cutting a meta é manter; em Growth Phase é crescer. A Transformação do HUB soma tudo.' },
      { ico: 'i-lucide-camera', t: 'Fotos honestas', d: 'Frente, lado e costas, mesma luz, mesmo horário, sem "sugar a barriga". A cada 4 semanas. Você vai se surpreender com o que a foto mostra que o espelho diário esconde.' },
      { ico: 'i-lucide-gauge', t: 'Sinais de que está certo', d: 'Peso caindo 0,5–1%/semana · cintura −1 cm a cada 2 semanas · força mantida ou subindo · sono e energia ok · fome controlável. Se dois desses falham por 2 semanas, ajuste.' },
      { ico: 'i-lucide-alert-triangle', t: 'Sinais de exagero', d: 'Força caindo em vários exercícios, fome constante, sono ruim, irritação, peso caindo mais de 1,5%/semana. Aí o déficit está grande demais: suba 200–300 kcal ou faça uma semana em manutenção.' },
    ],
    faq: [
      { q: 'Por que meu peso subiu depois do refeed?', a: 'Cada grama de carboidrato guarda ~3 g de água no músculo. +150 g de carbo pode significar +1 kg na balança no dia seguinte — que some em 2–3 dias. Por isso a média semanal.' },
      { q: 'Com que frequência tiro medidas?', a: 'A cada duas semanas, no mesmo dia e horário (ex.: domingo de manhã em jejum). Mais que isso gera ruído; menos, você perde o momento de ajustar.' },
      { q: 'Perco peso mas não vejo definição. Por quê?', a: 'Definição aparece quando a camada de gordura fica fina o bastante, geralmente abaixo de ~12%. Antes disso o corpo "murcha" sem definir. Continue: as últimas semanas mudam mais que as primeiras.' },
      { q: 'A força caiu um pouco. É normal?', a: 'Uma queda leve em 1 exercício em semana ruim de sono é normal. Queda em vários exercícios por 2 semanas seguidas não é: reveja calorias (provavelmente baixas demais), proteína e sono.' },
      { q: 'Qual meu peso ideal?', a: 'O programa não trabalha com peso-alvo, e sim com cintura e definição. Uma referência prática: cintura no umbigo em torno de 45% da altura (ex.: 1,80 m → ~81 cm) costuma coincidir com um físico bem definido.' },
    ],
    hub: [
      { label: 'Corpo', route: 'hub_health_corpo', ico: 'i-lucide-ruler' },
      { label: 'Análises', route: 'hub_health_dash', ico: 'i-lucide-area-chart' },
    ],
  },

  // ═══════════════════════════════════════════════════════════════════
  {
    key: 'estilo',
    ico: 'i-lucide-sunrise',
    label: 'Rotina e mente',
    sub: 'sono, descanso, constância e cabeça no lugar',
    resumo: [
      'O terceiro pilar é o que sustenta os outros dois: dormir 7 a 9 horas, manter uma rotina previsível (horários de acordar, treinar, comer) e cuidar do estresse. Sem isso, a força trava e a fome dispara.',
      'A regra mental do programa é "ser o guerreiro": treinar quando dá vontade e quando não dá, comer com disciplina sem obsessão, e aceitar que o resultado vem de semanas comuns bem feitas, não de dias heroicos.',
      'Constância vence intensidade. 80% de aderência por 24 semanas transforma mais que 100% por 3 semanas seguidas de abandono. O HUB mede a constância e celebra cada semana fechada por isso.',
    ],
    numeros: [
      { l: 'Sono', v: '7–9 h', s: 'horário fixo pra acordar', ico: 'i-lucide-bed' },
      { l: 'Aderência', v: '80%+', s: 'dos treinos e dias de dieta', ico: 'i-lucide-check-circle' },
      { l: 'Descanso', v: '48 h', s: 'entre treinos de pesos', ico: 'i-lucide-battery-charging' },
    ],
    principios: [
      { ico: 'i-lucide-bed', t: 'Sono é anabólico', d: 'É dormindo que o músculo se recupera e que os hormônios da queima se regulam. Uma noite ruim derruba a força e aumenta a fome no dia seguinte. Fixe o horário de acordar — o jejum da manhã fica fácil quando o sono está em dia.' },
      { ico: 'i-lucide-calendar-range', t: 'Rotina previsível', d: 'Mesmos dias de treino, mesmo horário da primeira refeição, caminhada no mesmo trecho do dia. Decidir menos = falhar menos. Monte a sua na tela Rotina, com os modelos "acorda cedo / tarde".' },
      { ico: 'i-lucide-shield', t: 'Mentalidade de guerreiro', d: 'Não é motivação, é identidade: "eu sou alguém que treina segunda, quarta e sexta". Nos dias sem vontade, faça o treino do jeito mínimo — a sessão feita mal é infinitamente melhor que a sessão não feita.' },
      { ico: 'i-lucide-check-circle', t: 'Aderência, não perfeição', d: 'Uma semana boa = 3 treinos feitos + 5 ou 6 dias de comida no alvo + passos na maioria dos dias. Não existe "estraguei tudo": existe a próxima refeição e o próximo treino.' },
      { ico: 'i-lucide-brain', t: 'Estresse e cortisol', d: 'Estresse crônico segura água, aumenta fome e atrapalha o sono. Caminhada, sol de manhã, respiração e limites de trabalho fazem parte do programa tanto quanto a barra.' },
      { ico: 'i-lucide-trophy', t: 'Celebre o processo', d: 'Cada semana fechada, cada medição, cada carga que subiu conta. O HUB anima essas conquistas de propósito: o cérebro precisa de recompensa curta pra sustentar um objetivo de 24 semanas.' },
    ],
    faq: [
      { q: 'Quantas horas de sono preciso?', a: 'Sete a nove. Se dorme menos de seis com frequência, espere força travada e fome alta — antes de mexer na dieta, arrume o sono.' },
      { q: 'Estou sem motivação. O que faço?', a: 'Reduza o tamanho da tarefa: só ir até a academia e fazer o primeiro exercício. Quase sempre o resto sai. E olhe o histórico no HUB: ver onde estava na semana 1 ajuda a lembrar por quê.' },
      { q: 'Posso treinar dois dias seguidos se precisar?', a: 'Pode, ocasionalmente (ex.: B na quinta e C na sexta). Evite que vire regra: a recuperação de 48 h é o que permite subir carga.' },
      { q: 'Como lido com a fome à noite?', a: 'Estruture o dia pra jantar grande e, se couber, lanche noturno (Massive Meal Option). Fome noturna forte geralmente significa que a primeira refeição foi grande demais ou que a proteína está baixa.' },
      { q: 'Quando devo "sair" da dieta?', a: 'Depois de 8–12 semanas de cutting, ou antes se a força cair em vários exercícios e o sono piorar. Uma semana em manutenção ou uma Growth Phase de 4 semanas resolve, e você volta melhor.' },
    ],
    hub: [
      { label: 'Rotina', route: 'hub_health_rotina', ico: 'i-lucide-calendar-range' },
      { label: 'Meu Painel', route: 'hub_health_painel', ico: 'i-lucide-gauge' },
    ],
  },
];

export const pillarOf = key => PILLARS.find(p => p.key === key) || PILLARS[0];

// Glossário rápido (termos que aparecem nas telas do HUB)
export const GLOSSARY = [
  { t: 'RPT', d: 'Reverse Pyramid Training — pirâmide reversa: a série mais pesada vem primeiro, e a carga cai ~10% a cada série.' },
  { t: 'Rest-Pause', d: 'Uma série de ativação (12–15) + 3 mini-séries (4–6) com a mesma carga e 10–20 s de pausa.' },
  { t: 'Pirâmide padrão', d: '12 / 10 / 8 / 6 repetições com a mesma carga e 30–60 s de descanso; progride reduzindo o descanso.' },
  { t: 'Topo da faixa', d: 'Bater o número máximo de repetições em todas as séries (ex.: 6/7/8). É o gatilho pra subir a carga.' },
  { t: 'Independent set loading', d: 'Cada série sobe de carga sozinha, começando pela última (3ª → 2ª → 1ª).' },
  { t: 'Cutting', d: 'Fase de perda de gordura: ~12 kcal por libra de peso (≈ 26 kcal/kg).' },
  { t: 'Growth Phase', d: 'Fase de ganho: ~15 kcal por libra (≈ 33 kcal/kg) por ~4 semanas, depois de 2–3 meses de cutting.' },
  { t: 'Refeed', d: 'Um dia por semana com +600 kcal só de carboidrato, no dia de treino.' },
  { t: 'Massive Meal Option', d: 'Refeição menor na quebra do jejum, jantar grande e lanche noturno opcional.' },
  { t: '1RM estimado', d: 'Força máxima calculada a partir da carga × repetições; o HUB usa pra comparar força ao longo do tempo.' },
];

// ═══════════════════════════════════════════════════════════════════
// TREINOS — intenção de cada ciclo, sessão e exercício (rodada 37).
// A prescrição em si (exercícios, método, faixas, descanso, progressão)
// vem do config do HUB (programs do seed); aqui mora só o "porquê".
// Casamento por palavra-chave no nome do exercício (sem acento).
// ═══════════════════════════════════════════════════════════════════
export const CYCLE_INTENTS = {
  c1: {
    title: 'Construir a base',
    text: 'Oito semanas pra dominar os movimentos que sustentam o programa inteiro: supino inclinado, desenvolvimento em pé, barra fixa, búlgaro e RDL. Aqui você descobre suas cargas reais, aprende a descansar 3 minutos sem culpa e cria o hábito de anotar tudo. A ênfase é peito superior e ombros — o que dá o formato de "V" — com braços e pernas pesados uma vez por semana.',
  },
  c2: {
    title: 'Encher o peitoral',
    text: 'Os movimentos mudam de ângulo pra atacar o peito por dois caminhos (inclinado com halteres e reto com barra) e ganham as paralelas. A barra fixa migra pro treino A pra ser feita descansado. Nas pernas entra o hip thrust pra glúteo e posterior. A base já existe; agora é volume um pouco maior nos pontos onde o físico mais aparece.',
  },
  c3: {
    title: 'Ombros em foco',
    text: 'O ciclo final coloca o desenvolvimento militar no treino A (descansado, depois do supino) e o desenvolvimento sentado com halteres no C. Entram o agachamento frontal, com faixa mais baixa (4–6) pra força pura, e a barra fixa pronada, que alarga as costas. É a fase de "acabamento": ombros largos e cintura fina fazem o corpo parecer maior mesmo mais leve.',
  },
  bonus: {
    title: 'Força e volume (Strength & Fullness)',
    text: 'Bloco alternativo de 8 semanas pra ser usado depois de um ciclo. Combina séries exatas 5/6/8 com carga independente por série (força), pirâmides 12/10/8/6 com a mesma carga e descanso curto (volume e "cheio") e rest-pause nos menores. Traz panturrilha e remada alta. Mais trabalho por sessão, mesma regra: subir carga ou reduzir descanso.',
  },
};

export const SESSION_INTENTS = {
  A: { title: 'Peito e braços', text: 'O treino mais "visível": peito superior primeiro, quando você está descansado, depois braços. Movimentos de empurrar e os bíceps, que crescem bem com o mesmo estímulo pesado.' },
  B: { title: 'Pernas e abdômen', text: 'Uma sessão por semana de pernas pesadas, unilateral (búlgaro) pra equilíbrio e sem sobrecarregar a lombar. RDL cuida do posterior e glúteo; o abdômen entra com carga porque também é músculo.' },
  C: { title: 'Ombros, costas e tríceps', text: 'Empurrar por cima (desenvolvimento) e puxar (barra fixa e remada) na mesma sessão: ombros largos e costas em V. Tríceps no fim, já aquecido pelos empurrões.' },
};

export const EXERCISE_INTENTS = [
  {
    match: /supino inclinado/,
    musc: 'Peito superior · ombro anterior · tríceps',
    why: 'O exercício mais importante do programa. O peito superior é o que "levanta" o tórax e dá a linha reta do peitoral até a clavícula; a maioria das pessoas o tem subdesenvolvido por só fazer supino reto. Vem primeiro no treino A porque exige o máximo de força.',
    cue: 'Banco a 30°. Barra desce até o alto do peito, cotovelos a ~45° do corpo, escápulas encaixadas. Pausa curta embaixo, sobe forte.',
  },
  {
    match: /supino reto|supino fechado|paralelas/,
    musc: 'Peito médio/inferior · tríceps',
    why: 'Complementa o inclinado atacando a porção média e inferior do peitoral com mais amplitude (halteres) ou mais carga (barra, paralelas). Faixas de 8–12 porque aqui o objetivo é volume e "encher", não força máxima.',
    cue: 'Halteres: desça até o cotovelo passar um pouco da linha do banco. Paralelas: tronco levemente inclinado à frente pra pegar o peito.',
  },
  {
    match: /crucifixo com halteres|crucifixo em inclina/,
    musc: 'Peito (alongamento) · ombro anterior',
    why: 'Isolamento do peito na posição alongada, onde o estímulo de crescimento é maior. Na pirâmide 12/10/8/6 com a mesma carga, a progressão é reduzir o descanso — treina densidade, não força.',
    cue: 'Cotovelos levemente dobrados e fixos; desça devagar até sentir o alongamento, suba fechando os braços como se abraçasse um tronco.',
  },
  {
    match: /rosca inclinada/,
    musc: 'Bíceps (cabeça longa)',
    why: 'No banco inclinado o braço fica atrás do corpo e o bíceps trabalha na posição alongada — é a variação que mais cresce o "pico". Faixa de 6–8 pesada porque o bíceps responde a carga, não a bombeio.',
    cue: 'Banco a 45–60°, ombros pra trás, cotovelos atrás do tronco. Suba sem balançar o corpo; desça em 2 segundos.',
  },
  {
    match: /rosca martelo/,
    musc: 'Braquial · braquiorradial · bíceps',
    why: 'A pegada neutra tira o bíceps do centro e coloca o braquial (que fica embaixo dele e "empurra" o bíceps pra cima) e o antebraço. Braço fica mais grosso de lado. Na corda, a tensão é constante.',
    cue: 'Cotovelos colados ao corpo; puxe a corda separando as pontas no topo. Nada de balanço.',
  },
  {
    match: /crucifixo inverso/,
    musc: 'Deltoide posterior · romboides · trapézio médio',
    why: 'O ombro posterior é o que dá "profundidade" ao ombro visto de lado e corrige a postura curvada do dia a dia no computador. Rest-pause porque é um músculo pequeno que aguenta muito volume com pouco descanso.',
    cue: 'Braços quase esticados, mova os cotovelos pra fora e pra trás, não as mãos. Carga leve: se está balançando, está pesado demais.',
  },
  {
    match: /bulgaro|búlgaro/,
    musc: 'Quadríceps · glúteo · estabilizadores',
    why: 'O agachamento de uma perna só entrega o estímulo do agachamento pesado sem carregar a coluna e sem precisar de barra nas costas. Corrige assimetrias entre as pernas e trabalha o glúteo a fundo.',
    cue: 'Pé de trás no banco só pelo peito do pé; tronco levemente inclinado à frente; desça até o joelho de trás quase tocar o chão. Um halter em cada mão.',
  },
  {
    match: /romeno|rdl|stiff/,
    musc: 'Posteriores de coxa · glúteo · lombar',
    why: 'A cadeia posterior é o que dá formato às pernas por trás e protege a lombar. Movimento de dobradiça de quadril: a carga sobe rápido, por isso a progressão de 8/8/8 → subir.',
    cue: 'Barra rente às pernas, joelhos levemente dobrados e fixos; empurre o quadril pra trás até sentir o posterior alongar (a barra em torno do meio da canela). Costas retas o tempo todo.',
  },
  {
    match: /extensora/,
    musc: 'Quadríceps (isolado)',
    why: 'Termina o quadríceps com volume e sem fadiga sistêmica, na faixa de 10–12. Dá o "corte" acima do joelho, que aparece muito com gordura baixa.',
    cue: 'Segure 1 segundo no topo contraindo; desça controlado. Não bata o peso embaixo.',
  },
  {
    match: /hip thrust|elevacao pelvica|elevação pélvica/,
    musc: 'Glúteo máximo · posteriores',
    why: 'É o exercício que mais ativa o glúteo, com carga alta e sem estresse na coluna. Entra no ciclo 2 pra completar o RDL e o búlgaro; faixas de 8–15 porque o glúteo responde bem a volume.',
    cue: 'Costas apoiadas no banco na altura das escápulas, queixo pra baixo; suba até o quadril alinhar com joelho e ombro, apertando o glúteo no topo.',
  },
  {
    match: /joelhos suspenso|elevacao de joelhos|elevação de joelhos/,
    musc: 'Abdômen inferior · flexores de quadril · pegada',
    why: 'Abdômen é músculo: com carga progressiva ele fica mais denso e aparece mais quando a gordura sai. Suspenso na barra também fortalece a pegada, que ajuda na barra fixa e no RDL.',
    cue: 'Suba os joelhos enrolando o quadril (a pelve gira pra cima), não só levantando as pernas. Desça devagar sem balançar.',
  },
  {
    match: /militar em pe|militar em pé|desenvolvimento militar/,
    musc: 'Deltoide anterior e médio · tríceps · core',
    why: 'O movimento de empurrar por cima em pé é o construtor de ombros mais completo — e um teste de força real, porque o corpo inteiro estabiliza. Ombros largos são o que mais muda a silhueta.',
    cue: 'Barra na altura das clavículas, cotovelos levemente à frente; glúteo e abdômen firmes; empurre até travar acima da cabeça, levando a cabeça "através" da barra no final.',
  },
  {
    match: /desenvolvimento sentado/,
    musc: 'Deltoide anterior e médio · tríceps',
    why: 'A versão sentada com halteres tira o componente de estabilização e permite mais carga direta no deltoide, com amplitude maior que a barra. Aparece no ciclo 3 e na Bônus quando o foco é ombro.',
    cue: 'Encosto a 80–90°; halteres na altura das orelhas; suba juntando-os no alto sem bater. Desça até os cotovelos ficarem um pouco abaixo dos ombros.',
  },
  {
    match: /elevacao lateral|elevação lateral/,
    musc: 'Deltoide médio',
    why: 'É o deltoide médio que dá largura ao ombro visto de frente, e ele só é bem trabalhado em isolamento. Rest-pause porque aguenta volume e a carga é baixa; progressão lenta e paciente.',
    cue: 'Cotovelos levemente dobrados, suba até a altura dos ombros com os cotovelos liderando (mindinho um pouco mais alto). Sem impulso.',
  },
  {
    match: /barra fixa pronada/,
    musc: 'Dorsal · redondo maior · bíceps',
    why: 'A pegada pronada (palmas pra frente) e mais aberta coloca o dorsal em evidência e dá largura às costas — o outro lado do V. Com peso adicional, vira um exercício de força.',
    cue: 'Pegada um pouco mais aberta que os ombros; puxe o peito em direção à barra, cotovelos pra baixo e pra trás. Desça completamente.',
  },
  {
    match: /barra fixa/,
    musc: 'Dorsal · bíceps · antebraços',
    why: 'O melhor exercício de puxar: dorsal e bíceps ao mesmo tempo, com o peso do corpo mais carga. Na pegada supinada o bíceps ajuda mais, por isso séries de 6 pesadas. A progressão de +1,1 kg por treino é lenta de propósito — é assim que se chega a 30–40 kg extras.',
    cue: 'Pendure completamente embaixo; puxe até o queixo passar a barra, peito pra cima; desça controlado. Cinto ou halter entre as pernas pra carga.',
  },
  {
    match: /remada baixa|remada sentada/,
    musc: 'Dorsal (espessura) · romboides · trapézio · bíceps',
    why: 'Se a barra fixa dá largura, a remada dá espessura: a musculatura do meio das costas que aparece de lado e melhora a postura. Feita depois da barra fixa, quando o dorsal já está aquecido.',
    cue: 'Peito alto, puxe o cabo até o abdômen levando os cotovelos pra trás, aperte as escápulas no fim. Não incline o tronco pra trás pra ajudar.',
  },
  {
    match: /remada alta/,
    musc: 'Deltoide médio · trapézio',
    why: 'Com pegada aberta, a remada alta vira um exercício de ombro (não de trapézio) e complementa a elevação lateral com mais carga. Rest-pause com faixa alta pra fadiga e volume.',
    cue: 'Pegada bem mais larga que os ombros; suba os cotovelos até a altura dos ombros, não mais. Barra ou cabo rente ao corpo.',
  },
  {
    match: /triceps|tríceps/,
    musc: 'Tríceps (cabeça lateral e longa)',
    why: 'O tríceps é dois terços do braço. Ele já trabalha muito nos supinos e desenvolvimentos; aqui recebe o volume final em isolamento, com a corda permitindo separar as mãos no final e contrair a cabeça lateral.',
    cue: 'Cotovelos fixos ao lado do corpo; estenda até travar, separando as pontas da corda. Suba controlado — não deixe a carga puxar os cotovelos pra cima.',
  },
  {
    match: /agachamento frontal/,
    musc: 'Quadríceps · core · costas superiores',
    why: 'A barra na frente obriga o tronco a ficar em pé e coloca o quadríceps como protagonista, com menos carga na lombar que o agachamento tradicional. Faixa de 4–6: é o exercício de força pura das pernas no ciclo 3.',
    cue: 'Barra apoiada nos ombros à frente (cotovelos altos), pés na largura dos ombros; desça profundo mantendo o peito pra cima. Se os cotovelos caírem, a barra cai.',
  },
  {
    match: /afundo/,
    musc: 'Quadríceps · glúteo',
    why: 'O afundo reverso (passo pra trás) protege o joelho da perna da frente e trabalha glúteo e quadríceps de forma unilateral, como o búlgaro, mas com menos exigência de equilíbrio — ótimo como segundo exercício de perna.',
    cue: 'Passo largo pra trás, joelho de trás quase no chão; empurre com o calcanhar da frente pra voltar. Tronco levemente inclinado à frente.',
  },
  {
    match: /panturrilha/,
    musc: 'Sóleo · gastrocnêmio',
    why: 'Panturrilha sentada pega o sóleo, o músculo "por baixo" que dá volume à perna. Pirâmide com descanso curto porque é um músculo de resistência: precisa de volume e tempo sob tensão.',
    cue: 'Amplitude completa: desça até alongar bem, suba na ponta e segure 1–2 segundos no topo. Sem quicar.',
  },
];

const stripAccents = s => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
export const exerciseIntent = name => {
  const n = stripAccents(name);
  return EXERCISE_INTENTS.find(e => e.match.test(n)) || null;
};

// ═══════════════════════════════════════════════════════════════════
// CIÊNCIA — o que acontece no corpo (rodada 37)
// ═══════════════════════════════════════════════════════════════════
export const SCIENCE = [
  {
    key: 'serie',
    short: 'Série pesada',
    ico: 'i-lucide-activity',
    title: 'O que acontece numa série pesada',
    lead: 'Uma série de 5–8 repetições perto da falha é o sinal mais forte que existe pra dizer ao músculo: "fique maior e mais forte".',
    steps: [
      { t: 'Recrutamento total', d: 'Com carga alta o cérebro precisa acionar as unidades motoras grandes — as fibras rápidas, que têm mais potencial de crescimento. Com carga leve elas só entram no fim da série, quando você já está cansado.' },
      { t: 'Tensão mecânica', d: 'É o principal gatilho da hipertrofia: a fibra sendo esticada e contraída sob carga. Cada repetição pesada e completa "avisa" sensores dentro da célula muscular que a estrutura precisa ser reforçada.' },
      { t: 'Micro-lesões controladas', d: 'As fibras sofrem pequenos danos, principalmente na descida (excêntrica). Não é o dano que faz crescer — é o reparo. Por isso descida controlada, não peso caindo.' },
      { t: 'Sinal de síntese', d: 'Nas 24–48 h seguintes o corpo aumenta a síntese de proteína muscular naquele músculo. Ele usa a proteína da comida como matéria-prima pra reconstruir a fibra um pouco mais espessa.' },
      { t: 'Adaptação neural', d: 'Nas primeiras semanas a força sobe rápido sem o músculo crescer muito: o sistema nervoso aprende a coordenar e a acionar mais fibras ao mesmo tempo. É por isso que a semana 1 é "calibração".' },
    ],
    practice: [
      'Primeira série pesada e descansado: é ela que recruta tudo. Por isso o RPT coloca a série mais pesada primeiro.',
      '3 minutos de descanso deixam o sistema nervoso e a energia rápida (fosfocreatina) se recuperarem — a série seguinte continua pesada de verdade.',
      'Parar 1 rep antes da falha entrega quase todo o estímulo com muito menos fadiga acumulada. Falha total só cansa mais, sem crescer mais.',
      'Subir a carga quando bate o topo da faixa é o que mantém o sinal: o músculo só se adapta a algo que ainda não conhece.',
    ],
  },
  {
    key: 'musculo',
    short: 'Músculo',
    ico: 'i-lucide-layers',
    title: 'Como o músculo cresce',
    lead: 'Músculo cresce quando, ao longo das semanas, a construção de proteína supera a quebra. Treino dá o sinal; comida dá o material; sono faz a obra.',
    steps: [
      { t: 'Estímulo → sinal', d: 'A tensão do treino ativa vias dentro da célula (a principal chama-se mTOR) que "ligam" a produção de novas proteínas contráteis. Sem estímulo suficiente, nada é construído.' },
      { t: 'Proteína → tijolos', d: 'Os aminoácidos da carne, ovos, laticínios e whey são os tijolos. Cerca de 1,8 g/kg por dia garante que nunca falte material, mesmo em déficit. Comer mais que isso não constrói mais rápido.' },
      { t: 'Sono → construção', d: 'Boa parte do reparo acontece durante o sono profundo, quando o hormônio do crescimento e a testosterona estão mais altos. Dormir 6 h em vez de 8 corta o resultado do treino que você já fez.' },
      { t: 'Repetição → acúmulo', d: 'Cada treino adiciona um pouco. O ganho visível vem de somar 24, 48, 100 sessões com progressão. É por isso que o programa repete os mesmos exercícios: pra somar no mesmo lugar.' },
      { t: 'Sobrecarga progressiva', d: 'O músculo se adapta ao estímulo e para de responder. Só continua crescendo se a carga (ou as reps, ou a densidade) subir. Toda regra de progressão do programa existe pra garantir isso.' },
    ],
    practice: [
      'Em cutting, a meta realista é manter músculo e ganhar força; em Growth Phase, ganhar 1–2 kg de músculo em 8–12 semanas já é excelente.',
      'Três treinos de força por semana são suficientes: cada músculo recebe o sinal e tem 5–7 dias pra se reconstruir antes do próximo.',
      'Volume alto não compensa carga baixa. 3 séries pesadas valem mais que 8 séries médias.',
      'A força subindo é a prova de que o músculo está sendo mantido ou construído — a balança não mostra isso, o caderno de cargas mostra.',
    ],
  },
  {
    key: 'gordura',
    short: 'Gordura',
    ico: 'i-lucide-flame',
    title: 'Como a gordura vai embora',
    lead: 'Gordura é energia guardada. Ela só sai quando o corpo precisa de mais energia do que está entrando — o déficit calórico. Tudo o mais é detalhe pra tornar isso fácil e sustentável.',
    steps: [
      { t: 'Balanço energético', d: 'Comer menos calorias do que gasta obriga o corpo a buscar energia nas reservas. 1 kg de gordura guarda ~7.000 kcal; um déficit de ~500 kcal/dia ≈ 0,5 kg por semana.' },
      { t: 'Mobilização', d: 'Com a insulina baixa (entre refeições, no jejum, durante a caminhada), hormônios como adrenalina e glucagon "abrem" as células de gordura e liberam ácidos graxos na circulação.' },
      { t: 'Oxidação', d: 'Os ácidos graxos vão pros músculos e órgãos e são queimados como combustível. Músculo mais treinado e mais ativo queima mais gordura — por isso a força e os passos ajudam.' },
      { t: 'Preservação do músculo', d: 'Em déficit o corpo também poderia quebrar músculo pra fazer energia. Treino pesado + proteína alta mandam a mensagem oposta: "este tecido está em uso, preserve". É o que diferencia emagrecer de "secar bem".' },
      { t: 'Adaptação e refeed', d: 'Semanas em déficit reduzem um pouco o gasto (leptina cai, você se mexe menos sem perceber). O refeed semanal e a Growth Phase periódica seguram essa adaptação e mantêm a força.' },
    ],
    practice: [
      'O jejum não queima mais gordura por si só — ele torna fácil comer menos e deixa refeições grandes e satisfatórias. É uma ferramenta de aderência.',
      'Cardio queima pouco (300 kcal em 30 min de corrida). Caminhar todo dia soma sem gerar fome; a dieta é a alavanca principal.',
      'Perder 0,5–1% do peso por semana é o ritmo em que a gordura sai e o músculo fica. Mais rápido que isso, você perde os dois.',
      'A balança sobe com carbo e sal (água) e desce com desidratação. Cintura e média semanal contam a verdade.',
    ],
  },
  {
    key: 'recomp',
    short: 'Forte e seco',
    ico: 'i-lucide-scale',
    title: 'Por que dá pra ficar forte enquanto seca',
    lead: 'Parece contraditório: perder peso e ganhar força. Não é — desde que o déficit seja moderado, a proteína alta e o treino pesado.',
    steps: [
      { t: 'Força é mais neural que muscular', d: 'Boa parte da força vem da coordenação e do recrutamento, não só do tamanho do músculo. Em déficit você continua aprendendo o movimento e recrutando melhor.' },
      { t: 'A gordura financia o treino', d: 'Com 15–20% de gordura corporal você tem dezenas de milhares de calorias guardadas. O corpo usa essa reserva pra sustentar a recuperação enquanto come menos.' },
      { t: 'Déficit moderado = sinal preservado', d: '12 kcal/lb fica ~20% abaixo da manutenção. Nessa faixa a síntese de proteína ainda responde ao treino. Em déficits agressivos (−40%), ela cai e a força vai junto.' },
      { t: 'Refeed e carbo no treino', d: 'Glicogênio cheio = séries pesadas fortes. O refeed e a refeição grande depois do treino mantêm o combustível rápido disponível.' },
      { t: 'Quando a força cai', d: 'É o alarme do programa. Queda em vários exercícios por 2 semanas = déficit grande demais ou sono ruim. Ajustar é parte do método, não falha.' },
    ],
    practice: [
      'Espere a força subir nos primeiros 2–3 meses de cutting; depois, manter já é vitória.',
      'Se a força cair, primeiro sono, depois +200 kcal de carbo, depois uma semana em manutenção.',
      'Iniciantes e quem voltou de uma pausa conseguem ganhar músculo e perder gordura ao mesmo tempo (recomposição). Avançados alternam fases.',
    ],
  },
  {
    key: 'recuperacao',
    short: 'Recuperação',
    ico: 'i-lucide-battery-charging',
    title: 'Recuperação: onde o resultado acontece',
    lead: 'Treino é o pedido. A resposta vem nas 48 horas seguintes — e só se você deixar o corpo responder.',
    steps: [
      { t: 'Supercompensação', d: 'Depois do estímulo o desempenho cai, o corpo repara e depois sobe um pouco acima do ponto inicial. Treinar de novo nesse pico é progredir; treinar antes é acumular fadiga.' },
      { t: '48 h entre sessões', d: 'Seg–qua–sex existe por isso. Cada grupo muscular ainda recebe sinal indireto em outros dias (ombro no supino, bíceps na barra fixa), então o estímulo semanal é maior do que parece.' },
      { t: 'Sistema nervoso também cansa', d: 'Cargas pesadas exigem muito do sistema nervoso central. Ele recupera mais devagar que o músculo — mais um motivo pra não adicionar treinos extras.' },
      { t: 'Sono, estresse e cortisol', d: 'Cortisol alto (pouco sono, estresse crônico) quebra proteína e segura água. Dormir e caminhar são "treinos" de recuperação.' },
      { t: 'Deload natural', d: 'A troca de ciclo a cada 8 semanas, com exercícios novos e cargas a redescobrir, funciona como uma semana mais leve embutida.' },
    ],
    practice: [
      'Dias sem pesos = caminhada, boxe leve, mobilidade. Nunca um "treino extra" de peito.',
      'Se dormiu mal, faça o treino com a mesma carga e menos expectativa; não pule.',
      'Sinais de excesso: força travada, sono ruim, irritação, vontade zero de treinar. Uma semana a 70% da carga resolve.',
    ],
  },
];

// ═══════════════════════════════════════════════════════════════════
// FILOSOFIA — o jeito de pensar por trás do programa (rodada 37)
// ═══════════════════════════════════════════════════════════════════
export const PHILOSOPHY = {
  manifesto: [
    'Força primeiro. O corpo que buscamos é consequência de ficar mais forte nos movimentos certos.',
    'Menos, melhor. Três treinos curtos por semana, poucos exercícios, feitos por anos.',
    'A vida cabe. Jejum de manhã, jantar grande, fim de semana com amigos — o método serve à vida, não o contrário.',
    'Constância vence intensidade. Semanas comuns bem feitas transformam mais que dias heroicos.',
    'Medir o que importa. Cargas, cintura, média de peso e fotos — não sensações nem a balança de um dia.',
    'Identidade, não motivação. Você não "tenta" treinar segunda, quarta e sexta. Você é alguém que treina.',
  ],
  ideas: [
    {
      ico: 'i-lucide-gem',
      t: 'Estética de proporção',
      d: 'O objetivo não é ser enorme, é ser proporcional: ombros largos, peito superior cheio, cintura estreita, braços fortes. Uma referência simples: cintura no umbigo perto de 45% da altura e ombros bem mais largos que a cintura. Esse formato faz um corpo de 80 kg parecer maior que um de 95 mal distribuído.',
    },
    {
      ico: 'i-lucide-minimize-2',
      t: 'Minimalismo deliberado',
      d: 'Cada exercício do programa está lá porque entrega muito por pouco: supino inclinado, desenvolvimento, barra fixa, búlgaro, RDL. Tudo que foi tirado (dezenas de máquinas, séries de "acabamento", cardio longo) foi tirado porque custa recuperação e não muda o resultado.',
    },
    {
      ico: 'i-lucide-sun',
      t: 'Energia, não sacrifício',
      d: 'O programa espera que você se sinta bem: manhã em jejum produtiva e focada, treino curto e pesado que dá disposição, refeições grandes que satisfazem, sono em dia. Se está sofrendo, algo foi ajustado errado — dieta agressiva demais ou treino demais.',
    },
    {
      ico: 'i-lucide-infinity',
      t: 'Um jeito de viver, não um desafio de 12 semanas',
      d: 'Depois das 24 semanas nada "acaba": alternam-se fases de definição e de crescimento, com o mesmo estilo de treino e de comer. O que você constrói é um sistema que dura décadas — por isso o HUB guarda o histórico pra vida toda.',
    },
    {
      ico: 'i-lucide-notebook-pen',
      t: 'Números honestos',
      d: 'Anotar cada série, pesar de manhã, medir a cintura a cada duas semanas. Não pra se cobrar, e sim pra tirar a emoção da equação: os números dizem se a carga sobe ou se as calorias precisam de ajuste. Sem dados, você negocia consigo mesmo.',
    },
    {
      ico: 'i-lucide-shield',
      t: 'O guerreiro',
      d: 'Disciplina calma. Treinar nos dias marcados sem drama, comer com regra sem obsessão, aceitar semanas ruins sem abandonar. Força física como base de força de caráter: quem cumpre o combinado consigo mesmo três vezes por semana cumpre no resto da vida também.',
    },
  ],
  not: [
    { t: 'Não é bombar até a falha todo dia', d: 'Falha e volume extremo cansam mais do que constroem, principalmente em déficit.' },
    { t: 'Não é dieta de sofrimento', d: '2–3 refeições grandes, refeed semanal e fase de crescimento periódica. Fome constante é sinal de erro, não de mérito.' },
    { t: 'Não é cardio pra compensar', d: 'Cardio é saúde e passos; gordura sai pela comida.' },
    { t: 'Não é troca de treino toda semana', d: 'Novidade impede progressão. Repetir é o caminho.' },
    { t: 'Não é correr atrás do peso da balança', d: 'É correr atrás de cintura menor com carga maior.' },
  ],
  rules: [
    'Segunda, quarta e sexta: pesos. Sem negociar.',
    'Todo treino tem um alvo de carga ou repetição. Vá pra bater esse alvo.',
    'Jejum de manhã, refeição grande à noite. Proteína em todas.',
    'Caminhe todos os dias. Durma 7–9 horas.',
    'Pese-se de manhã, olhe a média. Cintura a cada duas semanas. Foto por mês.',
    'Um dia ruim não existe: existe a próxima refeição e o próximo treino.',
  ],
};
