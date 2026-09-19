# 🎯 Central de Criativos (item 172)

Cada anúncio da Meta lido como **gancho, corpo e CTA**, com os números da própria
Meta e o que virou consulta e cirurgia no CRM. Relatórios → Central de Criativos.

## Como a Meta vira gancho / corpo / CTA

| Peça | Métrica | Conta |
|---|---|---|
| Gancho | taxa de parada | plays de 3 s ÷ impressões (só vídeo) |
| Corpo | retenção | ThruPlay ÷ plays de 3 s; curva 3 s → 25 → 50 → 75 → 100 % (% das impressões) |
| CTA | clique | cliques no link ÷ impressões |
| CTA → atendimento | conversa | conversas iniciadas no WhatsApp (janela 7 d) ÷ cliques |
| Depois | jornada | leads CTWA → consulta marcada → compareceu → cirurgia (mesma régua do relatório Anúncios) |

## Parâmetros (bom / atenção / ruim)

`Crm::CreativeTargets` — padrões dos benchmarks publicados para vídeo na Meta,
editáveis pelo admin (aba Parâmetros e fórmulas → `meta_ads_config.creative_targets`):

| Peça | Ruim | Bom |
|---|---|---|
| Taxa de parada | < 25 % | ≥ 35 % |
| Retenção (ThruPlay ÷ 3 s) | < 30 % | ≥ 50 % |
| CTR de link | < 0,7 % | ≥ 1,5 % |
| Conversa por clique | < 25 % | ≥ 45 % |
| Custo por conversa | > R$ 25 | ≤ R$ 10 |

Entre os dois fica a zona de atenção. Cada régua (BulletMeter) mostra as três
faixas, o traço do parâmetro bom e o triângulo da média da conta (ponderada por
impressões). O diagnóstico em uma frase cita o parâmetro e diz o que trabalhar
(`focus`: gancho / corpo / cta / conversa / publico / escalar / esperar).
Variação vs período anterior = o mesmo criativo no período imediatamente
anterior, de igual tamanho (`prev`, `prev_totals`, `prev_daily`).

### Modo automático (nosso histórico) e recordes

`creative_targets.mode = 'auto'` (+ `step`, 3 % padrão): bom = a nossa melhor
semana-calendário (≥ 4 dias, ≥ 1.500 impressões) mais o passo de superação;
ruim = abaixo da nossa mediana semanal. Sem histórico suficiente, a métrica cai
para o manual (`fallback`). `Crm::CreativeRecords` calcula recordes por dia /
semana / mês, hoje × ontem, semana × anterior, mês × anterior, e os campeões
de gancho, corpo, CTA, conversa e custo por mês e de todos os tempos.
`GET crm/creatives/history` entrega isso mais as peças campeãs por mês
(criativo dinâmico). Campeões do recorte (`champion_of`) ganham a moldura
"dopamina" `.cv-champion` do kit (sem animação: fio em degradê com todas
as cores e o selo dourado com o troféu). O botão **Transcrever** (`useTranscribe.js`) copia o texto da peça
campeã (gancho, corpo ou CTA, texto puro) ou o anúncio inteiro (bloco
rotulado Gancho/Corpo/CTA) para montar a copy fora do sistema; está no
histórico, no mês a mês, nas peças, no pódio, na ficha e no Ver a fundo.
Cartões de campanha usam `.cv-choice` (cartão-botão com contorno). Nota do
kit: `--cv-rgb` é "r g b" com ESPAÇO (rodada 4 corrigiu o bug que apagava
bordas e fundos do kit inteiro — ver BACKLOG item 172, rodada 4).
Fadiga = o anúncio segue
entregando (2ª metade ≥ 40 % das impressões da 1ª) e o CTR da 2ª metade caiu para
≤ 75 % do da 1ª (período ≥ 14 dias).

## Dados

- `cevico_ad_creatives` — 1 linha por anúncio: nome, conjunto, campanha, status,
  formato (video/image/carousel/dynamic/other) e `creative` jsonb
  (title/body/cta_type/description/thumbnail_url/image_url/video_id/permalink +
  listas titles/bodies/ctas/descriptions do criativo dinâmico).
- `cevico_ad_insights` — 1 linha por anúncio por DIA: `metrics` jsonb
  (spend, impressions, reach, frequency, clicks, link_clicks, plays_3s, plays_2s,
  thruplay, p25…p100, avg_watch, conversations, first_replies, leads,
  post_engagement, actions{}). Índice único (account, ad_id, date).
- Sincronização: `Crm::AdInsightsSyncService` → `GET /act_X/ads?fields=…creative{…}`
  e `GET /act_X/insights?level=ad&time_increment=1&time_range=…` (paginado).
  Cron `crm_ad_insights_sync_job` 07:20 UTC refaz 3 dias; botão "Atualizar
  dados" refaz 30 (mín. 10 min entre pedidos, `force=1` ignora); primeira carga
  90. Estado em `meta_ads_config['creatives_sync']`.
