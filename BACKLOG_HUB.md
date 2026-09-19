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

## SUBIDA 19/09 — RODADAS 24–28: "pode subir" → commit c703b888ea na
feat/hub-saude → push → docker-build disparado por workflow_dispatch
(run 35466594296) VERDE em ~4 min → **etiqueta `c703b88`** (sem
migration: os kinds novos são strings no jsonb). Falta ele colar a
etiqueta na Imagem do web + sidekiq no EasyPanel e Implantar os dois.
Depois, na VPS: Boxe → Repertório → "Importar biblioteca" (1 toque) e,
se quiser, Rotina → "Dia útil campeão". Nota de ambiente: o husky do
repo está quebrado (.husky/_/husky.sh ausente) → commit/push com
--no-verify; o workflow só roda sozinho na develop, na feat precisa
disparar (feito via API com a credencial do git do Mac).

## SUBIDA 18/09 — RODADAS 20–23: "subir tudo" → commit 1681fc7998 na
feat/hub-saude → push → docker-build (run 35406047125) VERDE →
etiqueta `1681fc7` (sem migration). Implantada? confirmar com ele.

## RODADA 28 — 19/09 ✅ EDITOR DE TREINO DE BOXE NO PADRÃO DO PLANO DE LUTA (working tree, NÃO subida)
Feedback dele 19/09 (prints do "Novo treino" e do plano de luta no
celular): "melhorar o enquadramento — espaços de preenchimento mais pra
direita, títulos maiores; opções pré-selecionáveis no montar treino com
'outro' pra escrever o que quiser; mais parecido com o plano de luta".
- **Kit**: .hub-form/.hub-form-row = rótulo em caixa alta à ESQUERDA
  (6,2 rem no celular · 8 rem no notebook) e campo à DIREITA ocupando o
  resto; .hub-sec-title subiu de 14 → 16 px; .hub-bump (−/+) e
  .hub-other (campo curto "outro").
- **Editor "Novo treino / Editar treino"** (boxWkForm) reescrito: cabeçalho
  .hub-sec com nº de blocos e minutos; Nome/Descrição em linhas de
  formulário; blocos em ACORDEÃO (1 aberto; fechado mostra ícone + nome ·
  ≈ min · formato · nº de sequências); dentro: Tipo em tags com ícone
  (pré-selecionável), Nome, Formato = segmentado "Tempo corrido | Rounds"
  (setBlockMode zera o outro modo), Minutos em chips 3/5/8/10/12/15 +
  "outro", Rounds −/+, Round em chips 1:00/1:30/2:00/2:30/3:00 + "outro"
  (segundos), Descanso em chips 15/30/45/60/90 s + "outro", O que fazer,
  Sequências (SeqPicker); subir/descer/remover como tags no rodapé do
  bloco; "+ bloco" abre o novo já expandido; Salvar em laranja.
- **Plano de luta**: cabeçalho do formulário virou linhas Nome/Atleta/
  Adversário/Rounds/Round/Descanso (mesmos chips + "outro"), rótulo
  "Rounds" antes do acordeão, Estratégia como linha; valores digitados em
  "outro" viram número no salvar.
## RODADA 27 — 19/09 ✅ "MAIS APPLE": SEM EMOJI, SEÇÕES COM CONTRASTE, BOTÕES DE VISUALIZAÇÃO, ENQUADRAMENTO (working tree, NÃO subida)
Feedback dele 19/09 (prints do repertório, do construtor por rounds e do
cardio): "está ficando super interessante; agora mais bonito e organizado
— pense como a Apple; histórico em lista é desagradável (sanfona ou
seção própria); o montar por rounds virou salada de frutas; botões de
visualização pra ter controle e limpeza; emojis assim ficam com cara de
feito por IA, pouco autêntico — vale pra TUDO; mais contraste entre as
seções; enquadramento otimizado pra celular e notebook, nada solto".

- **Kit de organização** (_hub-glass.scss, rodada 27): .hub-sec
  (cabeçalho de seção: quadrado com ÍCONE DE LINHA + título + subtítulo +
  ações à direita), .hub-label (rótulo em caixa alta com régua), .hub-seg
  (controle segmentado = botões de visualização; -full ocupa a largura),
  .hub-list/.hub-row/.hub-row-date/.hub-month (lista agrupada por mês,
  estilo iOS), .hub-tag (chip com ícone de linha; is-on/is-soft),
  .hub-grid-2/3/4 (grades FIXAS: 1 coluna no celular, 2/3/4 no notebook),
  .hub-acc (acordeão), .hub-zone, .hub-field (campo com largura fixa),
  .hub-h-ico (ícone dentro de título).
- **ZERO emoji em títulos e chips**: todos os h1/h2/h3 das 4 telas
  (HealthPage 19, HealthHome 5, HealthDashboard 19, RoutinePage 4)
  trocaram o emoji por ícone lucide (i-lucide-*); listas de dados
  (GOALS, MEASURE_DEFS, CARDIO_TYPES, SEQ_CATEGORIES, FIGHT_INTENTS,
  ROUTINE_CATS, BLOCK_TYPES, itens das celebrações) ganharam `ico`
  (lucide) — o campo `icon` (emoji) ficou só por compatibilidade. 117
  nomes de ícone conferidos contra o pacote @iconify-json/lucide.
  Pílulas do topo da tela de treino, da Rotina (Dia/Semana/Mês/Ano) e
  do assistente viraram .hub-seg. "🔥 HOJE" → "HOJE"; celebração usa
  ícones (troféu, régua, party-popper) no medalhão e nos cartões.
- **Botões de visualização**: Treino = Treinar · Planilha · Histórico
  (programa + cartões + fichas em Treinar; planilha sozinha; evolução de
  carga + histórico em Histórico); Cardio = Registrar · Histórico; Boxe =
  Treinar · Planos de luta · Repertório · Histórico.
- **Histórico virou seção própria** (treino, cardio, boxe): 3 tiles de
  estatística (sessões/minutos/rounds ou km) + lista agrupada por MÊS com
  badge de data (dia/mês), título, detalhe e ✕ — nada de lista corrida
  embaixo de tudo.
- **Construtor do professor**: cabeçalho .hub-sec, 4 controles em grade
  fixa (rounds −/+ · tempo 2:00/2:30/3:00 · descanso · aquecer/calma),
  rounds em ACORDEÃO (1 aberto por vez; fechado mostra foco · tipo · nº
  de sequências) e o **SeqPicker.vue (novo)**: só as sequências
  ESCOLHIDAS aparecem como chips; "+ sequência" abre UM painel com abas
  por etiqueta (contagem), busca e linhas nome · passos · quando usar;
  "aplicar este round aos demais". O mesmo seletor entrou no plano de
  luta (rounds em acordeão, intenções como .hub-tag com ícone) e no
  editor de blocos (adeus 30 chips repetidos).
