# BACKLOG — HUB (sistema pessoal do Guilherme)

Memória oficial do HUB. O HUB é a instância própria do fork coringa
(marca `hub`, segmento `saude`): painel pessoal de treino/dieta/corpo
agora, infoprodutos na fase 2, atalhos pros negócios (CEVICO/LIFE) na
tela-hub. Worktree: ~/hub, branch `feat/hub-saude`.

## Decisões do Guilherme (25/08)
- Nome: **HUB**. Painel Negócios = atalhos bonitos (KPIs ao vivo = fase 2).
- Fase 1 = Saúde primeiro. Vendas por plataforma pronta (Hotmart/Kiwify)
  c/ webhook; infoprodutos = calculadoras/ferramentas. VPS própria no ar.
- Ele vai mandar uma PLANILHA com o treino e a alimentação dele →
  importar como fichas de treino + plano alimentar (seed do config).

## RODADA 15 — 31/08 ✅ ÍCONES 100% HUB + TREINO "1 EXERCÍCIO = 1 TELA" + NEGÓCIOS SEM CIRURGIA
Feedback dele 31/08 (print da VPS já na e7b2440): ícones CEVICO ainda
presentes (favicon principalmente); roletas maiores e mais à direita c/
respiros; nome do exercício em destaque ocupando ~80% da tela do mobile
(tela "fixa" no exercício); remover menções de cirurgia/agendamento no
HUB (negócios 100% coringa fica pra depois).

- **ÍCONES**: os 30 arquivos de ícone da RAIZ do public/ (apple-icon-*,
  android-icon-*, ms-icon-*, favicon-*, favicon-badge-* — o badge é o
  favicon c/ bolinha vermelha de notificação que o Chatwoot troca em
  runtime!) eram arte CEVICO — TODOS substituídos pela arte hub
  (gerados do square512 + variante badge via Chrome headless); root
  manifest.json → name HUB/grafite. Vale só nesta branch (CEVICO usa
  develop). Favicon 512 do head usa LOGO_THUMBNAIL (marca.rb já veste).
- **TREINO mobile**: roleta cresceu de novo (item 36px, selecionado
  19px, altura 108px); série virou "rótulo+✕ e chip à esquerda ·
  roletas GRANDES ancoradas à direita" (justify-between); nome do
  exercício text-lg extrabold em linha própria; chavinha maior
  (1.6rem); card hub-ex-card c/ min-height 78vh no mobile + scroll-
  snap proximity no scroller da página (só durante a sessão) — 1
  exercício ≈ 1 tela (medido: 85% do viewport), o scroll assenta no
  começo do card. Sem overflow horizontal (375px ok).