- Quebras sob demanda com cache 6 h (`Crm::AdBreakdownService`): `summary`
  (alcance/frequência reais do período), `placement`
  (publisher_platform,platform_position), `age_gender`, `title_asset`,
  `body_asset`, `call_to_action_asset`, `video_asset`, `image_asset`. Ativos só
  existem em criativo dinâmico/flexível e só trazem spend/impressions/reach/
  clicks/actions.

## API (`crm/creatives`, capability `reports`)

- `GET /` — `preset|from|to`, `campaign_id`, `fmt` (⚠️ não `format`), `status`
  (vazio = com investimento; `active`; `all`), `q`, `sort`
  (spend|hook|hold|ctr|conversations|cost|leads|surgeries) → rows, totals,
  averages, campaigns, formats, daily, data_since, sync, configured, simulated.
- `GET /:ad_id` — row + daily[], halves{first,last}, summary, placements,
  age_gender, assets (se dinâmico).
- `GET /assets` — titles/bodies/ctas da conta + dynamic_ads.
- `POST /sync[?days=&force=]` — enfileira `Crm::AdInsightsSyncJob`; 409 se
  rodando, 429 se acabou de sincronizar. `GET /sync_status`.

## Tela

`reports/CreativesCenter.vue` (paleta `report:criativos`), componentes em
`components-next/cevico/creatives/`. Gráficos sem lib: MiniBars (série diária,
um eixo por gráfico), HBars (quebras/ativos), ShareBar (fatia), RetentionCurve
(SVG próprio), RateMeter (taxa × média da conta, veredito sempre com ícone +
texto). Comparação lado a lado (2–4) com troféu no melhor de cada linha.

## Simulação e testes

Token `simulate` na conta (ou `CEVICO_META_SIMULATE=1`) → `Crm::MetaSimulator`
devolve 8 anúncios fictícios com 90 dias no formato exato da Graph API (um deles
com fadiga, um dinâmico). Specs: `spec/services/crm/creatives_center_spec.rb`,
`spec/controllers/api/v1/accounts/crm/creatives_controller_spec.rb`.

## Deploy

Migration `20260919143000` → BACKUP antes; WEB + SIDEKIQ; depois Relatórios →
Central de Criativos → "Buscar agora". Precisa do token com `ads_read` já usado
pelo relatório Anúncios (Meta).

## Nossos dados (item 174): guardados aqui, independentes da Meta

Princípio: **o que a Meta entrega vira nosso.** Cada anúncio × dia fica em
`cevico_ad_insights`; o criativo (gancho, corpo, CTA, listas do dinâmico,
permalink) fica em `cevico_ad_creatives.creative`; e a miniatura ganha uma
cópia no nosso Active Storage (`has_one_attached :thumbnail`, preenchida por
`Crm::AdCreativeMediaJob` depois de cada carga, até 300 por vez — a URL da
Meta expira em horas). `AdCreative#thumbnail_src` devolve a cópia quando
existe; senão, a URL da Meta.

- **Histórico completo**: `MAX_DAYS = 1125` (37 meses, o limite da Meta).
  `AdInsightsSyncService` divide o período em **janelas de 90 dias**
  (`windows`, da mais recente para a mais antiga) e grava o progresso em
  `creatives_sync.progress` (`done/total/since/until`) — a tela mostra
  "carregando histórico: janela 3 de 13" e uma barra. `POST
  crm/creatives/load_history` (só admin) enfileira a carga; `history_days`
  guarda até onde já foi.
- **Anúncio apagado na Meta**: `/ads` é pedido com todos os `effective_status`
  (inclui DELETED/ARCHIVED). O que ainda assim vier só nos números
  (`effective_status: 'UNKNOWN'`, criativo vazio) é recuperado por id em
  `recover_missing_creatives` → `MetaGraph#fetch_objects` (`?ids=`, 50 por
  lote; lote recusado tenta um a um). Nome, texto, miniatura e status ficam
  guardados aqui. No simulador, o anúncio `2309` (DELETED, só dias com 46+
  de idade) exercita isso.
- **Exportar**: `GET crm/creatives/export[?all=1]` → CSV com `;`, BOM e
  vírgula decimal (`Crm::CreativesExport`): data, anúncio, campanha, conjunto,
  formato, status, gancho, corpo, CTA, investimento, impressões, alcance,
  frequência, cliques, plays 3 s, ThruPlay, 25/50/75/100 %, conversas, custo
  por conversa, miniatura guardada.