- **Cardio**: tipos em grade FIXA 2×/4× com ícone de linha (cartão
  .hub-cardio-type), tempo e intensidade em .hub-tag lado a lado (grade
  2), data/km/observação em grade 3 com campos de largura fixa.
- **Repertório**: filtros como .hub-tag com ícone e contagem; etiqueta
  no cartão como chip suave; "Quando usar" em negrito sem emoji.
- **Celular** (testado a 375px): ações do .hub-sec descem pra 2ª linha
  (título nunca espreme), .hub-seg-full com 4 itens cabe sem cortar
  ("Planos de luta" → "Planos"), Rotina/Dia empilha lista + linha do
  tempo (grade só no notebook). Notebook: grades fixas 2/3/4.
- TESTADO local: Treino (Treinar/Planilha/Histórico agrupado por mês c/
  badge de data), Cardio (grade 4 de tipos com ícone, tags de tempo/
  intensidade, histórico com tiles), Boxe (4 visualizações; professor com
  acordeão + SeqPicker com abas/busca; plano de luta com intenções em
  tags e rounds em acordeão; repertório com filtros-tag; histórico 29
  sessões/863 min/169 rounds agrupado por mês), Painel e Análises com
  ícones de linha nos títulos, Rotina com pílulas segmentadas.
- 🐛 corrigidos no caminho: título .hub-sec-title invisível em bloco
  escuro (color: inherit); pílulas de descanso estourando (flex-wrap).
- FILA: ainda há emojis em TEXTOS corridos e alerts (useAlert) — ele
  pediu "em tudo"; próxima passada: alerts, textos de ajuda, HubPage
  (mundos) e HealthDashboard tiles.
## RODADA 26 — 19/09 ✅ SITUAÇÃO NO PAINEL + CARDIO + MOLDURAS + BOXE (ETIQUETAS · PROFESSOR · PLANO DE LUTA) + ROTINA (working tree, NÃO subida)
Pedido dele 19/09 (print do Treino, "está ficando ótimo"), 7 pontos:
1. "treino atual, semana atual" no painel pra se situar → linha 📍 no
   hero da HealthHome: nome do programa · Semana X de Y (chip laranja) ·
   próximo Treino K · dia. Linha "Semana:" ganhou "🏃 N min de cardio".
2. Ambiente de CARDIO pré-configurado → aba Cardio (rota /health/cardio,
   item na sidebar, pílula na tela de treino): tipo em cartões
   (caminhada, corrida, bike, boxe, elíptico, natação, corda, escada,
   remo, futebol, outro) + tempo em chips (10/15/20/30/45/60 ou digitar)
   + intensidade (leve/moderado/forte) + data, km e observação opcionais;
   "3 toques e pronto". kind novo `cardio`; painel "últimos 30 dias por
   tipo" (barras) + lista dos últimos.
3. Moldura em TODOS os treinos, o da vez laranja → .hub-session-card
   (borda royal 1,5px + sombra) nos cartões A/B/C; o próximo segue
   laranja pulsando.
4. Boxe · PROFESSOR "cria o treino em rounds" → botão 👨‍🏫 Montar por
   rounds: nome, nº de rounds (−/+), tempo do round (2:00/2:30/3:00),
   descanso (30/45/60/90 s), aquecer/calma em min, e por round: tipo
   (sombra, técnica, sequências, saco…), foco, instrução e sequências →
   "Gerar treino" cria os blocos (1 por round, `rest_after` = descansa
   ANTES do próximo bloco, como entre rounds) e abre no editor normal
   pra revisar/salvar. Cronômetro ganhou a fase `rest_after` (tickBox +
   boxPct + textos), tipo de bloco "🔔 Round". Sanitize aceita rest_after.
5. Boxe · SEQUÊNCIAS com etiquetas "quando usar" → categoria (⚔️ ataque,
   ↩️ contra-ataque, 🌀 esquiva, 🛡 defesa/bloqueio, 👟 movimentação, ➡️
   aproximação, ⬅️ saída, 🤼 clinch) + campo "quando usar" no editor da
   sequência; chips de filtro por etiqueta com contagem; cartão mostra a
   etiqueta e "⏱ Quando usar"; 📚 Importar biblioteca traz 25 sequências
   prontas (SEQ_LIBRARY no warrior.js) sem repetir nomes. Sanitize:
   category/when; limite 150 sequências.
6. Boxe · PLANO DE LUTA → seção 🥇: rounds (−/+ até 15), tempo (2:00/
   3:00), descanso (60/90), nome/atleta/adversário; por round: INTENÇÃO
   (🔍 estudar, 🔥 pressionar, ↩️ contra-atacar, 📏 distância, 🎯 corpo,
   🏁 definir, 🧘 recuperar, ♻️ ritmo) + sequências do repertório (filtro
   por etiqueta) + observações; estratégia geral. kind novo `fight_plan`
   POR PESSOA (sanitize_fight_plan). Cartões dos planos c/ resumo dos
   rounds; ▶ Treinar este plano = fightPlanToWorkout → sessão guiada
   round a round no cronômetro (descanso entre rounds), registra como boxe.
7. ROTINA (item novo na sidebar e na barra de abas; /health/rotina;
   RoutinePage.vue novo; kind `routine` 1 por pessoa, salva sozinha 0,7 s
   após mexer, "salvo ✓ hh:mm"): pílulas Dia · Semana · Mês · Ano.
   · DIA: dia da semana (hoje marcado), blocos início–fim + nome + área
     da vida (💪 saúde, 💼 negócios, 👨‍👩‍👧 família, 🧠 mente, 🕊 espírito,
     🏠 casa, 😴 descanso) + detalhe; LINHA DO TEMPO 24 h colorida (bloco
     que passa da meia-noite vira 2 pedaços) + lista + "onde vai o dia"
     (barra por área) + copiar pra outros dias / Seg–Sex / limpar; dia
     vazio oferece "⚡ Dia útil campeão" e "🌿 Fim de semana" (presets
     editáveis em warrior.js).
   · SEMANA: 7 colunas mini-linha do tempo (toque abre o dia) + "onde vai
     o seu tempo na semana" (horas e % por área).
   · MÊS: ano ‹ ›, 12 cartões (o atual laranja sólido) c/ foco do mês,
     metas com checkbox e %, e chips 🏋️ dos programas de treino que
     passam pelo mês (Warrior do config + programas pessoais ativos).
   · ANO: "onde quero chegar" por área da vida (5 caixas) + metas do ano
     c/ % + linha do ano (12 meses c/ foco e barras dos programas: royal
     = Warrior, laranja = meu programa).