- **CIRURGIA/AGENDAMENTO fora do HUB**: showSurgeryHealth → isClinica
  (bloco Agenda de Cirurgias do Meu Painel some fora da clínica);
  38 substituições isClinica ? original : genérico no InicioPage
  (painel Agendamento→Captação, abouts/details/metas/cesto/pílulas do
  construtor/grupos de gráfico '🔪 Cirurgias'→'💰 Vendas', '% de
  agendamento'→'% de marcação', 'Agendamentos hoje'→'Marcações de
  hoje') — CEVICO fica byte-idêntica (ramo clinica); AgendaDashboard
  Core (pendência da rodada 1!) ganhou frase/isClinica: KPI Indicações
  via frase, bloco Cirurgias e barra Sala cirúrgica gateados, "próximos
  7 dias" sem a parte de cirurgia; HubPage desc sem "agenda"; saude.yml
  já cobria as frases (dedup de chaves duplicadas que criei sem ver).
- **CORPO alinhado** (pedido na sequência): "Registrar medidas" virou
  data em destaque (padrão do treino) + GRADE uniforme
  (.hub-measure-grid, minmax 5.8rem → 3 colunas no 375px; rótulo c/
  altura reservada de 2 linhas pra TODAS as roletas alinharem; roleta
  100% da célula; chip "última⤵" ou "1ª vez" com altura fixa) +
  observações e "✓ Salvar medidas" full-width no mobile. Detalhe:
  rótulo é flex (alinha embaixo) — texto embrulhado num span único
  senão o flex engole o espaço ("Pescoçocm").
- TESTADO local conta 3: Meu Painel do negócio c/ ZERO menções de
  cirurgia/agendamento (varredura no innerText), hero "Painel de
  Captação", treino mobile 85% viewport c/ snap, rolagem/chip ok no
  item 36px, ícones raiz servindo arte hub (badge conferido visual),
  Corpo c/ grade alinhada (tops idênticos medidos) e sem scroll-x.
  AGUARDA "pode subir".

## RODADA 14 — 31/08 ✅ MEU PAINEL ESSENCIAL (royal/laranja) + BOXE LIGÁVEL + DIETA CALCULADA
Pedidos dele 30/08: painel pré-configurado com o essencial (ciclos de
24 semanas, caixinhas de consistência c/ reagendado, metas de kcal,
projeções, elogio da semana completa, medidas e peso); omitir boxe de
todos até o admin liberar em Configurações (ambiente do HUB lá);
paleta AZUL ROYAL + LARANJA BRILHANTE c/ subtons; na Dieta, passar as
kcal → calcular proteína/carbo/gordura e metas por refeição c/ peso
CRU de carne.

- **Paleta do painel**: ROYAL #4169E1 · profundo #27408B · noite
  #111C3F · claro #8FA9F5 + LARANJA #FF8A00 · vivo #FF6B1A · claro
  #FFB25E (verde #30A46C só nas caixinhas de feito).
- **HealthHome reescrito**: HERO royal c/ badge laranja "Ciclo N"
  (conta de ciclos de 24 sem: cycleNumber/weekInCycle/cyclesDone —
  semana 25+ = ciclo 2; frase especial no 1º ciclo e "N ciclos
  completos" depois) + botão laranja do treino de hoje; CAIXINHAS DE
  CONSISTÊNCIA do ciclo (24 colunas × sessões planejadas: VERDE =
  feito no dia planejado · LARANJA = reagendado, ou seja feito noutro
  dia — automático comparando record_date × data planejada · VERMELHO
  = passou e não foi · cinza = a fazer; semana atual contornada;
  totais na legenda; tooltip por caixinha); ELOGIO da semana completa
  (vidro laranja, 4 frases rotacionando por semana, aparece quando os
  3 treinos da semana foram feitos); ALVOS recoloridos (peso-alvo
  royal, kcal laranja, proteína royal); HOJE sem card de boxe (salvo
  liberado); PROJEÇÕES: ritmo 30d, peso em 30d, CHEGADA AO ALVO (data
  estimada ≈ dd/mm + dias no ritmo atual, mín. de queda −0,1 kg/30d,
  teto 400 dias), kcal média × meta (Δ verde/vermelho), placar ▲▬▼;
  MEDIDAS E PESO: chips de cada medida c/ Δ vs medição anterior
  (semântica por medida: cintura caindo = verde, braço caindo =
  laranja) + curva royal c/ linha tracejada laranja do peso-alvo.
- **BOXE LIGÁVEL** (omitido de todos por padrão): health config ganhou
  features.boxing (sanitize_features, default false); settings_json
  expõe health_features (o menu lê do store); NOVO ambiente
  Configurações → HUB (settings/hub/Index.vue + rota
  hub_settings_index admin-only + item no menu de Configurações só no
  segmento saude) c/ chavinha iOS "Mundo Boxe" → salva via
  updateHealthConfig + refetch do settings (menu reage na hora).
  Escondido quando off: item Boxe do menu saúde, pílula Boxe do
  HealthPage, visão Boxe do dashboard, card Boxe do painel, e
  sessões/semana conta só musculação.
- **DIETA CALCULADA**: no editor Plano & metas, digitar as CALORIAS
  recalcula na hora proteína (1,8 g/kg do peso atual — cutting
  Warrior; fallback 30% kcal sem pesagem), gordura (25% kcal) e carbo
  (resto), e REDISTRIBUI kcal/P/C/G nas refeições mantendo as
  proporções que elas já têm (sem kcal = divisão igual) — tudo
  editável depois; no checklist da Dieta cada refeição mostra a
  EQUIVALÊNCIA da proteína em comida crua ("≈ 220 g de frango cru ·
  240 g de patinho cru · 9 ovos"; frango 23%, patinho 21%, ovo 6 g).
- TESTADO local conta 3: painel completo renderizado (ciclo 1 sem 22,
  55 no dia + 8 não foi da simulação, projeções −4,8/76,7, medidas c/
  Δ, curva royal), toggle do boxe ON→item no menu na hora→OFF→sumiu,
  kcal 2460→2000 recalculou 147P/56G/227C e refeições 570/1055/375
  proporcionais ✓, equivalências no checklist ✓ (editor cancelado sem
  salvar; bug de redeclaração latestWeight→pesoAtual corrigido).
  Sem migration. AGUARDA "pode subir" junto com 12 e 13.

## RODADA 13 — 30/08 ✅ CHAVINHA DE VARIAÇÃO + META POR SÉRIE NO VIDRO
Pedidos dele 30/08 (mesma conversa da 12): chavinha ativar/desativar
variação nos exercícios (barra ⇄ halter, máquina ⇄ halter…); sugestão
pra TODAS as séries seguindo os fundamentos; orientação "especial, com
fundo de vidro", destaque elegante — ele se importa muito com design.

- **Chavinha de variação**: prescrição ganhou `alt_tag` (variação B;
  sanitize_prescription aceita; editor ✎ tem os 2 campos "variação A/
  B" — preencheu os dois, o treino ganha a chavinha segmentada estilo
  iOS no cabeçalho do exercício). Trocar a chavinha RE-PREFILL as
  roletas com a última execução DAQUELA variação (lastSetsForTag
  busca no histórico inteiro pelo nome+tag salvo; registros antigos
  sem tag contam como variação principal), recalcula hint/alvos, e o
  registro salva a variação usada (out.tag) — carga de barra ≠ carga
  de halter, cada uma progride sozinha (verdict "first" na 1ª vez da
  variação).
- **Meta POR SÉRIE (setTargets no warrior.js)**: alvo carga×reps pra
  cada série pelos fundamentos — faixas (RPT/séries/rest-pause): topo
  de TODAS → +2,3 e reps no piso, senão mesma carga +1 rep até o teto
  (minis do rest-pause acompanham a carga da ativação no salto);
  independent_set: série que bateu o teto sobe sozinha; pirâmide/
  rest_reduction: mesma carga, reps do esquema; add_each_session:
  +1,1 em todas; extra/ficha: última execução +1 rep. Alvos caem na
  GRADE DE 0,5 kg (passo da roleta e das anilhas — sem 32,8 que a
  roleta não alcança).
- **Cartão de VIDRO (glassmorphism)**: hint + chips de alvo por série
  num cartão translúcido c/ backdrop-blur 14px, borda fina, brilho
  interno e sombra colorida — verde no dia a dia, OURO quando "meta
  atingida". Chips tocáveis: levar as roletas da série até a meta
  (applyTarget); série sem histórico mostra a faixa (não tocável).
  Chavinha e chips c/ micro-transições (scale no toque).
- TESTADO local conta 3: editor salvou A/B, chavinha ON halteres,
  vidro ouro, alvos conferidos na mão em TODOS os métodos (32,8→
  arredondado 33/30/27 ✓ RPT; rest-pause minis 17,8 seguindo ativação
  ✓), toque no alvo moveu roletas, barra → vazio "Primeira vez com
  barra", salvou tag="barra" verdict=first no banco, reabriu → barra
  lembrou 20×8 c/ alvo 22,5×4 e faixas nas séries sem histórico ✓.
  Teste apagado + config revertida (banco só sim). Sem migration.
  AGUARDA "pode subir" junto com a rodada 12.

## RODADA 12 — 30/08 ✅ ÍCONE DO HUB + ROLETA v2 (leve/Apple/em tudo)
Pedidos dele 30/08 (já usando as roletas na VPS, etiqueta 5140c43):
ícone do app estava CEVICO (tela de início do iPhone); "demorou pra
carregar, deixar leve"; roleta e infos maiores c/ respiros "ambiente
Apple"; roleta em TODOS os campos de número (Corpo etc.); teto fixo
(200 kg/220 cm, "não precisa ir até o infinito") c/ amortecedor do
iPhone nas pontas.

- **ÍCONE por marca**: o vazamento era o vueapp.html.erb — apple-touch
  -icons fixos em /apple-icon-*.png (arte CEVICO) + manifest.json da
  raiz (Android). Agora: marca c/ favicons_dir → apple-touch-icon
  180 + icon-192 + manifest.json DA PASTA DA MARCA + theme-color da
  cor primária; sem pacote (CEVICO) → tudo da raiz como sempre,
  theme-color azul padrão intacto. Gerados (Chrome headless achatando
  o logo_thumbnail 512 em quadrado grafite #0B1220 sem alpha, o iOS
  arredonda): apple-touch-icon.png 180 · icon-192 · icon-512 +
  manifest.json (name HUB, standalone, grafite) em brand-assets/hub/.
- **Roleta v2 (WheelInput)**: VIRTUALIZADA — só ~120 números em volta
  do valor no DOM (janela ±60 itens), espaçadores mantêm a altura;
  a janela NÃO segue o scroll ao vivo (mudar DOM no meio da rolagem
  faz o snap reancorar e derrapa — descoberto no teste) — congela,
  recentra no ASSENTAR e recoloca o scrollTop exato; overflow-anchor:
  none. DOM da sessão: ~4.700 → ~1.961 itens. TETO FIXO: carga 200 kg
  · reps 30 · medidas 220 cm · duração 180 · kcal 2.000 (régua
  infinita removida; roleta com fim = amortecedor nativo do iOS nas
  pontas; overscroll contain preserva o bounce). VISUAL: itens 32px,
  selecionado 17px bold, vizinhos 14px, fade suave, rounded-xl.
- **Treino estilo Apple**: card do exercício p-4/rounded-2xl/mb-4,
  nome text-sm, meta text-xs, séries gap-2, linha compacta que cabe
  nos 375px (label 2.6rem · chip 3.9rem · roletas 4.2/3rem · ✕) —
  conferido por screenshot (1ª versão quebrava a linha, apertada).
- **Roletas em tudo**: CORPO (11 medidas, passo 0,1 exato, prefill da
  última medição que JÁ EXISTIA desde a rodada 1 + chip "última
  medição ⤵" embaixo de cada roleta — lastBodyValue/copyLastBody);
  BOXE (duração passo 5 até 180 + rounds até 30); DIETA (kcal do
  extra, passo 10 até 2.000); PAINEL (peso-alvo passo 0,5). Editores
  de config (fichas, plano alimentar) continuam digitáveis de
  propósito (rolar até 2.460 kcal seria tortura).
- TESTADO local conta 3: salto 38 passos exato (49,5), rolagem
  seguinte após recentrar (74,5), chip treino (30,5×6) e corpo
  (81,5), boxe 30min via roleta, head do HTML c/ ícones da marca
  (curl), assets 200, Corpo salvo de ponta a ponta c/ peso rolado
  81,2 + medidas exatas 91,7 (registro de teste apagado; banco só
  sim). Sobre a demora: causa provável = 1º load pós-implantação
  (cache frio) + DOM das roletas v1 (agora 2,4× menor).
  AGUARDA "pode subir" (etiqueta nova, sem migration).

## RODADA 11 — 30/08 ✅ ROLETAS ESTILO iPHONE + EXERCÍCIO EXTRA DO DIA
Pedidos dele 30/08 (print do modo treino no celular): números das
caixinhas virarem roleta de rolar com o dedo ("roleta com ímã"), já
trazendo os valores pra só ajustar; e poder incluir exercícios
eventuais (crucifixo na máquina, panturrilha…) no treino de hoje,
salvando junto no histórico.

- **WheelInput.vue** (novo, na pasta health): roleta vertical com ímã
  via CSS scroll-snap (momentum nativo no iOS), 3 números visíveis
  (26px cada), fade em cima/embaixo (mask-image), linhas de mira,
  tocar num número rola até ele. v-model string compatível c/ toNum
  (vírgula decimal; '' = vazio, item "—" acima do 0 — série não feita
  continua não contando). Régua dinâmica: teto inicial
  max(prop, valor+20·step) e ESTICA sozinha ao chegar perto do fim
  (nunca muda os itens acima — o scroll não pula). Carga step 0,5
  máx 100 (estica) · reps step 1 máx 30.
- **Modo treino**: as duas caixinhas viraram roletas (largura igual,
  3,8/2,8rem — linha cabe nos 375px: 283px medidos); nascem na última
  execução (rodada 9 mantida); chip cinza "última vez" continua e
  tocar nele TRAZ A ROLETA DE VOLTA pro valor (copyPrev → watch).
  Instrução da sessão reescrita.
- **Exercício extra**: botão "➕ Adicionar exercício extra no treino de
  hoje" antes das observações/concluir → campo com datalist de
  sugestões (comuns fixos + toda a prescrição + histórico, menos os
  já na sessão) → card igual aos demais c/ chip dourado "extra" e ✕
  pra tirar. Última execução vem do histórico INTEIRO (lastAnySets:
  qualquer treino em que o nome apareceu) → roletas pré-preenchidas +
  chips + hint; 1ª vez = 3 séries vazias. Salva no MESMO registro com
  extra: true (backend já aceitava — data é permit! livre); verdict
  entra no placar; extra deixado em branco é filtrado do registro.
- TESTADO local conta 3 (banco = simulação): roletas nascem na última
  execução (conferido 3 exercícios vs chips), rolagem commita (30,5→33),
  chip devolve (33→30,5 c/ scrollTop exato), extra criado c/ 6 roletas
  vazias, preenchido 40×12/40×10 via roleta, salvo → banco: registro
  novo c/ [EXTRA] verdict=first, 3ª série vazia descartada, summary
  {tie:5, first:1}; nova sessão + mesmo extra → chips 40×12⤵/40×10⤵ e
  hint "Supere a última" ✓; ✕ removeu o extra ✓; mobile 375px 1 linha
  por série ✓. Registro de teste apagado (55 workouts, todos _sim).
  AGUARDA "pode subir" (etiqueta nova, sem migration).

## RODADA 10 — 28/08 ✅ MULTIUSUÁRIO: CONVIDADOS SÓ-SAÚDE C/ DADOS PRÓPRIOS
Pedido dele: dar acesso a outras pessoas SÓ ao mundo Saúde, cada uma
com registros e indicadores próprios, sem influenciar os dele.
Decisão dele: prescrição (programa Warrior + dieta) COMPARTILHADA;
execução/cargas/alvos por pessoa.

- **Isolamento por pessoa**: HealthController#scope agora filtra
  user_id = Current.user.id (todo registro já nascia com dono desde a
  rodada 1 — os dados dele ficaram intactos). KPIs/planilha/dashboards
  viram automaticamente "da pessoa logada". Upserts (dieta/corpo por
  dia) também por pessoa.
- **Kind novo `profile`** (1 registro por usuário, independente de
  data): peso-alvo e sessões/semana POR PESSOA. GET /health devolve
  `profile`; HealthHome grava o alvo via create_record kind=profile
  (goals saiu do config compartilhado).
- **Concessão 'health'**: entrou em Crm::AccessControl::CAPABILITIES e
  no AgentAccessModal ("Saúde (HUB)") — admin marca a área no modal de
  acessos do agente (mesma tranca allow-list do CEVICO; backend vale).
- **Convidado só-Saúde** (não-admin c/ grant health): menu = mundo
  Saúde SEMPRE (sem item HUB, sem Negócios — Sidebar.healthOnly);
  caiu fora do mundo → redirect pro /health/painel; HubPage esconde o
  card Negócios de não-admin (mundos = computed por isAdmin).
- **TESTADO ponta a ponta local**: convidado@hub.local /
  ConvidadoTeste@2026 (user 3 local, agent, grant ['health'] — MANTIDO
  no banco local pra ele testar): logou → HUB só c/ card Saúde ✓ →
  menu isolado sem HUB ✓ → painel ZERADO (0/3, sem peso) c/ prescrição
  compartilhada (2460 kcal · Treino C) ✓ → salvou peso 70,5 ✓ → banco:
  user 2 intacto (55/122/62/29) + user 3 c/ 1 body ✓ → relogou admin:
  painel dele 81,5 kg intacto, Negócios de volta ✓. Registro de teste
  do convidado apagado.
- CONVITE na VPS: e-mail de convite precisa de SMTP (não configurado)
  → criar usuário via console (comando pronto quando ele pedir).
- ⚠️ Nota: convidado NÃO-admin em rotas de negócios do dia a dia
  (conversas/CRM abertas a agents por design CEVICO) — menu esconde,
  mas endpoint responde se a pessoa souber a URL. Aceitável pro caso
  (convidados de confiança); trancar de verdade = rodada futura.

## RODADA 9 — 28/08 ✅ PAINEL DA SAÚDE + EDITOR DE EXERCÍCIOS + MARCA
Pedidos dele 26/08 (já usando NA VPS): cargas antigas JÁ PREENCHIDAS
pra salvar rápido (inverte parte da rodada 8 — mas o chip "última vez"
FICA, então antigo × novo continuam distinguíveis); adicionar/
substituir exercício e variação como tag; ícone próprio do HUB;
"Meu Painel" duplicado pro ambiente Saúde e remodelado.

- **Pré-preenchimento de volta**: buildTodaySets enche as caixinhas
  com a última execução; chip cinza continua ao lado como referência.
  Testado: 78,5×8 etc. já preenchidos ao abrir.
- **Editor de exercícios da prescrição** (✎ ao lado de cada Treino
  A/B/C): renomear (= substituição, histórico do zero — avisado na
  tela), campo VARIAÇÃO (tag halteres/barra/máquina — troca equipamento
  SEM perder histórico), remover (🗑/↩), + adicionar (método 'sets'
  3×8–12). Backend: sanitize_prescription ganhou 'tag'. Tag vira chip
  tracejado na sessão e "· tag" na planilha.
- **MEU PAINEL DA SAÚDE** (HealthHome.vue, /health/painel, item "Meu
  Painel" no menu; o mundo Saúde ENTRA por ele agora): hero semana/
  fase + "▶ Treino X de hoje"; 🎯 ALVOS (peso-alvo editável inline →
  config.goals novo c/ sanitize_goals; kcal/proteína de diet.targets;
  sessões/semana); ✅ HOJE (treino do dia por weekday, refeições N/M,
  boxe, pesagem da semana — cards clicáveis); 📶 SEMANA (sessões,
  placar ▲▬▼ calculado dos dados brutos, kcal média); 🦋 TRANSFORMAÇÃO
  (peso, Δ com sinal, ritmo 30d mínimos quadrados, falta pro alvo,
  projeção, curva das 24 pesagens).
- **MARCA HUB própria**: símbolo hub-and-spoke (6 nós verdes + núcleo
  sobre grafite) — public/brand-assets/hub/ (logo/logo_dark/thumbnail/
  favicons 16-32-96, Chrome headless + sips); hub.yml apontado. Login
  local já vestiu.
- TESTADO local conta 3 (sim): painel cheio (ritmo −4,7 kg/mês ✓,
  placar ▲4▬2▼3 ✓, alvo 80 → falta 1,5 kg ✓), editor salvou tag +
  exercício novo (conferido no banco), sessão pré-preenchida. Rastros
  de teste do config limpos. AGUARDA "pode subir" (etiqueta nova).
- 🐛 VPS pendente: "peso não salvou" — não reproduz local; aguarda os
  LOGS do POST create_record dele. (Na subida da VPS descobrimos
  migration faltando — db:migrate resolveu o painel de saúde.)
- FILA nova (pedidos 26/08): data do modo treino já vir com o DIA
  PLANEJADO do treino na semana; OBSERVAÇÃO POR EXERCÍCIO.

## RODADA 8 — 26/08 ✅ REGISTRO DE TREINO LIMPO (feedback dele)
Pedido: "selecionar a data e por o valor certo nas caixinhas; ver o
exercício, a carga antiga e a nova na MESMA visualização — está
bagunçado". Causa: caixinhas vinham PRÉ-PREENCHIDAS com a última
execução (antigo × novo indistinguíveis) + data escondida no canto +
semana não seguia a data.

- **Caixinhas nascem VAZIAS**: buildTodaySets agora devolve load/reps
  em branco + `prev` (última execução da série) + `range` (faixa da
  prescrição). Cada série vira UMA linha: rótulo · chip cinza
  tracejado "30,5×6⤵" (a última vez) · [carga] × [reps] · ✕.
  Placeholders cinza = última vez (ou faixa na 1ª vez). TOCAR no chip
  copia o valor pras caixinhas (copyPrev) — aí é só ajustar. Ficha
  avulsa (startSession) e addSet seguem o mesmo formato.
- **Data em DESTAQUE** no topo da sessão (caixa própria "📅 Data do
  treino" + dica "treinou outro dia? troque a data") e a **SEMANA
  segue a data** (watch → weekOf): registro retroativo cai na semana
  certa do programa, não na semana de hoje. Selo verde "Semana N" ao
  lado da data.
- **Backend**: update_record aceita record_date opcional (corrigir a
  data de um treino já salvo); crm.js updateHealthRecord ganhou o 3º
  parâmetro; saveSession passa a data no caminho de update (upsert
  por treino/semana continua — nada duplica).
- **Mobile 375px**: linha da série compactada (gap-1, larguras 3/4/
  3.8/2.8rem, sem textos "kg"/"reps" — o formato é ensinado na
  instrução) pra caber INTEIRA numa linha no celular da academia.
- TESTADO conta 3 (banco = simulação): chip copia ✓ (30,5/6),
  placeholders ✓ (27,5/24,5), data 10/08 → Semana 19 ✓, save semana
  21 criou registro certo (só exercício preenchido, demais skipped,
  sem vazar prev/range) ✓, reabrir+salvar ATUALIZOU o mesmo registro
  (id 286) c/ data corrigida 25/08 e verdict progress (31>30,5) ✓,
  toast "0 de 1" no empate ✓, mobile 1 linha por série ✓. Registro de
  teste apagado (55 workouts, todos _sim).

## RODADA 7 — 26/08 ✅ SIMULAÇÃO 20 SEMANAS + PROTOCOLO DE MEDIDAS
Ele passou as 12 medidas REAIS (26/08, protocolo relaxado) e pediu
dados fictícios no sistema local pra ver dashboards cheios + projeção.

- **Protocolo de medidas oficial** na aba Corpo: MEASURES virou o
  protocolo dele — peso, cintura umbigo, cintura estreita, quadril,
  peito, braço D/E (RELAXADO), coxa D/E (meio virilha-joelho),
  pescoço, ombros escapular — c/ nota do protocolo na tela. Baseline
  REAL dele: 92,4 kg · 104 · 96 · 108 · 109 · 41,5/42,5 · 59,5/58 ·
  40 · 129 (gravado no script).
- **db/seeds/hub_sim_20_semanas.rb** (SIM=apply | SIM=clean):
  · apply = APAGA registros, start_date → 2026-04-06 (20 sem atrás) e
    popula: 55 treinos (progressão por exercício via tabela LOADS
    início→fim, RPT −10%/série, reps subindo na faixa, ~8% sessões
    perdidas e dias ruins, Random.new(42) determinístico), 62 corpos
    (peso 3×/sem c/ ruído, curva cutting 12 sem −6,8 → growth 4 sem
    +0,2 → cutting 4 sem −4,3 = 92,4→81,5; medidas completas a cada
    4 sem interpoladas baseline→GOAL pela fração de perda), 122 dias
    de dieta (85% aderência, horários reais ±25min, refeed sáb +600,
    growth +600/dia sem 13-16), 29 boxes (ter/qui, 20→40min). Tudo
    marcado _sim=true.
  · clean = remove _sim, start_date → segunda da semana atual, recria
    a baseline real de 92,4 kg. RODAR QUANDO ELE FOR COMEÇAR DE VERDADE.
- **GOAL 20 semanas** (no script): 81,5 kg · cintura umbigo 92 ·
  estreita 87 · quadril 101,5 · peito 105 · braços 40,8/41,6 · coxas
  57,5/56,2 · pescoço 37,8 · ombros 126,5; força ex.: supino inclinado
  60→78, RDL 80→125, militar 40→54, barra fixa +10→+24.
- Limites do show: workouts/diets/bodies → 200 (20 semanas cabem).
- VERIFICADO: Transformação completa (peso caindo × força subindo ×
  kcal zigue-zague c/ refeeds), insights certeiros (recorde da semana,
  estagnação real detectada no Afundo reverso, −4,7 kg/mês), heatmap
  denso verde/roxo, aderência S1-S21 c/ vales, evolução Supino 60→78
  c/ e-1RM, placar semanal, grade de mini-gráficos POR exercício.
- ⚠️ ESTADO ATUAL DO BANCO LOCAL = SIMULAÇÃO (não é dado real dele).

## RODADA 6 — 26/08 ✅ DASHBOARD PRO: VISÃO GERAL + e-1RM + INSIGHTS
Proposta minha, ele aprovou AS 4: e-1RM/recordes + Transformação +
constância/aderência + insights/balanço. Tudo em HealthDashboard.vue.

- **Pílula nova 🎯 VISÃO GERAL** (padrão do dashboard):
  · 🧠 Insights automáticos (regras sobre os dados): recorde da semana,
    estagnação 3 sessões s/ superar e-1RM (sugere deload −10%),
    tendência do peso 30d (cutting funcionando/atenção), proteína <80%
    da meta 3+ dias/7, sessão planejada faltando na semana (seg/qua/sex
    já passados), melhor semana de volume. Max 6.
  · 🦋 A Transformação: peso (azul, y) × força e-1RM média (verde, y1)
    × kcal médias (ouro pontilhado, eixo oculto) por semana-calendário
    (12 sem, spanGaps) + tira de PROJEÇÕES: ritmo kg/mês do peso
    (fitSlope 30d, mínimos quadrados) c/ "em 30 dias ~X kg", ritmo da
    força, recordes da semana.
  · 🟩 Mapa de constância: heatmap 24 semanas × 7 dias (verde musc,
    roxo boxe, meio-a-meio ambos, contorno = hoje).
  · 📅 Aderência ao plano: % das 3 sessões/semana feitas (área, S1..).
- **e-1RM (Epley: carga × (1 + reps/30))** como medida de força real:
  dataset pontilhado no gráfico de evolução por exercício + 🏅 QUADRO
  DE RECORDES (tabela por exercício: carga máx, e-1RM, data, 🏅 se
  recorde nos últimos 7d; ordenado por e-1RM).
- **⚖️ Balanço muscular**: volume por grupo via regex no nome do
  exercício (empurrar/ombros/puxar/braços/pernas/core; crucifixo
  inverso vai pra puxar via lookahead) — barras c/ % e tonelagem.
- KPI Progressões e placar continuam do cálculo bruto (rodada 5).
- TESTADO conta 3 c/ seed marcado _test (8 registros: 2 treinos S1,
  3 pesos, 2 dietas, 1 boxe): insights certeiros ("Semana 1 em dia:
  2 de 3 previstas até hoje" numa quarta ✓), e-1RM conferido na mão
  (RDL 60×8 → 76 kg ✓), transformação/projeção (−3,8 kg/mês → ~89 kg),
  heatmap e aderência 67% S1 ✓. Teste apagado (resta só o peso real).

## RODADA 5 — 25/08 ✅ BOXE + DATAS RETROATIVAS + DASHBOARD COMPLETO
Pedidos dele: aba de boxe c/ sequências pra praticar + tempo de treino;
registrar dados passados com a data; gráfico pra TODO indicador
(histórico de carga por exercício, progressão, volume).

- **Kind novo `boxing`** (model KINDS + controller: show devolve
  boxings, create_record cria múltiplos por dia como workout; config
  ganhou sanitize_boxing → boxing.sequences).
- **Aba Boxe** (/health/boxe, item no menu Saúde): registrar treino
  (DATA + duração min + rounds + chips das sequências praticadas +
  obs); repertório de sequências em cards grandes (passos em destaque
  pra praticar lendo) c/ editor + legenda 1 jab · 2 direto · 3 hook
  esq · 4 hook dir · 5/6 uppercuts; histórico c/ delete. SEED: 8
  combos clássicos (b1–b8, numeração clássica) no seed + aplicado.
- **DATAS RETROATIVAS em tudo**: campo Data no boxe, no Corpo
  (medidas), no modo treino (sessão), e a Dieta ganhou SELETOR DE DIA
  (marca dias passados; upsert por data já existia; horário real da
  refeição só grava quando o dia = hoje). KPIs treinos-7d/sequência
  agora contam musculação + boxe.
- **Dashboard 3 visões** (Treino | Boxe | Dieta):
  · Treino +3 seções: 📶 Placar de progressão por semana (▲▬▼
    CALCULADO dos dados brutos — cada treino vs a ocorrência anterior
    do MESMO treino, via exerciseVerdict; funciona pra planilha e
    runner; KPI Progressões agora vem daí) + 🔁 Séries e reps por
    semana (2 eixos) + 🗂 Carga por exercício — histórico completo
    (mini-gráfico de linha/área POR exercício registrado, grade 3
    colunas c/ última carga).
  · Boxe: KPIs (sessões, tempo total em h, média/sessão, rounds) +
    ⏱ tempo por dia (área) c/ rounds (linha, 2 eixos, 30d) + 🏔 horas
    acumuladas + ranking das sequências mais praticadas.
- TESTADO conta 3 (dark mode ok): treino de boxe salvo com data
  RETROATIVA 24/08 (30min/6 rounds/b1+b3 conferido no banco), KPIs e
  gráficos do boxe reagiram, 6 seções do dashboard treino renderizam.
  Teste apagado no final.

## RODADA 4 — 25/08 ✅ HUB TELA CHEIA + PLANILHA DAS SEMANAS + DASHBOARDS
Pedidos dele: HUB sem barra lateral; treino em formato planilha
(A|B|C|Bônus × semanas); dashboards de linha/área (treino e dieta).

- **HUB tela cheia**: Dashboard.vue esconde o NextSidebar quando a rota
  é hub_home — a barra só existe DENTRO de um mundo.
- **📋 Planilha das semanas** (HealthPage, aba Treino): abas A (sem
  1–8) | B (9–16) | C (17–24) | Bônus (8 extra); linhas = exercícios
  agrupados por Treino A/B/C do ciclo (nome + faixas), colunas = as 8
  semanas (semana atual destacada •), lacuna = texto "60x6 54x7 48x8"
  (vírgula ok; separador espaço / · ;) parseado em séries; salva no
  blur. 1 REGISTRO POR TREINO/SEMANA: célula acha o registro
  (program/cycle/session/week) e faz update; se não existe, cria com a
  DATA PLANEJADA (start_date + semanas + dia da sessão — testado: S1
  Treino A → 2026-08-24). O modo treino (runner) também passou a
  UPSERTAR pela mesma chave — planilha e runner escrevem no mesmo
  registro, nada duplica.
- **Dashboard da Saúde** (HealthDashboard.vue, rota /health/dashboard,
  item "Dashboard" no menu Saúde) — chart.js linha/área:
  · TREINO: KPIs (treinos, volume total em t, progressões, semana
    N/24) + Volume por semana (área Total + linhas A/B/C, eixo S1–S24)
    + Evolução por exercício (carga máx linha + volume área, 2 eixos)
    + Acumulado do programa (área "montanha").
  · DIETA: KPIs (kcal média 7d, proteína média 7d, aderência 7d, dias)
    + Calorias/dia e Proteína/dia (área vs linha tracejada da meta,
    21 dias) + tabela Refeições × dias (14d): ✓ com HORÁRIO REAL da
    marcação (toggleMeal agora grava meals_done_at {id: "HH:MM"};
    horário cinza = o previsto do plano).
- TESTADO conta 3: hub sem barra ✓, célula S1 gravou 60x6 54x7 48x8
  com data 24/08 ✓, volume 1,1 t no KPI ✓, gráficos ok ✓, refeições
  ✓ 15:08/15:09 na tabela ✓. Dados de teste apagados de novo (peso
  93 kg preservado). NOTA: célula do Bônus registrada via runner não
  aparece na grade (runner sem week no bônus) — refinar depois.

## RODADA 3 — 25/08 ✅ TELA HUB + MUNDOS ISOLADOS (working tree)
Desenho dele (1 Negócios · 2 Saúde · 3 futuro) virou a porta de entrada:

- **HubPage** (/hub, rota hub_home): cards numerados 1 Negócios
  (azul→roxo) · 2 Saúde (verde) · 3 "Em breve" (tracejado). Escolher
  grava hub_mode no localStorage + dispara evento window 'hub:mode'.
- **Sidebar com mundos** (só no segmento saude; CEVICO/LIFE intactos):
  modo 'saude' → menu FIXO isolado (HUB · Treino · Dieta · Corpo,
  sem "Personalizar menu"); modo 'negocios'/nenhum → menu normal COM
  item HUB no topo e SEM o item Saúde (o item avulso da rodada 1 foi
  removido — virou código morto). Primeira entrada sem modo escolhido
  → redirect automático pra /hub (onMounted do Sidebar).
- **Rotas por aba da Saúde**: /health (treino) · /health/dieta ·
  /health/corpo (meta.healthTab) — o item certo acende no menu;
  HealthPage sincroniza a pílula com a rota (goTab navega).
- TESTADO conta 3: redirect automático pro /hub ✓, mundo Saúde
  isolado ✓, Dieta pelo menu abre a aba certa ✓, HUB → Negócios volta
  ao Meu Painel com menu completo (HUB no topo, sem Saúde) ✓.
  localStorage é por origem (3001 ≠ 3000) — não vaza pro CEVICO local.

## RODADA 2 — 25/08 ✅ MOTOR WARRIOR construído e testado (working tree)
Planilha dele (Warrior_Shredding_24_Semanas_Ciclos_Separados.xlsx em
~/Downloads) + especificação funcional viraram o motor de progressão:

- **Seed db/seeds/hub_warrior.rb** (rodado na conta 3; re-rodável):
  programs em agenda_config['health'] — Warrior 24 semanas (3 ciclos ×
  A/B/C, start_date 2026-08-24 = semana 1 do log da planilha, com
  descanso/aquecimento/regra de progressão POR exercício) + Rotina
  Bônus (RPT exato 5/6/8 independent_set, Pirâmide padrão 12/10/8/6
  rest_reduction, Rest-Pause) + dieta do método (cutting 93 kg →
  2.460 kcal · P164 C246 G90, 3 refeições Massive Meal Option
  [divisão por refeição = SUGESTÃO minha, editável], notes com
  jejum/refeed/growth phase).
- **PRESCRIÇÃO ≠ EXECUÇÃO**: prescrição no config (sanitize_program/
  cycle/prescription no HealthController — CRÍTICO: update_config
  preserva programs, senão a UI apagaria o seed); execução =
  hub_health_records imutáveis (data: program_id/cycle_id/session_key/
  week/exercises c/ sets{load,reps,kind}/verdict + summary).
- **warrior.js** (motor): semana/ciclo por start_date; próximo treino
  A→B→C; buildTodaySets pré-preenche com a ÚLTIMA execução;
  exerciseVerdict (progress/tie/regress série a série — sobre séries
  PREENCHIDAS, senão linha vazia = regressão falsa); targetHint por
  progression_type (top_of_ranges → "🎯 Meta atingida, suba +2,3 kg";
  abaixo do topo → "Supere a última: N reps na Xª série com Y kg";
  independent_set 3ª→2ª→1ª; rest_reduction 60→30 s; add_each_session
  barra fixa +1,1 kg); sessionSummary + summaryPhrase.
- **HealthPage v2**: card do programa (semana N de 24 · ciclo · chips
  A/B/C c/ "▶ próximo" + alternador 24 semanas/Rotina Bônus), sessão
  com chip do método (RPT azul/Rest-Pause roxo/Pirâmide ouro),
  ⏱ descanso + 🔥 aquecimento, "Última vez", meta do dia, rótulos
  Ativação/Mini nas séries; histórico com placar ▲n ▬n ▼n; fichas
  avulsas viraram seção recolhida (cardio/viagem); dieta mostra notes.
- **TESTADO ponta a ponta conta 3**: 1ª sessão (hints "primeira
  sessão"), 2ª sessão com 6/7/8 no topo → "🎯 Meta atingida" correto
  nos 3 casos, "Supere a última: 8 reps na 2ª série com 14 kg" e
  "6 reps na mini 2 com 10 kg" corretos; placar ▲2 ▬2 ▼1 exato;
  próximo pulou de A→B sozinho; dieta com barras reagindo ao checklist.
- Registros de TESTE apagados no final; semeado peso real 93 kg
  (25/08). Histórico começa limpo pra ele.
- FALTA (fila): timer de descanso na sessão; comparação por SEMANA
  (gráfico 24 semanas do exercício já dá pela evolução de carga);
  marcar sessão da rotina bônus alternando bloco automaticamente.

## RODADA 1 — 25/08 ✅ construída e testada (working tree, NÃO commitada*)
*exceção: o commit de merge 2d499b32c que criou a base da branch
(develop 785fa58ca + feat/sistema-coringa 9f3cad62a; 3 conflitos
resolvidos mantendo os dois lados — cards ricos 140-145 + terminologia
frase/termo; AgendaDashboard ficou com a versão enxuta da 136 + termo()
no subtítulo; pendência anotada: portar terminologia pro
AgendaDashboardCore.vue).

- **Marca `hub`** (config/brands/hub.yml → segmento saude; logos
  provisórios da CEVICO; cores grafite #0B1220 + verde #10B981).
- **Segmento `saude`** (config/segmentos/saude.yml): treino/aluno/
  treinador na terminologia, modalidades Treino/Cardio/Avaliação física
  (keys estáveis avaliacao/retorno/exames), jornada do aluno (funil de
  infoproduto), financeiro com categorias pessoais+produto, guardrails
  e prompts genéricos herdados do empresa.yml.
- **Módulo Saúde v1**: migration 20260825000001 (hub_health_records:
  kind workout|diet|body + data jsonb + record_date); model
  HubHealthRecord; HealthController (show/create_record/update_record/
  delete_record/update_config; dieta e corpo = upsert por dia; treino
  repete; config em agenda_config['health'] sanitizado; capability
  'health' fora da lista concedível → só admin); rotas crm/health;
  crm.js (5 métodos); HealthPage.vue (abas Treino/Dieta/Corpo, KPIs
  treinos-7d/sequência/peso/variação-30d, fichas + registro com séries
  pré-preenchidas do último treino, evolução de carga MiniBars,
  checklist de refeições + macros vs metas + extras, medidas + curva de
  peso); item "Saúde" na Sidebar (segmentoId==='saude' && canSee).
- **Testado ponta a ponta conta 3 local**: login HUB, Meu Painel com
  "Treinadores/Treinos agendados", ficha criada, treino registrado
  (62,5 kg com vírgula OK — toNum no front + tr(',','.') no sanitize),
  KPIs reagiram (1 treino, sequência 1, peso 82,5 kg), evolução e
  medidas OK. Lição: HMR do vite não pegou edição com o mount do
  Docker — recarregar a página após editar componente.

## Ambiente local (convive com o da CEVICO)
- `cd ~/hub && docker compose up -d rails sidekiq vite` — projeto
  docker "hub", volumes próprios (banco chatwoot_dev do projeto hub).
- Portas: rails 3001 · vite 3037 · postgres 5433 · redis 6380 ·
  mailhog 1026/8026 (docker-compose.override.yaml, NÃO commitado —
  listado no info/exclude do repo). CEVICO local segue nas portas padrão.
- http://localhost:3001 — atendimento@guilhermecorder.com.br /
  HubTrocar@2026 (provisória, trocar) — conta HUB = id 3.
- Vite reinstala pnpm a cada restart (entrypoint) — demora alguns minutos.

## FILA (próximas rodadas)
1. ~~Importar a planilha dele~~ ✅ rodada 2 (motor Warrior completo).
2. ~~Tela HUB~~ ✅ rodada 3 (mundos isolados). REFINO futuro: dentro de
   Negócios, cards/atalhos pra CEVICO e LIFE em produção (deep links
   com a marca de cada um) + nome do mundo 3.
3. Timer de descanso na sessão de treino (3 min RPT / 10-20 s
   rest-pause / 30-60 s pirâmide).
4. Marca de verdade: logo/favicons do HUB (brand-assets/hub/).
5. Fase 2 infoprodutos: webhook Hotmart/Kiwify → liberar acesso;
   páginas/calculadoras como produto.
6. KPIs ao vivo de CEVICO/LIFE no painel Negócios (fase 2 combinada).
7. Pendência técnica: portar terminologia por segmento pro
   AgendaDashboardCore.vue; rebasear quando feat/sistema-coringa
   entrar na develop.

## Regras
- NUNCA commit/push/merge sem "pode subir" (mesma regra CEVICO).
- Telas novas reusam o kit (DashKpi, MiniBars, PeriodRuler, pílulas).
- Nada aqui encosta nas branches/deploys da CEVICO e da LIFE.