- **Cache pré-aquecido**: no fim de cada carga, `warm_records_cache` calcula
  `CreativeRecords` (cache 1 h por carga) e as peças campeãs de 12 meses, para a
  tela não pagar os segundos do cálculo no clique. `AdBreakdownService` guarda
  período FECHADO (até 3 dias atrás) por 30 dias (`CLOSED_TTL`) e o corrente
  por 6 h — o histórico mês a mês não volta a bater na Meta.
- **Resumo na tela** (`storage` em `sync_status`/overview): anúncios guardados
  (e quantos já sumiram na Meta), dias com dados, linhas anúncio × dia,
  miniaturas guardadas. Aba "Parâmetros e dados" → bloco "Nossos dados".
- A lista "Campeões mês a mês" mostra 12 meses e dobra o resto; peças campeãs
  por mês buscam 12 meses de quebras.

## Teia (radar) dos criativos (item 175)

Mesmo desenho do radar da área de Pessoas, em versão pequena e reutilizável
do kit: `components-next/cevico/MiniRadar.vue` (anéis, raios, polígonos com
pontos, rótulos curtos; 46 px sem rótulos até 240 px; 2º polígono tracejado
= média da conta). `creatives/radarAxes.js` define os EIXOS (gancho, corpo,
CTA, conversa, custo, leads, fim do vídeo, frequência; para peças: CTA,
conversas, custo, fatia, parada), a FORÇA 0–100 de cada um e a escolha por
ambiente (`useRadarAxes(env)`, guardada em `localStorage`
`cevico_radar_axes:<env>`, mínimo 3 eixos, compartilhada por todos os cards
do ambiente). Força: com parâmetro → 0 no zero, 50 na linha do RUIM, 100 no
BOM (custo invertido); sem parâmetro → contra o melhor do recorte;
frequência fixa (1 = 100, 3 = 0). `CreativeRadar.vue` = teia de uma linha;
`RadarAxesPicker.vue` = chavinhas (`.cv-switch` no kit). Ambientes: fichas
(`criativos`, 150 px + média), tabela (46 px), Ver a fundo (`detalhe`, 184 px
+ média, sem eixos relativos), Comparar (`comparar`, uma teia com todos os
polígonos), Recordes (`recordes`, campeões de todos os tempos, taxas vindas
de `CreativeRecords#champions_for` → `rates`), peças (`pecas`, pódio).