- Backend: KINDS += cardio, fight_plan, routine; create_record: routine
  upserta como o profile; GET /health devolve cardios, fight_plans,
  routine. HealthDashboard: sem mudança (cardio ainda não entra no mapa
  de constância — fila).
- TESTADO local (conta 3): molduras nos cartões B/C ✓ (A laranja);
  Cardio: caminhada 30 min salvou, resumo 30 dias e lista ✓; Boxe:
  construtor por rounds gerou 8 blocos (aquec + 6 rounds + calma, 36 min)
  → editor → salvou como "Treino do professor — 6 rounds" ✓; plano "Luta
  teste · João" (3 rounds, R1 pressionar) salvou e ▶ Treinar abriu a
  sessão "Round 1 · Pressionar · ritmo alto, cortar o ringue · 3:00" ✓;
  📚 Importar biblioteca → 30 sequências, filtro Contra-ataque (4) com
  "Quando usar" ✓; Painel: linha 📍 "Rotina Bônus — Strength & Fullness ·
  Semana 1 de 8 · próximo: Treino A · Segunda" + "30 min de cardio" ✓;
  Rotina: preset dia útil → linha do tempo colorida + lista + onde vai o
  dia + copiar Seg–Sex (chips c/ 10 blocos) ✓, Mês c/ Set laranja e
  chips do Warrior ✓, Ano c/ 5 áreas + linha do ano ✓, "salvo ✓ hh:mm".
- Rastros: cardio, plano de luta e treino do professor apagados do banco
  local; a BIBLIOTECA de sequências importada e a ROTINA-preset ficaram
  pra ele ver (é só "limpar"). Na VPS ele precisa tocar "📚 Importar
  biblioteca" uma vez.
- Ajustes de tabela: blockMinutes conta o rest_after; inputs estreitos
  (minutos do cardio, aquecer/calma) com width fixo.
- FILA: cardio no mapa de constância e nas Análises; "modo luta" com
  placar por round; rotina → lembretes/notificações; rotina ligada ao
  treino do dia (bloco "Treino" abrir a sessão).

## RODADA 25 — 19/09 ✅ CRIAR/IMPORTAR MEU TREINO + HISTÓRICO + CELEBRAÇÕES ANIMADAS (working tree, NÃO subida)
Pedido dele 19/09: painéis "parecidos mas independentes do Warrior" —
escolher Warrior = configuração atual exata; "importar treino / criar meu
próprio treino" = assistente (1 divisão ABC + dias da semana · 1.1 por
quantas semanas · 2 exercícios de cada dia · 3 parâmetro de sucesso/
fracasso · 4 nome pro histórico), pra outras pessoas usarem o app a vida
toda "como um jogo agradável". E: toda semana ao fechar o 3º treino e a
cada medição, ANIMAR os relatórios onde houve progresso — bonito, alegre,
na nossa paleta, animações leves/tecnológicas/satisfatórias — VALENDO
PRO WARRIOR TAMBÉM (mensagem dele no meio da rodada).

- **Modelo**: kind novo `program` em hub_health_records (POR PESSOA, 1
  registro por programa, record_date = início; data = name/goal/status
  active|finished|archived/weeks/start_date/weekdays/sessions[{key,
  label, weekday, exercises = MESMA prescrição do Warrior}]/finished_at/
  result). Servidor: sanitize_custom_program (reusa sanitize_prescription)
  no create/update; GET /health devolve `programs`. A ficha (profile)
  ganhou `program_mode` ('warrior' | 'custom') + `active_program_id`.
  Decisão: Warrior segue COMPARTILHADO no config; programa pessoal é da
  pessoa (convidados montam o seu sem mexer no dele).
- **warrior.js**: GOALS (constância/força/emagrecimento/hipertrofia c/
  descrição do que mede), MEASURE_DEFS (lista única das 15 medidas),
  customToProgram (registro → formato de programa, 1 ciclo de N semanas),
  resolvePrograms(config, profile, programs) = o que cada tela usa,
  mainProgramOf (fim dos ids fixos 'warrior24' nas 3 telas),
  buildPrescriptionSets/schemeText (séries por método), parseImportText
  (COLAR lista: "Supino reto 3x8-12", "4 × 6–8", "3 x 10"; cabeçalhos
  "Treino A / B:" importam ABC de uma vez), goalProgress (quanto o
  programa entregou no parâmetro escolhido: constância = feitos ÷
  planejados (ok ≥ 80%); força = Σ e-1RM último × 1º por exercício;
  emagrecimento = peso (+ cintura) desde o start_date; hipertrofia = Σ cm
  dos músculos desde o início), workoutCelebration (semana fechada →
  treinos n/meta, semanas seguidas, exercícios que subiram, força vs
  última, top 4 ganhos) e bodyCelebration (medidas que andaram na direção
  certa vs anterior, Σ cm, "desde o início"; 1ª medição = ponto de
  partida; nada melhorou = "nada regrediu, X se mantiveram").
- **ProgramWizard.vue (novo)**: 4 passos com trilha (✓/atual laranja):
  dias da semana (chips) + divisão (−/+ ABC…, rotação A B C A quando há
  mais dias) + semanas (−/+, 1–104) + data de início · exercícios por
  letra (abas A/B/C c/ ✓, grupos do dia, linhas nome c/ autocompletar +
  método Séries/RPT/Rest-Pause/Pirâmide + séries −/+ + reps de/a +
  descanso; 📋 Importar (colar lista)) · objetivo (4 cartões) · nome +
  observação + resumo em cartão noite; validação por passo; editar
  programa existente reusa o assistente.
- **HealthPage**: barra de escolha 🛡 Warrior | ✨ programas pessoais
  ativos | + Criar / importar | 📜 Histórico (n); cartão do programa
  pessoal ganha bloco OBJETIVO (valor, detalhe, barra, ✎ editar, 🏁
  encerrar = guarda `result` com sucesso/abaixo do esperado e volta pro
  Warrior); cartões de treino mostram o grupo (A · Peito e tríceps);
  editor ✎ salva no registro quando o programa é pessoal; planilha vira
  aba "Semanas 1–N"; histórico lista nome/divisão/semanas/período/
  treinos feitos/objetivo/resultado c/ ▶ Usar · ✎ · 🏁 · 🗑 (só sem
  treinos); estado vazio "Nenhum programa ativo".
- **HubCelebration.vue (novo)**: sobreposição de vidro azul-noite c/ 26
  partículas caindo (royal/laranja/branco), medalhão laranja pulsando c/
  2 anéis, brilho varrendo o cartão, cartões entrando em cascata, números
  CONTANDO até o valor (rAF ease-out), barras enchendo com glow, ▲
  flutuando; botão "Continuar ✨"; prefers-reduced-motion desliga tudo.
  Disparo: saveSession (programa Warrior OU pessoal) quando a semana
  Seg–Dom do treino salvo atinge sessões/semana (profile.weekly_sessions
  ou nº de treinos do ciclo) e saveBody sempre. Chave por semana/registro
  guardada no aparelho (hub_celebrated) pra não repetir ao editar.
- **HealthHome**: usa resolvePrograms; CYCLE_LEN virou cycleLen (24 no
  Warrior, N semanas no pessoal); hero mostra "Objetivo Força: +x% ·
  detalhe" no programa pessoal. **HealthDashboard**: mainProgram
  genérico (registros do programa principal pelo id).
- TESTADO local (conta 3, banco de simulação): assistente ponta a ponta
  c/ importação colada de 3 treinos (A ✓ B ✓ C ✓, faixas 3 × 6 a 8
  corretas), programa "Greek God · teste" criado → ativo (Semana 1 de 12,
  objetivo Força, cartões A · Peito e tríceps…), barra de escolha c/ chip
  laranja no pessoal e Warrior intacto ao voltar.
  CELEBRAÇÕES testadas: medição com peso −0,1 / cintura −0,1 / braço D
  +0,1 / coxa D +0,1 → "4 indicadores na direção certa!" c/ Σ 0,3 cm,
  cada medida com "desde o início", partículas e barras ✓; treinos A, B
  e C do programa de teste no mesmo dia → no C: "Semana 1 fechada!" c/
  Treinos da semana 3/3 (1ª semana = sem vereditos ainda) ✓. Meu Painel
  c/ programa pessoal: hero "Semana 1 de 12 · Greek God · teste — 💪
  Força" + linha do objetivo ✓; Análises abre e o "desde a semana 1"
  usa o programa pessoal ✓.
- 🐛 corrigido de tabela: sortRecs empatava registros da MESMA data e o
  "próximo treino" apontava errado quando havia 2 treinos no dia (o B
  abriu de novo em vez do C) — desempate por id maior primeiro.
- Rastros de teste (programa "Greek God · teste", 3 treinos, medição de
  19/09, modo do profile) apagados do banco local no fim; localStorage
  hub_celebrated limpo. Banco local segue sendo a simulação.
- FILA (ideias dele nesta rodada, não feitas): celebração mais rica na
  semana quando há vereditos (já prevista no código: ▲ exercícios que
  subiram, força vs última, top ganhos — aparece a partir da 2ª semana);
  mais tipos de importação (foto/PDF via IA); presets de programas
  famosos (Greek God etc.) prontos pra copiar.

## RODADA 23 — 18/09 ✅ ATUAL→ALVO + CM×PESO + ONDE QUERO + FORÇA A/B/C + VIDRO + ANÁLISES REORDENADA (subida na 1681fc7)
Pedido dele 18/09 (prints do painel e do treino), 7 pontos:
1. "meus dados atuais e desejados neste primeiro painel" → bloco 🎯 ONDE
   ESTOU → ONDE QUERO CHEGAR logo após o hero: peso + 8 medidas (braço e
   coxa = média D/E) com atual → alvo, barra "% do caminho" (1ª medição →
   alvo), "faltam X", ETA no peso; ✎ alvos abre grade de roletas e salva
   em profile.targets {key: valor} (weight_goal segue junto). Sem alvo
   mostra Δ desde o início. Tile Força total no fim da grade (leva ao bloco
   de força). Os 3 tiles antigos saíram.
2. Cores padronizadas SÓ azul + laranja em tons (painel e Análises): ▲ =
   royal, ▼ = laranja vivo, "direção certa" = azul, "contra" = laranja;
   VERDICT_COLORS local; sem verde/vermelho (import limpo).
3. Gráfico 📐 CENTÍMETROS TOTAIS × PESO logo no início (bloco laranja):
   Σ de todas as circunferências (carry-forward) laranja × peso azul,
   eixo duplo, com os números e Δ no cabeçalho.
4. Gráfico "onde quero perder × onde quero ganhar" (Δ desde a 1ª medição
   por grupo, laranja/azul) no bloco Centímetros — substituiu o "direção
   certa" da rodada 22. Áreas do corpo mantidas.
5. 📈 FORÇA NOS TREINOS: chavinha Geral | A | B | C → 3 números (força
   total, relativa, % subindo) + gráfico semanal força × relativa
   (strengthChartFor de volta, eixo duplo). Tile de força rola até aqui.
6. Treino: os 3 treinos viraram CARTÕES DE VIDRO clicáveis (letra grande,
   dia, nº de exercícios, "▶ Fazer este"); o da vez em laranja sólido
   PULSANDO com selo "🔥 HOJE" (dia da prescrição = hoje) ou "▶ próximo";
   ✎ fica no cartão (stop). Auto-start por ?start= mantido.
7. VISUAL DE VIDRO: _hub-glass.scss (novo, importado no app.scss) portado
   do kit iMac G3 + vidro da CEVICO (develop) com a paleta do HUB —
   .hub-page (luz do alto), .hub-block (carcaça translúcida c/ crista e
   luz no canto), .hub-block-solid, .hub-block-hover, .hub-block-today
   (halo pulsando), .hub-orange, .hub-chip; dark mode. As 3 telas do mundo
   Saúde vestem .hub-page e os cards viraram .hub-block.
8. ANÁLISES · Visão geral reordenada: 🟦 Mapa de constância PRIMEIRO,
   depois 📈 DESDE A SEMANA 1 (novo: força total Σ e-1RM carry-forward ×
   peso × centímetros totais por semana do programa, indexados em 100 na
   S1, tooltip com valores reais, 3 mini-cards c/ Δ desde S1), depois
   Insights, Transformação, Aderência.
- Sem migration. Alvos de teste semeados no profile local (78 kg / 88 cm
  / braço 43 / peito 106) — banco local é simulação.

## RODADA 22 — 18/09 ✅ PAINEL MAIS CLARO (4 cortes aprovados por ele) (subida na 1681fc7)
Ele perguntou "o painel já está claro o suficiente?"; propus 4 cortes e
ele aprovou ("vamos neste sentido"). Só HealthHome.vue.