**Teias com lógica (19/09 noite, 2ª revisão a pedido dele: "pouca lógica
por trás dos 6 pontos; divida em mais de um radar"):** cada teia responde
UMA pergunta e só mistura eixos da MESMA régua (`RADAR_GROUPS` em
`radarAxes.js`):
- **Copy × parâmetros** — *qual bloco está fraco?* Gancho, Corpo, CTA,
  Conversa e Custo, todos contra o SEU parâmetro (100 = bateu o bom, 50 =
  linha do ruim, 0 = zero; custo invertido). A ponta curta é o bloco a
  trocar. É a teia de fichas, tabela, Ver a fundo, Comparar e Recordes.
- **Retenção do vídeo** — *onde o vídeo solta?* Parada 3 s (contra o
  parâmetro) e, de quem parou, quanto chegou a 25 %, 50 %, 75 % e ao fim
  (escala fixa, 100 = todos). Só em vídeo; a ficha mostra as duas teias lado
  a lado.
- **Peça × recorte** — *qual peça rende mais?* CTA e custo contra o
  parâmetro; conversas e fatia contra a melhor peça (pódio).
Eixos relativos ao melhor do recorte (cliques, CPC, leads, frequência)
SAÍRAM das teias — misturavam réguas e a forma não dizia nada; leads
continuam na linha de jornada da ficha. `RadarAxesPicker` = uma linha por
teia (pergunta + chavinhas, mínimo 3; prop `only` limita as teias);
`CreativeRadar` recebe `group`; guardado em `localStorage` como
`{ selected: { copy, video, asset } }`.

**Leitura por bloco enxuta (mesma revisão):** `BulletMeter` mostra só o que
decide — rótulo · métrica, valor, régua (faixas ruim/atenção/bom, traço do
parâmetro, triângulo da média), situação, "média x" e "▲ n % vs anterior".
Os parâmetros ("bom ≥ … · ruim < …") e "acima/abaixo da média" foram para o
tooltip.

**Moldura das fichas (`.cv-frame`, ajuste 19/09 noite):** interior de cor
DIFERENTE do fundo da página — BRANCO no claro (`rgba(255,255,255,.9)`) e
PRETO no escuro (`rgba(7,7,11,.84)`), com `backdrop-filter: blur(24px)
saturate(1.4)` dando corpo de vidro e o brilho só na borda (`::after` com
sombras internas: fio de luz no topo, halo leve). Sem tinta da paleta e sem
"fosco" lilás: o `.cv-block` interno fica transparente (sem fundo, borda,
luz do canto ou brilho). Quem colore é só o fio de 2 px do campeão
(`.cv-champion::before`, degradê vertical começando pelo azul em cima:
azul → violeta → rosa → laranja → amarelo → verde). Vale para fichas,
Recordes (campeões de todos os tempos) e pódio. O bloco de TRÁS das abas
Criativos / Peças / Recordes usa `.cv-block-sheer` (kit): quase nada de
fundo, só uma borda translúcida, sem luz do canto — para as molduras
ganharem contraste contra a página. No seletor de modo da teia, a explicação
do modo fica em linha própria e as chavinhas na linha seguinte.

**Página inteira "sheer" + cor complementar (19/09 noite, pedido dele):** o
root da página leva `cv-page-sheer` → TODO `.cv-block` de fundo (hero de
números, Campanhas, abas, Ritmo, Fatia, Parâmetros) vira quase nada com
borda translúcida (faixas `.cv-strip` continuam coloridas). E cada paleta
ganhou uma cor COMPLEMENTAR (`alt` em `cevicoPalettes.js`: Grape → ouro,
Bondi/Blueberry/Mirtilo → amarelo/âmbar, Lime/Kiwi/Abacate → rosa/vermelho,
Strawberry/Cereja/Melancia → verde-água/esmeralda, Tangerine/Laranja/Pêssego →
azul, Limão → roxo, Uva → laranja, Coco → petróleo, Graphite → ouro CEVICO;
Salada → Uva) com `altFamily` (4 degradês gerados por `shade()`), variáveis
`--cv-alt/--cv-alt-rgb/--cv-alt-grad` e a classe `.cv-alt` no kit. Nos
"Números do período" os cards alternam família × complementar em xadrez
(`blockAltFamily('kpis')` em Taxa de parada, Retenção, Custo por conversa e
Leads no CRM).

## Layout da página (ajuste 19/09)

Ordem: hero → Números do período → Campanhas → **abas + período** (o
seletor de período fica logo abaixo das abas Criativos / Ganchos, corpos e
CTAs / Recordes / Ritmo / Parâmetros e dados) → conteúdo da aba. Os filtros
de recorte (formato, status, ordem, busca, Comparar) vivem dentro da aba
Criativos. As fichas usam SEMPRE o layout "de celular" e ficam 2 por linha
no desktop; o interior responde à largura da ficha com container queries do
kit (`.cv-cq` = `container-type: inline-size`; `.cv-cq-thumb`,
`.cv-cq-meters`, `.cv-cq-kpis`, `.cv-cq-radar`). A tabela cabe sem barra
horizontal (`table-fixed`; colunas menos essenciais só em md/xl).

## Paleta pessoal + respiro (19/09 noite, pedido dele)

- **Escopo `report:criativos`** entrou em `REPORT_PALETTE_SCOPES` no
  `settings_controller` — sem isso o backend descartava a escolha do admin
  nesta tela (era por isso que "não dava para mudar o tema").
- **Cada pessoa escolhe as cores do próprio painel** (`useCevicoPalette`):
  a escolha pessoal fica em `ui_settings.cevico_palettes[escopo]`
  (`{ mode: 'fixed'|'salad'|'day', key }`) e vence a do admin só para quem
  escolheu. O popup `CevicoPalettePicker` ganhou "Para quem": *Só para mim*
  (todo mundo; opção "Padrão da clínica" volta a seguir o admin) × *Para todo
  mundo* (admin; com blocos). O chip do banner (`CevicoHero`) e o do Meu
  Painel abrem o popup para qualquer usuário.
- **Nota no Meu Painel** (`.cv-notice-dopamine`, InicioPage): "Seu painel, as
  suas cores" com botão para abrir o popup; some ao dispensar
  (`localStorage cevico_note_dopamine_colors_v1`).
- **Respiro:** blocos da Central com `p-6 sm:p-9 mb-10`; títulos de bloco
  `text-xl sm:text-2xl` (seções `text-lg sm:text-xl`); ficha `p-6 sm:p-8`
  com `gap-7`, caixa da copy `p-6`, réguas `gap-x-8 gap-y-5`, KPIs `gap-5`.

**Complementar: tinta e degradê pela luminância (19/09 noite, Tangerine):**
`altInk` em cada paleta = `dark` só quando a complementar é clara (amarelo,
ouro) — o texto usa `--cv-deep`; nas fortes (azul, rosa, verde, roxo) o
texto é branco e a `altFamily` não sobe até o tom claro (branco sobre
azul-claro não lê). `blockAltInk(blockId)` no composable, `--cv-alt-ink` nas
variáveis. Rótulo da teia de retenção: `Fim` (o "Fim do vídeo" vazava do
SVG para a teia vizinha).