1. **Gráfico de cm virou "Centímetros na direção certa"**: uma lógica só,
   SUBIR É BOM — cintura que caiu e braço que cresceu somam na linha
   verde; o que foi contra vira a linha vermelha; saldo pontilhado. Eixo
   começa em zero. (Antes laranja descia = bom e azul subia = bom, e o
   −12 dos braços assustava.)
2. **Cards de carga leves**: frente = nome (+🏅/tag), "+3 kg no ciclo
   (+4%)", carga grande (peso comum) e sparkline. TOQUE no card abre o
   detalhe: séries e data da última, veredito, Δ vs anterior, força
   estimada, nº de execuções, linha ⚖ do peso comum e a carga registrada
   na variação. (openCards Set + toggleCard.) Parágrafo de ajuda encurtado.
3. **Bloco "Progresso de força" SAIU do painel** (carrossel Geral|A|B|C,
   4 KPIs e gráfico semanal) — mora em Análises; o tile "Força total" do
   Resultado fica e agora leva pra Análises. Removidos strengthSlides/
   forceCarousel/strengthChartFor/consistency/adherence/volume da semana
   (lint sem sobras).
4. **Gráfico "cintura × peso × alvo" SAIU** (repetia a área Abdômen e o
   tile de peso; a área Peso já traz a linha do alvo).
Painel final: hero → 3 tiles → Centímetros (balanço + chips + 1 gráfico
+ áreas) → Cargas (cards leves, botão Fazer Treino) → Metas dobráveis →
link Análises.

## RODADA 21 — 18/09 ✅ "FAZER TREINO" NO CARROSSEL + PESO COMUM ENTRE VARIAÇÕES (subida na 1681fc7)
Pedido dele 18/09 (print do carrossel Treino A): botão "fazer treino" ali;
e quando marca máquina num exercício que também faz com halteres,
"chegar num peso comum" (30 kg por halter ≈ 70 kg na máquina, como na
barra).

- **▶ Fazer Treino X** no topo de cada slide do Progresso das cargas
  (goStart → sessão aberta com metas; selo "é o da vez").
- **PESO COMUM (warrior.js)**: cada variação tem um FATOR pra mesma
  escala — DEFAULT_EQUIV halteres ×2 (cada lado → total), barra/smith/
  polia ×1, máquina sem fator fixo = CALIBRADA pelo histórico
  (learnEquiv: e-1RM da execução mais recente da base ÷ e-1RM da mais
  recente da variação); fator fixo opcional na prescrição `equiv`
  {tag: fator} (sanitize novo no controller). A escala exibida é a da
  VARIAÇÃO PRINCIPAL do exercício (supino com halteres continua mostrando
  o número do halter; barra/máquina entram convertidas).
- **Painel**: execuções ganham `common`; número grande, Δ ciclo, Δ vs
  anterior e sparkline usam o peso comum; quando o histórico mistura
  variações aparece a linha "⚖ peso comum · halteres 30 ≈ máquina 70
  (×0,43)" e, sob o número, a carga registrada na variação.
- **Sessão (HealthPage)**: chavinha pra variação SEM histórico → roletas
  nascem ESTIMADAS pelo peso comum a partir da execução mais recente em
  outra variação (convertLoad, grade de 0,5 kg) com hint "Primeira vez
  com máquina — estimado pelo peso comum: halteres 30×8 … ≈ 70×8 …";
  linha "⚖" sob a chavinha mostra a conversão e os fatores ≠ 1. Editor ✎:
  "barra | halteres ×2 | máquina ×0,85" (parseVariants extrai o ×n pra
  `equiv`; ajuda no texto).

## RODADA 20 — 18/09 ✅ NAVEGAÇÃO "APP DA APPLE" + PAINEL ENXUTO + CM POR ÁREA + EXTRA PUXA + BOXE PROGRAMADO (subida na 1681fc7)
Pedido dele 18/09 (prints do painel e do balanço de cm): (1) acesso e
navegação fáceis "como um app feito pela Apple", 1–2 cliques pra chegar
em qualquer lugar; (2) enxugar o Meu Painel — as coisas mais importantes
no início (cargas, progresso, medidas em cm, relação com a meta); (3)
gráfico com TODOS os centímetros ganhos/perdidos + gráficos separados por
ÁREA do corpo; (4) exercício complementar (extra) não puxava as
informações anteriores; (5) reativar o BOXE com treinos pré-programados
de ~60 min estruturados (aquecimento, sequências, footwork…).

- **HubTabBar.vue (novo)**: barra de abas fixa no rodapé, só no celular
  (< 768px; no desktop a sidebar já resolve) — Painel · Treino · Boxe (se
  ligado) · Corpo · Dieta · Análises; vidro azul-noite, aba ativa laranja
  com brilho, safe-area do iPhone. Incluída nas 3 telas (HealthHome,
  HealthPage, HealthDashboard) com pb-28 no conteúdo. O hambúrguer do app
  (#mobile-sidebar-launcher) sobe acima da barra via classe no body
  (`hub-tabbar-on`) + style global. "Dashboard" virou "Análises" (sidebar
  + título da tela).
- **Atalho de 2 toques**: "▶ Treino X de hoje" no painel navega pra
  hub_health com `?start=X`; HealthPage no onMounted abre a sessão
  (startProgramSession) e limpa a query. Botão "▶ Começar Treino X" também
  dentro das Metas.
- **Meu Painel reescrito (HealthHome)**: ordem = HERO (ciclo/semana/
  placar + CTA) → RESULTADO (3 tiles: Peso × alvo c/ barra de progresso
  "% do caminho"/faltam/ETA/ritmo e alvo editável ali; Cintura umbigo c/
  Δ início/última/ritmo + sparkline; Força total Σ e-1RM c/ Δ ciclo, força
  relativa e taxa) → 📐 CENTÍMETROS (balanço 3 cards + chips; GRÁFICO
  "todos os centímetros, medição a medição" = Σ Δ desde a 1ª medição com
  carry-forward, laranja = onde quer perder, royal = onde quer ganhar,
  saldo pontilhado; ÁREAS DO CORPO = chavinha rolável Abdômen · Quadril ·
  Peito · Braços · Coxas · Ombros · Pescoço · Peso → cards por medida
  (umbigo+estreita, D+E) c/ Δ início/última em cor semântica + gráfico da
  área; cintura×peso×alvo mantido) → 🏋️ Cargas (carrossel A|B|C intacto)
  → 📈 Força (carrossel Geral|A|B|C intacto; slide Geral ganhou linha
  recordes/progressões/aderência e volume da semana na tonelagem) → 🎯
  METAS do próximo treino DOBRÁVEL (fechada por padrão, lembra em
  localStorage hub_painel_metas). SAÍRAM: elogio (virou chip "🏆 semana
  completa" no hero), fileira de 4 KPIs, caixinhas de consistência (moram
  em Análises), card de dieta. Tiles Cintura/Força rolam pra seção.
- **Extra puxa a última execução (HealthPage)**: normName (sem acento/
  preposição/pontuação) + normLoose (sem equipamento no fim, com ou sem
  preposição) — "rosca martelo halteres" acha "Rosca martelo com
  halteres"; lastAnyEntry devolve também a data; PREFILL SEMPRE
  (buildTodaySets com as séries da última vez mesmo com técnica diferente;
  veredito/alvos só na mesma técnica, senão hint "Última vez dd/mm em X:
  … Técnica nova"); nome salvo = o canônico do histórico; PRÉVIA ao vivo
  no seletor ("↩ Última vez 24/08 · RPT · 41×10 · 37×12 — as caixinhas já
  vêm assim"); CHIPS "Seus extras recentes" (até 8, 1 toque = entra com
  a técnica da última vez, pickExtra). Provável causa real no iPhone: o
  datalist não aparece no Safari e ele digitava diferente do nome salvo.
- **WheelInput assenta**: roleta nascendo fora da tela (extra no fim da
  sessão) parava num número errado e o onScroll gravava no modelo (viu
  28,5 no lugar de 37) — centerOn reaplica o scroll em 3 tempos (nextTick
  → rAF → +80 ms) e ignora scroll até assentar (`settling`).
- **BOXE PRÉ-PROGRAMADO**: config.boxing.workouts (sanitize novo
  sanitize_box_workout: ≤30 treinos × ≤20 blocos; bloco = type/title/
  minutes/rounds/round_sec/rest_sec/seqs/desc). 3 treinos DE FÁBRICA no
  front (DEFAULT_BOX_WORKOUTS, aparecem enquanto não salvar os dele):
  Fundamentos 60 min (corda+mobilidade 10 · sombra 3×3' · sequências 4×3'
  · footwork 3×3' · saco 4×3' · condicionamento 5×40"/20" · volta à calma
  3), Sequências e footwork 45, Rápido 30. Cards c/ minutos/blocos/rounds/
  sequências + "▶ Iniciar" e "✓ Já fiz" (registra sem cronômetro).
  SESSÃO GUIADA: trilha dos blocos, bloco atual c/ descrição e "Round i
  de n"/descanso, relógio circular SVG grande (mm:ss, arco laranja no
  round e azul-claro no descanso), sequências do bloco em cards grandes,
  ‹ ▶/⏸ › , apitos WebAudio (3-2-1, troca de round, fim), wake lock da
  tela, data/observações e "✓ Concluir" → registro kind=boxing c/
  duration_min (tempo real ≥1 min, senão o planejado), planned_min,
  rounds, sequences (união), workout_id/name, blocks[{type,title,minutes,
  done}]. EDITOR de treino programado (nome/desc/blocos c/ tipo · título ·
  min · rounds × seg · descanso · desc · chips das sequências · ↑↓ ✕ ·
  + bloco · excluir). Registro livre antigo virou dobrável "✍️ Registrar
  treino livre". saveSeq/deleteSeq preservam `workouts` no config.
  Histórico mostra o nome do treino programado.
- **HealthPage enxuta**: fileira de KPIs do topo (7 dias/sequência/peso/
  variação) saiu; título = aba atual; pílulas só no desktop (no celular a
  barra faz isso).
- Boxe LIGADO no banco local pra testar (features.boxing = true — banco
  local é simulação). Sem migration.
- TESTADO local (375px): painel completo (tiles, gráfico de cm, áreas,
  carrosséis), CTA → sessão aberta com metas, extra "rosca martelo" c/
  prévia + prefill + chip recente + 1 toque (registro 292 apagado).

## RODADA 19 — 10/09 ✅ PORTA DE ENTRADA = MEU PAINEL DA SAÚDE (working tree)
Feedback dele com a 11ee29e no ar: (1) ícone do iPhone ainda era o
olho da CEVICO; (2) abrir o app caía no /inicio (painel de negócios)
mesmo no modo Saúde.

- **Ícone**: a VPS já serve a arte hub (apple-touch-icon.png md5
  5c059c69… idêntico ao local, head c/ /brand-assets/hub/…, theme-color
  #111C3F). O iOS grava o ícone NA HORA em que o atalho é criado e não
  atualiza — o atalho dele é anterior à rodada 12. Solução = apagar o
  atalho "Hub" e adicionar de novo pelo Safari. Nada a mudar no código.
- **Entrada**: routes/index.js, guard da primeira navegação — antes só
  `home` → /inicio. Agora `home` OU `inicio_home` (atalho do iPhone
  salvo em /inicio) na 1ª navegação: segmento saude + hub_mode 'saude'
  → /health/painel; sem modo → segue (Sidebar leva ao /hub); 'negocios'
  → /inicio como antes. Import de segmentoId no router. Testado local:
  saude+/inicio → painel, saude+/dashboard → painel, negocios+/dashboard
  → /inicio. subiu junto com a arte nova (abaixo).
- **ARTE NOVA EM AZUL + LARANJA** (pedido dele na sequência): símbolo
  hub-and-spoke redesenhado — fundo gradiente royal noite→profundo→royal,
  raios azul-claro #8FA9F5, 6 nós laranja c/ brilho, centro anel laranja
  c/ miolo laranja-claro. Gerado por HTML/SVG + Chrome headless
  (scratchpad/icone/*.html → square/square_badge/thumb 1024, logo/
  logo_dark 1280×400) e reduzido c/ sips: brand-assets/hub (icon-512/192,
  apple-touch-icon 180, favicons 16/32/96, logo_thumbnail 512 c/ cantos
  transparentes, logo + logo_dark 640×200 c/ "HUB" noite/branco e
  tagline laranja) + os 30 ícones da RAIZ (apple/android/ms/favicon +
  favicon-badge c/ bolinha vermelha) no tamanho de cada arquivo; os 2
  manifest.json → #111C3F. Ele precisa APAGAR e RECRIAR o atalho no
  iPhone pra ver o ícone novo.
- **SUBIDA 10/09**: commit 14538a8f7 → docker-build (run 34523796622)
  VERDE → **etiqueta `14538a8`** (sem migration).

## RODADA 18 — 10/09 ✅ CHAVINHA A|B|C NAS METAS + CARROSSEL DO PROGRESSO (working tree)
Pedido dele 10/09 (print das Metas): chavinha "Treino A/B/C" nas metas
pra ver as metas de qualquer treino; no Progresso das cargas, "Treino A"
mais evidente e separado — carrossel com os 3 treinos, passar pro lado.

- **Metas**: hub-seg (mesma chavinha segmentada do treino) Treino A | B |
  C no cabeçalho; metasKey vazio = treino da vez (selo laranja "da vez"
  quando o escolhido é ele); upcomingPlan passou a ler metasSession.
- **Carrossel** (.hub-carousel flex + scroll-snap x mandatory, 1 slide
  = 100%, scrollbar escondida, snap-stop always): slide por treino com
  CABEÇALHO grande (faixa royal noite, letra do treino num quadrado
  laranja, dia da semana, nº de exercícios, dica "empurrar + braços"/
  "pernas + core"/"puxar + ombros" — SESSION_HINT fixo por letra) e
  setas ‹ › + contador i/n; chavinha A|B|C acima e bolinhas embaixo;
  slideIdx segue o scroll (round(scrollLeft/clientWidth)); goSlide
  scrollTo suave. No celular desliza com o dedo. Só HealthHome.vue.
- **Complemento (print dele)**: título do hero "Meu Painel · Treino"
  BRANCO (h1 global pintava escuro; class text-white + style); PROGRESSO
  DE FORÇA também em carrossel **Geral | A | B | C** — useCarousel
  (composable inline: el/idx/go/onScroll c/ debounce) reusado nos 2
  blocos; strengthFor(sessionKey|null) calcula força total/relativa/
  taxa/tonelagem/gráfico só c/ os exercícios do treino (verdictsFor,
  strengthChartFor por conjunto); slide Geral = faixa laranja c/ "Σ",
  treinos = faixa noite c/ letra laranja. Testado: Geral 806 kg/9,89×/
  59%/63 t · A 272/3,34×/50%/19,9 t · B 294/3,61×/65%/26,5 t · C 240/
  2,95×/67%/16,6 t, 4 gráficos, pílulas e bolinhas.
- **SUBIDA 10/09 (rodadas 17+18)**: "pode subir" → commit 11ee29eaf →
  push → docker-build (run 34513630217) VERDE → **etiqueta `11ee29e`**
  (sem migration). Falta ele colar no EasyPanel (web+sidekiq) e Implantar.

## RODADA 17 — 10/09 ✅ BALANÇO DE CENTÍMETROS + PROGRESSO DE FORÇA (working tree)
Pedido dele 10/09 (logo após a 16 subir): no Meu Painel, "volume total
de centímetros ganhos ou perdidos" + "formas de mensurar o progresso de
pesos". Só HealthHome.vue, sem migration.

- **📐 Balanço de centímetros** (dentro do bloco Corpo, antes do
  gráfico): 3 cards — "Onde quer perder" (cintura umbigo + estreita +
  quadril + pescoço; Σ Δ desde a 1ª medição, laranja se caiu, vermelho
  se subiu), "Onde quer ganhar" (peito + braços + coxas + ombros; royal
  se subiu, laranja se caiu) e "Saldo total" (Σ com sinal + "cm movidos"
  = Σ |Δ|); cada card traz também o Δ vs última medição; chips de cada
  medida ordenados por |Δ| c/ cor semântica (verde = na direção certa).
  cmBalance usa seriesOf(key) — só medidas com ≥2 registros entram.
- **📈 Progresso de força** (bloco novo após "Progresso das cargas"):
  FORÇA TOTAL = Σ e-1RM da última execução de cada exercício do ciclo
  vs Σ na 1ª execução do ciclo (Δ kg e %); FORÇA RELATIVA = força total
  ÷ peso corporal (peso do início do ciclo pelo weightAt(cycleStartISO))
  — o índice do cutting; TAXA DE PROGRESSÃO = ▲ ÷ (▲+▬+▼) do ciclo;
  TONELAGEM do ciclo + média/semana. GRÁFICO semana a semana: força
  total c/ carry-forward (cada exercício vale o último e-1RM conhecido
  até a semana; execuções ganharam `week`) × força relativa (eixo dir.).
  Cards por exercício ganharam o % (Δ ciclo +3 kg (+4%)).
- **cycleVerdicts**: vereditos do ciclo derivados das execuções quando
  o registro não tem `verdict` (planilha/simulação) — alimenta
  "Progressões no ciclo" e a taxa. Bloco todo mora depois das séries do
  corpo (no-use-before-define limpo).
- TESTADO local (simulação): força total 806 kg (+34, +4,4%), relativa
  9,89× (+0,9), taxa 59% (▲35 ▬12 ▼12), tonelagem 63 t (≈9 t/sem),
  gráfico S17–S23; balanço −30,6 cm onde quer perder / −12,3 onde quer
  ganhar (cutting) / saldo −42,9 c/ chips. AGUARDA "pode subir".

## RODADA 16 — 10/09 ✅ CHAVINHA N OPÇÕES + ROLETAS|DIGITAR + EXTRA C/ TÉCNICA + PAINEL 95% TREINO + PALETA ROYAL/LARANJA EM TUDO
Pedidos dele 10/09: (1) chavinhas de substituição com várias opções
(supino inclinado → barra | halteres | máquina); (2) no treino, escolher
entre roletas ou digitar; (3) exercício extra já com a técnica escolhida
(ex.: rest-pause) vindo pré-configurado; (4) Meu Painel 95% treino/cargas/
progresso, dieta só referência, indicadores de peso/medidas com a
CIRCUNFERÊNCIA ABDOMINAL como principal; (5) paleta azul+laranja do
painel em TODO o sistema (treino, corpo, dashboard).

- **palette.js** (novo): ROYAL #4169E1 · profundo #27408B · noite
  #111C3F · claro #8FA9F5 · LARANJA #FF8A00 · vivo #FF6B1A · claro
  #FFB25E · escuro #B85C00 + VERDE_OK/VERMELHO/CINZA só p/ semântica
  (▲▬▼, feito/não foi) + gradientes GRAD_ROYAL/NOITE/CLARO/LARANJA.
  HealthPage, HealthDashboard e HealthHome importam daí (zero verde/
  ouro/roxo/rosa sobrando); HubPage card Saúde → royal; hub.yml
  cores primaria #111C3F / destaque #4169E1 (theme-color). A ARTE do
  logo (hub-and-spoke verde) NÃO foi refeita — fica pra ele decidir.
  Convenção: botão principal/pílulas/abas = GRAD_ROYAL; CTA "Concluir
  treino"/"Adicionar" = GRAD_LARANJA; vidro royal, ouro→laranja na
  meta atingida; método rest_pause = laranja vivo, pirâmide = laranja,
  RPT/séries = royal; dieta kcal laranja/proteína royal/carbo royal
  claro/gordura laranja claro; boxe (quando ligado) = royal noite.
- **Chavinha com N opções (warrior.js equipmentOf)**: prescrição aceita
  `variants` (lista, sanitize ≤6×30 chars; tag/alt_tag antigos ainda
  valem = 2 primeiras opções). SEM lista, as opções saem do NOME por
  regras (supino/desenvolvimento → barra|halteres|máquina; rosca →
  halteres|barra|cabo; rosca martelo → halteres|corda; crucifixo →
  halteres|máquina|cabo; elevação lateral → halteres|cabo|máquina;
  remada → polia|barra|halteres|máquina; tríceps → corda|barra|
  halteres; agachamento/afundo → halteres|barra|smith; terra/stiff →
  barra|halteres; hip thrust → barra|máquina; panturrilha → máquina|
  halteres|smith). BASE = equipamento citado no nome ("com barra" →
  barra; "na polia com corda" → corda) se estiver nas opções, senão a
  1ª; registros antigos sem tag contam como base. Cadeira extensora/
  barra fixa/joelhos = sem chavinha. Nome no card perde o sufixo de
  equipamento (nameWithoutEquipment: "Supino inclinado" + chavinha).
  A sessão NASCE na variação usada da última vez (lastEntry.tag), e a
  última execução vem por nome+variação em qualquer treino
  (lastSetsForTag; normTag/lastSetsForTag subiram no arquivo). Editor
  ✎: campo único "chavinha: barra | halteres | máquina" (pré-preenchido
  c/ as opções atuais, inclusive as inferidas) — vazio = automático,
  1 opção = SEM chavinha, 2+ = chavinha; salva variants + tag=1ª.
- **Roletas | Digitar** (HealthPage): chavinha segmentada no topo da
  sessão; preferência em localStorage `hub_input_mode`; modo digitar =
  input inputmode decimal/numeric grande (.hub-type-input 3rem, 19px
  bold, borda royal) no lugar das 2 roletas, mesmo v-model string
  (chip "última vez⤵" continua funcionando). Só no ambiente de treino
  (pedido); Corpo/Boxe/Dieta continuam com roleta.
- **Extra com TÉCNICA** (EXTRA_METHODS no warrior.js): Séries 3×8–12
  (60–90 s) · RPT 6–8/8–10/10–12 (2–3 min, top_of_ranges) · Rest-Pause
  ativação 12–15 + 3 minis 4–6 (10–20 s) · Pirâmide 12/10/8/6 (30–60 s,
  rest_reduction). Pílulas na caixa do extra; o exercício nasce com
  presc completa → hint/alvos/labels (Ativação/Mini) do motor como no
  programa; scheme/rest no card; salva `method` no registro. Se o nome
  já foi feito antes: a técnica da última vez vem selecionada (watch);
  comparação HOJE×última só na MESMA técnica — técnica diferente vira
  referência no hint ("da última vez, em Séries: 40×12 · 40×10").
- **Meu Painel 95% treino (HealthHome reescrito)**: hero royal c/ ciclo
  + botão laranja do treino da vez (de hoje se não feito, senão o
  próximo) + sessões da semana e placar ▲▬▼ no hero; KPIs Volume da
  semana (vs passada) · Progressões no ciclo (summary ou vereditos por
  exercício) · Recordes (exercícios cujo último e-1RM é o melhor de
  todos) · Aderência do ciclo %; **🎯 Metas do Treino X**: cada
  exercício da próxima sessão c/ variação, método, última execução e
  alvos por série (setTargets) + hint — dá pra ir pra academia olhando
  o painel; **🏋️ Progresso das cargas**: card por exercício do ciclo
  (agrupado A/B/C, sem duplicar nome) c/ carga máx grande, últimas
  séries, Δ ciclo (vs 1ª execução DESTE ciclo), veredito, e-1RM, 🏅 e
  sparkline SVG das últimas 10 execuções (royal subindo/laranja
  caindo); consistência mantida; **📏 Corpo**: CIRCUNFERÊNCIA
  ABDOMINAL em card laranja grande (Δ vs anterior, Δ desde o início,
  ritmo cm/mês, sparkline) + peso atual (royal) + peso-alvo editável
  (roleta) + ritmo/peso em 30d/chegada ao alvo + chips das outras
  medidas c/ Δ semântico + gráfico cintura (laranja, eixo esq.) × peso
  (royal, eixo dir.) c/ linha do alvo; **🍽 Dieta (referência)**: 1
  faixa só (meta kcal/proteína · refeições de hoje · média da semana
  × meta) que abre a aba Dieta. Saíram do painel: cards de alvos de
  kcal/proteína, "Hoje" com refeições, kcal×meta como KPI.
- TESTADO local conta 3 (banco = simulação): painel completo via
  texto+screenshot (Metas do Treino C c/ 5 exercícios e alvos, 14
  cards de progresso c/ 🏅/Δ/sparkline, cintura 91,7 −4,8/−12,2,
  gráfico), treino: chavinha halteres|barra|máquina, barra → "Primeira
  vez com barra" c/ faixas, Digitar → caixinhas, extra "Crucifixo na
  máquina" em Rest-Pause nasceu c/ Ativação/Mini 1-3 + faixas + hint
  laranja/royal; inferência conferida via node (13 nomes). Sem
  migration.
- **SUBIDA 10/09**: "pode subir" → commit c822ae686 na feat/hub-saude →
  push → workflow_dispatch docker-build.yml (run 34502402898) BUILD
  VERDE → **etiqueta `c822ae6`** (sem migration). Falta ele colar a
  etiqueta no campo Imagem do web+sidekiq no EasyPanel e Implantar.

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
- ⚠️ 18/09: abrir o HUB local em **http://127.0.0.1:3001**, nunca
  localhost:3001 — a CEVICO local (localhost:3000) e o HUB dividem o
  cookie `cw_d_session_info` (cookie é por host, ignora porta): logar
  num derruba o outro ("sempre precisa logar de novo"). Links SSO do
  rails runner são de USO ÚNICO (2º clique = credenciais inválidas).
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
