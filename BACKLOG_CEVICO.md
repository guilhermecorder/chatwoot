# Backlog CEVICO — próximas funcionalidades

> Requisitos combinados com o Guilherme para as próximas sessões.
> Contexto: fork Chatwoot em `~/chatwoot`, produção na VPS (EasyPanel,
> projeto `sistema_cevico`), banco migrado do Robomaster (~20k contatos).
> Fluxo: código → push `develop` → GitHub Actions build → Implantar web+sidekiq.

## ⚠️ PROTOCOLO DE PRODUÇÃO (desde 2026-07-10 — sistema atende leads REAIS)
O sistema NÃO é mais ambiente de teste: há atendimento humano ao vivo.
Regras para toda mudança daqui pra frente:
1. Testar SEMPRE no Docker local antes de push. Inegociável.
2. Deploy só em janela de baixo movimento — o Guilherme controla o botão
   Implantar e decide a hora. Nunca apressar.
3. Backup do banco ANTES de deploy sensível (migration/core). Por isso o
   backup automático (item 8) é PRÉ-REQUISITO das próximas features.
4. Mudanças pequenas e isoladas, uma de cada vez (fácil reverter/diagnosticar).
5. Sempre informar o plano de reversão em 1 linha antes do deploy
   (geralmente: reimplantar imagem anterior no histórico do EasyPanel).
6. Experimentos ousados → branch separada/staging, nunca no que atende.

## 1. Automação "quem NÃO tem etiqueta X → coluna Y"

Regra de segmentação por condição negativa, no Tratamento de dados (ou nova
aba de regras). Objetivo do Guilherme: medir **volume e % de leads não
responsivos** — os que nem chegam ao orçamento — e rodar campanhas/automações
específicas para eles.

- Backend: estender lógica de público para suportar "ausência de etiqueta".
  Reaproveitar `Crm::RetroLabelJob` / `resolve_audience` com condição NOT.
- Ação: mover o card desses contatos para uma coluna escolhida (ex.
  "Sem resposta") — já existe `place_in_stage` no RetroLabelJob.
- Bônus analítico: card no dashboard com % de leads que não passaram do
  primeiro estágio (funil já tem as contagens por stage).

## 2. Ticket médio por etiqueta/procedimento

Mapa etiqueta → valor médio, aplicado automaticamente ao campo `value` do
card. Exemplos dados pelo Guilherme:
- `refrativa` → R$ 5.000
- `artisan`   → R$ 11.900
- (e assim por diante, por procedimento)

- Precisa de uma tela de config (CRM → Integrações/Configurações) com o
  mapa etiqueta→valor.
- Aplicar o valor quando a etiqueta de orçamento for adicionada (na régua
  de automação e/ou no Tratamento de dados retroativo).
- Alimenta os KPIs de valor e "valor por etapa" do dashboard.

## 3. Caixa de entrada "Fechamento" (segundo número)

Adicionar a inbox "Fechamento" (outro número WhatsApp) que já funcionava no
"outro banco de dados". **CLARIFICAR na próxima sessão:** em qual banco ela
estava?
- Se estava no Robomaster → já veio na migração; só reconectar/registrar
  webhook (como a inbox principal — o botão "Cadastrar Webhook" é o corte).
- Se estava em outro lugar → conectar como nova inbox WhatsApp Cloud.

## 4. Dashboard "origem dos leads" = caixa de entrada

Hoje o `by_origin` do dashboard usa o campo `crm_contacts.origin` (às vezes
vazio nos cards migrados/retro). Trocar para derivar a origem da **inbox**
por onde o contato entrou (inbox das conversas do contato).
- Arquivo: `app/controllers/api/v1/accounts/crm/dashboards_controller.rb`
  método `build_by_origin`.
- Agrupar por inbox_name das conversas em vez do campo origin livre.

## 5. Mobile — CRM e sistema funcionais no celular

O Chatwoot core já é responsivo (conversas funcionam bem no celular), mas as
telas CUSTOMIZADAS foram desenhadas para desktop e precisam de adaptação:
- **CRM board**: colunas largas fixas (w-64) com scroll horizontal — no
  celular precisa de navegação melhor (ex: uma coluna por vez com swipe,
  ou seletor de coluna no topo).
- **Campanha WhatsApp**: composers em modal largo (max-w-2xl) — empilhar
  campos no mobile.
- **Dashboards/Funil de Tráfego/Saúde**: grids já usam breakpoints sm/lg,
  conferir e ajustar.
- **Academia**: grid já responsivo, conferir hero.
- Testar tudo com viewport ~390px.

## 6. ~~Corte final~~ — CONCLUÍDO (2026-07-10, via Henrique, fora do processo planejado)

Henrique desconectou o número do Robomaster e conectou direto no CEVICO,
e conectou o N8N (automação de atendimento IA). **Não foi feita a
ressincronização planejada** — 42 conversas que chegaram no Robomaster
entre a migração e a troca ficaram só lá. Decisão do Guilherme: aceitar a
perda (o agendamento dessas pessoas já tinha sido feito manualmente) —
NÃO importar. Robomaster permanece como backup, pode ser mantido rodando
ou parado (opcional, economiza recursos da VPS já que não recebe mais nada).

**Implicação técnica importante:** CEVICO agora é o banco vivo de produção.
Não fazer mais nenhum "dump-and-replace" geral — qualquer recuperação de
dados do Robomaster daqui pra frente precisa ser importação cirúrgica
(registros específicos), nunca substituição do banco inteiro.

## 8. Backup periódico do banco CEVICO — ✅ FEITO (2026-07-10)

Configurado na VPS: `/root/backup_cevico.sh` + cron `0 6 * * *` (3h BRT).
pg_dump do `chatwoot_migrado` (resolve o container dinamicamente pelo nome
sistema_cevico_postgres, que muda a cada deploy), gzip, salvo em
`/root/backups/cevico/`, retenção 14 dias, log em backup.log. Primeiro
backup validado (~39MB). Restore: `gunzip -c ARQUIVO.sql.gz | docker exec
-i CONTAINER psql -U postgres -d BANCO_DESTINO`.
- PENDENTE (próximo passo de resiliência): cópia off-VPS automática (rclone
  → Google Drive/S3) para proteger contra falha total da VPS. Hoje o backup
  é só local ao disco da VPS.

## 7. Caixas de entrada por atendente ("selecionar e ocultar")

Primeiro testar o NATIVO: atendentes como papel Agente + colaboradores por
caixa (Config → Caixas → Colaboradores). Agente só vê as caixas em que está;
para "cobrir a parceira", ambas nas duas caixas e cada uma filtra clicando
na sua na sidebar. Se o fluxo nativo não bastar, construir preferência
por usuária de mostrar/ocultar caixas na sidebar.

## 9. DASHBOARD DO NEGÓCIO (grande — arquitetura completa)

**FORMATO: página VIVA dentro de Relatórios** (Vue, como CrmDashboard/
TrafficFunnel/WhatsappHealth), interativa, com filtro de datas. NÃO é site
externo. Fontes "plugáveis" via CRM → Integrações (padrão já existente):
o usuário conecta e o painel acende. Maquete de layout aprovada (artifact
publicado — 6 painéis + selos de fonte). Gráficos clean, barra E pizza.

**Oftalmofácil (ERP) = fonte da JORNADA COMPLETA do paciente** (substitui a
planilha manual quando conectado). PENDENTE: confirmar se o Oftalmofácil
oferece API/webhook/export automático — perguntar ao suporte deles. Até lá,
planilha de fechamento é a ponte (CSV por URL já testado). Trocar planilha→
ERP depois sem refazer o dashboard.

Decisão pendente p/ Fase A: quais stages do CRM = "Agendamento" e "Cirurgia"
(provável: "Agendamento de Consulta" e "Cirurgia") — confirmar com Guilherme.

Ordem: Fase A (só CRM: funil, leads, origem, recordes, metas, filtro datas —
sem dep. externa, seguro) → Fase B (planilha/Oftalmofácil: faturamento,
cirurgias, ticket, procedimentos, status) → Fase C (Meta pronto/falta
ad_account_id; Google/TikTok futuros).

Arquitetura deve prever TODOS os números abaixo, mesmo os sem fonte ainda
(placeholder "conectar fonte"), para a estrutura já existir:

KPIs/víses pedidas pelo Guilherme:
- CAC (investimento ÷ novos clientes) — investimento vem do Meta (já temos
  insights via ad_account_id), Google e TikTok (futuros)
- Ranking de campanhas: quais geram mais/menos resultado (otimizar verba)
- Visão de anúncios por plataforma: Meta ✅(API pronta), Google (precisa
  developer token — processo), TikTok (Business API — avaliar)
- Desempenho de conteúdos (fonte a definir — talvez TACOH/social)
- Volume de leads, responsividade (% que respondem), % conversão etapa a
  etapa do funil
- Recordes (melhor mês/dia de leads, faturamento, cirurgias)
- Faturamento e volume de cirurgias vindos da PLANILHA DE FECHAMENTO:
  https://docs.google.com/spreadsheets/d/1CjA1P8Hh0Ca0dhasDTVWEsUgzqXrZL58yNrAsTNeY-0
  Estrutura confirmada (CSV export funciona sem auth):
  colunas Status (Ativa/Cancelada/Não Compareceu), Data (DD/MM/YYYY),
  Paciente, Procedimento, Olho, Valor total (R$). 1 linha = 1 procedimento.
  → dá para importar por URL CSV (job periódico) e calcular: faturamento
  por período, volume de cirurgias, mix de procedimentos, taxa de
  não-comparecimento, ticket médio real por procedimento.

## 10. MOBILE — fase 1 ✅ FEITA (2026-07-11, aguarda deploy)
- CRM carrega por padrão só leads ativos dos últimos 30 dias (leve!) com
  botão "Carregar todos desde o início" (scope=all); meta {total, shown}.
- Colunas em carrossel no celular: 1 coluna por tela (86vw) com scroll-snap,
  desliza pro lado; desktop inalterado (md:).
Próximas fases mobile: composers de campanha empilhados, revisar dashboards
em 390px.

## 11. AUDITORIA GUILHERME+HENRIQUE (2026-07-11) — 6 blocos

Implementados de uma vez no Docker local (blocos 1,2,3,4,6; bloco 5 fica p/ depois):

**Bloco 1 — UX das atendentes (CRM)** ✅ código pronto
- Backend manda unread_count/awaiting_reply/waiting_since por card (1 query extra).
- CRM: chip "Sem resposta (N)", ordenação (aguardando/antigo→novo/novo→antigo),
  seletor de caixa na barra principal, prévia da última msg do paciente em card
  com não lidas, popup de conversa completa com RESPOSTA oficial
  (ConversationChatModal — Enter envia, marca como lida), presets de colunas
  nomeados (Vaneide/Elizangela/Gabriela/Natália — crm_settings.column_presets,
  livres para todas, gerenciáveis no seletor "Visualização").
- Caixa de entrada: usar o sort NATIVO "Aguardando há mais tempo" (já traduzido).

**Bloco 2 — Unificação de contatos/etiquetas** ✅ código pronto
- Etiqueta de conversa agora propaga ADITIVAMENTE para o contato
  (Conversation#update_labels override).
- Auto-merge por telefone/e-mail: Crm::ContactUnificationService (+Job/rotas
  crm/contact_unification/preview|apply, admin-only) com dry-run; UI em
  Campanha WhatsApp → aba Automações → card "Unificar contatos duplicados".
- Merge manual: botão "Mesclar com contato duplicado" no ContactModal do CRM
  (aba Contato) usando ContactMergeAction do core.
- ⚠ Antes do apply em produção: backup do banco. Mesclagem é irreversível.

**Bloco 3 — Tarefas (kanban)** ✅ código pronto
- Model Task (tasks: title, description, task_type, priority enum, status enum
  todo/doing/done, due_at, creator/assignee) + API /api/v1/accounts/:id/tasks.
- Página "Tarefas" na sidebar: kanban 3 colunas com drag, modal criar/editar,
  filtro minhas/todas/por pessoa, mini-dashboard (a fazer/fazendo/feito/atrasadas).

**Bloco 4 — Integrações Meta/Google completas** ✅ código pronto
- CrmIntegrationsModal ganhou seções completas Meta e Google (substituiu "Em breve"):
  Meta = pixel_id, token, ad_account_id, test_event_code + requisitos + testar envio
  (CAPI já existia e JÁ ESTÁ ligado às automações do CRM via CrmAutomationFireJob).
  Google = GA4 measurement_id/api_secret + developer_token/customer_id (Ads API,
  aguardando aprovação do token pelo Google — tela pronta).
- Status badges Envio/Recebimento por plataforma.

**Bloco 6 — Permissões/visualização de agentes** ✅ código pronto
- crm_settings.agent_permissions {user_id: [features bloqueadas]} — só admin altera
  (403 caso contrário). Config em Configurações → Agentes → botão escudo "Acessos".
- Sidebar filtra seções bloqueadas + "Personalizar menu" (ocultar/mostrar pessoal,
  localStorage). Guard de rota barra URL direta (fail-open se settings não carregou).
- Features: crm, crm_campaigns, tasks, reports, academy, companies, captain.

**Bloco 5 — Automação Instagram (direct/comentário via API oficial)** ⏳ NÃO iniciado (decisão: depois).

Migrations novas: 20260711000001 (column_presets), 20260711000002 (tasks),
20260711000003 (agent_permissions). Todas aditivas, rodaram limpas no Docker.

## 12. MARATONA 2026-07-11→13 (rodadas 1–9) — CRM vira o hub de atendimento ✅ TUDO NO GITHUB

Depois da auditoria (item 11), mais 5 rodadas de refinamento guiadas por teste
em produção. Estado: **tudo commitado e buildado** (último: `8935f3cde`).

**CRM como central de atendimento:**
- Balão de conversa nos cards: chat completo com resposta oficial, POLLING a
  cada 4s (chat "vivo"), emojis, templates WhatsApp (remarketing), resolver/
  reabrir, telefone copiável, painel mover-card+etiquetas dentro do balão,
  scroll abre no fim. Contato sem conversa → botão "Iniciar conversa" (cria
  conversation na caixa WhatsApp escolhida).
- Carga em 2 fases: 15 cards/coluna na abertura (window function) + resto em
  background. Ordenação padrão: não lidas no topo, depois última msg desc.
- Drag de cards OTIMISTA (assenta na hora, API confirma; reverte se falhar);
  coluna inteira é alvo de drop. Drag de coluna consertado (bug: componente
  multi-root quebra vuedraggable — TODO componente em draggable precisa de
  raiz única!).
- Presets de colunas por atendente (multi-seleção, união); filtros com
  rascunho + botão Aplicar; etapas multi-select; busca ignora filtro de
  período e carrega base completa; "sem resposta" (resolvida = respondida).
- Não-admin: sem ferramentas de edição, sem valores R$, sem Caixa de Entrada
  na sidebar, sem Personalizar menu.

**Robô de follow-up (crm_followup_bots):**
- Cadência texto OU mensagem modelo; minutos/horas/dias; janela começa/para;
  filtros TEM/NÃO-TEM etiqueta; por caixa OU por coluna (modo programação);
  1 conversa por contato (a mais recente = caixa prioritária); cron */2min.
- Para quando: pausado, paciente responde, ou etiqueta NÃO-TEM aparece.

**Outros módulos novos:** Tarefas (kanban+donut+avisos de prazo), Agenda
(calendário mensal, unidades Tatuapé=azul/Paulista=laranja, admin vê todas),
Automações & Robôs em Configurações, ação nativa "Mover card do CRM" nas
Automation Rules, acessos por agente (11 categorias), Tratamento de dados
(substituir/remover etiqueta em massa, valor pelo orçamento, unificação de
contatos), etiquetas de conversa sincronizam com o contato (add+remove),
integrações Meta/Google completas na UI.

**Migrations do período (todas aditivas):** 20260711000001-3 e
20260712000001-5 (column_presets, tasks+unit, agent_permissions,
crm_followup_bots + label filters + janela + stage).

**Lições técnicas:** (1) componente multi-root quebra v-show E vuedraggable;
(2) before_action com `only:` desatualizado = 500 silencioso (fronts com
.catch vazio escondem); (3) cron 15min ≠ cadência em minutos; (4) contadores:
9227 = cards no funil (inclui migrados sem conversa), 2333 = conversas
ABERTAS — métricas diferentes, ambas corretas.

## 13. RODADA 2026-07-13 — Atribuição de anúncios Meta (estilo Tintim) ⏳ AGUARDA TESTE DO GUILHERME

**Objetivo: saber QUAL ANÚNCIO gerou cada lead e cada cirurgia.**

**Como funciona (CTWA — click-to-WhatsApp):** a Meta manda um bloco `referral`
na primeira mensagem de quem clica em anúncio (id do anúncio, título, texto,
URL, ctwa_clid). O Chatwoot core já guardava isso no content_attributes da
mensagem — agora o sistema usa:

- `Crm::AdAttributionService`: carimba `additional_attributes.meta_ads` no
  CONTATO (primeiro toque — nunca sobrescreve) e na CONVERSA. Hook no
  webhook do WhatsApp (IncomingMessageBaseService#stamp_ad_attribution).
- `Crm::AdAttributionBackfillJob` (fila low): retroativo — varre mensagens
  antigas com referral e carimba os contatos. Botão "Processar histórico"
  no relatório de anúncios.
- **Exibição "muito evidente" (SÓ ADMIN — agente tem painel simples):** card
  azul "Veio de anúncio (Meta)" no painel do contato dentro da conversa
  (AdOriginCard.vue no ContactPanel) + linha "Anúncio: …" no cabeçalho do
  balão do CRM. contact_json só envia meta_ads para admin (backend também).
- **Relatórios → Anúncios (Meta)** (`/reports/ads`, admin): tabela por anúncio
  juntando Marketing API (investimento/impressões/cliques, level=ad,
  Crm::MetaAdsReportService) × leads atribuídos × conversões do CRM.
  KPIs: investimento, leads, CPL, conversões, CAC, receita, ROAS.
  Etapas de conversão configuráveis (meta_ads_config.conversion_stage_ids,
  padrão: etapas com "cirurgia" no nome). Anúncio pausado com lead aparece.
- **CAPI agora envia ctwa_clid** (action_source=business_messaging +
  messaging_channel=whatsapp) quando o contato veio de anúncio — a Meta
  atribui a conversão DIRETO ao anúncio, do lado deles também.
- Endpoints: GET/POST `crm/ads_report[/backfill]` (admin). Sem migration.

**Também nesta rodada:**
- Agente (não-admin) não vê mais Menções/Participantes/Não atendidas em Conversas.
- Balão do CRM: digitar "/" abre as mensagens rápidas (CannedResponse/MentionBox
  do core; Enter escolhe, setas navegam).

**Testado no Docker:** serviço de atribuição (carimbo+primeiro toque), payload
CAPI com ctwa_clid, endpoint do relatório (detectou etapa Cirurgia id=5,
lead+conversão+receita corretos), backfill enfileira, Vite compila tudo.
Contato de teste no banco local (account 3) ficou carimbado de propósito para
ver a UI. Falta: teste visual do Guilherme + deploy.

## 14. RODADA 2026-07-13/14 — IA interna + Formulários ⏳ AGUARDA TESTE

**Camada de IA interna (SDK oficial `anthropic` no Gemfile):**
- CRM → Integrações → IA: api_key da Anthropic + modelo (padrão
  claude-opus-4-8; opções sonnet-5/haiku-4-5). Migration ai_config (jsonb).
- Painel da conversa: card-resumo (nome/telefone copiáveis 1 clique,
  estágio do CRM com cor, etiquetas, responsividade %, msgs, última
  resposta) + botão "Analisar com IA" → indicador de interesse
  (alto/médio/baixo/perdido) + parágrafo + próximo passo, salvo em
  conversation.additional_attributes.ai_insight. Custo ~8 centavos/análise
  (Opus). Macros e Atributos do contato removidos do painel.
- Serviços: Crm::ConversationInsightService, Crm::FormInsightService
  (structured outputs — JSON garantido).

**Formulários (pré-operatório etc.):**
- Tabelas crm_forms/crm_form_responses (migration 20260714000002).
- Página pública /forms/:slug/:token (SEM login, token assinado por
  contato via message_verifier) — wizard estilo Typeform: 1 pergunta por
  vez, barra de progresso, mobile-first, azul CEVICO. Tipos: escolha única,
  múltipla, sim/não, escala 0-10, aberta. Resposta cai amarrada ao contato.
- Página "Formulários" (sidebar, admin): builder de perguntas + dashboard
  (barras % por opção, média de escala, respostas abertas) + botão
  "Gerar insights com IA" (dores/desejos/objeções/recomendações).
- Automação de coluna "Enviar formulário" (send_form): manda link único
  na conversa mais recente, {{nome}}/{{link}}, não reenvia p/ quem já
  respondeu. Uso: coluna Agendamento de Consulta → formulário pré-op.
- Link usa FRONTEND_URL — conferir env na produção.

**Reorganização (mesma rodada):**
- Sidebar: CRM em 1º; abas "Automações" (Réguas/Robôs/Regras da caixa/
  Agentes de IA/Modo Programação/Tratamento) e "Integrações" acima de
  Configurações (admin). Saíram de Configurações: Automações/Robôs/
  Automation nativa.
- Integrações = página única (crm/integrations): central CEVICO (n8n/Meta/
  Google/Claude com "Testar conexão" real via test_ai) + apps nativos
  (IntegrationItem reusado). Botão do board aponta pra lá.
- Agentes de IA editáveis: ai_config.agents.{conversation,form} com
  enabled (botão Parar/Ativar) e prompt custom — services respeitam.
- Nova ação de coluna "ai_analyze" (Analisar com IA ao entrar na coluna).
- CRM board aceita ?programming=1; Campanha aceita ?tab=automations.
- Dashboard CEVICO: presets hoje/ontem/semana, "conversa" no lugar de
  "lead", KPIs em gradiente (azul/lime/ouro/roxo), timeline em colunas
  arredondadas 3 séries (conversas/agendamentos/cirurgias via stage_logs),
  origem = conversas por caixa de entrada, bloco Atendimento por agente
  (abertas/sem resposta/1ª resposta, seletor individual), + espaçamento.
  Funil de Tráfego e Tarefas com mais respiro.

## 15. RODADA 2026-07-13 (tarde) — Início + Google Sheets + Agendamento por IA ⏳ AGUARDA TESTE

**Tela de Início (`/inicio`, 1º item da sidebar, admin+agente):**
- Boas-vindas com nome de quem está logado (Bom dia/Boa tarde/Boa noite) +
  data em pt-BR, banner em gradiente azul→roxo.
- KPIs do dia (fuso São Paulo): conversas hoje, aguardando resposta,
  consultas hoje (agenda das unidades), cirurgias na semana (stage_logs).
- Acesso rápido (CRM/Conversas/Agenda/Tarefas) + próximas 6 consultas.
- Backend: `crm/home_controller` (GET crm/home). Sem migration própria.

**Google Sheets (planilha de cirurgias → Dashboard):**
- Migration `20260714000003` (sheets_config jsonb em crm_settings).
- Card "Google Sheets" em Integrações: cola o link de compartilhamento
  ("qualquer pessoa com o link" — Leitor), botão "Importar agora" com
  prévia das 5 primeiras linhas.
- `Crm::SheetsSurgeryService`: converte link→CSV export, colunas flexíveis
  (Data/Nome|Paciente/Telefone/Procedimento|Cirurgia/Valor/Unidade),
  entende "R$ 5.000,00" e datas dd/mm[/aaaa]; cache 1h no jsonb.
- Dashboard CEVICO: bloco "Cirurgias — planilha" (qtd, receita, por
  unidade, por procedimento) filtrado pelo período selecionado.

**Agente de Agendamento (IA) + Agenda repaginada:**
- Nova ação de coluna "Agendar consulta (IA)" (`schedule_appointment`):
  quando o card entra (ex. coluna "Consulta agendada"), a Claude lê a
  conversa e extrai nome/telefone/dia/hora/unidade (structured output,
  `Crm::AppointmentExtractionService`, fuso SP, dias da semana em pt).
- Com dia+hora confirmados → cria tarefa-consulta na Agenda (unit
  tatuape/paulista, task_type 'consulta', dedup por título+horário) +
  nota privada na conversa. Sem confirmação → tarefa "⚠️ Confirmar
  consulta" (prioridade alta) para a equipe completar.
- Config da automação: unidade padrão opcional (default_unit).
- 3º agente em Automações → Agentes de IA ('scheduler': parar/ativar +
  prompt custom, respeitado pelo service).
- Agenda: header no estilo do Dashboard CRM (ícone gradiente, botão Hoje
  gradiente) + KPIs (hoje/semana/unidade no mês; card da unidade filtra).

**Testado no Docker:** migration ok, parser da planilha (valores/datas/
acentos), export_url, task-consulta no fuso certo, rotas novas, erro
amigável p/ link fake, Vite compila os 11 arquivos. Falta: teste visual
do Guilherme (a extração por IA precisa da chave configurada) + deploy.

## 16. RODADA 2026-07-13 (noite) — Modelo/esforço por agente + Dashboard Campanhas + sidebar gradiente ⏳ AGUARDA TESTE

**Modelo e esforço de IA por agente (sem migration):**
- Novo módulo `Crm::AiAgentConfig` compartilhado pelos 3 services: modelo e
  esforço resolvem por agente > global > padrão (Opus 4.8 / high).
- "Esforço" = `output_config.effort` da API da Anthropic (low/medium/high/
  max, GA). Haiku 4.5 NÃO aceita o parâmetro — o módulo omite sozinho.
- Integrações → Claude: ganhou select de "Esforço padrão" ao lado do modelo.
- Automações → Agentes de IA repaginada: cards com faixa/gradiente e cor
  própria por agente, etiqueta de categoria (Atendimento/Marketing/Agenda),
  chips "Onde se aplica" (botões/ações que disparam cada agente), selects de
  Modelo e Esforço por agente ('' = padrão global), selo "Em uso: modelo ·
  esforço" resolvido, e dica de custo por agente.
- max_tokens: conversa 1024→2048, agendamento 512→1024 (folga p/ Sonnet 5,
  que pensa por padrão).

**Dashboard de Campanhas (Relatórios → Dashboard Campanhas):**
- `crm/campaigns_dashboards_controller` (GET crm/campaigns_dashboard):
  presets de período iguais ao Dashboard CRM + custo por mensagem (campo na
  tela, salvo no navegador) → investimento = enviadas × custo.
- KPIs: investimento, volume de mensagens, taxa de responsividade (respondeu
  após o disparo), valor em campanha ($ dos cards dos destinatários),
  avaliações agendadas + % consultas, cirurgias + % (destinatários cujo card
  ENTROU nas etapas Agendamento/Cirurgia após o disparo, via stage_logs).
- Tipo de mensagem: barras por template. Tabela campanha por campanha.
- Visual idêntico ao Dashboard CRM (KPIs gradiente, header, presets).
- Campanha "Teste Dashboard" criada no banco LOCAL (conta 3) p/ visualizar.

**Sidebar com ícones em gradiente:**
- Cada item do menu recebe a cor interpolada da sua posição: Início azul
  (#0F5FA6) → meio roxo (#7C3AED) → Configurações dourado (#D4A017).
- Props iconColor em SidebarGroup/SidebarGroupHeader (vale também colapsada).

**Testado no Docker:** resolução por agente (scheduler Sonnet/low, form
Haiku sem effort, conversation herda global), rota nova, agregação do
dashboard (1 enviada/1 resposta/investimento), Vite compila os 8 arquivos.

## 17. RODADA 2026-07-13 (noite 2) — Agenda de Consultas (Mês/Semana/Dia) + pílulas no CRM ⏳ AGUARDA TESTE

**Agenda vira Agenda de Consultas (migration 20260714000004):**
- tasks ganham phone, procedure (problema) e doctor — a ficha da consulta é
  Nome | Telefone | Problema | Dia | Horário | Médico | Unidade.
- AgendaBoard reescrita: visões **Mês / Semana / Dia** em pílulas gradiente.
  Semana = 7 colunas com cards por horário; Dia = timeline 07h–20h com a
  ficha completa (telefone/problema/médico/unidade). Todo o texto virou
  "consulta/agendamento" (nada de "tarefa").
- Modal novo de consulta: nome*, telefone, problema (sugestões: catarata,
  refrativa, ceratocone, lentes fácicas, exames...), dia, horário, médico,
  unidade, situação (Agendada/Concluída), observações.
- Filtro: "Todas as consultas" (padrão), por unidade, agenda pessoal e por
  pessoa (admin). Agente de Agendamento (IA) agora extrai também problema e
  médico e preenche os campos estruturados.
- Consulta de teste "Maria Silva" (15/07 14h, Catarata, Dr. Corder, Tatuapé)
  criada no banco local.

**CRM board — botões pré-configurados e layout novo:**
- Visualizações de colunas (column_presets) deixaram o dropdown e viraram
  GRUPO DE PÍLULAS na linha de filtros (direita): "Todas as colunas" +
  uma pílula por preset (ativa = gradiente azul→roxo, multi-seleção) +
  engrenagem para gerenciar.
- Botões do topo (Editar Kanban / Modo Programação / Integrações /
  Mensagens em massa / Novo funil) agrupados num único container de
  pílulas alinhado, no mesmo design dos presets do dashboard; lápis/lixeira
  do funil num grupo compacto separado.

**Testado no Docker:** migration ok, consulta com todos os campos criada,
sintaxe Ruby, Vite compila Agenda/CrmBoard/Início.
⚠️ Deploy: agora são **4 migrations** pendentes no lote.

## 18. RODADA 2026-07-13 (noite 3) — Radar de Oportunidades + custos de IA + Meu Painel ⏳ AGUARDA TESTE

**Robô de follow-up — tipo de contagem por etapa:**
- Cada etapa ganhou o seletor "contando a partir de": *sem resposta do
  paciente* (padrão, comportamento atual) ou *desde a entrada na coluna*
  (só robôs de coluna). step['delay_from'] no job.

**Uso de tokens + relatório de gastos (migration 20260714000005):**
- Tabela crm_ai_usages: toda chamada de agente grava tokens + custo US$
  (preços Anthropic no Crm::AiAgentConfig::PRICING).
- Automações → Agentes de IA: painel "Gasto com os agentes" (hoje/7d/30d/
  total + por agente) e selo "30 dias: N análises · US$ X" em cada card.
- Endpoint GET crm/settings/ai_usage.

**Radar de Oportunidades (4º agente, key 'opportunity'):**
- Objetivo: nunca mais perder paciente pronto para agendar por falta de
  atendimento. Cron a cada 10 min (Crm::OpportunityRadarJob).
- Config no card do agente: colunas vigiadas (pílulas) + minutos de espera
  (padrão 10). Sem coluna marcada = desligado.
- Crm::OpportunityRadarService: candidatos = conversas abertas de contatos
  nas colunas vigiadas com waiting_since > N min; IA (Haiku recomendado)
  classifica "quente?" + motivo + ação; máx 15 análises/rodada; não
  reanalisa a mesma conversa por 6h; aviso some quando atendida.
- Avisos no MEU PAINEL: bloco vermelho com nome, telefone, coluna, tempo
  de espera, motivo, "o que fazer" e botão "Atender agora →".
- Aviso SIMULADO no banco local para ver o visual.

**Modelos recomendados pré-selecionados (Crm::AiAgentConfig::RECOMMENDED):**
- Analista de Conversas → Opus 4.8/alto; Formulários → Sonnet 5/alto;
  Agendamento → Sonnet 5/médio; Radar → Haiku 4.5 (sem esforço).
- Resolução: escolha do agente > recomendado > global. Selects mostram
  "⭐ Recomendado — X" como opção padrão.

**Meu Painel = tela inicial:**
- "Início" renomeado para "Meu Painel"; primeira navegação após login/
  abertura cai no /inicio em vez de Conversas (guard no router).

**Fix de ambiente local:** o container sidekiq caía em loop desde a gem
anthropic (sem bundle install no boot). Criado docker/entrypoints/
sidekiq.sh + entrypoint no docker-compose — crons agora rodam localmente.

⚠️ Deploy: lote com **5 migrations**. Produção não é afetada pelo fix do
compose (EasyPanel usa imagem própria).

## 19. RODADA 2026-07-14 — Radar na sidebar, formulários prontos, agenda dos médicos ⏳ AGUARDA TESTE

**Radar chama atenção:** badge com o nº de avisos ativos no item "Meu
Painel" da sidebar (getter crm/getRadarAlertCount, refresh a cada 5 min).

**CRM board:** filtros (Sem resposta/ordenação/caixa/Filtros) agrupados à
direita JUNTO das pílulas de visualização; contador ficou ao lado da busca;
botão "excluir funil" OCULTADO (lápis de renomear continua).

**Trava operacional nos prompts:** Crm::AiAgentConfig::OPERATIONAL_GUARDRAIL
anexada a TODO system_prompt (padrão OU personalizado): agente é interno,
NUNCA envia/redige mensagem para paciente, responde só no formato pedido.
(Nenhum agente tem canal de envio no código — a trava é reforço.)

**Formulários prontos (lib/tasks/cevico_forms.rake, idempotente por slug):**
- "Pré-Operatório" (15 perguntas: saúde, medicamentos, alergias, lentes e
  prazo de suspensão, gripe/COVID, acompanhante, contato de emergência,
  ansiedade, medos) — slug pre-operatorio.
- "Antes da Consulta de Avaliação" (13 perguntas: objetivo, tempo de óculos,
  grau, família, condições, incômodos, motivação 0-10, prazo, origem) —
  slug antes-da-avaliacao. Criados na conta 3 local; em produção rodar:
  `bundle exec rails cevico:seed_forms ACCOUNT_ID=1`.
- Layout público já é o typeform azul CEVICO (item 14).

**Agenda — médicos e janelas de avaliação:**
- 3 médicos com cor própria: Dr. Gustavo Bittar (azul), Dr. Henrique
  Gemelli (roxo), Dra. Roberta Negri (dourado). Modal usa select.
- 7 JANELAS hardcoded (WINDOWS no AgendaBoard): seg Gustavo Paulista 8h30-10h;
  ter Henrique Paulista 8h-11h30 + Roberta Paulista 14h30-16h15; qua Henrique
  Paulista 13h-17h + Gustavo Tatuapé 8h30-11h (10min); qui Gustavo Paulista
  8h30-11h; sex Roberta Tatuapé 10h30-13h (10min). Sáb/dom BLOQUEADOS.
- Visão DIA: grade de blocos por janela — livre (tracejado, clique agenda
  pré-preenchido com horário/unidade/médico) vs ocupado (nome do paciente).
- Visão SEMANA: chips dos médicos no cabeçalho de cada dia; fim de semana
  cinza "Bloqueado". Mês: fim de semana esmaecido com cadeado.
- Botão "Janelas dos médicos" no header → modal com o mapa semanal completo.

**Critérios dos modelos por agente** (registrado p/ referência): complexidade
da tarefa × frequência/custo × risco do erro. Conversas=Opus (nuance, sob
demanda); Formulários=Sonnet/alto (síntese volumosa); Agendamento=Sonnet/
médio (extração estruturada, erro visível na Agenda); Radar=Haiku (sim/não
frequente, barato).

## 20. RODADA 2026-07-14 (2) — Janelas editáveis, horário do Radar, barra do CRM ⏳ AGUARDA TESTE

- **Janelas dos médicos EDITÁVEIS** (migration 20260714000006, agenda_config
  jsonb): botão Editar no modal (admin) — dia, médico, unidade, turno,
  início/fim, bloco (10/15/20/30) + adicionar/remover. Salva via POST
  crm/settings/update_agenda; Agenda lê das settings (padrão = as 7 janelas).
- **Cores trocadas**: Henrique → dourado (#B8860B), Roberta → roxo (#7C3AED).
- **Radar com expediente**: cron continua */10, mas o job só age das
  07:30–18:00 (SP); fora disso roda só às 20h/00h/04h (a cada 4h).
  Testado com 10 horários (todos ✓).
- **Barra do CRM repaginada**: título com ícone gradiente, aba do funil
  ativa em gradiente, linha de filtros estável (busca → filtros → pílulas
  de visualização → contador no fim, flex-wrap sem pílula órfã).
- **Botões de Automações do menu CONSERTADOS**: os subitens apontam para a
  mesma rota com ?tab= — faltava watch no route.query.tab do hub; agora
  Robôs/Agentes de IA/Modo Programação/Tratamento trocam a aba de verdade.

⚠️ Deploy: lote com **6 migrations** (ai, forms, sheets, tasks-consulta,
ai_usages, agenda_config). Backup antes, sempre.

## 21. RODADA 2026-07-14 (3) — Etiquetas no Dashboard, Radar refinado, cadeado, Radar da Agenda ⏳ AGUARDA TESTE

**Dashboard CRM:**
- Doughnut "Etiquetas dos leads" (volume + % por etiqueta, lista ao lado,
  top 12, via taggings dos contatos do funil).
- Card "Radar de Oportunidades": oportunidades detectadas × consultas
  agendadas no período (histórico de detecções em opportunity_state.history,
  cap 500).

**Radar de Oportunidades:**
- Monitora SÓ movimento novo: lookback configurável (6/12/24/48h, padrão
  24h) — não varre o estoque da coluna. Faixa "O que o Radar monitora" bem
  evidente no card + estatísticas da última rodada (candidatos/analisados/
  novas oportunidades).
- **Varredura manual**: por coluna, etiqueta e período (6h/24h/3d/7d) —
  botão "Varrer agora" → POST crm/settings/radar_scan → job assíncrono
  (teto 40 análises). Avisos caem no Meu Painel.

**Agenda — cadeado de horários:**
- Bloco livre ganha mini-cadeado (hover, admin) → fecha o horário; bloco
  fechado fica cinza com 🔒 e clique reabre. Salvo em agenda_config.blocked
  ({date,time,unit,doctor}); update_agenda agora aceita windows E blocked
  separadamente. Bloqueados saem da conta de ocupação.

**Meu Painel — "Radar da Agenda" (substitui Próximas consultas):**
- Vagas livres mais próximas (3 chips, 14 dias, clicáveis → Agenda).
- Agenda % cheia próximos 7 dias (barra) · Aproveitamento últimos 7 dias ·
  % comparecimento (30d) · **% de agendamento** (consultas÷novos contatos
  30d) com veredito colorido (≥15% muito bom / ≥10% bom / ≥5% regular /
  <5% fraco) + linha "próxima consulta".
- Helper compartilhado dashboard/helper/cevicoAgenda.js (janelas, blocos,
  scanAgenda) usado pela Agenda e pelo Meu Painel.

Sem migration nova (lote segue com 6).

## 22. RODADA 2026-07-14 (final) — Meu Painel v2, fechar dias, Radar limpo, menu do agente ⏳ AGUARDA TESTE

**Meu Painel redesenhado (v2):**
- Presets: Hoje | Ontem | Essa semana | Este mês | Mês passado (home
  controller aceita ?preset=, fuso SP).
- Indicadores do período: novas conversas, consultas agendadas, taxa de
  agendamento (consultas÷conversas, com veredito), cirurgias fechadas
  (planilha Sheets), reagendadas, canceladas, indicações de cirurgia
  (entradas na etapa Cirurgia).
- Saúde da Agenda: barras mais grossas (h-3.5) — agenda cheia 7d,
  aproveitamento 7d, comparecimento 30d + % agendamento 30d (15/10/5) +
  vagas livres (4 chips) + próxima consulta.
- Acesso rápido compacto em linha (4 tiles largura toda); termômetro do
  momento no rodapé. Grid responsivo (mobile 2 col).
- Migration 20260714000007: tasks.canceled_at + rescheduled_count.
  tasks#update incrementa reagendamento quando due_at muda em consulta;
  param canceled define canceled_at. Modal da Agenda ganhou pílula
  "Cancelada" (sai do calendário, conta no painel).

**Agenda — fechar DIAS inteiros:**
- Botão "Fechar este dia" na visão Dia (admin) → agenda_config.blocked_days;
  dia fechado: banner vermelho + cadeado vermelho no mês/semana + fora da
  conta de ocupação/vagas. Reabrir no próprio banner.

**Radar de Oportunidades — card simplificado:**
- Faixa de 2 linhas: "monitora só movimento novo · avisa no Meu Painel ·
  nunca fala com o paciente" + última rodada.
- Varredura pontual saiu do card → JANELA PRÓPRIA (modal isolado) com
  coluna/etiqueta/período + explicação.
- Custo estimado (registrado): ~US$0,002/análise no Haiku; com dedup de 6h
  o custo depende do nº de conversas novas/dia, não da cadência —
  30 conversas/dia ≈ US$ 1,60/mês; teto prático ~US$ 10/mês. 10 vs 15 min
  quase não muda o custo.

**Menu do agente (não-admin):** Meu Painel | CRM | Conversas | Agenda |
Tarefas | Configurações (→ perfil: nome/e-mail/foto/senha). Meu Painel já
era acessível a agentes (rota admin+agent).

⚠️ Deploy: lote com **7 migrations**. Backup antes, sempre.

---

## 23. RODADA 2026-07-14 (madrugada 2) — Radar em vigias + Radar pontual ⏳ AGUARDA TESTE

Finalização do Radar de Oportunidades, agora em DUAS peças distintas:

**Radar perene (vigias):**
- As "colunas vigiadas" viraram VIGIAS: cada vigia = coluna do CRM +
  painel de destino ("avisar no painel de": um atendente específico ou
  👥 Todos) + janela de tempo própria (6/12/24/48h). Botão "+ Vigiar
  outra coluna" adiciona quantas quiser; lixeira remove.
- Config salva em ai_config.agents.opportunity.watchers
  [{stage_id, user_id, lookback_hours}]; wait_minutes continua global.
  Compat: config antiga (stage_ids) vira vigia "Todos" automaticamente.
- Aviso do Radar agora carrega user_id/user_name do painel de destino.
- Meu Painel: ADMIN vê todos os avisos (com selo "📌 para Fulana");
  ATENDENTE só vê os avisos direcionados a ela + os gerais (sem destino).
  Badge da sidebar (opportunity_alerts_count) segue a mesma regra.

**Radar pontual (varredura única):**
- Modal renomeado "Radar pontual" com selo "roda uma vez": escolhe coluna,
  ATENDENTE de destino (novo), etiqueta opcional e período — dispara o
  job uma vez e NÃO fica ativo. Endpoint radar_scan aceita user_id.

Arquivos: opportunity_radar_service.rb (vigias/effective_watchers/
build_alert com destino), opportunity_radar_job.rb (skip por watchers),
settings_controller.rb (permit watchers + radar_scan user_id + badge
filtrado), home_controller.rb (filtro por papel), AutomationsHub.vue
(UI das vigias + modal), InicioPage.vue (selo de destino).

Testado no Docker local: permit round-trip, save pela tela, job pontual
com {stage_ids:[1], since_hours:6, user_id:1} nos logs do sidekiq
(parou em "sem chave de API", guarda esperado no local), avisos
simulados no Meu Painel com selo. Sem migration nova.

---

## 24. RODADA 2026-07-14 (madrugada 3) — Painel panorâmico + Agenda por médico e ocupação ⏳ AGUARDA TESTE

**Modo Programação = painel panorâmico de automações (AutomationsHub):**
A aba deixou de listar só automações de coluna e virou a visão de TUDO que
trabalha sozinho, em 4 seções com contagem e situação de cada item:
- ✨ Agentes de IA (4): status Ativo/Parado + modelo em uso; Radar mostra
  nº de colunas vigiadas. Clique → aba Agentes.
- 🤖 Robôs de follow-up: nome, nº de cutucadas, Ativo/Pausado → aba Robôs.
- 📣 Réguas de mensagem (fetchMessageAutomations no mount) → Campanha WhatsApp.
- ⚡ Automações de coluna (lista existente) + botão "Abrir Modo Programação
  no CRM" (crm?programming=1).

**Agenda — filtro por médico + ocupação % (AgendaBoard):**
- Seletor ganhou grupo "Médicos" (view `doctor:Nome`): filtra consultas E
  janelas do médico em todas as visões; "Nova consulta" pré-preenche o
  médico filtrado.
- Card "Ocupação da agenda" no topo: 3 medidores (Dia/Semana/Mês, seguindo
  a navegação do calendário e o filtro ativo — clínica/unidade/médico),
  com % + "X de Y blocos ocupados". Fórmula: blocos ocupados ÷ blocos das
  janelas (cadeados e dias fechados fora da conta; scanAgenda compartilhado
  com o Meu Painel). Cores: verde <50 (com vagas) · dourado 50–79 ·
  vermelho ≥80 (quase cheia).
- Chip de % em cada dia nas visões Mês e Semana (mesmas cores).
- Visão Dia: chip "X% ocupado" no card de cada janela de médico.
- Ocupação some nas visões pessoais (me/pessoa), onde não há janelas.

Testado no Docker local: consulta de teste 15/07 13:00 (Paulista/Henrique)
id=5 → dia 6% (1 de 16), semana 3% (1 de 30), mês 1% (1 de 136) no filtro
do médico. Sem migration, sem mudança de backend.

---

## 25. RODADA 2026-07-14 (pós-deploy) — Ajustes do feedback de produção ⏳ AGUARDA TESTE

Lote 14–24 FOI PRO AR (deploy EasyPanel ok, backup manual feito antes,
build ~26min por recompilação sem cache — gem nova). Ajustes pedidos pelo
Guilherme olhando produção:

1. **Responsividade (Dashboard CRM):** barras em GRADIENTE (paleta oficial)
   com largura proporcional à MAIOR etapa (não ao total) — cheias e
   legíveis, "X% · N conversas" escrito dentro (ou ao lado quando curta).
2. **Conversas ao longo do tempo:** séries de agendamento/cirurgia viraram
   COORTE — leads distribuídos pela data REAL de chegada (contacts
   .created_at), contando quantos avançaram até a etapa. Antes usava
   entered_at do stage_log → pico artificial de 2k no dia do tratamento
   em massa. Séries renomeadas: "Chegaram a agendar/à cirurgia".
3. **Meu Painel:** "Consultas agendadas" = max(Agenda tasks, entradas em
   etapa %agendamento% no CRM via StageLog) — produção agenda no CRM.
   CUTOFF 2026-07-14 00:00 BRT ignora o retro em massa (constante
   CRM_TRACKING_START no home_controller). + auto-refresh: 2 min +
   visibilitychange.
4. **CRM board:** pílulas DOURADAS de período do lead (Hoje|Ontem|Essa
   semana|Últimos 7 dias|Este mês) à direita das pílulas de colunas —
   preenchem o De/Até; re-clique desliga; edição manual no painel de
   filtros desliga a pílula.
5. **Agenda:** botão "Nova consulta" movido pra ESQUERDA (ao lado do
   título) em verde contrastante (#059669→#34D399).

Sem migration. Testado no Docker local (dashboard, board, agenda, painel).

---

---

## 26. RODADA 2026-07-14 (dia) — Interruptor definitivo dos agentes de IA ⏳ AGUARDA TESTE

Pedido do Guilherme (receio de "ligar a IA e não conseguir desligar"):

**Interruptor definitivo (kill switch) em 3 camadas:**
1. `Crm::AiAgentConfig#agent_paused?` agora exige `enabled == true` GRAVADO
   — padrão (sem config) = DESLIGADO. Vale para TODOS os caminhos: botão
   na conversa, automação de coluna e cron do Radar (job também opt-in).
2. Toggle na tela dos agentes grava NA HORA (updateAi com merge por
   agente — não apaga prompt/modelo/vigias; endpoint agora faz deep-merge
   em vez de substituir cfg["agents"] inteiro). Chips "Ligado/Desligado",
   selo "vale na hora".
3. Automação de coluna com agente desligado = serviço recusa e nada roda
   (sem custo, sem chamada à API).

**Modal "Nova automação" (Modo Programação):** ações "Analisar com IA" e
"Agendar consulta (IA)" viraram UMA ação "🤖 Adicionar agente de IA" com
seletor "Qual agente?" (por baixo continua ai_analyze/schedule_appointment
— zero mudança de backend) + aviso âmbar de que só roda com o agente
LIGADO. ACTION_LABELS do painel panorâmico atualizados.

Testado no Docker local: 3 estados do interruptor (ausente/false→pausado,
true→roda), clique liga/desliga gravando na hora preservando vigias e os
demais agentes, modal com a ação nova. PENDENTE: Guilherme vai enviar o
JSON do fluxo N8N do agente de agendamento p/ mapear o comportamento.

---

## 27. RODADA 2026-07-14 (tarde) — Gatilho "Mensagem criada" + preço no card + N8N mapeado ⏳ NÃO COMMITADO, AGUARDA APROVAÇÃO

⚠️ REGRA REFORÇADA PELO GUILHERME: NUNCA commit/push sem aprovação
explícita dele. Este lote está SÓ no working tree local.

**1. Gatilho "Mensagem criada na conversa" (automações de coluna):**
- CrmListener#message_created (async dispatcher): mensagem não-privada
  incoming/outgoing → dispara automações trigger_type=message_created da
  coluna onde o card está AGORA. 2 consultas indexadas por mensagem.
- Config (action_config): message_direction incoming(padrão)/outgoing/both
  + throttle_minutes (0=toda mensagem p/ n8n; 5/30/60/1440 = no máx 1 por
  período POR CONTATO, via AutomationLog). Notas internas não disparam.
- Testado: mensagem → set_value aplicou; 2ª mensagem segurada pela trava.

**2. Ação "Adicionar preço no card" (set_value):**
- action_config: value + value_mode (always substitui | if_empty só se
  vazio | add soma). Alimenta valor em pipeline/valor por etapa.
- Uso combinado c/ item 2 do backlog antigo (ticket médio por etiqueta):
  gatilho etiqueta adicionada + set_value já cobre parte do caso.

**3. Tratamento "contém X, ou Y, ou Z → mover coluna":** JÁ EXISTIA no
motor (RetroLabelJob: etiqueta OPCIONAL, multi-termo por vírgula = OR,
place_in_stage) — só o texto da tela escondia. Títulos/descrições
atualizados ("Etiquetar e/ou MOVER por conteúdo").

**FLUXO N8N "AGENTE DE AGENDAMENTO" MAPEADO (JSON recebido, 102 nós):**
- Gatilho: webhook message_created do Chatwoot (Robomaster).
- Pausa: msg da atendente pausa IA; emoji 😊 na msg do bot pausa
  (confirmação de agendamento tem 😊 → pausa sozinho); 👍 reativa;
  estado em Supabase dados_cliente.atendimento_ia.
- Fila: mensagens do paciente acumulam no Redis, espera 10s, junta tudo
  e processa 1 vez (anti-mensagem-picada); compara com última pra dedup.
- Mídia: áudio → Whisper transcreve; imagem → gpt-4o-mini OCR.
- Supervisor (gpt-5-mini + memória Postgres 20 msgs + RAG + calculator):
  prompt 44k chars "Guilherme, atendente da CEVICO" — 5 contextos (novo/
  agendado/pós-consulta/pós-cirúrgico/reagendamento), fluxo 6 etapas
  (recepção→sondagem→autoridade→orçamento→agendamento→confirmação),
  máx 3 frases/150 chars por msg, sem emoji (exceto 😊 confirmação),
  sem travessão/markdown. Scripts de autoridade (Schwind Amaris 1050RS,
  Dr Jorge Haddad 30k cirurgias, unidades Paulista/Tatuapé c/ links).
- calendar_agent (sub-agente): Google Calendar por unidade (2 agendas),
  blocos 15min (manhã 9h-11h, tarde 13h30-16h), Tatuapé 10min,
  description obrigatória "Telefone/Nome/Valor" (consulta ~R$150).
- Saída: resposta fatiada em msgs humanizadas de 150-250 chars
  (gpt-4.1-mini) com intervalo entre envios.
- Prompt completo salvo em /tmp/supervisor_prompt.txt (local).
- PRÓXIMO PASSO combinado: usar esse mapa p/ calibrar os agentes internos
  (interiorização gradual), começando pelos agentes de leitura.

---

## 28. RODADA 2026-07-14 (tarde 2) — Analista de Conversas com frases sugeridas (script CEVICO) ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Pedido do Guilherme (2026-07-14): o Analista de Conversas deve, além do
parecer de interesse, dar RECOMENDAÇÕES DE FRASES para a atendente falar
e formas de conduzir, seguindo a lógica do script de agendamento do N8N
(item 27 — prompt em /tmp/supervisor_prompt.txt e no JSON em ~/Downloads).

IMPLEMENTADO (working tree, junto com o lote 27 — sem migration):
1. conversation_insight_service.rb: SYSTEM_PROMPT ganhou o resumo do
   script CEVICO (10 etapas: recepcao/sondagem/autoridade/orcamento/
   objecoes/agendamento/pos_agendamento/pos_consulta/pos_cirurgico/
   reagendamento), regras de tom (≤150 chars, sem emoji/travessão/listas,
   "investimento" no lugar de "preço", consultivo, terminar com pergunta,
   máx 2 convites de agendamento) e DADOS OFICIAIS (valores, médicos,
   Schwind Amaris, unidades, dias de consulta, Vaneide). Novos campos
   OBRIGATÓRIOS no JSON de saída: etapa_do_script (enum 10 etapas) e
   frases_sugeridas (array 2-3 frases). Prompt+guardrail = ~4,1k chars.
   Controller/job salvam o hash inteiro → persistência automática em
   additional_attributes.ai_insight (script_stage/suggested_phrases).
2. Guardrail (ai_agent_config.rb): agora PERMITE sugerir frases prontas
   PARA A ATENDENTE (quando o formato de saída tiver campo pra isso);
   continua proibido enviar/interagir com o paciente. Vale p/ os 4 agentes.
3. ConversationSummaryCard.vue: chip "Etapa do script: X" (📍) + bloco
   "Frases sugeridas" — cada frase é um botão que COPIA ao clicar, com
   nota "Revise antes de enviar — quem decide é você".

Testado no Docker local: sintaxe Ruby ok, schema/prompt/guardrail
validados no Rails do container, Vite serve o componente sem erro,
insight SIMULADO com os campos novos na conversa #3 (conta 3) para o
teste visual. Prompt custom salvo pelo Guilherme na tela continua
substituindo o padrão — para usar o script novo, o campo custom do
Analista deve estar VAZIO (ou atualizado).

---

## 29. RODADA 2026-07-14 (tarde 3) — Editar/Salvar/Publicar nos agentes + lote no Tratamento + gatilho de valor ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Pedidos do Guilherme. Sem migration. Tudo no working tree com 27–28.

**1. Agentes de IA — Editar | Salvar | Publicar + Ativar/Desativar:**
- Cards abrem TRAVADOS (leitura). "Editar" destrava; "Salvar rascunho"
  grava draft que NÃO muda o agente no ar; "Publicar" aplica de verdade
  (e limpa o rascunho); "Descartar mudanças" volta atrás. Chip âmbar
  "📝 Rascunho não publicado" + botão "Publicar rascunho" fora da edição.
  Interruptor Ativar/Desativar continua gravando NA HORA (kill switch).
- Backend: update_ai aceita agents.{key}.draft (deep-merge; draft vazio
  = limpar), ai_json devolve draft. Services leem SÓ o publicado.
- Botão global "Salvar agentes" removido (agora é por agente).
- Testado: round-trip salvar/publicar/toggle/vigias no container (4 ✓).

**2. Tratamento de dados — "Mover e etiquetar em LOTE":**
- Crm::BatchUpdateJob (fila low, modo leve): filtros combináveis
  stage_id (coluna atual) + value_filter with/without + inbox_id
  (contato com conversa na caixa) + label (contato TEM etiqueta);
  ações target_stage_id (mover; StageLog normal) e/ou add_label
  (direto em taggings, NUNCA duplica — find_or_create_by).
- Endpoints POST crm/batch_updates/preview|apply (admin-only; apply
  exige ≥1 filtro — proteção contra varrer a base inteira sem querer).
- Painel novo na aba Automações (CrmCampaigns) com prévia; card no
  hub de Tratamento. Casos do Guilherme: "COM valor em Novos Contatos
  → Envio de Orçamento" e "caixa GOOGLE → etiqueta consulta_google".
- Testado no banco local: achou card com valor, moveu Novos Contatos→
  Envio de Orçamento, não duplicou etiqueta, filtros caixa/etiqueta ok.

**3. Gatilho "Valor adicionado no card" (value_added) — o "SEMPRE":**
- Crm::Contact after_update (value mudou para > 0) dispara automações
  trigger value_added da coluna ATUAL — cobre valor digitado no board,
  detectado do orçamento e ação set_value. Anti-loop: automação
  value_added não pode ter ação set_value.
- Opção no modal Nova automação (Modo Programação) com explicação.
- Config recomendada p/ produção: coluna Novos Contatos → gatilho
  "Valor adicionado" → ação "Mover para coluna: Envio de Orçamento".
- Testado ponta a ponta com sidekiq real: valor aplicado → card moveu
  sozinho → log fired; mesmo valor de novo NÃO redispara.

---

## 30. RODADA 2026-07-14 (noite) — Frases-chave, dashboard de automações, caixa por coluna, pílulas em Conversas ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Pedidos do Guilherme (prints). ⚠️ Traz a migration **20260714000008**
(crm_stages.settings jsonb, aditiva) — 1ª migration do lote 27-30.

**1. Fix: unidade de tempo nos passos do robô (AutomationsHub):**
delayLabel tratava 'minutes' como horas ("60 min" virava "60h") —
agora minutos÷60, dias×24 (igual ao backend step_delay_hours).

**2. Frases-chave no gatilho "Mensagem criada":**
- action_config.message_contains no CrmListener: vírgula = OU, "aspas" =
  frase exata, ignora acento/caixa (Crm::RetroLabelJob.parse_terms +
  transliterate). Vazio = qualquer mensagem (como era).
- Campo no modal Nova automação, entre direção e frequência.
- Testado: 4 cenários ✓ (acento/caixa, sem match, frase exata, vazio).

**3. Dashboard de resultados das automações (aba 📊 Resultados no hub):**
- GET crm/automations_dashboard?preset= (mesmos presets do Meu Painel,
  fuso SP): KPIs disparos/pacientes alcançados/automações ativas/falhas,
  disparos por dia (barras), ranking automação por automação (coluna,
  gatilho→ação, contatos, falhas, último disparo). Fonte:
  crm_automation_logs. Réguas continuam na Campanha WhatsApp.

**4. Caixa de entrada PRINCIPAL por coluna (migration 20260714000008):**
- crm_stages.settings.main_inbox_ids (multi). Config: modal da coluna
  (lápis) → aba Configurações → "Caixas de entrada principais" com
  checkboxes (agora salva de verdade; os toggles fake ficaram abaixo).
- EFEITOS: balão do card abre a conversa mais recente DAS CAIXAS
  PRINCIPAIS da coluna (fallback: mais recente geral); "Iniciar
  conversa" pré-seleciona a caixa principal. Sem marcação = como era.
- preload_card_data refatorado: conversa escolhida POR CARD (uma query
  a menos); board smoke-testado via API real (200, balão populado).
- Uso combinado: Novos Contatos→Orçamento = google+instagram;
  colunas pós-agendamento = caixa Confirmação de Consulta.

**5. Pílulas de caixa de entrada no topo de CONVERSAS (ChatList core):**
- Barra "Todas | caixa1 | caixa2..." no estilo dos presets do Meu Painel
  (gradiente azul→roxo na ativa), só nas visões puras (não em times/
  etiquetas/menções/pastas). Clique navega home/inbox_dashboard.
- PRÉ-SELEÇÃO: escolha salva no navegador (localStorage
  cevico_conversas_inbox); abrir Conversas volta pra última caixa.

**6. Fixes visuais:** pílula da coluna no card-resumo do contato em 1
linha com truncate (funil embaixo) — não quebra mais em 2 linhas;
KanbanColumn ganhou ícones/labels dos gatilhos e ações novos
(message_created, value_added, set_value, IA, formulário, Meta/Google).

Testado no Docker: Vite compila os 9 arquivos, migration ok, board via
API real ok, dashboard agregando certo, prioridade de caixa no balão ✓.
⚠️ Deploy do lote 27-30: rodar migration (aditiva) — backup antes.

---

## 31. RODADA 2026-07-14 (noite 2) — Agenda operacional completa + mover card na conversa ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Pedidos do Guilherme (prints). Migration **20260714000009** (tasks:
attendance, surgery_indication, indicated_procedure — aditiva).
Lote 27-31 agora tem 2 migrations (…08 e …09).

**1. Mover card do CRM DE DENTRO DA CONVERSA:**
- Card-resumo do painel: pílula da coluna atual + botão "Mover" → botões
  de todas as colunas do funil (mobile-friendly). POST
  crm/conversation_summary/move_stage dispara card_entered/card_left
  (mesmas automações do board). Testado via API real ✓.

**2. Agenda — conferência do dia (visão Dia):**
- Cada consulta na linha do tempo ganhou botões ✓ Compareceu | ✗ Faltou;
  compareceu abre 🎯 Cirurgia indicada (escolhe o procedimento numa
  lista: Catarata, PRK, Lasik, Fácica, Foco Estendido, Trifocal, Anel,
  Pterígio, YAG, Outro) | Sem indicação. Re-clique desfaz. Chips de
  status no card. Compareceu marca a consulta como concluída.
- REFLEXO NO CRM: tasks_controller move o card do paciente (match por
  telefone, últimos 8 dígitos) p/ colunas configuráveis e dispara as
  automações da coluna destino (régua de conversão/reagendamento).
  Config: Agenda → "Janelas dos médicos" → seção "Conferência do dia →
  CRM" (3 selects: compareceu/faltou/indicada; agenda_config
  .attendance_stages). Testado via API real: faltou moveu o card ✓.

**3. Encaixe:** bloco ocupado da visão Dia mostra "+N" quando há mais de
um paciente e ganhou botão "+" (hover) p/ agendar OUTRO no mesmo horário.

**4. Lista do dia p/ IMPRIMIR (PDF):** botão dourado "Imprimir lista
(PDF)" na visão Dia → janela de impressão com tabela (hora, paciente,
telefone, problema, médico, unidade, obs + colunas ☐ Compareceu ☐ Faltou
☐ Cirurgia indicada p/ marcar no papel). window.print() = salvar em PDF.

**5. Agente de Agendamento turbinado:**
- Extração ganhou: observação IMPORTANTE do paciente (recepção precisa
  saber) + valor_consulta (ex. R\$ 150) + flag reagendamento — tudo vai
  pra descrição da consulta.
- Crm::AppointmentRecorder (novo service): cria OU REAGENDA — consulta
  futura do mesmo telefone vira o novo horário (rescheduled_count++,
  sem duplicar). Usado pela ação de coluna e pelo backfill. Testado:
  criar→already→reagendar ✓.
- **Preencher agenda com o HISTÓRICO** (migração de agendas SEM mexer no
  N8N): Crm::AgendaBackfillJob varre conversas com "consulta confirmada/
  consulta agendada/agendamento confirmado" (outgoing) no período e roda
  o agente em cada uma (teto 300; para sozinho sem chave/agente
  desligado; resultado em agenda_config.backfill_last_run). Botão
  dourado no card do agente (modal: período 7/30/90/180d + teto + aviso
  de custo). POST crm/settings/agenda_backfill (admin).
- Fluxo contínuo (sem código novo): automação de coluna gatilho
  "Mensagem criada" (da atendente/bot, frases-chave "consulta
  confirmada") → ação "Agendar consulta (IA)".

**6. Agenda UX (tablet/notebook/mobile):**
- Conteúdo centralizado (max-w 1440px) c/ respiros; visão Dia max-w-4xl.
- Semana: grid responsivo (2/4/7 colunas), horários LIVRES clicáveis em
  cada dia (4 primeiros + "+N livres →" abre a visão Dia) e ARRASTAR
  consulta p/ outro dia = reagendar (abre o modal com a nova data pra
  confirmar; ring dourado no dia alvo).

**7. Pílulas de Conversas** em gradiente DOURADO (pedido de ajuste).

Dados de teste local: consultas hoje 14h ×2 (encaixe) e 15h (botões).
Testado: migration ✓, recorder ✓, reflexo no CRM via API ✓, move_stage
via API ✓, backfill acha conversa e para sem chave ✓, Vite 5 arquivos ✓.

---

## 32. RODADA 2026-07-15 (madrugada) — Secretário v2, Agenda de Cirurgias, Tarefas v2, CRM mês ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Pedidos do Guilherme. Migration **20260714000010** (tasks.comments
jsonb). Lote 27-32 tem 3 migrations aditivas (08/09/10).

**NOMENCLATURA OFICIAL (aprovada):** agente interno = "Secretário da
Agenda" (só lê e anota, nunca fala com paciente); bot do N8N =
"Atendente IA (N8N)" (quem conversa). Renomeado em toda a UI/textos.

**1. Secretário da Agenda v2:**
- 📒 REGISTRO DE ATIVIDADE no card do agente: cada leitura vira linha
  (data · paciente · consulta · criada/reagendada/já existia/sem dia-hora)
  — agenda_config.scheduler_log cap 100, serializado (30) no settings.
  É onde se ENTENDE os números da IA de agendamento.
- COLUNAS DE ATUAÇÃO (multi): pílulas no card; salvar sincroniza
  automações marcadas "Secretário da Agenda (automático)" via POST
  crm/settings/sync_scheduler_stages (cria/remove só as gerenciadas;
  manuais do Modo Programação intactas). FUNCIONAMENTO: por EVENTO
  (card entra na coluna → 1 leitura), não por varredura/cron.
- Impressão da lista do dia pré-configurada A4 retrato (@page).

**2. Agenda de Cirurgias (trilho paralelo):**
- Toggle Consultas | 🔪 Cirurgias no cabeçalho (dourado, faixa "AGENDA
  DE CIRURGIAS" + anel — impossível confundir). task_type='cirurgia'.
- Consulta com indicação ganha botão "📅 Agendar cirurgia" (abre o
  trilho dourado pré-preenchido: nome/fone/procedimento indicado).
- Conferência da cirurgia: ✓ Realizada | ✗ Não veio → move card p/
  colunas próprias (surgery_done/missed_stage_id na config Conferência
  do dia). Jornada completa: consulta → indicação → cirurgia → pós, tudo
  refletindo no CRM. Janelas/ocupação só no trilho de consultas.

**3. Agenda vertical (tablet):** cabeçalho FIXO enxuto (título/Nova/
navegação/visões/trilho/filtro); KPIs+ocupação rolam com o conteúdo.
Visão Dia: 4 horários por linha (blocos maiores, mais comprida). Visão
SEMANA reescrita: grade horária estilo Google (horas à esquerda 07-20h,
célula vazia = 1 clique agenda naquela hora, arrastar consulta p/ outra
célula = reagendar confirmando no modal). Mês com células min-h fixa.

**4. Conversas:** pílulas aceitam MAIS DE UMA caixa (1 = rota nativa;
2+ = filtro local na visão geral; "Todas" limpa) — localStorage
cevico_conversas_inboxes, pré-seleção mantida.

**5. CRM:** padrão da janela = ESTE MÊS (dias desde o dia 1º — mais
leve); seletor Este mês|7d|15d|30d|Personalizado… (carrega tudo + abre
De/Até)|Tudo. Pílulas de período saíram do dourado (ruim no tema claro)
→ gradiente azul→roxo.

**6. Tarefas v2:**
- Solicitações/ajuda: thread dentro da tarefa (executor ↔ criador,
  POST tasks/:id/comment, admin também; tasks.comments jsonb).
- Visual: topo das colunas em GRADIENTE (A fazer azul→roxo, Fazendo
  dourado, Feito verde), painel de resumo com tiles em gradiente.
- 🏆 Concluir ANTES do prazo = troféu + confete (CSS puro, 2,6s).
- Board 100% FEITO = anel dourado brilhante e pulsante no painel.
- Badge da sidebar: Tarefas = DOURADO com brilho animado (conta a fazer
  + atrasadas do usuário); Meu Painel/Radar = VERDE (coisa boa).
  (countVariant em SidebarGroup/Header; CSS shimmer leve.)
- Meu Painel: bloco dourado "N tarefa(s) esperando você" (top 5 c/
  prioridade/criador/prazo/💬, botão Abrir Tarefas; my_tasks no home).

Testado no Docker: 3 migrations ok, comentário via API real ✓, my_tasks
no home ✓, sync de colunas do Secretário (add/remove) via API ✓,
scheduler_log gravando ✓, Vite compila os 13 arquivos ✓. Tarefa "Teste
solicitações" criada no local p/ ver aviso dourado + thread.

## 33. RODADA 2026-07-15 — Follow-up CONSERTADO + painéis por pessoa + Cirurgias azul vítreo ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Migration **20260715000001** (crm_followup_bots: activity_log jsonb +
last_run_at — aditiva). Lote 27-33 tem **4 migrations** (…08/09/10 + esta).

**1. 🐛 BUG DE PRODUÇÃO DO FOLLOW-UP ACHADO E CORRIGIDO:**
- Causa: Message tem default_scope por created_at ASC, que VENCE o
  .order(desc) do job — a checagem "última mensagem é do atendimento?"
  olhava a PRIMEIRA mensagem da conversa. Robô só funcionava quando a
  conversa começava com msg do atendimento (caso do teste do Guilherme) e
  NUNCA nas conversas reais (paciente fala primeiro). Fix: comparação por
  maximum(created_at) de incoming vs outgoing (imune a ordenação).
- Fixes extras: estado por robô ({bots: {id: ...}} — 2 robôs ativos não
  apagam mais o marcador um do outro; formato legado migra sozinho);
  etapas "desde a entrada na coluna" têm marcador próprio amarrado à
  entrada (resposta do paciente não as redispara).
- **[nome] inteligente**: limpa emojis/números/símbolos do nome do
  WhatsApp, usa só o primeiro nome capitalizado; sem nome aproveitável →
  "oi" no lugar (e "Oi oi" vira "Oi"). Dica atualizada no modal.
- **📒 Registro de atividade por robô** (activity_log): cada rodada grava
  status, candidatos, enviados e MOTIVOS de quem não recebeu (aguardando
  prazo / paciente falou por último / cadência completa / etiquetas /
  erro) + histórico dos envios (cap 60). Aba Robôs mostra: aviso âmbar
  quando a janela "para em" já passou (causa silenciosa nº 1), linha da
  última rodada e o registro expandível.
- Testado no Docker: envio real com nome limpo ("Oi Maria..."), sem
  reenvio (cadência completa), fora_da_janela logado, legado sem reenvio.

**2. Meu Painel — preset "Este ano" + PAINÉIS POR PESSOA (?panel=):**
- Mesmo layout, cores e indicadores da função; escolha fica no navegador
  (localStorage) — cada pessoa abre no seu. Banner/pílulas seguem o tema.
- Agendamento (Vaneide, padrão azul→roxo): igual ao atual (coorte CRM).
- Condução (Elisangela, teal): consultas do período, compareceram, %
  comparecimento, indicações + destaque "consultas sem conferência".
- Cirurgias (Gabriela, vinho/rosa): indicações, cirurgias agendadas, taxa
  de fechamento, realizadas + "indicados aguardando fechamento".
- Médicos (azul céu): pílulas por médico (?doctor=) — consultas,
  presença, faltas, indicações + cirurgias do médico.
- Painéis da Agenda contam o período-calendário INTEIRO (consulta de hoje
  à tarde conta em "Hoje"); o de leads corta em "agora" (coorte).
- Testado via API real: 4 painéis × presets today/year respondendo.

**3. Tarefas — visual:**
- Donut macio/brilhante: borderRadius 14 (pontas arredondadas até na
  parte reta), gradiente por fatia, spacing, glow suave atrás.
- Board 100% FEITO: anel dourado GIRANDO (conic-gradient + mask, estilo
  anel do Sonic) com brilho; coluna iluminada continua.
- Troféu: movimento 3D (rotateY 720°) + EXPLOSÃO de confetes localizada
  (radial, perto do painel de resumo — não chove mais na tela inteira).
- Badge da sidebar mais sutil: só o círculo dourado com o número + pulso
  suave em volta (shimmer removido).

**4. Agenda de Cirurgias — azul claro vítreo:**
- Tema trocado: dourado → azul claro vítreo (SURGERY_GRAD #0284C7→#7DD3FC,
  classe .cevico-glass com brilho interno; cores dos médicos intactas).
- Faixa "🔪 trilho paralelo" REMOVIDA; título "Agenda de Cirurgias" em
  destaque (maior, texto em gradiente azul).
- Modal do trilho = "Agendar cirurgia" (título, botão salvar e botão do
  topo); Editar/Excluir também no vocabulário certo.
- **Local da cirurgia** (clínicas parceiras): campo no lugar de Unidade no
  trilho de cirurgias; cadastro em modal próprio (admin, "gerenciar") —
  agenda_config.surgery_locations (padrão IOP); KPI "no mês" por local;
  update_agenda aceita surgery_locations (testado via API real).

Testado no Docker: migration ok, Vite compila os 7 arquivos, follow-up
ponta a ponta, home 4 painéis via API, locais round-trip via API.

## 34. RODADA 2026-07-15 (2) — TEMAS de lugares + sala cirúrgica + blocos proporcionais + Gestor + agentes Fechamento/NPS ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Sem migration nova (lote 27-34 segue com 4). Pedidos do Guilherme (refs Santorini).

**1. 🎨 SISTEMA DE TEMAS (ideia do Guilherme — lugares maravilhosos):**
- helper cevicoThemes.js: CEVICO (padrão) + Santorini 🇬🇷 (azul cristalino/
  branco/cinza) + Flor del Mar 🌺 (fúcsia+azul) + Flamingo 🦩 (rosa-coral) +
  Praia do Caribe 🏝️ (turquesa) + Aloe Vera 🌿 (verde). Cada tema define
  primary/action/accent/pill/soft/ring/glass (efeito vítreo .cevico-glass).
- Admin escolhe no botão 🎨 (header da Agenda) → agenda_config.theme →
  Agenda (título, Hoje, visões, trilhos, KPIs, círculos de hoje, modais) e
  Tarefas (colunas, tiles, ícone) seguem o tema. Tema padrão = visual atual.
- Round-trip testado via API (theme:'santorini' salva e devolve).

**2. Agenda de Cirurgias completada:**
- OCUPAÇÃO % no trilho de cirurgias (dia/semana/mês + chip por dia), a
  partir das JANELAS DA SALA CIRÚRGICA — modal próprio (substitui "Janelas
  dos médicos" no trilho): clínica (locais) + dia + início/fim + bloco
  (30/60/90/120 min); agenda_config.surgery_windows; scanAgenda reaproveitado
  (window.unit = key do local). Visão Dia mostra os blocos da sala como os
  dos médicos (livre clica-agenda / ocupado / cadeado).
- Header realinhado em 2 LINHAS: título+ação | navegação; visões·trilho·
  janelas·filtro·tema numa linha só com scroll lateral (mobile/tablet/desktop).
- Pré-definições com cores do tema (pill).

**3. Blocos PROPORCIONAIS ao tempo (semana e dia):**
- consulta = 15 min (25% da hora) · cirurgia = 60 min. Semana: célula da
  hora relativa, bloco posicionado por minuto com altura proporcional.
- Dia: "Linha do tempo do dia" virou grade estilo Google (1h = 88px, bloco
  mede o tempo, clique no vazio agenda de 15 em 15) + seção "Conferência do
  dia" com os cards completos (botões que o Guilherme elogiou, intactos).

**4. Meu Painel — GESTOR + atribuição por pessoa:**
- 5º painel "Gestor" (grafite): leads, taxa de agendamento, comparecimento,
  fechamento de cirurgias + destaque Satisfação (NPS).
- Admin (engrenagem nas pílulas): define o painel de CADA agente
  (agenda_config.panel_assignments); agente atribuído fica TRAVADO nele
  (frontend só mostra o painel dele; backend força também).

**5. Cirurgia — conferência ampliada + 💰 (admin):**
- Botão "⚠️ Veio e não fez" (só cirurgia): abre campo de MOTIVO → grava
  attendance='attended_not_done' + motivo na descrição. Chips novos.
- 💰 valor da cirurgia SÓ ADMIN no card da conferência: valor do card do
  CRM (match por telefone) + forma de pagamento captada pela IA
  (contact.surgery_closing). Testado via API real (5000 · PIX à vista).

**6. Agentes de IA novos (6 no total):**
- 💰 MONITOR DE FECHAMENTO (key 'closing', Sonnet/médio): ação de coluna →
  extrai valor fechado/forma de pagamento/data da cirurgia (structured
  output), grava no contato + preenche o valor do card se vazio.
- 🌟 AGENTE DE NPS (key 'nps', Haiku): ação de coluna (ex. Pós-Operatório)
  → lê a nota 0-10 e ETIQUETA o contato (nps-9-10/nps-7-8/nps-0-6) +
  grava contact.nps. Ambos nos cards de Agentes, no seletor "Adicionar
  agente de IA" (closing_extract/nps_score no fire job) e no kill switch.
- Dashboard CRM: bloco "Satisfação dos pacientes (NPS)" — % satisfação,
  NPS score e barras 9-10/7-8/0-6, recorte nos cards que chegaram ao
  pós-operatório. Testado: 1 promotor → 100% ✓.

**7. Dashboard CRM — visual:**
- Doughnuts (caixas + etiquetas) no estilo do donut de Tarefas: pontas
  arredondadas (borderRadius 14), gradiente por fatia, spacing.
- Etiquetas: lista virou COLUNAS arredondadas em gradiente (mín. 33%).
- Responsividade: barras com mínimo 33% preenchido + gradientes tema
  "Flor del Mar" (fúcsia/azul-mar).

Dados de teste local (conta 3): card no Pós Operatório c/ nps-9-10 e
surgery_closing 5000/PIX, cirurgia "Cirurgia Teste NPS" hoje 16h no local
IOP c/ attended_not_done + motivo, janela da sala ter 08-12h IOP, tema
santorini APLICADO (volte pro 'cevico' no 🎨 se quiser o visual padrão).
Testado: Vite 8 arquivos ✓, tema/sala/painéis round-trip ✓, gestor ✓,
NPS dashboard ✓, valor admin ✓, attended_not_done ✓.

## 35. RODADA 2026-07-15 (3) — Feedback dos temas + Dashboard dos Médicos + NPS 5 faixas + celebração de emojis ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Sem migration (lote 27-35 segue com 4). Feedback do Guilherme sobre a rodada 34.

**1. Temas — Consultas × Cirurgias bem mais evidente:**
- Cada tema ganhou surgeryGrad/surgeryText: o trilho de cirurgias usa a
  MESMA cor do tema "puxando para o branco", com texto na cor escura
  (classe .cevico-surgery-ink força a tinta nos filhos). Padrão CEVICO
  continua com o azul vítreo próprio.
- Tema agora em TODOS os botões do ambiente: Imprimir lista (accent),
  modal janelas dos médicos, Nova tarefa/Salvar das Tarefas, calendário.
- Locais padrão: IOP (geralmente PRK) + Ocular Surgery (geralmente Lasik)
  — atualizados também no banco local.

**2. 📅 Calendário INTERATIVO:** clicar no rótulo do período (ex. "Julho de
2026") abre popover arredondado com o mês navegável — clicou no dia, o
calendário vai pra lá (funciona nos dois trilhos; botão Hoje incluso).

**3. Duração configurável dos blocos:** a duração do agendamento vem do
BLOCO da janela onde o horário cai (médicos ou sala cirúrgica) — é só
editar as janelas; sem janela: consulta 15 min / cirurgia 60. Sala
cirúrgica ganhou opções de 10/15/20 min. 💰 forma de pagamento foi para a
DIREITA da linha na conferência.

**4. Agentes closing/nps APARECENDO:** bug — loadAgents reconstruía a lista
só com os 4 antigos; agora Monitor de Fechamento e Agente de NPS têm card
completo em Automações → Agentes de IA (Editar/Salvar/Publicar/interruptor).

**5. CRM board:** janela de carga ganhou "Este ano"; "Tudo" virou "Desde o
início"; pílulas de período ganharam "Este ano" e "Desde o início".

**6. NPS em 5 FAIXAS oficiais:** 9-10 promotores · 7-8 · 5-6 · 3-4 · 1-2
detratores (0 conta em 1-2). NpsService etiqueta nps-9-10/7-8/5-6/3-4/1-2;
Dashboard CRM mostra as 5 barras; nps_score = promotores − (notas ≤6).

**7. Meu Painel:**
- Banner com letras SEMPRE brancas (independe de tema claro/escuro).
- Saúde da "Agenda de Cirurgias" (sala cheia 7d + aproveitamento 7d, das
  janelas da sala) nos painéis Médicos, Condução, Cirurgias e Gestor.
- Painel do médico: tiles novos — Conversão em cirurgia (indicados que
  viraram cirurgia marcada, match por telefone) e NPS médio dos pacientes.

**8. 📊 DASHBOARD DOS MÉDICOS (Relatórios → Dashboard dos Médicos, admin):**
- Ranking 🥇 de conversão consulta→cirurgia por médico (consultas,
  comparecimento, indicações + taxa, conversões, cirurgias realizadas,
  NPS médio dos pacientes dele — rastreado pelo telefone do contato).
- Volume de cirurgias por clínica (IOP / Ocular Surgery) com realizadas.
- Presets semana/mês/mês passado/ano/desde o início.
- Backend: GET crm/doctors_dashboard (doctors_dashboards_controller).

**9. Tarefas — celebração v2 (tchau troféus):**
- EXPLOSÃO DE EMOJIS aleatórios do set ❤️😧🥳👏⭐️🔥🥇🚀❤️‍🔥💖✅🔝💎 —
  60 no "antes do prazo", 150 quando o board zera (sempre diferente).
- Board 100%: ANEL DOURADO 3D (sombreado metálico, gira em torno do
  próprio eixo — referência das argolas) + "Parabéns, 100% das tarefas
  concluídas. Você desenrola mesmo!".

Testado: Vite 10 arquivos ✓, doctors_dashboard via API (ranking + IOP) ✓,
painel médico c/ conversão ✓, NPS 5 faixas ✓, locais IOP+Ocular Surgery ✓.

## 36. RODADA 2026-07-15 (4) — Prazo da conferência, Consultor Comercial, colunas nos agentes, fix Tarefas ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Sem migration (lote 27-36 segue com 4). ⚠️ cron NOVO no schedule.yml
(crm_attendance_reminder_job */30) — produção: reimplantar sidekiq.

**1. 🐛 FIX "Tarefas não abre":** o watch da explosão avaliava o computed
allDone na montagem, antes de `stats` existir (TDZ) → página quebrava.
Movido para depois de stats. + celebração "antes do prazo" = só 3 emojis
(board zerado continua 150).

**2. ⏰ PRAZO DA CONFERÊNCIA DO DIA (Crm::AttendanceReminderJob, cron */30):**
- Config no modal Janelas dos médicos → seção Conferência: responsável das
  CONSULTAS (Elisangela), responsável das CIRURGIAS (Gabriela) e horário
  limite (padrão 19:00) — agenda_config.attendance_owners.
- Passou do prazo com agendamento do dia sem ✓/✗ → tarefa automática
  "✅ Concluir a conferência do dia — Consultas/Cirurgias (dd/mm)" pra
  pessoa certa (prioridade alta, 1 por tipo/dia, sem duplicar) → badge
  dourado na sidebar + aviso "esperando você" no Meu Painel dela.
- Testado: criou p/ responsável, 2ª rodada não duplicou ✓.
- Seção da visão Dia destacada: "✅ Conferência das Consultas/Cirurgias do
  dia" + chip "N pendente(s)" / "tudo conferido ✓".

**3. Colunas de atuação em TODOS os agentes de coluna:**
- Endpoint genérico sync_agent_stages (marker "Agente de IA: X (automático)")
  p/ Analista/Monitor de Fechamento/NPS — pills de colunas no card de cada
  agente (sugestões: closing → "Indicação de Cirurgia"; nps → Pós-Operatório).
- MODO PROGRAMAÇÃO: automação com agente de IA ganhou FAIXA colorida no
  card da coluna (nome do agente + LIGADO/desligado + botão "editar") que
  abre modal de EDIÇÃO RÁPIDA dali mesmo (liga/desliga, modelo, prompt —
  salva e publica na hora; Teleport p/ manter raiz única do componente).

**4. 💼 CONSULTOR COMERCIAL (7º agente, key 'sales', Opus/alto):**
- AO VIVO: botão "💼 Ajuda com objeção (IA)" no painel da conversa —
  identifica a objeção (preço/medo/vou pensar/família...), leitura do
  paciente, 2-3 respostas prontas (clique copia) e próximo passo.
  POST crm/conversation_summary/sales_help (Crm::SalesCoachService#coach).
- GESTÃO: botão "Gerar insights comerciais" no card do agente — analisa
  as conversas que FECHARAM cirurgia (contatos com surgery_closing do
  Monitor de Fechamento) e grava relatório (o que funciona / objeções
  vencidas / melhorias / recomendações) em ai_config.agents.sales.insights
  (Crm::SalesInsightsJob, fila low; POST crm/settings/sales_insights).
- PROMPTS MELHORADOS de todos os agentes novos: closing e nps ganharam
  contexto CEVICO completo (unidades, IOP=PRK/Ocular Surgery=Lasik,
  valores de referência, "investimento" não "preço", regras anti-invenção);
  sales tem script de objeções e tom ≤150 chars sem emoji.

**5. Sidebar — Radar:** badge do Meu Painel saiu do verde → LARANJA-
AVERMELHADO (cor do agente) pulsando; o ÍCONE do menu pulsa junto, no
mesmo ritmo (countVariant 'radar').

**6. Agenda de Cirurgias — cores:** IOP = azul claro (#38BDF8), Ocular
Surgery = PRATEADO (#94A3B8) — cards, KPIs, janelas da sala e pontinhos
seguem a cor da clínica. KPI "Nesta semana" agora também "puxa pro branco"
no trilho (surgerySoft por tema — meio-termo, menos claro que o "hoje").

**7. Dashboard dos Médicos — mais indicadores:**
- 💰 FATURAMENTO GERADO pela indicação de cada médico (soma dos fechamentos
  dos indicados que viraram cirurgia; fallback: valor do card).
- Consultas por UNIDADE (Tatuapé/Paulista): volume + taxa de comparecimento.
- NPS dos pacientes que operaram em CADA CLÍNICA (IOP × Ocular Surgery).

Testado: Vite 9 arquivos ✓, job do prazo ✓ (cria 1x, não duplica),
doctors_dashboard c/ unidades+revenue via API ✓, sidekiq local reiniciado
(cron novo). Produção: lembrar de reimplantar SIDEKIQ junto (cron novo).

**Ajuste fino pós-feedback (mesma rodada):** anel das Tarefas agora fica
PARADO — quem gira (sentido horário) é o BRILHO do conic-gradient, com
pulso dourado junto (sem rotateY); explosão de emojis nasce do CENTRO do
anel quando o board completa; cada explosão usa 1 TIPO só de emoji
(sorteado do set — 150 no board zerado, 3 no antes-do-prazo); botão "Nova
tarefa" reposicionado abaixo do título com ícone (mesmo padrão da Agenda);
título da conferência sem o emoji ✅.

**Ajuste fino 2 (mesma rodada):** legenda do donut de Tarefas ARREDONDADA
(usePointStyle); sequência do board zerado = anel TREME (0,75s) → explosão
de emojis do centro → anel vira VERDE pulsante com brilho horário, e TODA
a tela (colunas, botão Nova tarefa, ícones, tiles do resumo) assume o
verde do anel enquanto o board estiver 100%; Saúde da Agenda do Meu Painel
reorganizada em 2 RETÂNGULOS SIMÉTRICOS (Consultas: 3 barras + vagas
livres + próxima consulta · Cirurgias: sala cheia + aproveitamento +
🎯 META DO ANO de 100 cirurgias com barra de progresso + próxima
cirurgia); % de agendamento virou linha compacta abaixo; painel do
MÉDICO ganhou "Com indicação" (nº + % de quem compareceu) e "Sem
indicação" (nº + %) — backend medico_metrics c/ indication_rate/
no_indication/no_indication_rate.

**Ajuste fino 3 (mesma rodada):** meta de cirurgias virou MENSAL ("Meta do
mês: 100 cirurgias", conta as realizadas no mês corrente); anel custom
DESCARTADO — o anel oficial é o PRÓPRIO DONUT do Resumo: fecha verde →
treme (0,75s) → explosão de emojis do centro → a fatia vira DOURADA e o
donut PULSA forte em dourado no ritmo dos ícones da sidebar (2,2s);
donutChart rastreia ringPhase p/ repintar.

**Ajuste final do donut (fechado ✅):** após a explosão o donut dourado
GIRA em sentido horário (8s, só o canvas — emojis não giram) com pulso
REDUZIDO (drop-shadow 14px, opacidade 0,92); legenda do chart.js
substituída por legenda PRÓPRIA em HTML, centralizada/alinhada abaixo do
anel, que fica toda DOURADA junto com a explosão; a CAIXA do painel pulsa
DOURADA (não mais verde) e o modo 100% da tela (colunas/botões/tiles)
também virou dourado, acompanhando o anel.
**+ retoque:** o emoji sorteado da explosão fica morando no CENTRO do
donut durante a fase dourada (abriu já completo = sorteia um); o giro
arranca RÁPIDO (2 voltas desacelerando em 1,8s) e estabiliza no ritmo
lento de 8s.
**+ polish do painel de resumo:** no modo 100% só a caixinha FEITO fica
dourada (pulsando); as zeradas ficam escuras; legenda do donut em grade
2×2 (2 de cada lado); respiros maiores (p-5, gap-3); parabéns em 2 linhas
com destaques próprios ("Parabéns..." dourado claro + "Você desenrola
mesmo! ✨" maior, dourado escuro).

## 37. RODADA 2026-07-15 (tarde) — Travas do follow-up, Dashboard dos Agentes, modalidades, coerência do menu ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Migration **20260715000002** (tasks.modality — aditiva). Lote tem 1 migration.

**1. 🔒 TRAVAS do robô de follow-up (pedido: "as meninas conseguirem pará-lo"):**
- TRAVA INDIVIDUAL: botão "Pausar follow-up p/ este paciente" no painel do
  balão do CRM (seção 🤖 no painel mover-card/etiquetas) E no card-resumo do
  painel de Conversas. Grava quem pausou (contact.additional_attributes
  .cevico_followup_paused); o job pula o contato (motivo
  "pausado_para_paciente" no registro). Endpoint: POST
  crm/conversation_summary/toggle_followup (aberto a atendentes).
- CHAVE DE EMERGÊNCIA por robô: lista dos robôs que alcançam a conversa no
  mesmo painel, com "Parar para todos" — POST crm/followup_bots/:id/toggle
  (ABERTO a atendentes; gerenciar continua admin). Registra "⏸ pausado por
  Fulana" no registro de atividade do robô.
- summary_json ganhou followup {paused, paused_by, bots[]}.

**2. Etiquetamento automático — cadeia fechada:** o combo já existia
(gatilho "Mensagem criada" + frases-chave + ação "Aplicar etiqueta");
agora a etiqueta aplicada POR AUTOMAÇÃO também dispara as automações
"Etiqueta adicionada" da coluna (cadeias: frase → etiqueta → mover/valor).
Anti-loop: etiqueta que o contato já tem não redispara. 🐛 BUG ACHADO NO
TESTE: ações "Registrar na conversa"/"Avisar equipe"/nota do Secretário
criavam Message SEM INBOX → falha silenciosa em produção (provável causa
das 12 falhas do "Secretário da Agenda (automático)" no print) — corrigido
(inbox: conversation.inbox nos 3 pontos).

**3. Dashboard dos Agentes (Relatórios, admin, GET crm/agents_dashboard):**
- Por pessoa: conversas atribuídas, mensagens enviadas, 1ª resposta média
  (reporting_events), resolvidas, consultas agendadas, avisos do Radar
  respondidos + tempo médio. Presets hoje/semana/mês/mês passado/ano.
- RESPONSIVIDADE AO RADAR: histórico do Radar agora grava destino+coluna;
  1ª msg outgoing após o aviso = resposta (taxa geral + por painel de
  destino + por quem respondeu). ⚠️ lição repetida: default_scope do
  Message quebra GROUP BY → reorder(nil).

**4. Agenda — modalidade da consulta:** avaliacao|retorno|exames
(tasks.modality; pílulas no modal, chip colorido no card da visão Dia).
Ocupação (dia/semana/mês) virou barra SEGMENTADA por tipo + legenda +
"Avaliação X% · Retorno Y%" no rodapé. Sem tipo = avaliação. scanAgenda
devolve byModality (MODALITIES exportado no cevicoAgenda.js).

**5. Ajustes:** Menções/Participantes REMOVIDOS de Conversas p/ todos;
Dashboard dos Médicos só com os 3 oficiais (Crm::DoctorNames normaliza
grafias; Meu Painel médico usa o mesmo filtro); CRM abre em "Essa semana"
(nova janela de carga, localStorage novo padrão) e mover COLUNA só no modo
edição; Meu Painel com saúde de Cirurgias SEMPRE lado a lado; menu
Automações = abas do hub (aba nova "Regras da caixa de entrada" com
liga/desliga das regras nativas + item "Resultados" no menu).

**6. INSTAGRAM/FACEBOOK (item grande — DECISÕES PENDENTES do Guilherme):**
plano desenhado (agente interno respondedor por INBOX, inspirado no fluxo
N8N mapeado no item 27; confirmações oficiais sempre via WhatsApp; fase 1
= DM, fase 2 = comentários). Aguardando: caixa Instagram conectada?
escopo do prompt, expediente, e aprovação do desenho.

Testado no Docker (API real, conta 3): trava individual e chave por robô
(atendente pode toggle, update 403), job pula pausado, cadeia
etiqueta→label_added fired ✓ + anti-loop ✓, agents_dashboard ✓,
doctors dedupe ✓ (Jorge Haddad fora), modality round-trip ✓, migration ✓,
Vite compila os 12 arquivos ✓. Usuária de teste "atendente.teste@cevico
.local" criada no local; consulta "Teste Modalidade" id 21 (16/07 14h,
retorno) p/ ver o chip e a barra segmentada.

## 38. RODADA 2026-07-15 (noite) — ATENDENTE INSTAGRAM + Dashboard da Agenda + menu ordenável ⏳ NÃO COMMITADO, AGUARDA TESTE VISUAL

Sem migration nova (lote 37-38 = só a 20260715000002 do item 37).

**1. 🤖📱 ATENDENTE INSTAGRAM (8º agente, key 'instagram') — o 1º agente
RESPONDEDOR (fala com o paciente):**
- Crm::InstagramAgentService: prompt DESTILADO do fluxo N8N (46k → ~8k),
  Sonnet 5/médio recomendado; structured output {mensagens[1-3], etapa,
  agendar, agendamento{nome/telefone/dia/hora/unidade/procedimento},
  pausar, chamar_humano}. Guardrail PRÓPRIO (RESPONDER_GUARDRAIL no
  AiAgentConfig — RESPONDER_AGENTS): nunca inventar valor/horário, nunca
  diagnóstico, urgência → PA + chamar_humano.
- Crm::AgendaSlots (NOVO): vagas livres calculadas NO SERVIDOR (janelas ×
  consultas × cadeados; espelho do DEFAULT_WINDOWS) → o prompt recebe
  HORÁRIOS DISPONÍVEIS reais; slot_available? valida antes de gravar.
- Crm::InstagramAgentJob: espera 12s e só responde se a mensagem ainda é a
  última (anti-picada, junta mensagens), teto 60 respostas/dia/conversa,
  envia mensagens marcadas (additional_attributes.cevico_ia_agent),
  agenda via AppointmentRecorder (horário inválido → tarefa ⚠️ em vez de
  gravar errado), captura telefone p/ o contato (+55, ponte p/ WhatsApp),
  nota privada 📅, registro de atividade em ai_config.instagram_state.
- CrmListener#handle_instagram_agent: SÓ nas caixas escolhidas
  (agents.instagram.inbox_ids) e com o agente LIGADO. Emojis do N8N:
  humano respondeu → PAUSA (nota ⏸); humano manda 👍 → REATIVA (nota ▶️);
  confirmação de agendamento (😊) → o próprio agente se pausa (pausar).
  Mensagens do agente e do robô de follow-up não mexem na pausa.
- Confirmações oficiais: o agente avisa que confirmação/lembretes vão
  pelo WHATSAPP (regra no prompt) e a equipe/robôs seguem por lá.
- UI: card completo no hub (faixa rosa de aviso, pílulas de CAIXAS,
  registro de atividade, Editar/Salvar/Publicar/interruptor);
  update_ai permite agents.instagram.inbox_ids; ai_json expõe inbox_ids
  + instagram_events.
- Canal Instagram nativo: card em Caixas de Entrada TRAVADO porque faltam
  INSTAGRAM_APP_ID/SECRET/VERIFY_TOKEN (app da Meta — passos externos
  documentados p/ o Guilherme; feature flag da conta já está ON).
- Testado no Docker: slots reais ✓, slot inválido ✓, listener incoming ✓,
  job sem chave → erro amigável logado ✓, pausa por humano ✓, 👍 reativa ✓,
  agendamento válido criou consulta+nota ✓, inválido criou tarefa ⚠️ ✓.
- FUTURO combinado: agentes de atendimento POR COLUNA (reagendamento p/
  quem já agendou; suporte pós-operatório com escalada a humano) — a
  arquitetura do respondedor já nasce pronta p/ isso.

**2. 📊 Dashboard da Agenda (Relatórios, admin, GET crm/agenda_dashboard):**
KPIs consultas (total/comparecimento/faltas/canceladas/reagendadas/SEM
CONFERÊNCIA/indicações), mix por modalidade (share + comparecimento),
por médico (DoctorNames), por unidade, volume por dia da semana,
cirurgias (realizadas/não veio/veio-e-não-fez/por clínica), ocupação
(agenda cheia 7d + aproveitamento 7d + sala cirúrgica, client-side com
scanAgenda) e "o que vem pela frente" (próx. 7 dias + conferência
pendente 30d). Testado via API real.

**3. Menu lateral ORDENÁVEL:** Relatórios agora logo abaixo do CRM
(ordem padrão nova) e o "Personalizar menu" ganhou setas ↑/↓ por item +
"Restaurar ordem padrão" (localStorage cevico_menu_order, por pessoa).

**4. Follow-up pausado→retomado NÃO reenvia** (verificado com teste real:
marcadores das etapas moram na conversa; pausar/religar robô ou paciente
não zera nada; etapas vencidas na pausa caem no anti-rajada).

**5. Tipo de consulta ACOMPANHA A JORNADA (Task#infer_consulta_modality):**
consulta criada SEM tipo explícito (Secretário/Atendente Instagram/
backfill) nasce RETORNO se o paciente já tem consulta anterior (telefone,
8 dígitos) e AVALIAÇÃO se é a primeira; escolha manual no modal sempre
vence. Testado: novato→avaliacao, volta→retorno, manual→exames ✓.

**6. PLANEJADOS (combinados 15/07, construir nas próximas rodadas):**
- 📞 AGENTE DE TELEFONEMA: decisão do Guilherme (15/07 noite) = INTEGRAR
  um sistema PRONTO de voz por IA que ele conhece (contrata e pluga no
  nosso via API/webhook) em vez de construir pipeline próprio — fica NO
  RADAR; quando contratar, mapeamos a API e conectamos (fila de quem está
  parado nas colunas + resultado da ligação de volta pro card). O plano
  v1 "Discador do CRM" (humano liga, IA prepara roteiro) segue disponível
  como alternativa caso a integração demore.

## 39. 🏥 CENTRAL DO PACIENTE — PRÓXIMA GRANDE CRIAÇÃO (especificada 15/07, construir na próxima sessão)

A página única do paciente, acessível de TODOS os pontos de contato
(card do CRM, balão, painel da conversa, Agenda, busca). Três camadas:

**FASE 0 — Unificação (pedra fundamental, vem primeiro):**
- Migration aditiva `tasks.contact_id` (+ índice) + backfill por telefone
  (últimos 8 dígitos) — acaba com matches frágeis e N+1 de telefone em
  loop (candidatos da auditoria ganham a solução definitiva).
- Consulta criada passa a amarrar no contato; telefone continua como
  fallback p/ quem não existe ainda. Informações SEMPRE unificadas.

**FASE 1 — Jornada (tudo já existe no banco, é costurar):**
- Identidade (nome, telefones, e-mail, etiquetas, card/coluna atual).
- LINHA DO TEMPO completa: anúncio de origem (meta_ads) → conversas por
  canal → movimentos no funil (stage_logs) → consultas (com tipo/
  comparecimento/reagendamentos) → indicação → fechamento (valor/
  pagamento) → cirurgia → pós-op → NPS → formulários respondidos →
  follow-ups recebidos. Indicadores do paciente (responsividade, tempo
  no funil, valor).

**FASE 2 — ESPAÇO NOBRE DO MÉDICO (anotações de consulta, ref. foto do
sistema atual do IOP que o Guilherme mostrou 15/07):**
- Registro clínico por consulta com CAMPOS RÁPIDOS (a vida do médico
  fácil): tipo de procedimento (refrativa → técnica PRK/Lasik; catarata
  → tipo de lente nacional/Rayner/foco estendido/trifocal/tórica...),
  OLHO (OD | OE | AO), refração OD/OE, acuidade, PIO, biomicroscopia,
  fundoscopia, CONDUTA/indicação (pílulas), pedido de exames + campo
  livre de observações.
- UPLOAD DE FOTOS/EXAMES (ActiveStorage já existe no Chatwoot — viável;
  atenção: storage na VPS entra no plano de backup).
- Permissões: médicos e admin editam; equipe visualiza o que for
  liberado. ⚠️ LGPD: dado de SAÚDE é sensível — módulo nasce como
  "anotações internas da clínica" (não substitui prontuário certificado
  SBIS/CFM); acesso restrito e auditável.
- Conduta preenchida pelo médico pode alimentar a indicação/CRM
  automaticamente (mesmo reflexo da conferência do dia).

**FASE 3 — IA em cima do banco (pedido do Guilherme):** análise do
perfil do paciente cruzando jornada + formulários + anotações (o que
converte, o que prevê falta, sugestão de abordagem por perfil).

Ordem de construção: Fase 0 → 1 → 2 (a 3 depois da auditoria).

**✅ CONSTRUÍDO (15/07, noite — Fases 0, 1 e 2; falta a 3, pós-auditoria).
No working tree, NÃO commitado, junto com o lote dos itens 37–38.**

- **Fase 0 (unificação):** migration aditiva `20260715000003`
  (tasks.contact_id + FK + índice + backfill em SQL puro pelos últimos 8
  dígitos, preferindo match de número inteiro). Task ganhou
  `belongs_to :contact`, hook `link_contact_by_phone` (toda task nasce
  amarrada ao contato, venha do modal, Secretário, Atendente Instagram ou
  automação; contato explícito vence), `Task.for_patient` e
  `Task.match_contact` (critério único de match). `infer_consulta_modality`
  agora usa o histórico do CONTATO. AppointmentRecorder grava/reagenda com
  contact; tasks_controller aceita contact_id e o devolve no JSON.
- **Fase 0b (fim dos N+1 de telefone):** Dashboard dos Médicos
  (conversion_infos em lote: 3 queries; nps por contact_ids) e Meu Painel
  (count_conversions em lote) — regexp de telefone só como fallback de
  registro antigo sem link.
- **Fase 1 (Espaço do Paciente):** `GET /crm/patients/:contact_id`
  (patients_controller) → identity (nome/fones/etiquetas/cards do funil/
  anúncio de origem), timeline (origem → conversas → funil → consultas c/
  tipo/comparecimento/reagendamento/indicação → fechamento → cirurgia →
  NPS → formulários c/ respostas → follow-ups por robô) e indicators
  (dias de jornada, responsividade in/out, funil atual + dias, consultas
  ✓/✗/🔁, valor, NPS). Página `patient/PatientSpace.vue` (rota
  `/patient/:contactId`), header azul vítreo + KPIs + linha do tempo
  vertical (toggle recente/início). ATALHOS nos 4 pontos: card do CRM
  (ContactCard, ícone ao lado do balão), balão (ConversationChatModal,
  header), painel da conversa (ConversationSummaryCard, link sob o
  telefone) e Agenda (modal de edição, quando a consulta tem contato).
- **Fase 2 (Espaço Nobre do Médico):** migration aditiva `20260715000004`
  (crm_clinical_notes: contact/task/author, doctor, performed_at, fields
  jsonb, observations) + fotos via ActiveStorage (has_many_attached, ⚠️
  storage da VPS entra no plano de backup). Campos rápidos no modal:
  procedimento (refrativa→PRK/Lasik | catarata→lente nacional/Rayner/foco
  estendido/trifocal/tórica), olho OD/OE/AO, refração/acuidade/PIO por
  olho, biomicroscopia, fundoscopia, conduta (linhas→pílulas), exames
  pedidos, indicação de cirurgia. Indicação marcada + consulta ligada →
  task vira 'indicated' e o card move no CRM via `Crm::AttendanceReflector`
  (serviço extraído do tasks_controller; conferência do dia usa o mesmo).
  PERMISSÕES (agenda_config.clinical_access, config no escudo 🛡️ da
  própria seção, admin): médicos (doctor_user_ids) + admin editam (cada
  médico só edita a própria; admin todas), equipe só vê com team_view
  ligado (padrão DESLIGADO — LGPD); acesso auditado no log
  ("[CEVICO clínico]"). Testado por HTTP: 403 p/ agente, 200 admin,
  upload/remoção de foto ok, team_view liga/desliga ok.
- **Testes locais (Docker):** consulta criada por API com telefone →
  contact_id linkado sozinho + modality inferida (avaliação → retorno na
  2ª); backfill validou (3/6 tasks com fone casaram na base local);
  paciente 1 da conta 3 → 34 eventos na timeline; dashboards refatorados
  respondendo; rubocop limpo nos arquivos novos; Vite compilando tudo.
- **Dados de teste locais (conta 3, podem apagar):** consulta "Teste
  Fase 0" 20/07 14h (task 27) e anotação clínica #2 (Dr. Gustavo,
  refrativa PRK AO, com foto exame.png) no paciente 1.
- **⚠️ DEPLOY DESTE PEDAÇO:** 2 migrations aditivas (…000003 backfill +
  …000004 tabela nova) → BACKUP ANTES. Reversão: reimplantar imagem
  anterior no EasyPanel. Depois do deploy: marcar os médicos no 🛡️ do
  Espaço do Médico (senão só admin edita) e decidir team_view.
- **Fase 3 (IA no banco):** NÃO construída — combinado deixar para depois
  da auditoria (semana de 20/07).
- **🎨 REPAGINADA "DOPAMINE COLOR" (15/07, madrugada — pedido do Guilherme
  após aprovar o painel):** o ambiente inteiro se veste com a cor do
  paciente — homem = azul (jovem→azul céu, maduro→azul profundo, 60+→céu
  noturno COM ESTRELAS), mulher = rosa (jovem→claro, madura→intenso,
  60+→roxo); sem sexo/idade no contato = azul CEVICO neutro. Sexo/idade
  vêm de additional/custom_attributes do contato (sexo/gender/genero +
  data_nascimento/date_of_birth/idade) — a equipe preenche e a página
  colore sozinha. Barra superior = trunfo: card do funil + sinais rápidos
  (formulários ✓, NPS, robôs rodando, follow-up pausado). Cards de
  informação novos: Consultas (datas+motivo+✓/✗), Procedimento &
  Investimento (orçamento de indicação × fechamento × TAXA DE PERFORMANCE
  %), NPS & Pesquisas, Automações neste contato (robôs de follow-up
  aplicáveis + automações da coluna + pausa — backend novo `automations`).
  JORNADA EMPILHADA: estágios do funil em pilha vertical (1º em cima →
  atual embaixo com anel), data + salto de dias à esquerda, dias dentro de
  cada estágio, etiquetas ganhas no período (backend novo `label_events`
  via taggings.created_at — remoção não tem histórico no core), rodapé com
  total da jornada + média por estágio; toggle "eventos detalhados" mantém
  a timeline completa. Espaço do Médico PROTAGONISTA (coluna larga) com
  faixa "À uma vista" (última anotação resumida). Bloco ATUALIZAÇÕES
  (backend novo `updates`): próximos compromissos, pendências abertas,
  notas da equipe. Modal do médico: PROCEDIMENTOS OFICIAIS COM PREÇO —
  Refrativa (PRK/Lasik R$5.000), Catarata (Nacional 2.800 | Mono Rayner
  3.200 | Tórica monofocal 5.600 | Foco estendido 5.690 | Trifocal 8.490 |
  Galaxy 14.990), Faco Refrativa (Trifocal/Galaxy), Artisan (11.900),
  Outros (Anel de Ferrara/Crosslinking/Glaucoma/Retina/Lente Escleral/
  Blefaroplastia) — escolher GERA O ORÇAMENTO DE INDICAÇÃO (editável,
  fields.indicated_value), que preenche o valor do card no CRM (se vazio)
  e depois é comparado ao fechamento da IA → taxa de performance (quanto
  vendemos do máximo; base p/ precificação/descontos). Ícone
  característico PatientSpaceIcon (medalhão gradiente azul→lilás→rosa)
  nos 4 atalhos. Sem migration nova nesta repaginada (tudo jsonb/payload).
  Teste visual: contato 1 da conta 3 está como masculino/31 anos (tema
  azul adulto) — mudar sexo/data_nascimento no contato troca o tema.
- **🎨 RODADA 2 DA DOPAMINE (16/07, madrugada — feedback do Guilherme):**
  (a) SEXO DO PACIENTE: botões em linha ♂/♀ no cabeçalho do Espaço do
  Paciente (POST crm/patients/:id/update_profile) + o Secretário da Agenda
  DETECTA o sexo pelo nome/contexto da conversa ("minha mãe", "meu pai") —
  campo sexo no schema do extraction service, carimbado via
  AppointmentRecorder.stamp_gender (manual vence); sexo desconhecido =
  tema VERDE dopamine (novos contatos/orçamento), muda de cor sozinho
  quando descoberto. (b) Jornada CORRIDA: estágios repetidos consecutivos
  fundidos num bloco só. (c) 🐛 FIX agentes de IA: os 7 pontos do
  CrmAutomationFireJob liam a conversa CRIADA por último (created_at) —
  agora leem a de ATIVIDADE mais recente (latest_conversation; causa
  provável do "não está agendando direito"); sales_coach idem. Sobre "não
  pega a coluna Consulta Realizada": automações disparam quando o card
  ENTRA na coluna — quem já estava lá quando o agente foi ligado não
  dispara (usar o disparo manual da automação no Modo Programação ou o
  Preencher histórico do Secretário). (d) MEU PAINEL: "Consultas
  agendadas" agora = appointments_booked (tasks consulta CRIADAS no
  período — volume concreto da Vaneide), com o recorte por coorte como
  subtítulo; botão PULSANTE "Ir para agenda" na Saúde da Agenda
  (animação cevico-pulse). (e) CRM local espelhado com as 12 colunas da
  CEVICO (Novos Contatos → ... → Pós Operatório; "Cirurgia" renomeada p/
  "Cirurgia Agendada" preservando cards). (f) BALÃO azul céu dopamine:
  bolhas enviadas com gradiente #0EA5E9→#38BDF8→#7DD3FC no chat core
  (bubbles/Base.vue, variant AGENT) e no balão do CRM. (g) PAINEL DIREITO
  enxuto: saíram Time/Prioridade/Informações da conversa/Participantes;
  "Pessoa responsável" (ex-Agente atribuído) em BOTÕES EM LINHA — termo
  oficial adotado p/ o padrão de seleção do sistema; Notas do contato sem
  gaveta, com caixa de texto direta embaixo (Cmd+Enter salva).
  (h) FORMULÁRIOS PÚBLICOS dopamine: fundo troca com crossfade a cada
  pergunta (céu→esmeralda→dourado→lilás→rosa→coral→teal; abertura azul
  marinho CEVICO, agradecimento dourado), cartão acompanha via CSS vars.
  (i) RADAR: título com plural correto; "O que fazer" em tom PROFESSORAL
  (sem urgência); "Motivo" direto; prompt recebe a COLUNA da jornada e
  orienta acolhimento em etapas pós-consulta (paciente ansioso) — vigia
  na coluna Consulta Realizada já funciona (vigias por coluna); prompt
  custom do Radar pode ser editado no card do agente. Sem migration nova.

## 40. 🌐 AMBIENTE DE PÁGINAS + refinamentos (16/07 — construído, no working tree)

- **PÁGINAS CEVICO** (item novo do menu lateral, ícone painéis): sites
  públicos para anunciar procedimentos, quebrar objeções e nutrir
  pacientes, organizados pelas 4 CATEGORIAS de estágio da jornada:
  Captação | Pré consulta | Pré cirurgia | Pós operatório. Migration
  aditiva `20260716000001` (cevico_pages: título, slug único, categoria,
  status draft/published, emoji, cor, subtítulo, corpo em markdown
  (CommonMarker), meta_title/meta_description SEO, CTA label/url,
  views_count). Página pública em `/p/:slug` (cevico_pages_controller,
  sem login): hero navy+dourado c/ selo CEVICO, corpo formatado
  (destaques em dourado via blockquote), CTA dourado p/ WhatsApp, footer
  "não substitui avaliação médica"; SEO completo: title/description
  próprios, canonical, Open Graph, h1 — pronto p/ ranquear (catarata,
  refrativa, lasik, prk, artisan, trifocal, galaxy, fácica, riscos).
  Admin em `PagesHome.vue` (visual otimizado da Academia: header da
  marca, cards médios c/ cor+emoji do assunto, selo NO AR/RASCUNHO,
  visitas, copiar link/abrir), editor c/ categoria em botões em linha,
  paleta de cores, bloco SEO explicado e Publicar dourado. Equipe vê,
  só admin edita (menu do agente enxuto não mostra — decidir depois).
  Página de teste local: /p/cirurgia-de-catarata-... (conta 3).
- **Meu Painel**: + `appointments_same_day` — "chegaram E agendaram no
  período" (lead novo que já saiu com consulta; via contact_id da Fase 0)
  no subtítulo do card Consultas agendadas.
- **Formulários (rodada de refinamento)**: dourado "ouro de verdade"
  (#D4AF37/#F4DE8E, menos queimado); abertura = fundo navy CEVICO +
  cartão branco com BRILHO DOURADO PULSANTE (gold-glow); selo oficial
  CEVICO (marca C + nome) em TODOS os cards; textos base novos — intro
  "Vale a pena responder essas perguntas..." e final "Parabéns, você já
  é um dos nossos pacientes preferidos..." (intro_text/thank_you_text
  próprios do formulário continuam vencendo); final com logo FLUTUANDO
  e pulsando em dourado, cartão pulsando e fundo navy bem escuro; barra
  de progresso com PSICOLOGIA (avança rápido até ~50%, desacelera no fim
  — easing 1-(1-t)²) e EFEITO ENERGIZANTE estilo "Ultracode" (shimmer
  que acelera e ganha glow dourado perto do fim — CSS puro, leve,
  --energy 0→1).
- **Balão das conversas**: azul ROYAL com gradiente (#1D4ED8→#2563EB→
  #3B82F6) — contraste melhor com letra branca (chat core + balão CRM).
- **Alterar fontes** (menu do perfil, abaixo de Alterar Tema): cada
  clique troca a combinação — Padrão | Serifada (Georgia/Cambria) |
  Mista (títulos com serifa) — html[data-cevico-font] + CSS no
  app.scss, salvo por aparelho (localStorage cevico_font_combo), fontes
  do sistema (zero download).
- Deploy deste pedaço: 1 migration aditiva nova (…20260716000001) →
  backup antes. Reversão: imagem anterior no EasyPanel.

## 41. 🏅 MARCA REAL + formulários "efeito rampa" + fontes v2 (16/07 — construído, no working tree) ⏳ AGUARDA TESTE VISUAL

Sem migration nova. Rodada guiada pelo logo oficial + pesquisa de
dopamine colors do Guilherme (sequência em blocos) + pesquisa de fontes.

- **MARCA OFICIAL NO SISTEMA:** logo vetorizado em
  `public/brand-assets/cevico-eye.svg` (olho na moldura, gradiente ouro,
  fundo transparente — feito a partir do logo enviado; se vier o PNG
  original, salvar ao lado). Lockup completo (olho + CEVICO em Cinzel
  dourado + CUIDADOS OCULARES) montado em HTML/CSS. Cores do logo:
  navy #1E2B5B (profundo #111C42) + ouro #D4AF37/#C9A24B/#F5E9B8.
  Aplicado: selo de TODOS os cards do formulário, lockup grande na
  abertura, medalhão flutuante no final, hero + selo das Páginas
  (adeus "C" em CSS). Cinzel via Google Fonts só nas páginas públicas.
- **FORMULÁRIOS — sequência dopamine em BLOCOS (pesquisa 16/07):**
  Bloco 1 engajamento (laranja ↔ turquesa), Bloco 2 miolo/zona de risco
  (magenta, verde lima, roxo elétrico, amarelo sol), Bloco 3 reta final
  (coral, azul royal; formulários longos pousam em royal → navy suave).
  buildSequence() adapta a qualquer nº de perguntas (13 perguntas caem
  EXATAMENTE na tabela de 15 cards da pesquisa). Abertura/encerramento
  = navy do logo + ouro. MICRO-TEXTOS: 3ª pergunta "Muito bem, vamos em
  frente...", metade "Falta pouco! Suas respostas estão nos ajudando
  muito. 🌟", última "Última pergunta!" (fonte menor, cor do tema).
- **CARD DE MENSAGEM (💬, tipo 'message'):** card só de frase + texto de
  apoio + COR (botões em linha no criador: Sequência/Marca/8 cores) —
  um respiro/celebração no meio do formulário. Não conta na numeração
  nem no dashboard de respostas; backend permite text/color.
  Botão próprio "+ 💬 Card de mensagem" no criador.
- **NÉVOA DE ÁTOMOS na barra de progresso:** canvas leve com partículas
  na cor do card (com pitada de ouro) dançando ao redor da linha; fica
  mais densa conforme avança; no envio ENERGIZA o cartão inteiro
  (pulso dourado ~1,6s) e suaviza para o card final. Respeita
  prefers-reduced-motion.
- **FONTES v2 (menu do perfil):** seleção em PAINEL igual ao de temas
  (ninja-keys, parent font_settings). Combinações novas da pesquisa —
  Padrão (Inter) | Clássica Medicinal (Lora + Open Sans) | Científica
  Moderna (Merriweather + IBM Plex Sans) | Editorial Elegante (Playfair
  Display + Inter). Serifa SÓ em títulos (h1-h4) — nunca em inputs/chat/
  números (regra de ouro da pesquisa). Google Fonts baixa só quando a
  combinação é escolhida (cevicoFontHelper injeta o link); chaves
  antigas serif/mixed migram sozinhas.
- **Meu Painel:** card "Consultas agendadas" sem frase quebrada — duas
  linhas curtas propositais ("registradas no período" + "⚡ N chegaram
  e agendaram"), com truncate de guarda.
- Testado no Docker (browser real): abertura com logo ✓, laranja→
  turquesa→…→amarelo na última ✓, card de mensagem magenta ✓,
  micro-textos nas 3 posições ✓, névoa densificando ✓, envio gravou
  resposta SEM os cards de mensagem ✓, final ouro sobre navy escuro ✓,
  hero das Páginas com logo real ✓, Vite compila os 6 arquivos ✓,
  rubocop: só ofensas herdadas. Dados de teste: card de mensagem
  "Você está indo muito bem! 🚀" inserido no formulário da conta 3;
  meta_title da página de catarata corrigido p/ "Cuidados Oculares".
- **DECIDIDO (16/07): CONSTRUTOR DE PÁGINAS v2 por SEÇÕES** — em vez de
  markdown corrido: seções empilháveis (hero/texto/benefícios/FAQ/
  depoimento/CTA/galeria), cada uma com efeito escolhível, + seção IA
  (gera/repagina seção ou página inteira com a chave Anthropic).
  Imagens: IA de imagem é serviço externo (decidir depois). Proposta
  detalhada apresentada; aguardando aprovação do desenho p/ construir.

## 42. 🏗️ CONSTRUTOR v2 (Páginas POR SEÇÕES + efeitos + agente Copywriter) + refinos do formulário + Agenda (16/07, tarde 2 — working tree) ⏳ AGUARDA TESTE VISUAL

Migration aditiva **20260716000002** (cevico_pages.sections jsonb, default []).
Páginas antigas (markdown) continuam funcionando — seções vencem quando existem.

- **CONSTRUTOR DE PÁGINAS POR SEÇÕES (manual):** no editor de Páginas,
  seções empilháveis em botões em linha — Texto, Benefícios (cards c/ selo
  dourado), Passo a passo (números dourados), FAQ (sanfona), Depoimento,
  👁️ EXPERIÊNCIA DE VISÃO (frase embaçada + slider dourado "como você
  enxerga hoje → visão corrigida ✨" — conexão emocional com o paciente),
  Faixa de destaque (navy+ouro) e CTA. Cada seção com EFEITO próprio em
  botões em linha: Sem efeito | Movimentação (sobe em cascata) |
  Desfocado→foco | Líquido (fundo ondulando) | EFEITO MIOPIA (a seção
  nasce embaçada como o míope enxerga e o SCROLL "corrige" a visão, com
  legenda) | EFEITO ASTIGMATISMO (visão dupla que se alinha) | Brilho
  dourado. Renderer público novo em cevico_pages/show.html.erb
  (IntersectionObserver + scroll-progress, prefers-reduced-motion ok).
  Página demo local: /p/demo-construtor-v2 (conta 3).
- **9º AGENTE: COPYWRITER DE PÁGINAS (key 'copywriter', Opus/high
  recomendado):** Crm::CopywriterService — recebe briefing + etapa da
  jornada + (opcional) INSIGHTS de um formulário (dores/desejos/objeções
  reais) e escreve a página INTEIRA em seções (structured output:
  title/subtitle/emoji/meta SEO/cta/sections c/ efeitos), com persona de
  copywriter oftalmo (quebra objeção, preços oficiais só se pedido, nunca
  inventa depoimento, nunca promete resultado). Botão "🪄 Gerar página com
  IA" no editor (briefing + select "usar insights de: formulário X") —
  preenche o editor, admin revisa e publica. Card completo no hub de
  Agentes (Editar/Salvar/Publicar/interruptor, padrão OFF). POST
  crm/pages/generate (admin). Modalidades futuras combinadas: carrossel,
  roteiro de reels, descrição de post, anúncio (próxima rodada).
- **CHAVE DO GEMINI (Google):** campo próprio em Integrações → Claude
  (gemini_api_key, mascarada como a da Anthropic; gemini_key_set no
  ai_json) — RESERVADA para gerar IMAGENS nas Páginas (plugar na próxima
  rodada; Anthropic não gera imagem).
- **FORMULÁRIOS (refinos do feedback):** SEM contador "Pergunta X de Y"
  (a névoa já dá o progresso); micro-textos FIÉIS à pesquisa nas
  fronteiras dos blocos (3ª "Muito bem, vamos em frente...", 4ª "Olha só,
  você já começou muito bem! 🚀", 1ª pergunta do bloco 2 "Vamos para a
  melhor parte? ✨", metade "Falta pouco! 🌟", 1ª do bloco 3 "Quase lá! ⏳",
  última "Última pergunta! Prometo. 😉" — fronteiras caem na primeira
  PERGUNTA do bloco, nunca em card de mensagem); NÉVOA mais forte e
  GRUDADA NA PONTA conforme avança (enxame na ponta + rastro, alpha maior
  na ponta); FINAL NOVO: a linha completa faz a VOLTA NA BORDA do card
  (segmento dourado, 2 voltas via SVG pathLength) enquanto a névoa
  energiza, e volta pro lugar; logo vira MOEDA GROSSA 3D girando e
  brilhando infinitamente (4 camadas de espessura + drop-shadow pulsante);
  COR ESCOLHÍVEL em QUALQUER card do criador (pills em todos os tipos,
  override da sequência).
- **AGENDA (usabilidade):** botão + FLUTUANTE redondo (canto inferior
  direito, cor do tema) = caminho principal de agendar; clicar num DIA do
  MÊS agora ABRE A SEMANA daquele dia; na SEMANA, a ALTURA do clique na
  célula define a meia hora (metade de cima = HH:00, de baixo = HH:30).
- **LOGO OFICIAL INTEGRADO (arquivos reais recebidos 16/07):** originais
  salvos em public/brand-assets/ — cevico-logo.png (lockup 626×212, fundo
  navy), cevico-eye.png (olho 282×268) e cevico-logo-dark-bg.png (fundo
  removido via fuzz — SÓ p/ fundos escuros, tem halo leve). Navy EXATO
  medido do arquivo: #152C61 (profundo #0C1B40, claro #23407F) — aplicado
  em formulários (fundo, paletas navy/navySuave/final) e Páginas (hero).
  Abertura do formulário = PLACA do logo original (PNG com cantos
  arredondados); hero das Páginas = lockup transparente real;
  cevico-eye.svg REDESENHADO fiel (moldura aberta nas laterais, olho
  atravessa) p/ fundos claros (selo dos cards + moeda 3D).
- Testado no Docker (browser real): página demo com todos os efeitos ✓
  (miopia corrige no scroll, slider da visão ✓, benefícios focam, faixa
  brilha, CTA dourado), formulário sem contador ✓ + frases nas fronteiras
  certas ✓ + moeda girando com espessura visível ✓ + névoa na ponta ✓,
  Vite compila os 8 arquivos ✓, rubocop: arquivos novos limpos (ofensas
  restantes herdadas), migration aplicada ✓. Copywriter SEM teste de API
  real local (sem chave no Docker) — testar em produção com o agente
  ligado. Dados de teste: /p/demo-construtor-v2.

## 43. ✍️ COPYWRITER MULTI-FORMATO + Construtor de Páginas (10º agente) + hub sanfona + Gemini nativo (16/07, noite — working tree) ⏳ AGUARDA TESTE VISUAL

Sem migration nova. Feedback do teste visual do Guilherme + pedidos novos.

- **HUB DE AGENTES EM SANFONA:** com 10 agentes, os cards agora ficam
  RECOLHIDOS (faixa colorida + ícone + título + tags + descrição resumida
  + interruptor); clicar no cabeçalho desce o agente completo com
  animação leve (opacity+translate 0.28s, chevron girando). Interruptor
  não abre/fecha (@click.stop).
- **COPYWRITER MULTI-FORMATO (evoluiu):** modalidades página | carrossel
  | roteiro de reels | post | anúncio; ESTRUTURAS validadas com "como
  usar" no prompt — Kishōtenketsu, Storytelling, Jornada do Herói,
  Notícia (pirâmide invertida), Perguntas e Respostas, Diálogo — em
  botões em linha; campo "SUAS estruturas e referências" salvo na config
  do agente (agents.copywriter.references, entra em TODO prompt).
  **ESTÚDIO DE CONTEÚDO** dentro do card do agente: formato + estrutura +
  briefing + insights de formulário → resultado em blocos (cards/cenas/
  variações) + legenda + hashtags + "Copiar tudo". POST
  crm/settings/copywriter_content (admin). Schemas extraídos p/
  Crm::CopywriterSchemas (rubocop limpo).
- **10º AGENTE: CONSTRUTOR DE PÁGINAS (key 'pagebuilder', Sonnet/médio):**
  a dupla do Copywriter — recebe COPY PRONTA e MONTA a página (seções +
  efeitos + SEO) SEM reescrever o conteúdo. No editor de Páginas o painel
  de IA ganhou DOIS MODOS em botões em linha: "✍️ Escrever do zero
  (Copywriter)" | "🧱 Montar de copy pronta (Construtor)". Card completo
  no hub (OFF por padrão).
- **TIME CRIA PÁGINAS:** qualquer pessoa do time abre o editor, usa a IA
  e salva RASCUNHO (controller força: não-admin não muda status — não
  publica nem despublica; excluir e slug seguem admin). Aviso no editor:
  "rascunho salvo vai para o admin publicar".
- **GEMINI NATIVO em Integrações:** card próprio (ícone gradiente Google)
  + seção no modal com chave mascarada (Google AI Studio), Salvar e
  TESTAR CONEXÃO real (GET /v1beta/models). Campo saiu de dentro do
  Claude. POST crm/settings/test_gemini. Botão "Gerar imagem" nas seções
  = próxima rodada.
- **FORMULÁRIO (feedback):** bug visual da barra no 100% corrigido (o
  glow era cortado pelo overflow do trilho — glow removido, energia é
  toda da névoa); NUVEM maior: resíduos soltos ao redor e além da ponta
  (18% strays), rastro mais visível, canvas mais alto (52px), 16+130
  partículas — mantendo o volume na ponta; SELO = mini placa do logo
  oficial (PNG real arredondado); MOEDA final = MEDALHA com o olho
  oficial (cevico-eye.png, fundo navy + borda ouro).
- **CAPTAIN REMOVIDO:** o balão flutuante do Copilot/Captain do Chatwoot
  (canto inferior direito, brigava com o + da Agenda) saiu do Dashboard.
- Testado no Docker: Vite compila os 6 arquivos ✓, rubocop 100% limpo nos
  arquivos novos/tocados ✓, services carregam e rotas resolvem ✓
  (copywriter_content + test_gemini), formulário no browser real:
  barra 100% limpa + nuvem espalhada + medalha oficial ✓. Estúdio/
  sanfona/Gemini aguardam teste visual logado (sem chave de IA local).

## 44. 🚨😊 Rodada pós-deploy 16/07 (tarde) — popup do Radar, feedback de bugs, fixes de produção ⏳ NO WORKING TREE

Sem migration nova. Feedback real do primeiro dia do lote no ar.

- **🐛 FIX "88 consultas agendadas" (contador fantasma):** consulta
  registrada PARA O PASSADO (preenchimento de histórico/disparo
  retroativo: due_at < created_at) não conta mais como "agendada no
  período" — booked_scope no Meu Painel (appointments_booked e
  same_day). Testado: retro fica fora ✓.
- **🐛 FIX horário errado do Secretário (11h → 11:30):** regra de
  HORÁRIO LITERAL no prompt de extração ("11h"=11:00, NUNCA arredondar,
  vale só o horário da confirmação final, não explícito = vazio).
- **📆 "Ver na agenda"** nas notas de agendamento da IA (Secretário e
  Atendente Instagram): link markdown que abre a Agenda direto no DIA
  da consulta (AgendaBoard lê ?date= e abre na visão Dia).
- **🧞 POPUP "PRIORIDADE MÁXIMA" do Radar:** paciente quente esperando
  20+ min → popup salta na tela do atendente com animação GÊNIO DA
  LÂMPADA (canto inferior direito); re-checa AO VIVO no servidor (se já
  responderam, não incomoda); clicar fora = tremidinha + "Essa é a
  prioridade máxima. 😊" + card laranja→azul + botão Atender agora
  PULSANDO; Atender agora abre a conversa (mesma conversa não repete
  por 15 min). Polling leve 90s (GET crm/home/radar_ping).
- **⏸ Radar: desativação manual pela atendente** (botão no bloco de
  avisos do Meu Painel) com REGISTRO de quem/quando
  (opportunity_state.manual_log, POST crm/home/toggle_radar).
- **🐞 FEEDBACK DE BUGS do time:** "Reportar problema 🐞" no menu do
  perfil → gaveta lateral (título + detalhes + tela atual automática) →
  vira card no board do Guilherme (assignee = 1º admin, task_type bug,
  prioridade alta — aparece no Meu Painel dele) → quando o card é
  CONCLUÍDO, quem reportou vê "🎉 problema que você reportou foi
  resolvido!" no próprio Meu Painel (7 dias). POST crm/bug_reports.
- **ESPAÇO DO PACIENTE:** (a) CONTRASTE automático — temas claros
  (azul jovem, rosa jovem, verde) trocam letras/chips para tinta escura
  (.cevico-ink-dark, sem mexer nos temas escuros); (b) ANÚNCIO DE
  ORIGEM em PLACA DOURADA no header ("Anúncio do 1º contato") + cada
  conversa da timeline mostra "📣 Veio do anúncio: X" (meta_ads da
  própria conversa); (c) TRILHA DE AUTOMAÇÕES: CrmAutomationFireJob
  grava cada disparo no contato (cevico_automation_trail, últimos 60) e
  o card Automações ganha "🧭 Por onde ele já passou" com data/hora —
  base p/ saber qual automação realmente ajuda.
- **📝 PROMPT DE AGENDAMENTO N8N v2** (Google Agenda, ANTES de
  internalizar): entregue em ~/Desktop/CEVICO/prompt-agendamento-v2.md —
  contrato ESTRUTURADO supervisor↔calendar_agent (OPERACAO/DATA/BLOCO/
  DURACAO_MIN/...), horário LITERAL, sequência verificar_dia →
  ofertar 2 → verificar_bloco → criar → LER o evento e confirmar só com
  os dados LIDOS (fim da confirmação falsa), STATUS explícito
  (LIVRE/OCUPADO/CRIADO/ERRO), fuso fixo, checklist final, prompt novo
  do calendar_agent e 5 ajustes de config (temperature 0, tools nativas
  separadas, timeZone no nó, cortes de data como variável, log 1 semana).
- **🔍 IMAGENS/ÁUDIOS não abrem (produção):** balão azul NÃO é a causa
  (só estiliza variant AGENT). Suspeita: mídia do WhatsApp Cloud não
  baixada p/ o ActiveStorage (fica só a URL da Meta, que EXPIRA) ou
  storage/proxy da VPS. DIAGNÓSTICO pronto p/ rodar na VPS (ver mensagem
  16/07) — corrigir com evidência na próxima rodada.

### NO RADAR (pedidos 16/07 — construir depois, ordem a combinar)
- 🏆 PRÊMIOS de zerar a fila: quando a responsável zera 100% das
  conversas pendentes das colunas dela → celebração com animação,
  elogio e frases motivacionais (Meu Painel).
- 💀 SKELETON SCREENS no carregamento ("o sistema se constrói na frente
  da pessoa, como a armadura do Homem de Ferro") — vira padrão de
  design do sistema.
- ⌘P BUSCA UNIVERSAL: CMD/CTRL+P abre busca rápida de paciente/lead/
  histórico de qualquer lugar → ficha do paciente (Espaço do Paciente).
- 📱 EFEITOS "iPhone": rodada de polimento de animações/transições p/
  deixar o sistema viciante.
- 🤖 AUDITOR DE DADOS POR IA ("ambiente de tratamento de dados por IA"):
  analista que audita o que o admin pedir no CRM e organiza — agenda,
  cards fora de coluna, valores errados — com relatório e ações
  aprováveis. Encaixa com a AUDITORIA da semana de 20/07.

## 45. 🏆 CARDS VIVOS do Meu Painel — metas, recordes e "posso viajar?" (16/07, noite) ⏳ NO WORKING TREE

Sem migration nova. Junto com o item 44 no working tree.

- **METAS POR PAINEL (🎯 admin, ao lado da engrenagem):** meta MENSAL por
  indicador de cada painel (agendamento/condução/cirurgias/médicos/
  gestor; % é meta direta). Salvas em agenda_config.panel_goals. O
  backend converte a meta pro período visto (hoje = fatia diária,
  semana = 7 dias, este mês = proporcional aos dias corridos, ano =
  meses corridos).
- **CARDS VIVOS (todos os painéis):** ritmo contra a meta muda a COR do
  card na paleta do próprio painel — 🔴 <40% do esperado (vinho/alerta),
  🟠 40-70% (âmbar), 70-100% mantém as cores normais, 🟢 meta batida
  (verde do painel + selo ✓ META + pulso suave) — "cores mais
  preocupantes quando for mal, já nos alerta". Medidor fino de "% do
  ritmo da meta" + valor esperado no rodapé do card.
- **🏆 RECORDES AUTOMÁTICOS:** melhor valor já visto por indicador e por
  tipo de período (dia/semana/mês/ano), gravado sozinho quando batido
  (agenda_config.panel_records). Card recordista ganha selo 🏆 RECORDE,
  anel dourado e a **AURA DE ÁTOMOS orbitando RENTE à borda em SENTIDO
  HORÁRIO** (TileAura.vue, canvas leve, mesma linguagem da névoa dos
  formulários) — mais forte quanto mais acima da meta.
- **✈️ GESTOR — indicador próprio de decisão:** card grande no topo do
  painel Gestor com o veredito "Tudo bem — pode viajar ✈️" (verde) /
  "Atenção hoje 🟠" / "Ação imediata ⚠️" (vermelho) + CENTRAL DE AVISOS
  com os motivos prontos: metas em vermelho/âmbar, pacientes quentes do
  Radar, conversas sem resposta (>8), consultas sem conferência e
  tarefas no board.
- **Popup do Radar:** entrar no Meu Painel = o aviso cumpriu o papel →
  popup se despede sozinho (e não abre enquanto estiver lá).
- Teste local: metas de teste na conta 3 (agendamento: 900 leads/mês,
  220 consultas/mês, taxa 15%) — hoje deve mostrar meta batida em leads
  e consultas (com 🏆 na primeira carga) e taxa em ritmo ok.
- Rubocop: 2 ofensas novas corrigidas; restantes herdadas. Vite ✓.

## 46. 📱🌐 CRM mobile + cores por caixa + domínio público oficial (16/07, noite 2) ⏳ NO WORKING TREE

Sem migration nova. Pedidos do Guilherme na retomada da noite.

- **CRM abre SEMPRE em "Últimos 7 dias"**: a janela de trabalho não fica
  mais gravada no aparelho (localStorage → sessionStorage): toda visita
  nova começa nos 7 dias (garantia de carga leve no celular — a janela
  pesada salva era o que travava). Trocar a janela continua valendo
  durante a sessão do navegador.
- **CRM MOBILE (abaixo de 768px)**: navegador de colunas fixo no topo —
  chips com bolinha da cor da coluna + nome + contagem; o chip ativo
  (gradiente azul→roxo) acompanha o deslize e clicar PULA direto pra
  coluna (com 12 colunas o deslize era maratona). Barras do topo/filtros/
  janela viram trilhos deslizáveis de 1 linha (não empilham mais), texto
  explicativo da janela some no celular, padding do board 12px.
  ⚠️ Lições técnicas: snap "x mandatory" CANCELA scroll programático
  (desligar o snap no pulo e religar ~80ms depois; o alvo já é posição de
  snap); scroll-behavior:smooth inline fazia até behavior:'auto' virar
  smooth (removido — o pulo é instantâneo e confiável). No webview do
  teste, eventos de scroll programático não disparam (chip-segue-deslize
  conferir no celular real).
- **COR PRÓPRIA POR CAIXA DE ENTRADA** (helper cevicoInboxColors.js):
  paleta de 8 gradientes; a cor segue a ORDEM DE CRIAÇÃO da caixa (caixa
  nova não muda a cor das antigas; nome fora do cadastro cai em hash).
  Aplicada nas pílulas de Conversas (ativa = gradiente da caixa; inativa
  = pontinho da cor) e no filtro do CRM, que deixou de ser select cinza e
  virou BOTÕES EM LINHA coloridos. Dourado ficou reservado pro "Todas".
- **DOMÍNIO PÚBLICO OFICIAL das páginas/formulários** (Meta e Google):
  nova env `CEVICO_PUBLIC_HOST` (ex. www.cevico.com.br). Com ela setada:
  páginas respondem na RAIZ do domínio oficial (www.cevico.com.br/
  preoperatorio — rota coringa no FIM das rotas, só no host oficial),
  raiz "/" = índice bonito das páginas publicadas por categoria
  (identidade navy+ouro, logo real), /p/slug e links antigos de
  formulário redirecionam 301 pro oficial, canonical/og:url apontam
  SEMPRE pro oficial, links de formulário do WhatsApp já saem no domínio
  oficial, tela Páginas mostra/abre a URL nova. Slugs reservados
  (app/api/forms/health/...) bloqueados no modelo. SEM a env, nada muda.
  Helper central: app/services/cevico/public_site.rb.
  ⚠️ ORDEM DO DEPLOY: primeiro apontar DNS + adicionar o domínio no
  EasyPanel (SSL emitido), SÓ DEPOIS setar a env em web+sidekiq — env
  setada com domínio morto = links antigos redirecionando pro vazio.
  PENDENTE: Guilherme descobrir onde o site cevico.com.br está hospedado
  (caminho /preoperatorio no www exige proxy lá; subdomínio dedicado ex.
  conteudo.cevico.com.br é o caminho simples).
- Testes: vite 200 nos 4 arquivos; rubocop zero ofensas nos arquivos
  novos; bateria HTTP local (índice 200, página na raiz 200, 301 do /p/ e
  do form antigo com token válido, 404 slug inexistente, form 200 no host
  oficial, baseline sem env intacta); visual desktop+mobile 390px no
  browser embutido. Senha local do admin@admin.com (conta 3) =
  CevicoTeste@2026 (só Docker local, p/ teste visual).

## 47. 💚🌐 Radar verde dopamine + Configurações → Domínio (17/07) ⏳ NO WORKING TREE

Sem migration nova. Junto com o item 46 no working tree.

- **RADAR VERDE DOPAMINE** (pedido: oportunidade é convite, não bronca —
  o laranja-avermelhado dava tom de punição): gradiente novo
  #059669→#4ADE80 em TODAS as superfícies do agente — badge pulsante da
  sidebar (SidebarGroupHeader), popup gênio da lâmpada (estado inicial;
  o "acalmado" segue azul), bloco de avisos do Meu Painel (moldura,
  barra, chamas, pílula ⏱ e botão Atender agora), card do agente no hub
  (identidade opportunity), caixa de config + botão Radar pontual +
  modal, bloco Radar×Consultas do Dashboard CRM. Vermelho continua só
  onde é semântico (bugs 🐞, atrasos, metas vermelhas, falhas).
- **CONFIGURAÇÕES → DOMÍNIO** (novo item no menu Configurações, só
  admin): o domínio público agora é configurado NA TELA e fica no BANCO
  (InstallationConfig CEVICO_PUBLIC_HOST, cache GlobalConfig/Redis; env
  continua como fallback). A tela tem: input com normalização
  (https://…/ vira host limpo), botão 🔍 Verificar (DNS resolve? HTTPS
  /health responde? selos verdes), Salvar com aviso se o domínio ainda
  não responde, passo a passo Hostinger+EasyPanel com o CNAME alvo
  (app_host) e botão copiar, exemplos de URL ao vivo e aviso quando o
  valor vem da env. Backend: GET public_domain / POST
  update_public_domain (422 p/ host inválido, admin-only) / POST
  check_public_domain no settings_controller do CRM.
- **DOIS MODOS de domínio** (Cevico::PublicSite.dedicated_host?):
  dedicado (host ≠ FRONTEND_URL → raiz vira índice de páginas) e MESMO
  domínio do sistema (ex. sistema.cevico.com.br → app continua na raiz
  e /app; páginas moram nos caminhos /nome-da-pagina; /p/ normaliza 301).
  Decisão do Guilherme 17/07: subdomínio sistema.cevico.com.br (site
  cevico.com.br é Hostinger, conta compartilhada pelo Henrique).
- Senha local do admin@admin.com RESTAURADA p/ Admin@123456 (a troca de
  ontem era só p/ meu teste visual).
- Testes: vite 200 nos 9 arquivos; rubocop zero nos métodos novos
  (check_public_domain refatorado em helpers); bateria HTTP com config
  DO BANCO: dedicado (índice 200, página raiz 200, /p/ 301) + mesmo-host
  (app na raiz, página no caminho, /app intacto, /p/ normaliza) + 422
  inválido + check google.com dns/http ok; visual: tela Domínio + Meu
  Painel verde + badge verde.
- PRÓXIMAS RODADAS COMBINADAS (aguardando ordem do Guilherme):
  (A) DESIGN_CEVICO.md + tokens (cores dopamine, espaçamentos, molas de
  movimento estilo iPhone, componentes oficiais: pílulas de período,
  botões em linha, cards vivos) → alicerce do "repasse geral";
  (B) repasse dos DASHBOARDS (paleta dopamine, animações de recorde,
  mobile/tablet); (C) microinterações (menus, skeleton armadura do Homem
  de Ferro, gênio da lâmpada) + ícones próprios da sidebar
  (descaracterizar Chatwoot); (D) experiência do time (frases
  motivacionais + elogios estratégicos no Meu Painel; ambiente de
  relacionamento interno home-office); (E) ambiente de PLANEJAMENTO DE
  CONTEÚDOS estilo workflow/canvas (especificar juntos antes de
  construir).

## 48. 🤍⚡ Radar branco energizado + CRM 2 linhas + PÁGINAS: projetos, funil e conversão (17/07, madrugada) ⏳ NO WORKING TREE — ⚠️ TEM MIGRATION

⚠️ MIGRATION NOVA: 20260717000001 (funil/rastreio em cevico_pages) —
BACKUP DO BANCO antes do deploy. Reversão: reimplantar imagem anterior
(migration é aditiva, não precisa reverter o banco).

- **🤍 Notificação do Radar no Meu Painel repaginada** (feedback: layout
  deixava a desejar): cartão FUNDO BRANCO fixo nos dois temas (tinta
  escura própria, chips verdes/dourados) e botão "Atender agora" com
  ANIMAÇÃO DE ENERGIA (.cevico-energy-btn: respiração + anéis verdes
  emanando + brilho varrendo + gradiente vivo; respeita
  prefers-reduced-motion).
- **📐 Toolbar do CRM em 2 LINHAS intencionais** (feedback: "alinhar,
  espaçar, distribuir"): linha 1 = o que eu PROCURO (busca, sem
  resposta, ordenação, caixas, Filtros + contador à direita); linha 2 =
  o que eu VEJO (visualizações de colunas, período do lead, limpar).
  TODOS os controles com 34px de altura; no celular cada linha é um
  trilho deslizável.
- **🔎 Empty state explicativo**: quando o filtro de período zera o
  board ("Exibindo 0 de N" que assustou o Guilherme), a tela agora diz
  que o filtro olha a DATA DE CHEGADA do lead e que os cards continuam
  no funil; pílulas ganharam tooltip "leads que CHEGARAM...".
- **📋 PÁGINAS — gestão de projetos**: status novo 'idea' (💡 Ideia →
  🛠 Em produção → 🟢 Publicada/NO AR), chips de filtro com contagem no
  topo, badge tri-estado nos cards, seletor "Etapa do projeto" no editor
  (admin; equipe segue criando rascunho).
- **➡️ FUNIL DE PÁGINAS**: campo next_page_id — o botão da página pode
  "reapontar para outra página da CEVICO" (captação despretensiosa →
  aprofundamento → convite WhatsApp). Editor: bloco "Próximo passo do
  botão" (botões em linha WhatsApp | Outra página + select de destino +
  aviso se destino não publicado). Texto do botão automático
  ("Continuar: {título} →") quando vazio.
- **📊 RASTREAMENTO/CONVERSÃO**: redirecionadores que CONTAM clique —
  /p/:slug/cta (convite WhatsApp) e /p/:slug/next (funil, manda ?de=slug
  pra próxima página registrar a ORIGEM). daily_stats jsonb por dia
  {view/cta/next/de:{slug:n}} + contadores totais (cta_clicks_count,
  next_clicks_count; view via track_hit!). Cards do admin mostram
  👁 visitas · ➡ funil · 💬 WhatsApp · % clicam; API manda last7.
  Base p/ "público super qualificado" (pixel/CAPI nas páginas = rodada
  futura).
- **🔍 CAUSA DAS IMAGENS/ÁUDIOS ACHADA** (diagnóstico na VPS):
  active_storage service = LOCAL e TODOS os anexos recentes "ARQUIVO
  SUMIU do disco" → /app/storage NÃO é volume persistente (cada
  Implantar descarta os arquivos) e web/sidekiq têm discos separados
  (mídia baixada pelo sidekiq nunca aparece pro web). FIX SEM CÓDIGO no
  EasyPanel: criar VOLUME COMPARTILHADO (mesmo nome, ex. cevico-storage)
  montado em /app/storage NOS DOIS serviços (web e sidekiq) e
  reimplantar; arquivos antigos são irrecuperáveis (URLs da Meta
  expiram). Depois: rclone do volume (fotos clínicas!) e avaliar S3/R2.
- Testes: migration local ok (annotate atualizou o model), vite 200,
  rubocop zero nos arquivos tocados (helpers extraídos), e2e do funil
  com contadores conferidos no banco (A next=1, B view c/ origem
  de:{demo}=1, cta=1), visual: chips/status/cards/editor confirmados.
  Dados de teste do funil só no Docker local.

## 49. 🔧 FIX gerador de páginas IA + radar só admin + leads de teste (17/07, madrugada 2) ⏳ NO WORKING TREE

Sem migration nova. Feedback do teste do Guilherme em produção.

- **🐛 FIX "Internal Server Error" do Gerar página com IA**: causa
  principal = timeout do cliente Anthropic em 60s — o Copywriter escreve
  páginas inteiras (Opus, esforço alto, até 8k tokens = MINUTOS) e a
  chamada morria no meio. Timeout → 300s (agentes rápidos não mudam).
  Blindagem completa: resposta vazia vira mensagem amigável (era
  JSON.parse(nil) = 500), rescue amplo com log nos dois serviços
  ([Copywriter]/[PageBuilder] no log) e rescue no Pages#generate — o
  botão NUNCA mais devolve 500 seco; sempre explica o que houve.
  parse_structured_response compartilhado no AiAgentConfig. Schemas
  conferidos: sem minItems/pattern (lição antiga ok). Se em produção
  ainda estourar (proxy matando requisição longa), próximo passo é gerar
  em background com aviso — anotado.
- **⏸ Pausar radar SÓ ADMIN**: botão some para atendentes no Meu Painel
  e o backend recusa (403) — pausar o Radar é decisão de gestão.
- **🧪 20 LEADS DE TESTE por comando** (novo padrão de teste): rake
  `cevico:seed_test_leads ACCOUNT_ID=3` cria 20 leads variados (12
  colunas, datas espalhadas em 45 dias, valores reais dos procedimentos,
  etiquetas sortidas + `teste-lote` p/ achar/limpar). Rodada 2x local =
  40 leads no board de teste.

## 50. 🧭 Radar formato CRM + Meta de tempo + Mentor do Time + Painel Estratégico (17/07, manhã) ⏳ NO WORKING TREE — ⚠️ TEM 2 MIGRATIONS

⚠️ MIGRATIONS NOVAS: 20260717000002 (cevico_pillars + cevico_strategies) e
20260717000003 (crm_weekly_feedbacks) — BACKUP DO BANCO antes do deploy.
Reversão: reimplantar imagem anterior (migrations aditivas). Cron novo
(crm_weekly_mentor_job) → reimplantar SIDEKIQ junto, inegociável.

- **💚 Radar no formato do card do CRM** (pedido: "melhor distribuído,
  desktop e mobile, parecido com o card do CRM"): cada aviso virou um card
  irmão do ContactCard — avatar com iniciais (gradiente verde), nome +
  telefone, pílula da coluna com bolinha, pílula ⏱ de espera, motivo como
  prévia de mensagem (barra verde à esquerda), "💡 O que fazer" e rodapé de
  ações com ícone do Espaço do Paciente + botão energizado "Atender agora".
  Grade de 2 colunas no desktop (lg:grid-cols-2), empilhado no mobile. O
  card inteiro clica para a conversa. Backend: build_alert agora manda
  contact_id (avisos antigos sem contact_id só escondem o medalhão).
- **🎯 META DE TEMPO DE ATENDIMENTO** (config no agente): campo novo na
  caixa do Radar (Automações → Radar) — "responder o paciente em até N
  minutos" (ai_config.agents.opportunity.response_goal_minutes, padrão 15,
  entra no rascunho/Publicar como os demais campos). Relatório PESSOAL no
  Meu Painel (card "Meta de tempo de atendimento", respeita o período):
  tempo médio, % dentro da meta, nº respostas, barra + selo (🏅 Meta batida
  ≥70% e média dentro / 💪 No ritmo / ⏳ Fora da meta). Atendente vê só o
  seu; admin vê a quebra "Time no período". Fonte: reporting_events
  reply_time (>0) que o Chatwoot já grava — sem migration.
- **🧭 MENTOR DO TIME** (agente novo, opt-in, nasce DESLIGADO): toda
  segunda 08h SP (cron 0 11 * * 1) coleta os dados de uso da semana de
  CADA pessoa (respostas, tempo médio, % na meta, conversas resolvidas,
  mensagens enviadas, tarefas concluídas) e a IA escreve feedback
  individual: resumo, ponto forte, O PONTO FRACO a corrigir e 2-3 soluções
  simples + incentivo. Compara com a MEDIANA do time sem expor colegas.
  Card no Meu Painel (moldura navy→ouro; admin navega por pílulas com o
  time inteiro). Semana sem uso = sem feedback. Botão "Gerar feedback
  agora" no card do agente (admin; últimos 7 dias). Tabela
  crm_weekly_feedbacks (1 registro por pessoa/semana, stats + feedback).
  Recomendado Sonnet 5 esforço alto (~5 chamadas/semana). Schema sem
  minItems (lição antiga ok).
- **🏛️ PAINEL ESTRATÉGICO** (menu "Estratégia", só admin, ícone bússola,
  logo abaixo de Relatórios): a CEVICO por PILARES do negócio. Nascem
  prontos os 3 combinados: 🧲 Aquisição de Pacientes (marketing/vendas),
  🏥 Operação Clínica (exames/consultas/cirurgias), 💰 Financeiro &
  Tributário. Cada pilar: responsáveis (pílulas douradas), SEMÁFORO de
  saúde clicável (🟢 Saudável / 🟡 Atenção / 🔴 Crítico), nota "como está
  hoje" (desempenho/contexto), barra de progresso (% de estratégias
  concluídas) e a lista de 🎯 estratégias / 🛠 correções — cada uma com
  dono, prazo (vermelho se vencido) e andamento que GIRA no clique
  (💡 Ideia → ▶️ Em andamento → ✅ Concluída → ⏸ Pausada). Expandir o item
  abre descrição/dono/prazo/tipo/excluir. Modal do pilar: emoji, nome,
  cobertura, 6 cores, responsáveis, excluir. "+ Novo pilar" para outros
  setores. 3 colunas no desktop largo, 1 no celular.
- ⚠️ Lição nova: o reset global do Chatwoot deixa select/input com 100% de
  largura e VENCE utilitários Tailwind (input:not([type]) tem
  especificidade maior que .w-16) — em linhas flex, travar com style
  inline (width: Xrem). Corrigido no Painel Estratégico e nos dois inputs
  numéricos da caixa do Radar.
- Testes: 2 migrations locais ok; rubocop zero nos métodos/arquivos novos;
  vite 200 nos 7 arquivos; spec do schedule.yml verde; visual desktop +
  mobile 375px no browser embutido (Meu Painel com os 3 cards novos,
  Estratégia com criação/giro de status/modal, Automações com Mentor +
  campo da meta); seeds de teste na conta 3 (avisos do Radar com
  contact_id, reply_time, 2 feedbacks simulados, 3 pilares + 4 itens).

## 51. 📊 Jornada de atendimento por pessoa + ajustes de feedback do 50 (17/07, manhã 2) ⏳ NO WORKING TREE

Sem migration nova. Feedback do Guilherme sobre o item 50 + pedido novo.

- **📊 DASHBOARD DOS AGENTES — jornada de atendimento por pessoa** (pedido:
  "cada agente deve ter o seu dashboard, com as suas estatísticas, para
  feedback"): cada card de pessoa ganhou (a) tile novo "resposta ao lead
  (média)" = média de TODAS as respostas (reporting_events reply_time>0,
  não só a 1ª) com contagem; (b) bloco "jornada": horário da 1ª mensagem
  em média, da última mensagem em média, dias com atendimento; (c)
  MAIORES PAUSAS do período (top 3 intervalos ≥30min entre uma mensagem
  enviada e outra no mesmo dia, com dia da semana, faixa de horário e
  duração colorida: 1h+ âmbar, 2h+ vermelho). Backend: workday_stats no
  agents_dashboards_controller (1 pluck de sender_id+created_at, agrupado
  por pessoa/dia no fuso SP).
- **🔎 CRM: "Limpar filtros" só para filtros de verdade**: as opções
  pré-definidas sempre visíveis (pílulas de período, botões de caixa,
  visualizações de colunas, Sem resposta) NÃO acendem mais o botão
  "Limpar filtros" nem o contador do Filtros — cada uma desliga no
  próprio lugar. O empty state explicativo continua enxergando qualquer
  filtragem (computed anyFilteringActive separado).
- **🎨 Painel Estratégico repaginado** (feedback: "pesou a mão nos
  emojis"): semáforo com BOLINHAS coloridas, itens com ícones lucide
  (alvo azul = estratégia, chave âmbar = correção), status em texto puro,
  prazo com ícone de relógio — emoji ficou só na identidade do pilar.
- **🧡 GRADIENTE NAVY→DOURADO ABOLIDO** (feedback: "não ficou bom, evite"):
  Estratégia = navy→azul royal (#152C61→#3B82F6); Mentor do Time = LARANJA
  (#C2410C→#FB923C) em tudo (card do hub, faixa, card do Meu Painel,
  pílulas, números das soluções). Labels do feedback sem emoji.
- Testes: vite 200 nos 5 arquivos, rubocop (só ofensas herdadas do
  radar_stats, 10→6), visual completo (dashboard com jornada e pausas,
  CRM sem limpar-filtros nos presets, Estratégia limpa, Mentor laranja).

## 52. 🚀 PÁGINAS PRO + PESSOAS PRO + Workflow de conteúdos (17/07, manhã 3) ⏳ NO WORKING TREE — ⚠️ TEM 2 MIGRATIONS + CRON NOVO

⚠️ MIGRATIONS: 20260717000004 (ab_variants+team_comments em cevico_pages
+ tabela cevico_content_items) e 20260717000005 (cevico_people_profiles
+ cadence nos feedbacks c/ reindex único). CRON NOVO crm_monthly_mentor_job
(dia 1, 08:30 SP) → reimplantar SIDEKIQ. Backup antes, como sempre.

**📄 PÁGINAS PRO** (menu Páginas virou grupo: Minhas páginas / Análise &
funis (admin) / Planejamento de conteúdos):
- **Testes A/B**: variações de título/subtítulo/botão servidas SORTEADAS
  no MESMO endereço (ab_variants; 'a' = original; até 3 variações);
  visitante do teste carrega ?v= nos cliques → visitas/cliques/conversão
  POR VARIAÇÃO no daily_stats (view_b/cta_b/next_b). Bloco "Teste A/B"
  no editor c/ placar ao vivo e checkbox "no ar (sorteada)"; placar
  também na Análise c/ selo "liderando" (10+ visitas/variação).
- **Estúdio de copy**: comentários do time por página (team_comments,
  add/delete autor-ou-admin, thread no editor).
- **ANÁLISE DE PÁGINAS** (/pages/analise, admin): tabela geral (visitas,
  cliques, % clicam, badge de teste no ar), série diária 30d em barras,
  QUANTO DA PÁGINA LERAM (beacon sendBeacon de profundidade 25/50/75/100
  → POST /p/:slug/track, skip_forgery), origens do funil (?de=), placar A/B.
- **MONTADOR DE FUNIS** (o "link build"): cadeias de next_page_id
  desenhadas como trilha horizontal c/ conversão de cada elo (X seguiram
  · %), visitas vindas do elo anterior, fim = WhatsApp; select em cada nó
  REAPONTA o funil na hora; páginas publicadas fora de funil listadas p/
  virar novo caminho.
- Mapa de calor de cliques = fase 2 (anotado).

**🧭 WORKFLOW DE CONTEÚDOS** (/pages/conteudos, time inteiro): kanban
ideia → copy → produção → revisão → publicado; cards c/ formato (reels/
carrossel/post/anúncio/página/e-mail em pill colorida), dono, prazo
(vermelho vencido), notas; criar rápido por coluna; mover c/ ← →;
excluir = admin. Tabela cevico_content_items.

**💚 PESSOAS PRO** (menu "Pessoas", cada um vê o seu; admin vê o time;
atendente ganhou 'People' no menu enxuto):
- **DISC / 4 temperamentos**: questionário próprio de 12 perguntas
  (discQuiz.js; D=Colérico, I=Sanguíneo, S=Fleumático, C=Melancólico),
  a própria pessoa responde (2 min); dashboard individual: barras
  D/I/S/C, perfil dominante c/ headline, combinação dominante+secundário
  (DISC_DUOS), pontos fortes, pontos de atenção e "como se comunicar";
  visão do gestor: grid do time c/ perfil dominante de cada um
  (combinar pessoas/montar times). Salvo em cevico_people_profiles.disc.
- **Desenvolvimento pessoal**: objetivos c/ porquê + prazo + status
  (andamento/concluído/pausado no clique) + METAS checkbox → barra de
  progresso ao vivo; goals jsonb; pessoa edita o seu, admin edita todos.
- **Feedbacks**: linha do tempo dos ciclos do Mentor c/ badge SEMANAL
  (laranja) / MENSAL (roxo), resumo + forte + a corrigir.
- **Mentor MENSAL**: WeeklyMentorService ganhou cadence ('monthly' =
  mês fechado, prompt avisa que é visão de evolução), Crm::MonthlyMentorJob
  + cron dia 1; card do Meu Painel segue SEMANAL (weekly filtrado).
- Testes: migrations ok; rubocop ZERO nos 11 arquivos backend; vite 200
  nos 10 arquivos frontend; spec do schedule verde; e2e público do A/B
  via curl (sorteio alternando h1, ?v=b forçando, CTA carregando ?v=b,
  beacon 204, contadores view_a/view_b/cta_b/scroll conferidos no banco);
  visual completo (Análise c/ funil e placar, Conteúdos, Pessoas c/ quiz
  DISC respondido de ponta a ponta, objetivo criado e meta batida a 100%,
  timeline semanal+mensal, editor c/ estúdio A/B e comentários).

## 53. 🎯 METAS + Objeções high-ticket + Pessoas v2 (Roda da Vida) + Conteúdos/A/B + Google + agentes de comentários (17/07, tarde) ⏳ NO WORKING TREE — ⚠️ 2 MIGRATIONS + CRON NOVO

⚠️ MIGRATIONS: 20260717000006 (cevico_goal_plans) e 20260717000007
(life+assessments em cevico_people_profiles). CRON NOVO
crm_comments_agent_job (*/5) → reimplantar SIDEKIQ. Backup antes.

- **🎯 PAINEL DE METAS** (menu "Metas"; admin edita, time vê): plano por
  MÊS (mês atual/próximo/qualquer) com 6 indicadores oficiais (leads,
  consultas agendadas/realizadas, cirurgias agendadas/realizadas, valor
  fechado via StageLog "Cirurgia Realizada"×value), HISTÓRICO de 12 meses
  em barras por indicador (mês selecionado destacado) + alvo editável +
  progresso do mês contra a meta; orientações "como vamos chegar lá";
  MARCOS com check e prazo; notas de AJUSTE DE PROCESSO por pessoa;
  criação de TAREFA real pro time (tasks/create, prefixo 🎯); ROTINAS do
  time + FERRAMENTAS importantes (agenda_config). **MEU PAINEL ganhou a
  faixa Metas do mês (barras) · Rotinas · Ferramentas** e o MENTOR recebe
  meta_do_mes (alvos+orientações+marcos pendentes) no payload — orienta a
  equipe rumo à meta.
- **⚔️ FERRAMENTAS DE FECHAMENTO** (/tools, time lê; atalho na faixa do
  Meu Painel): SCRIPT de fechamento editável (admin) + **MAPA DE
  OBJEÇÕES gerado por IA** (Crm::ObjectionMapService, agente sales):
  lê conversas de quem AVANÇOU nos 4 estágios-chave (StageLog 120d) e
  extrai por estágio as maiores objeções (frequência alta/média/baixa) +
  a MELHOR RESPOSTA real que converteu (frase pronta, clique = copia) +
  por que funciona. Botão admin "Gerar/Atualizar com IA".
- **💚 PESSOAS v2**: DISC agora com **28 itens** (16 escolhas + 12
  escalas 0-10 — mais dados); teste novo dos **4 TEMPERAMENTOS** (12
  situações de vida); todo teste fica **ARQUIVADO** (assessments, compara
  no radar); card do time mostra a **ORDEM dos 4** (D › I › S › C
  colorida — a ordem importa) + temperamento dominante; **RADAR (teia)**
  DISC × Temperamentos × teste arquivado (RadarChart.vue, estilo o
  gráfico de jogador). **ABA VIDA (privada — nem admin vê)**:
  **RODA DA VIDA** animada de 8 áreas coloridas (fatias crescem até a
  nota, média no centro, polígono da avaliação ANTERIOR por cima =
  evolução visível, pergunta reflexiva por área, histórico de momentos
  com nota do momento) · **OBJETIVOS POR HORIZONTE** (20/10/5/3/1 anos,
  3/1 meses, 1 semana, 1 dia, AGORA) · **HÁBITOS & CRENÇAS** com a ficha
  estratégica (com quem aprendeu? era autoridade? o que é absurdo? o que
  Deus pensa? pelo que vai trocar?) + PREÇO pago em 4 áreas (0-10, mini-
  barras coloridas = forças/fraquezas) + status "vencido 🏆".
- **📚 MENU "CONTEÚDOS"** (ex-Páginas): Páginas · Planejamento de
  conteúdos · Análise de funis · **TESTES A/B (central)** — nova tela
  /pages/ab com tudo num lugar: testes NO AR com placar e líder,
  variações pausadas, páginas candidatas (ordenadas por visitas).
- **🏆 TAREFAS**: BANCO DE ELOGIOS (16 frases bem-humoradas, sorteio a
  cada 100%, destaque maior) + donut dourado SEM glow, com **névoa de
  partículas douradas orbitando** (16 partículas, raio/velocidade/opacity
  variados, prefers-reduced-motion ok).
- **📊 DASHBOARD GOOGLE (Ads + GA4)** em Relatórios: estado da conexão
  GA4 (measurement_id+api_secret — já existia o GoogleAdsConversionsService
  via Measurement Protocol e a ação de coluna google_ads_conversion),
  série de 30 dias das CONVERSÕES ENVIADAS (log novo sent_log por
  dia/evento no service), totais por evento e as colunas plugadas; espaço
  pronto pro developer token (investimento/cliques, como o painel Meta).
- **💬 AGENTES DA META**: Atendente Instagram virou **"Atendente Direct &
  Messenger"** (o seletor de caixas já aceita qualquer canal — com a caixa
  do Messenger conectada ele responde lá também); **12º agente
  "RESPONDEDOR DE COMENTÁRIOS"** (IG+FB): varre comentários novos dos
  posts/anúncios a cada 5 min (Graph API v19), responde em público no tom
  CEVICO (curto, sem preço/dado clínico, convida pro direct), caso sério
  = marca pro humano e silencia; config no card (Page token write-only +
  fb_page_id + ig_user_id) + registro de atividade estilo nativo
  (comments_state.events); nasce DESLIGADO e precisa do token do app da
  Meta (mesmo pendente do canal Instagram — item 38).
- Testes: 2 migrations ok; rubocop zero em TODOS os arquivos novos/
  tocados; vite 200 nos 19 arquivos; spec do schedule verde; visual:
  Painel de Metas com histórico real e progresso, faixa do Meu Painel,
  teste dos temperamentos respondido de ponta a ponta + radar comparando,
  Roda da Vida avaliada e registrada com histórico, Ferramentas com
  script salvo. Mapa de objeções e comentários dependem de chave/token
  (produção).

## 54. 💰 GESTÃO FINANCEIRA + Reportar problema padrão + Radar verde + valores da marca (17/07, madrugada 2) ⏳ NO WORKING TREE — ⚠️ TEM MIGRATION

⚠️ MIGRATION NOVA: 20260717000008 (cevico_finance_entries) — BACKUP DO
BANCO antes do deploy. Aditiva; reversão = reimplantar imagem anterior.
Sem cron novo nesta rodada.

- **💰 GESTÃO FINANCEIRA** (menu "Financeiro", logo abaixo de Estratégia,
  SÓ ADMIN — backend também bloqueia): o caixa da CEVICO num lugar só.
  - **Lançamentos** (livro caixa): receitas (consultas/cirurgias/exames/
    convênios), tributos, custos (serviços/comissões/distribuição de
    lucros/serviços médicos/sala cirúrgica), investimento em PRODUTO &
    ESTOQUE (lentes/insumos/medicamentos) e em EQUIPAMENTOS (+manutenção/
    tecnologia). Formulário rápido (data, tipo→categorias dinâmicas,
    descrição, valor pt-BR "1.234,56"), editar (lápis carrega no form) e
    excluir com confirmação; lista do período com pílula colorida por
    tipo e valor +verde/−vermelho.
  - **Visão geral**: KPIs do período (Receita, Custos, Tributos, Lucro c/
    % de margem, Produto & Estoque, Equipamentos, Resultado do caixa =
    lucro − investimentos), GRÁFICO DE LINHA de 12 meses (receita/custos/
    tributos/lucro/investimentos; lucro ouro mais grosso = protagonista,
    investimentos tracejado) e donuts de custos/receitas por categoria
    (mesmo aspecto macio dos outros painéis).
  - **Períodos**: Hoje · Ontem · Essa semana · Este mês · Mês passado ·
    Este ano · **PERSONALIZADO** (duas datas livres + Aplicar) — pedido
    novo, período de análise escolhido pela pessoa.
  - **COMPARAR MESES**: dois seletores de mês lado a lado → tabela de
    indicadores (A, B, variação % com seta; direção "boa" colorida:
    receita/lucro subindo = verde, custo/tributo subindo = vermelho,
    investimento neutro) + quebra de custos por categoria A vs B.
  - Backend: tabela cevico_finance_entries (account, entry_date, kind,
    category, description, amount decimal 12,2, created_by_id) +
    finance_controller (show/create_entry/update_entry/delete_entry/
    compare) — só admin.
- **🐞 "Reportar problema" PADRÃO no Meu Painel de todos**: botão no topo
  do cartão de boas-vindas (vidro branco translúcido), abre a mesma
  gaveta global; funciona em qualquer painel/tema e no celular.
- **💚 Ícone do Radar VERDE**: o ícone do "Meu Painel" na sidebar agora
  pulsa no MESMO verde do badge (#10B981) quando há avisos do Radar —
  antes ficava laranja-avermelhado (#EA3E23), destoava da notificação.
- **✍️ VALORES DA MARCA no Copywriter** (registro oficial): "tecnologia
  de ponta, acolhimento humano e clareza visual" entraram no SYSTEM_PROMPT
  do Crm::CopywriterService como a bússola de toda comunicação (equipamento
  de primeira sem frieza, cuidado pelo nome, comunicação de bater o olho).
- ⚠️ Lição nova: o field-base global (_base.scss) dá `mb-4` + `w-full` a
  TODO input/select e o `select` perde a borda — em formulários custom,
  travar `margin-bottom: 0` e borda com STYLE INLINE (irmão da lição do
  width:100%).
- Testes: migration local ok; rubocop zero nos 4 arquivos ruby; vite 200
  nos 7 arquivos; visual desktop + mobile 375px nos DOIS temas (claro e
  escuro): 3 abas do Financeiro, lançamento criado de ponta a ponta pelo
  form (custo sala cirúrgica R$ 2.350), personalizado 10/05→10/07,
  comparação jun×jul com variações certas, botão Reportar problema
  abrindo a gaveta no desktop e no mobile, ícone verde confirmado via
  computed style. Massa de teste: 124 lançamentos em 12 meses na conta 3
  (embutida direto via runner, sem rake novo).
- **PÓS-"PODE SUBIR" 2 (mesmo dia): CRM sem controle duplicado de dias** —
  a barra "Janela:" (Essa semana/Este mês/Este ano/7d/15d/30d/Personalizado/
  Desde o início) duplicava as pílulas de período da linha 2 e confundia.
  Agora: barra virou SÓ AVISO (⚡ leads ativos + contagem + spinner qdo
  carregando); as PÍLULAS de período são o controle único — cada uma
  ALARGA a janela de carregamento que precisa (ensureWindowForPreset:
  mês→janela mês, ano→ano, Desde o início→base completa; nunca encolhe);
  De/Até manual no painel de Filtros também puxa a base completa se o
  intervalo for mais antigo que a janela (watch). E o trilho das CAIXAS
  perdeu o max-w-440px que cortava os nomes — quebra linha no desktop
  (md:flex-wrap + min-h), celular segue trilho. Testado: pílula Este mês
  alargou a janela sozinha (aviso mudou junto), Desde o início carregou
  44/44 e o aviso sumiu, caixas inteiras.
- **PÓS-"PODE SUBIR" (mesmo dia): Acessos ganharam Metas e Pessoas** —
  as seções novas do menu enxuto (itens 52-53) não apareciam no modal
  "Acessos de Usuário" (Configurações → Agentes → escudo) e o admin não
  conseguia bloquear. Agora: chaves 'goals' e 'people' no FEATURES do
  AgentAccessModal + no FEATURE_BY_ITEM_NAME da Sidebar (o filtro que
  esconde do menu). Backend já aceitava (agent_permissions jsonb livre).
  Testado: bloqueio via banco no admin some Metas+Pessoas do menu,
  restaura ao limpar; modal mostra as 2 seções novas.

### 🏗️ PRÓXIMA GRANDE RODADA — "PÁGINAS PRO" (pedidos 17/07, especificar juntos antes de construir)
1. **Estúdio de Copy por página**: ambiente de criação/edição da copy
   com estrutura entendida pelo Construtor (título/subtítulo/bullets),
   salvar rápido e visual, copy OFICIAL + variações de teste,
   comentários do time.
2. **Testes A/B**: variações de página servidas alternadamente no mesmo
   slug + resultados (visitas/cliques/conversão por variação) — base
   já existe (daily_stats/redirecionadores).
3. **Ambiente de ANÁLISE no menu lateral**: estatísticas completas por
   página (série diária de visitas/cliques, origem do funil, taxa),
   mapa de calor de cliques/scroll (coleta leve na página pública),
   e DASHBOARD geral de páginas.
4. **MONTADOR DE FUNIS visual**: tela onde os funis são montados
   ligando páginas (página → página → WhatsApp), vendo o caminho e a
   conversão de cada elo — o "link build" da CEVICO. Base: next_page_id.

## 55. 🔐 ACESSOS POR CONCESSÃO + Tabela de preços + Metas com dono + paleta (17/07, noite) ⏳ NO WORKING TREE (branch feat/acessos-concessao-frontend) — ⚠️ TEM 1 MIGRATION

Parte 1 da auditoria do frontend (relatório `AUDITORIA_FRONTEND_2026-07.md`)
aprovada pelo Guilherme + decisões da rodada. Tudo testado no Docker local
(admin + atendente.teste, API e visual). **Aguarda "pode subir".**

**a) Controle de acessos vira CONCESSÃO de verdade (Lote 3 completo):**
- Backend: `finance`/`strategy`/`pages`/`data_tools`/`reports`/`campaigns`/
  `automations` agora usam `require_capability` (antes eram check_admin seco
  — conceder não abria nada). Dashboards CRM/Campanhas/Automações ganharam
  trava (estavam ABERTOS). `followup_bots` criar/editar = automations
  (toggle segue livre p/ atendentes). `goals` SAIU das capabilities (edição
  de Metas = só admin, decisão do dia). `update_agent_grants` agora aceita
  também `menu` (itens do dia a dia por pessoa), merge por usuário no
  servidor — sem clobber.
- Modal "Acessos" reescrito: perfis rápidos (Atendimento padrão / Agenda &
  Conferência / Médico) + grupo "Menu do dia a dia" (checkboxes visuais) +
  grupo "Áreas administrativas" (concessões reais c/ selo verde). Admin-alvo
  = tela explica que admin tem tudo.
- Sidebar: menu padrão do atendente = **Meu Painel | CRM | Conversas |
  Agenda | Metas | Respostas prontas** (item novo → canned do core, rota já
  aceitava agente) + Conteúdos (rascunhos do time, decisão do dia) +
  Configurações (perfil). Tarefas/Pessoas/Academia ligáveis por pessoa no
  modal. Áreas concedidas APARECEM no menu (Relatórios só c/ dashboards
  CEVICO; core reports continua admin). Hub de Automações filtra ABAS por
  concessão (robôs/resultados=automations, tratamento=data_tools, resto
  admin). AGENT_MENU_ORDER próprio (admin mantém a ordem de sempre).
- Rotas: `meta.permissions` das rotas concedíveis ganharam 'agent' + guard
  novo `CEVICO_GRANTED_ROUTES` em routes/index.js (fail-closed, espera as
  settings carregarem p/ decidir). Bloqueio legado morreu; listas antigas
  valem só como "esconder do menu" (default preservado). grants começa
  vazio = ninguém ganha nem perde acesso no deploy.
- ⚠️ MUDANÇA VISÍVEL: Tarefas e Pessoas SAEM do menu padrão das meninas
  (pedido explícito) — religar por pessoa no 🛡️ Acessos após o deploy.

**b) 💰 TABELA DE PREÇOS central (Configurações → Tabela de preços):**
grupo/procedimento/preço/promo (promo vale na frente), em
`agenda_config.price_table` (sem migration). Alimenta: Espaço do Paciente
(orçamento de indicação; PRK/Lasik corrigidos p/ 4.900/5.700 dos prompts) e
os prompts do Atendente IA + Analista via token `{{TABELA_DE_PRECOS}}`
(substituído na chamada; sem tabela salva = padrões idênticos aos de hoje;
prompts CUSTOM salvos precisam incluir o token p/ aderir).

**c) 🎯 METAS com dono e caminho:** cada indicador ganhou "responsável"
(select do time) + "o que é preciso para alcançar" (admin prepara; time vê
"Fulana puxa essa meta" + o texto). Migration `20260718000001`
(cevico_goal_plans.indicator_meta jsonb) — **backup antes do deploy**.

**d) 🎨 PALETA TAILWIND completada** (F1 🔴 da auditoria): sky/blue/emerald/
amber/teal/orange/rose/pink/cyan/lime/fuchsia/purple/indigo/gray entram no
tailwind.config.js ANTES das cores do tema (149 usos de classes-fantasma
passam a valer; pílula ♂/♀ do Espaço do Paciente legível — bug provado).
Paletas do tema (green/yellow/red/violet/slate/n/woot) intactas.

**e) F5:** deletePage/deleteClinicalNote agora avisam sucesso/erro (antes
falhavam mudos).

Deploy: 1 migration aditiva → backup (`/root/backup_cevico.sh`); sem cron
novo; reversão = imagem anterior. Pós-deploy: conferir acessos de cada
atendente no 🛡️ (religar Tarefas p/ quem usa) e revisar a Tabela de preços.

## 56. 📊 REPASSE DOS DASHBOARDS DE RELATÓRIOS (rodada B, 18/07 madrugada) ⏳ NO WORKING TREE (mesma branch do 55) — sem migration

Pedido: todos os dashboards de Relatórios no padrão CEVICO, mais bonitos e
coloridos, com animações relevantes — recorde, meta batida e muito abaixo
da meta. Construído e testado ao vivo (admin, desktop + 390px).

**Kit novo (reusável):**
- `components-next/cevico/DashKpi.vue` — card de KPI padrão: gradiente por
  dashboard, número com CONTAGEM ANIMADA (easeOut 750ms), barra de meta e
  4 estados vivos: 🏆 `record` (aura de átomos TileAura + selo dourado
  shimmer + brilho), 🎯 `hit` (respiração verde), ⏳ `low` (selo âmbar),
  🚨 `critical` (anel vermelho pulsando). Respeita prefers-reduced-motion.
- `composables/useCevicoGoals.js` — metas OFICIAIS do mês via
  `goal_plans#show` (mesma fonte do Painel de Metas → selos nunca
  discordam da tela de Metas): valor do mês, meta, ritmo esperado
  (proporcional ao dia), recorde de 12 meses (exige histórico real > 0;
  regras: ≥meta=hit, <65% do ritmo=low, <35%=critical, record vence).

**Onde os selos de meta/recorde entraram** (sempre indicadores oficiais):
- Dashboard CRM → Novas no período (new_leads)
- Dashboard da Agenda → Consultas (appointments_booked), Comparecimento
  (consultations_attended), Cirurgias agendadas/realizadas
  (surgeries_booked/done)
- Dashboard dos Médicos → FAIXA-RESUMO NOVA no topo (consultas realizadas,
  viraram cirurgia, cirurgias realizadas, faturamento c/ meta
  revenue_closed) + FIX: nome do médico não trunca mais p/ "Dr. …" no
  celular (quebra linha)
- Dashboard dos Agentes → faixa do Radar em DashKpi (cores semânticas) +
  fix de truncamento do nome

**Só padronização visual (sem metas):** Dashboard Campanhas (4 KPIs →
DashKpi), Google (card de conversões), Funil de Tráfego + Saúde do
WhatsApp + Anúncios Meta (cabeçalho da família: chip gradiente + título).

Obs.: selo/barra de meta usa SEMPRE o número oficial do mês ("meta do
mês: X de Y"), mesmo com o KPI filtrado em outro período — decisão de
consistência com o Painel de Metas. Local: metas da conta 3 ajustadas p/
demo (appointments_booked=8 → meta batida). Deploy: junto com o item 55.

# ═══ LOTE 57–80 — pedido do Guilherme em 18/07 (📋 A FAZER) ═══

> Registrado na íntegra em 18/07, logo após o merge do PR #1 (itens 55/56).
> Ordem de construção sugerida: refinos rápidos (67, 71, 74, 79, 80) →
> médios (58, 61, 62, 63, 69, 72, 73, 75, 76, 78) → grandes (57, 59, 60,
> 64–66, 68, 70, 77).

## 57. 🧲 CONSTRUTOR — painel personalizado drag-and-drop ✅ CONSTRUÍDO (19/07)
Aba nova "Construtor": montar painel totalmente personalizado com QUALQUER
elemento/indicador já existente no sistema. Drag-and-drop "com ímã"
(snap/grade magnética), espaço já pré-configurado para ficar bonito
(UI/UX), escolha de paleta de cores etc.
COMO FICOU: menu novo "Construtor" (🧲, abaixo de Metas, admin E equipe;
rota /builder). Catálogo com 10 elementos vivos (KPIs de hoje/30d, Metas
do mês, Radar, Tarefas, Próximas consultas, Minha meta de tempo — mesmas
fontes do Meu Painel/Painel de Metas). Grade magnética de 12 colunas:
arrastar reordena com deslize de ímã (TransitionGroup), tamanhos P/M/G
(3/6/12 colunas), 5 paletas (CEVICO/Dourado/Oceano/Verde vivo/Flor del
Mar). Modo "🧲 Personalizar" liga catálogo/remoção/tamanhos; layout salvo
por pessoa neste navegador (cevico_builder_{uid}). Sem migration.

## 58. 🎯 Painel de Metas multi-período ✅ CONSTRUÍDO (19/07, working tree)
Ambientes de metas: do DIA, da SEMANA, do FINAL DE SEMANA, do MÊS, do
TRIMESTRE e do ANO — e metas de INDICADORES (% de conversão, outros).
COMO FICOU: linha de pílulas Dia|Semana|Fim de semana|Mês|Trimestre|Ano no
Painel de Metas, navegação ‹ Atual › por período (+ calendário no mês).
Cada ambiente tem plano próprio (alvos, responsável, "o que é preciso",
marcos, notas) e histórico calibrador: 14 dias / 12 semanas / 12 fins de
semana / 12 meses / 8 trimestres / 5 anos — agregação no fuso de SP.
3 metas de indicadores em %: agendamento (lead→consulta), comparecimento
(agendada→realizada), conversão (consulta→cirurgia) — sempre CALCULADAS
dos mesmos números, nunca digitadas. MÊS segue sendo a fonte oficial dos
selos (useCevicoGoals/Meu Painel/Mentor intocados). Backend: migration
20260719000001 (period_type + índice único novo, ADITIVA), service novo
Crm::GoalPeriodHistoryService, controller multi-período. Rotinas &
ferramentas (globais) só aparecem no ambiente do mês.

## 59. 🏭 DESENHO DO PROCESSO (aba no Estratégico) ✅ CONSTRUÍDO (19/07)
COMO FICOU: aba nova "Desenho do Processo" no Painel Estratégico (dourada,
ao lado de Pilares). A MÁQUINA: etapas em cards numerados conectados por
setas com o PASSE DE BASTÃO escrito em cada elo; clique = ZOOM da etapa
(o que acontece, responsável "quem segura o bastão", o que dispara a
próxima). Admin desenha (criar processos, adicionar/mover/excluir etapas,
salvar); quem tem acesso ao Estratégico vê. A jornada padrão do Guilherme
(agendamento → comparecimento → consulta → indicação ou não → fechamento
ou não) nasce pronta. Dados em agenda_config.process_designs (sem
migration; endpoint POST strategy/save_processes).
Ambiente para DESCREVER cada estágio do processo e montar o plano de forma
visual — "desenhar o processo como uma máquina": etapas, zoom em etapas,
criação de processos, passe de bastão. Ex.: agendamento → comparecimento →
consulta → indicação de cirurgia (ou não) → fechamento (ou não). Para o
time todo ver e entender o processo como o Guilherme entende.

## 60. 🌪️ Montador de Funis — aba própria em Conteúdos ✅ CONSTRUÍDO (19/07)
Selecionar fontes de tráfego E outras fontes de captação (médicos
parceiros, indicação etc.).
COMO FICOU: item novo "Montador de Funis" no submenu Conteúdos (rota
/pages/funis, concessão pages). Cada funil mostra [📥 Fontes de captação]
→ páginas encadeadas (visitas, % de cada elo) → 💬 WhatsApp. Catálogo de
fontes com 5 padrões (Tráfego Meta, Tráfego Google, Orgânico, Médicos
parceiros, Indicação de paciente) + criar fontes novas (ex.: um médico
parceiro específico). Admin escolhe as fontes por funil e reaponta elos
(next_page_id) na mesma tela; páginas soltas viram início de novo caminho.
Dados em agenda_config.funnel_sources/funnel_source_catalog (sem
migration; endpoint POST pages_dashboard/save_funnel_sources).

## 61. 🧠 DISC + 4 Temperamentos — gráficos completos ✅ CONSTRUÍDO (19/07, working tree)
Um gráfico completo para o DISC e outro para os 4 Temperamentos, com opção
de vê-los SOBREPOSTOS ou LADO A LADO.
COMO FICOU: botões em linha "Sobrepostos | Lado a lado" no card "O mapa
dos 4" (aba Perfil do Pessoas; aparecem quando a pessoa tem os 2 testes).
Sobrepostos = radar único comparando (comportamento anterior, com comparar
arquivado). Lado a lado = um gráfico COMPLETO por teste: radar próprio
(DISC azul / Temperamentos rosa) + barras % por dimensão em ordem de
ranking (1º, 2º…) com nome completo (D — Dominância / Sanguíneo…) e
gradiente da dimensão. Sem migration, só TestsTab.vue.

## 62. 🛡️ Acessos — refino por seção + selecionar tudo
Aprofundar o refino: abrir seções (ex. "Relatórios") e escolher QUAIS
relatórios o agente acessa; opção "selecionar tudo" para agilizar. Visual
bonito, mais sério: estilo CEVICO com cores sóbrias de ambiente de
configuração. (Elogio registrado: forma de visualizar atual "ótima".)

## 63. 📢 Radar de Oportunidades — notificação em CARDS EMPILHADOS
Desktop + celular: pilha de cards (não quadros lado a lado). Cards de trás
mostram só nome + tempo sem resposta; o card da frente mostra tudo:
estágio do CRM, etiquetas, último contexto MUITO breve ("quer agendar dia
15", "qual a diferença entre galaxy e trifocal?"), botão convidativo
(manter) + acesso à ficha da pessoa. Ao tocar no botão: mini-prêmio — 3
emojis de ✅ pipocam do ponto do toque.

## 64. 🤖 Agente de AGENDAMENTO interno ("N8N melhorado")
Agenda na agenda interna, faz reagendamento.

## 65. 🤖 Agente de SUPORTE PRÉ-CONSULTA (avaliação)
Responde principais dúvidas, ajuda com reagendamento, fala sobre colírios.

## 66. 🤖 Agente de FECHAMENTO de cirurgia + follow-up longo
Aborda com mensagem modelo; follow-up com mensagens modelo quando
necessário; quando a pessoa responde, segue SCRIPT VALIDADO (Guilherme vai
fornecer — construir com campo/placeholder) e conduz ao fechamento com
elegância. Fechou → agenda cirurgia. Precisa pensar → follow-up modelo em
7, 30, 90, 180, 270 e 360 dias. Objetivo: acompanhamento LONGO do funil.

## 67. 💬 Conversas — limpeza + filtros de jornada
Remover as 3 seleções "Minhas / Não atribuídas / Todos" (nossa seleção é
melhor). Menu lateral de conversas: tirar tudo, deixar só o principal. No
TOPO do Conversas: filtro por estágio da jornada (coluna do CRM) e por
etiquetas.

## 68. 📦 Financeiro — ESTOQUE + gráficos em verde ✅ CONSTRUÍDO (19/07, noite 3)
Ambiente de estoque com dashboard próprio: custo, potencial de lucro, e
CONSULTA AUTOMÁTICA quando solicitado — ex.: indicação de lente trifocal
config. xyz já consulta o estoque → tem? agenda cirurgia p/ data próxima;
não tem? encomendar e abrir PEDIDO vinculado ao card do paciente (motivo).
+ Atualizar cor dos gráficos do Financeiro: VERDE como cor principal.
COMO FICOU: aba ESTOQUE dentro do Financeiro (4ª aba) com KPIs (unidades,
custo parado, potencial de lucro — itens sem preço de venda ficam de fora
—, pedidos abertos), alerta âmbar de estoque mínimo, catálogo com CRUD
(categoria, config, qtd/qtd mínima, custo, preço, fornecedor) e PEDIDOS
com fluxo pendente → encomendado → recebido (recebido SOMA a quantidade
no estoque) / cancelado + chip do paciente que abre o Espaço dele.
CONSULTA AUTOMÁTICA no Espaço do Paciente: marcou "⭐ Saiu com indicação"
e escolheu a lente → lookup em 400ms: TEM (caixa verde "Em estoque: … N
un." + botão 📅 Agendar cirurgia → Agenda) ou NÃO TEM (caixa âmbar +
🛒 Encomendar para este paciente → pedido com motivo "Indicação: … —
paciente Fulano", task_id da consulta ligada + contact_id). Acessos:
dashboard/CRUD = concessão finance; lookup/criar pedido = time logado
(lookup NÃO expõe custo nem preço). Migration ADITIVA 20260719000005
(cevico_stock_items + cevico_stock_orders). Gráficos do Financeiro:
paleta dos donuts liderada por verdes e Receita virou a linha
protagonista (verde, mais grossa) no histórico de 12 meses.
Testado no Docker: rails runner (custo/lucro/low_stock/lookup/receber
soma) + HTTP (admin 200; atendente lookup/pedido 200, dashboard/CRUD
403) + visual (aba, alerta, Recebi ✓, consulta verde/âmbar no paciente).

## 69. 📣 Campanha de WhatsApp — repaginada ✅ CONSTRUÍDO (19/07)
Organizar ambiente, cores, botões; fluidez das seleções do "Nova
campanha". Clarear "o que conta como conversão": ex. explícito "conversão
desta campanha = lead sair de 'Orçamento enviado' → 'Consulta agendada'".
COMO FICOU: header c/ medalhão verde WhatsApp + abas dopamine (Campanhas
verde/Automações roxa/Painel azul) + botões gradiente; composer com PASSOS
numerados (1 A mensagem azul · 2 O público roxo · 3 Conversão verde);
seção de conversão ganhou a FRASE POR EXTENSO montada ao vivo das seleções
("Conversão desta campanha = o lead ENTRAR na coluna X…") e, vazia, mostra
o exemplo explícito do Orçamento enviado → Consulta agendada.

## 70. 🧹 Automações = Tratamento de dados unificado ✅ CONSTRUÍDO (19/07, noite 3)
Ambiente com TODAS as ferramentas para tratar o banco contextualizado ao
sistema — identificação tradicional + IA. Aprimorar ambiente e painel.
+ Ajustar layout/design de TODAS as abas dentro de Automações.
COMO FICOU: as 6 ferramentas saíram da Campanha WhatsApp e viraram o
componente compartilhado DataTreatmentTools.vue, montado DENTRO de
Automações → Tratamento de dados (funcionam ali mesmo, sem pular de
tela). Duas seções: IDENTIFICAÇÃO TRADICIONAL (etiquetar/mover por
conteúdo ouro, lote azul, substituir roxa, remover vermelha, unificar
teal — cada uma com medalhão de cor própria, prévia antes de aplicar) e
IDENTIFICAÇÃO COM INTELIGÊNCIA (valores pelo orçamento verde) + 2 cards
só-admin que abrem os modais já existentes (Radar pontual, Preencher a
Agenda com o histórico). Layout das abas: header com medalhão workflow
roxo + TODAS as abas com pílula colorida própria (Robôs azul, Regras
ciano, Agentes roxa, Programação âmbar, Resultados verde-lima,
Tratamento teal) com ícone lucide. Na Campanha WhatsApp, a aba
Automações ficou SÓ com as réguas + card-aviso "mudaram de casa" que
leva direto ao hub. Sem migration. Testado no Docker: tela unificada
renderiza, prévia de unificação roda da nova casa (0 duplicados ✓),
card-aviso navega certo, aba Robôs intacta.

## 71. 🎬 Conteúdos/Planejamento — FIX criar peça + comemorações
BUG: não é possível criar peça nova em NENHUMA coluna — corrigir.
Animação de comemoração PROGRESSIVA ao mover: Copy → algo de "foco,
ideias"; Em produção → corações; Publicado → CHUVA DE FOGUETES.

## 72. 📄 Análise de Páginas — reorganizar ✅ CONSTRUÍDO (19/07)
Visualização pré-configurada por CATEGORIA de página (captação,
pré-consulta, pré-cirurgia, pós-operatório); lugar para seleção de
PALAVRAS-CHAVE; analisar performance com indicadores chave, espaços bem
aproveitados, respiros, cores — estilo CEVICO. (Elogio: "ficou muito bom".)
COMO FICOU: pílulas de categoria no topo (cores/ícones da jornada; escolher
uma pré-seleciona a página mais visitada da categoria); PALAVRAS-CHAVE
novas por página (campo no bloco SEO do editor, migration ADITIVA
20260719000002 cevico_pages.seo_keywords, entra na meta keywords pública)
viram chips com contagem que FILTRAM a lista; página escolhida ganhou
selo da categoria + chips 🔑 + 4 KPIs dopamine (Visitas 30d azul, Cliques
roxo, Taxa dourado, Leram até o fim verde).

## 73. 📝 Formulários — hub inicial + retenção/abandono ✅ CONSTRUÍDO (19/07)
Sessão inicial: formulários construídos + dados gerais envio × respostas +
% conversão de respostas por envio, POR formulário. Clique no formulário →
dashboard organizado e visual. Se possível: gráfico de ABANDONO (retenção)
por card do formulário, com %.
FIX: na explosão de transição p/ o último card, a margem da "aura de
átomos" aparece e fica estranho → aparição do card CEVICO fluída e
agradável, apenas transição ok.
COMO FICOU: hub inicial = card por formulário c/ envios × respostas × %
conversão + mini-gráfico de retenção + % de abandono; dashboard do form
ganhou "Retenção card a card" completo (barras verde/laranja/vermelho por
% que chegou em cada card, aberturas × concluíram). Dados novos: migration
ADITIVA 20260719000003 (crm_forms.sent_count + funnel_stats), envio
contado no send_form do job, aberto/concluído contados no controller
público, beacon 1x por card no JS público (sendBeacon → POST /track,
incremento atômico jsonb_set). FIX da aura: partículas agora se DISSOLVEM
perto das bordas do canvas (fade por distância) em vez de cortar na linha
reta — some a "margem" no surge. Testado por HTTP (200/204 + contadores).

## 74. ✅ Tarefas — ajustes dopamine
Ajustar a dopamine color do painel. Donut de tarefas: aura dourada MAIS
espalhada e REMOVER o glow do donut.

## 75. 📅 Agenda de cirurgias — temas + barra de navegação ✅ CONSTRUÍDO (19/07)
Tema padrão do gradiente: "cor dopamine → cor esbranquiçada". Escolha de
tema vira POPUP que salta na tela; botão do tema em lugar independente, ao
lado ESQUERDO do calendário. Linha de visualização: mês | semana | dia |
personalizado (com o calendário). "HOJE" ao lado esquerdo da seleção de
dias, com "+dia / −dia" ao redor, e mostrando junto o dia/mês/ano.
COMO FICOU: gradiente padrão já era dopamine→branco (pedido 18/07 no
DEFAULT_THEME); tema agora é POPUP central c/ animação "salta na tela"
(cards de gradiente 2 colunas, ring no ativo) e o botão 🎨 mudou p/ o
lado ESQUERDO do bloco do calendário; navegação nova: [🎨] [−dia]
[Hoje · dd/mm/aaaa] [+dia] | [‹ período ▾ ›]; linha de visões ganhou
"Personalizado" que abre o calendário arredondado (pílula acende enquanto
aberto). Vale p/ Consultas E Cirurgias (mesma tela).

## 76. 👨‍⚕️ Agenda dos médicos — controle + layout ✅ CONSTRUÍDO (19/07)
COMO FICOU: (1) modal Janelas → cada médico tem "⏸ Fechar agenda /
▶️ Reabrir" (salvo em agenda_config.closed_doctors; resolveWindows filtra
em TODO lugar — agenda, ocupação, saúde; personalizar dias/horários segue
no Editar); (2) linha "Ver:" com botões em linha — Toda a clínica +
médicos (cores) no trilho de consultas, Todos os locais + clínicas no de
cirurgias; (3) semana 08h–18h espichada (célula 48→64px) + toggle
"Esconder sáb/dom" (localStorage); (4) dia mais estreito (max-w-3xl) e
mais alto (88→112px/h); (5) lista do dia com 🏷 etiquetas do paciente +
botão "📖 Ler respostas do formulário" (modal roxo; endpoint novo GET
tasks/agenda_details c/ etiquetas + última resposta por consulta);
(6) conferência com cards mais respirados (borda 1px, raio maior,
espaçamento 2.5). Testado no Docker ponta a ponta (fechar/reabrir médico
persistiu e restaurou; modal de respostas abriu).
- Janela dos médicos, ao lado de "editar": FECHAR a agenda do médico, ou
  abrir em dias/horários personalizáveis.
- Agenda (consulta E cirurgia): seleção "pré-configurada em linha" para
  mostrar só "agenda do médico" ou "cirurgia aqui ou ali".
- Visualização semanal: toggle "remover sábado e domingo" (limpa e
  aproveita espaço). Horários das 08 às 18. "Espichar" verticalmente.
- Agenda do DIA dos médicos (elogiada): reduzir horizontalmente e aumentar
  verticalmente os horários, bem ajustada ponta a ponta, com respiros.
- Lista abaixo: + etiqueta da paciente e, se respondeu formulário, botão
  para o médico LER as respostas antes da consulta.
- "Conferência das Consultas do dia" (excelente): só espaçamento/layout
  mais claro e menos poluído.

## 77. 🎓 Academia CEVICO — temas novos + ambiente Ferramentas ✅ CONSTRUÍDO (19/07, noite 3)
Atualizar assuntos com temas para corrigir gargalos do funil/jornada do
paciente. Criar ambiente "Ferramentas": Guilherme cria ferramentas em
texto bonito para o time.
COMO FICOU: Academia ganhou 2 abas (Trilhas azul / Ferramentas ouro c/
contador). TRILHAS: nova 1ª seção "Gargalos da jornada — onde o lead
trava (e como destravar)" com 5 temas-gargalo (Lead novo que não
responde, Orçamento que esfria, No-show, Indicação sem fechamento,
Pós-op sem indicação), cada um com cor/ícone próprios; seções antigas
mantidas. FERRAMENTAS: admin escreve com marcação leve (# título,
## subtítulo, - lista, 1. passos, > citação, **negrito**, --- divisor)
num editor com PRÉVIA ao vivo lado a lado; time lê em página bonita
(modal com faixa navy+ouro, título serifado, subtítulos ouro, bullets
com ponto dourado) — renderização SEGURA por blocos, sem v-html.
Rascunho (não publicada) só o admin vê; agrupamento por categoria.
Migration ADITIVA 20260719000006 (cevico_tools) + TeamToolsController
(index aberto ao time logado; escrever = só admin). Testado no Docker:
HTTP (admin CRUD 200; atendente vê só publicadas, criar = 403) +
visual (abas, gargalos, card, leitura formatada).
Dados de teste conta 3: ferramentas "Script de confirmação de véspera"
e "Rascunho secreto".

## 78. ⚙️ Integrações unificadas dentro de Configurações ✅ CONSTRUÍDO (19/07)
Unificar as abas de "Integrações" e movê-las para Configurações.
COMO FICOU: a central única (CEVICO: n8n/Meta/Google/Claude/Gemini/Sheets
+ Aplicativos do sistema) virou o 1º item DENTRO de Configurações; o item
de topo saiu do menu e a entrada nativa duplicada ("Integrations" →
settings_applications) foi removida — tudo em /crm/integrations, mesma
concessão de acesso (settings).

## 79. 🏠 Meu Painel — lógica de cores de meta UNIVERSAL
Cores de abaixo/dentro/acima da meta valendo para TODOS os ambientes
("agendamento — Vaneide", "condução — Elizangela" etc.).
FIX de dado: corrigir nome "Elizangela" com Z (conferir se é cadastro).

## 80. 📇 CRM — período personalizado + dashboard alinhado
Linha "Hoje, Ontem, …": adicionar "Personalizado" à direita, abrindo o
calendário bonito e arredondado já criado. Dashboard CRM: alinhar os dados
para caberem perfeitamente no espaço; relacionar indicadores com a meta
(como já feito em "novas no período").

## 81. 🪞 Pessoas — AUTOCONHECIMENTO do colaborador ✅ CONSTRUÍDO (19/07, noite 3)
Quem preenche DISC/Temperamentos passa a VER as próprias respostas e a
análise do seu perfil (objetivo: autoconhecimento e desenvolvimento da
equipe). Painel de GESTÃO disso para o Guilherme + cada pessoa pode
refazer a avaliação 1x a cada 3 meses (trava de 90 dias).
COMO FICOU: o runner agora grava as RESPOSTAS pergunta a pergunta
(q + escolha + dimensão; escala vira "N/10") dentro do assessment
(jsonb, sem migration). No arquivo de testes, botão "ver respostas"
(própria pessoa + admin) abre modal com a ANÁLISE do teste (perfil
dominante + headline + ranking com %) e a lista das respostas com selo
colorido da dimensão. TRAVA DE 90 DIAS: backend recusa (422 com a data
de liberação) refazer o mesmo tipo antes de 3 meses — admin bypassa;
no front o botão vira "🔒 Refazer libera em DD/MM/AA". GESTÃO (admin):
card sanfona "Gestão dos testes do time" no topo do Pessoas — por
pessoa: DISC e Temperamentos com dominante colorido, data, 🔒 refaz
DD/MM/AA ou ✅ pode refazer, nº de respostas; clique no nome abre o
espaço da pessoa. Testado no Docker: HTTP (atendente grava 2 respostas,
2ª tentativa 422 "libera em 17/10/2026", admin 2× 200, payload com
answers) + visual (painel de gestão + modal de respostas).
Dados de teste conta 3: assessments de temperamentos do Atendente
Teste e do Guilherme (2 respostas cada).

# ═══ 🚀 SUBIDA DO LOTE — 20/07 ~02h (STATUS AO FECHAR A SESSÃO) ═══
- Commit 028cf2d49 (92 arquivos) → PR #3 → mergeado na develop
  (16a589d99) → **BUILD #59 VERDE** (houve partial_outage do GitHub
  Actions no meio — ~1h de fila — resolveu sozinho).
- **BACKUP FEITO E VERIFICADO**: /root/backup_cevico_antes_deploy_
  20260720_0221.sql.gz na VPS — 42M, gzip íntegro, 114 tabelas, banco
  chatwoot_migrado c/ contacts/conversations/crm_pipelines/tasks.
  ⚠️ LIÇÃO: o $POSTGRES_DB do container aponta pro banco 'postgres'
  (vazio) — backup SEMPRE com `-d chatwoot_migrado` explícito.
- **FALTA SÓ O BOTÃO**: Implantar web → Implantar sidekiq no EasyPanel
  (7 migrations aditivas rodam sozinhas no web). Reversão: imagem
  anterior no histórico, banco intacto.
- PÓS-DEPLOY (ordem): conferência rápida → religar 1 robô de follow-up
  olhando o registro (trava_* = proteção ok) → 🛡️ ACESSOS DAS
  ATENDENTES ANTES DA CLÍNICA ABRIR (concessões nascem vazias!) →
  💰 tabela de preços → 🎯 metas de julho → 📣 fixar colunas de
  conversão dos Anúncios (número vai cair — é o default honesto) →
  dry-run cevico:fix_imported_dates[1] → médicos no 🛡️ clínico.

# ═══ ONDE PARAMOS — 19/07 (noite 3 — blocos grandes) ═══
- 🎨 RODADA PRÉ-DEPLOY (teste visual do Guilherme, 6 ajustes, tudo
  testado no Docker): (1) INTEGRAÇÃO OFTALMOFÁCIL nativa na central de
  Integrações — card teal + modal (URL base + chave protegida, nunca
  volta pra tela; agenda_config.oftalmofacil, endpoint
  update_oftalmofacil só admin/settings; fluxo de dados liga quando a
  documentação da API chegar); (2) fonte do ambiente do PACIENTE:
  BRANCA em todos os temas — tinta escura ficou SÓ nos clarinhos de
  verdade (azul jovem + rosa jovem); o VERDE passou a fonte branca
  (decisão: era o que o print pedia; 1 linha p/ reverter se quiser
  verde-preto); (3) FINANCEIRO dopamine colors — KPIs em degradê pleno
  c/ fonte branca e ícone marca-d'água (verde/vermelho/âmbar/ouro/azul/
  roxo/teal, negativos viram vermelho); (4) CONVERSAS enquadrado (calha
  única px-3 nas pílulas/filtros) + ORDENAÇÃO visível "Da mais recente
  para a mais antiga" ↔ inversa (trio nativo completo:
  setChatSortFilter + uiSettings + refetch — provado invertendo a
  lista); (5) CONSTRUTOR: catálogo COMPLETO em 4 seções (5 indicadores
  de agora + 11 do dia via painel gestor [taxa de agendamento,
  comparecimento, fechamento pós-indicação, NPS…] + 5 blocos vivos +
  13 ATALHOS DE DASHBOARDS que navegam) + PREDEFINIÇÕES nomeadas
  (salvar/aplicar/excluir, localStorage por pessoa); (6) FORMULÁRIOS:
  dashboard enquadrado em max-w-5xl centrado, cards das perguntas mais
  estreitos c/ min-height (leitura equilibrada). Dados de teste:
  conexão OftalmoFácil salva na conta 3 + predefinição "Manhã de
  segunda". VÍDEOS 92-94 adiados por decisão; kit CEVICO virou
  convenção (nota antes da Rodada 3).
- 🔍 AUDITORIA DOS 6 BLOCOS feita NA MESMA SESSÃO (relatório
  AUDITORIA_BLOCOS_2026-07-19.md na raiz): 11 achados (2🔴 provados no
  Estoque — duplicação no ciclo de status + escrita cross-account — 5🟡
  4⚪) e TODOS CORRIGIDOS após o "corrige tudo" do Guilherme, com
  re-teste completo (transições finais + with_lock, item validado na
  conta, PATCH parcial das Ferramentas preservando campos, pedido da
  indicação vinculado ao catálogo, confirm antes de sair da anotação,
  N+1 dos pedidos em lote, alerta de mínimo só com min>0, sparkline no
  fuso SP, trava 90d enxerga DISC legado, save_assessment sob trava).
  A1 = pós-deploy: avisar que as conversões de Anúncios podem CAIR (o
  default parou de contar "Indicação") e fixar as colunas oficiais no
  seletor. Convenção nova registrada: REUSAR O KIT CEVICO em toda tela
  nova (ver nota antes da Rodada 3); vídeos 92–94 adiados.
- CONSTRUÍDOS NESTA SESSÃO (working tree, todos testados no Docker):
  itens 68 (Estoque no Financeiro + gráficos verdes + consulta automática
  na indicação do Espaço do Paciente), 70 (Tratamento de dados UNIFICADO
  em Automações + abas coloridas do hub; Campanha WhatsApp ficou só com
  réguas + card-aviso), 77 (Academia: gargalos da jornada + ambiente
  FERRAMENTAS com editor/prévia e leitura bonita), 81 (autoconhecimento:
  respostas gravadas + modal de leitura + trava 90 dias + gestão dos
  testes p/ admin), 85 (Painel dos agentes de IA em Automações, fonte
  crm_ai_usages) e 87 (Anúncios Meta repaginado + default de conversão
  sem "indicação").
- MIGRATIONS NOVAS (aditivas): 20260719000005 (cevico_stock_items +
  cevico_stock_orders) e 20260719000006 (cevico_tools). Backup antes do
  deploy, como sempre.
- LIÇÃO NOVA: pluck com múltiplos agregados SEM ALIAS (3× SUM) gera
  colunas homônimas "sum" e o cast mistura os tipos (decimal virava 0) —
  sempre dar alias distinto em cada agregado.
- FALTAM dos grandes: 64-66 (aguardam script validado do Guilherme) e
  92-94 (vídeo — aguardam decisão de infra VPS × Bunny/Mux).
- DADOS DE TESTE desta sessão (conta 3, podem limpar): itens/pedidos de
  estoque, ferramentas "Script de confirmação de véspera" e "Rascunho
  secreto", assessments de temperamentos (Atendente Teste + Guilherme),
  50 registros semeados em crm_ai_usages.

# ═══ ONDE PARAMOS — 19/07 (noite 2 — sessão de aceleração) ═══
- CONSTRUÍDOS HOJE (working tree, todos testados no Docker): itens 57, 58,
  59, 60, 61, 69, 72, 73, 75, 76, 78, 83, 86, 88, 95 + teste dos
  Temperamentos c/ 24 perguntas + CHECK ✓ nos avisos do Meu Painel
  (feedback/Radar/tarefas/WhatsApp).
- MIGRATIONS NOVAS DA SESSÃO (todas aditivas): 20260719000001 (period_type
  em cevico_goal_plans), 20260719000002 (seo_keywords em cevico_pages),
  20260719000003 (sent_count + funnel_stats em crm_forms), 20260719000004
  (archived_at em tasks + cevico_content_items).
- AINDA A FAZER dos grandes: 68 (Estoque), 70 (Automações unificadas), 77
  (Academia + Ferramentas), 81 (Autoconhecimento), 85 (Dashboard dos
  agentes IA), 87 (Anúncios Meta repaginar) — cada um é um ambiente
  inteiro, próximas sessões; 64-66 aguardam o script validado; 92-94
  (vídeo: editor IA/player/hospedagem) PRECISAM DE DECISÃO do Guilherme
  (custo de armazenamento/transcodificação ou serviço externo tipo
  Bunny/Mux — não dá pra construir sem escolher o caminho).
- Dados de teste locais desta sessão (conta 3, podem limpar): metas
  semanais/diárias, keywords "catarata", funnel_stats do form, task 35,
  attended_log simulado, tarefas arquivadas.

# ═══ ONDE PARAMOS — 19/07 (noite) ═══
- HOTFIX do follow-up (item 91): commit 42bba6ac1 → PR #2 MERGEADO na
  develop (695b6517f) → build 58 VERDE. ⏳ DEPLOY PENDENTE (backup → web →
  sidekiq → religar robôs olhando o registro de atividade). Robôs DESLIGADOS
  até lá. Esse deploy carrega o lote 55/56 aprovado (1 migration aditiva).
- WORKING TREE (não commitado, testado no Docker local): itens 62, 63, 67,
  71+refinos, 74, 79, 80, 82, 84, 89 (skeleton em 17 telas), 90 + Meu
  Painel (strip abaixo da agenda, Metas do mês roxa) + CRM sem "Filtros"
  (pílulas Responsável/Etiqueta + ferramentas dopamine) + rake
  cevico:fix_imported_dates (datas do lote importado — item da rodada 19/07).
- ITEM 58 CONSTRUÍDO 19/07 (working tree): Metas multi-período + % —
  migration nova 20260719000001 (aditiva; period_type em cevico_goal_plans).
  Testado no Docker (6 períodos + save semanal + Meu Painel intacto).
- ITEM 61 CONSTRUÍDO 19/07 (working tree): DISC + Temperamentos com
  Sobrepostos | Lado a lado no Pessoas (sem migration).
- RODADA 19/07 tarde (pedidos novos, construídos): teste dos 4
  TEMPERAMENTOS ampliado p/ 24 perguntas equilibradas (1 opção por
  temperamento em cada; validador rodado) + CHECK ✓ nos avisos do Meu
  Painel (feedback da semana, Radar, tarefas esperando): a janelinha some
  e VOLTA quando há novidade (assinatura por conteúdo: outra semana/outros
  pacientes/outras tarefas; localStorage por pessoa).
- PRÓXIMO DA FILA: médios (69, 72, 73, 75, 76, 78, 86, 88) → grandes (57,
  59, 60, 64-66, 68, 70, 77, 81, 83, 85, 87, 92-95).
- Pós-deploy c/ Guilherme: dry-run cevico:fix_imported_dates[1] na produção
  (mostra distribuição por mês; APPLY=1 depois de conferir) + 🛡️ acessos +
  💰 tabela de preços + 🎯 metas de julho.
- Husky quebrado nesta máquina (npx fora do PATH) → commits com --no-verify.

# ═══ 🚨 ITEM 91 — INCIDENTE do follow-up (18-19/07) + TRAVAS ═══

**O que houve:** robô de follow-up enviou DEZENAS de mensagens idênticas
aos mesmos pacientes, de 2 em 2 min (giro do cron), em produção.
**Causa raiz:** o marcador de "já enviei" vive em additional_attributes da
conversa; escritores CONCORRENTES gravavam esse JSON com padrão
lê→altera→grava SEM trava e apagavam o marcador (pior: o ai_insight do
crm_automation_fire_job, que segura o objeto por segundos durante a
chamada de IA e grava snapshot velho). Sem marcador, cada rodada reenviava.
**Correção (3 camadas, à prova de qualquer causa):**
1. TRAVA FÍSICA no job: fonte da verdade = tabela de MENSAGENS (cutucadas
   carregam cevico_followup_bot_id). Piso de 30 min entre cutucadas por
   conversa, teto = nº de etapas por âncora, teto diário de 4 — valem
   mesmo com marcador apagado. Motivos novos no registro de atividade:
   trava_intervalo_minimo / trava_cadencia_completa / trava_teto_diario.
2. Marcar ANTES de enviar (falha segura: perde 1 cutucada, nunca duplica).
3. TODOS os 6 escritores diretos de additional_attributes convertidos para
   Cevico::AttributeMerge.merge! (ai_insight ×2, atribuição de anúncios,
   perfil do paciente, webhook Instagram, sync WhatsApp) — também protege
   a PAUSA por paciente, que podia ser apagada do mesmo jeito.
**Prova:** tmp/test_followup_guard.rb reproduz o incidente (apaga o
marcador 5× e roda o job) — com o fix, permanece 1 única mensagem.
**Plano de subida:** hotfix a partir de f6605d379 (leva junto o lote 55/56
já aprovado — 1 migration aditiva → backup antes); robôs DESLIGADOS até o
deploy; religar depois e acompanhar o registro de atividade.

# ═══ RODADA 2 do lote — pedidos 18/07 (manhã) ═══

## 82. 🖥️ CRM — modo TELA CHEIA (desktop)
Botão para o board ocupar TODA a janela do navegador: só a linha de
filtros pré-selecionados + colunas/cards. Conforto pro trabalho do dia a
dia (não precisa ser fullscreen do navegador, é ocupar a janela toda).

## 83. 📡 Radar — indicador de EFICÁCIA (conversões pós-notificação) ✅ CONSTRUÍDO (19/07)
O widget do Radar deve mostrar as CONVERSÕES GERADAS após o aviso do
agente: quantas consultas a mais estamos agendando por causa dele
(atribuição: lead avisado → agendou depois do aviso).
COMO FICOU: selo verde "📈 N consulta(s) geradas · X%" no cabeçalho do
widget do Radar no Meu Painel. Atribuição: dos avisos ATENDIDOS nos
últimos 30 dias (attended_log do item 63), conta os pacientes cuja
consulta foi CRIADA depois do toque em "Atender agora" (janela de 14
dias). Cálculo no crm/home (payload efficacy), validado no Docker
(cenário 2 atendidos → 1 conversão = 50%).

## 84. 📊 Funil de Tráfego — barras SIMÉTRICAS + Personalizado
É o nosso funil mais completo, mas as barras não estão boas: centralizar
(simétricas, como texto centralizado), diferenciar queda × ganho, suavizar
o preenchimento (bonito como a barra de progresso do formulário).
+ Na linha de período: adicionar "Personalizado".

## 85. 🤖 Dashboard dos AGENTES DE IA ✅ CONSTRUÍDO (19/07, noite 3)
Novo dashboard: o que os agentes (Secretário, Analista, Radar, Copywriter,
Atendente…) estão fazendo + principais indicadores de cada um.
COMO FICOU: aba nova "Painel dos agentes" (rosa, só admin) dentro de
Automações + item no submenu lateral. Período Hoje/7d/30d; 4 KPIs
(trabalhos, custo US$ estimado por tokens, agentes ligados X/12, mais
ativo) + um CARD POR AGENTE (12): medalhão colorido, o-que-faz em uma
linha, selo ligado/desligado (interruptor definitivo), selo "fala c/
paciente" nos respondedores, nº de trabalhos, custo, mini-gráfico de
barras do ritmo diário (14 dias), modelo em uso (mesma resolução do
runtime: agente > recomendado > global) e "última atividade: há Xh /
nunca rodou". Ordenado: ligados primeiro, mais ativos no topo. Fonte:
crm_ai_usages (1 linha por chamada) + ai_config do crm_settings. Extras:
feedbacks do Mentor 30d. Endpoint novo ai_dashboard (só admin), sem
migration. FIX importante no caminho: pluck com 3 SUMs SEM ALIAS gera
colunas homônimas "sum" e o cast mistura os tipos (custo virava 0) →
aliases distintos resolvem. LIÇÃO p/ o repo: sempre dar alias em
múltiplos agregados no pluck. Testado no Docker: endpoint (custos
corretos por agente após o fix) + visual (KPIs, cards, sparkline,
"nunca rodou"). Dados de teste conta 3: 50 crm_ai_usages semeados.

## 86. 📅 Dashboard da Agenda — atalho em todos os painéis + equipe ✅ CONSTRUÍDO (19/07)
Atalho para o Dashboard da Agenda em TODOS os painéis do Meu Painel;
liberar esse dashboard para a equipe (não só admin).
COMO FICOU: botão azul "Dashboard da Agenda" fixo na linha do seletor de
painéis (aparece em todos, p/ todos); backend perdeu a exigência da
capability reports (dado operacional, sem valores financeiros) — qualquer
pessoa logada da conta acessa.

## 87. 📣 Anúncios (Meta) — repaginar ✅ CONSTRUÍDO (19/07, noite 3)
Ambiente importantíssimo, ainda cru: conversões não representam a
realidade, layout desalinhado do nosso padrão. Atualizar forma de exibir,
clareza da conversão e visual.
COMO FICOU: (1) CONVERSÃO MAIS FIEL — o padrão de colunas de conversão
agora EXCLUI as etapas de indicação ("%cirurgia%" sem "%indica%";
indicação ainda não é venda e inflava o número; se a conta só tiver
colunas com "indica", cai no padrão antigo; config manual continua
valendo). (2) CLAREZA — frase POR EXTENSO estilo item 69, montada ao
vivo das colunas escolhidas: "Conversão deste painel = o card do lead
PASSAR pela coluna 'X' ou 'Y' — vale para leads que CHEGARAM pelo
anúncio no período, mesmo que a cirurgia feche depois", com o seletor
de colunas dopamine logo abaixo (chips verdes) e aviso "indicação ainda
não é venda" no picker. (3) VISUAL padrão CEVICO — hero azul Meta com
períodos embutidos, 6 KPIs com medalhão colorido (Investimento azul,
Leads roxo, CPL ciano, Conversões verde, CAC âmbar, Receita ouro), card
ROAS com cor pelo resultado (≥2× verde / ≥1× ouro / <1× vermelho) e
frase "cada R$ 1 investido virou R$ X", card 🏆 CAMPEÃO DO PERÍODO,
tabela com medalhas 🥇🥈🥉 no top 3, pílula de ROAS colorida por linha e
skeleton no carregamento. Sem migration, endpoints mantidos. Testado no
Docker: visual completo com o lead/conversão real da conta 3 (campeão
"Cirurgia refrativa", R$ 5.000) e frase provando o novo default (só
Cirurgia Agendada/Realizada, sem Indicação).

## 88. 💬 Status do WhatsApp no painel do GESTOR ✅ CONSTRUÍDO (19/07)
Painel do admin/gestor com avisos SE os números de WhatsApp estão ok ou
não — sempre evidente. Avisos podem ser marcados com ✓ (limpar a tela).
COMO FICOU: card no topo do Meu Painel (só admin) listando cada número
WhatsApp Cloud: ✅ funcionando / 🔴 precisa reautorizar / ⚠️ N falhas de
envio em 24h (mensagens outgoing status failed); verde quando tudo ok,
vermelho quando não; ✓ usa o mecanismo de check novo (some e VOLTA sozinho
quando o estado de qualquer número muda). Payload whatsapp_status no
crm/home (nil p/ atendente e p/ conta sem WhatsApp — local não renderiza,
produção sim).

## 89. 💀⚡ SKELETON "armadura do Homem de Ferro"
Carregamento progressivo (skeleton) em vez de tela branca — vai montando
o ambiente de forma inteligente e agradável. Começar por Meu Painel e CRM.

## 90. 💬🎨 Conversas — balão de estágio/etiquetas + cor da caixa
Na lista de conversas: mostrar etiquetas e a coluna da jornada; abrir em
BALÃOZINHO (como o popover de estágio dentro da conversa). Cor do TEXTO
da conversa = cor principal da caixa de entrada (indicador vivo, cor
sólida dopamine, sem gradiente).

## Refinos da rodada 2 sobre itens já construídos
- **71 (Planejamento)**: animação do PUBLICADO baseada na das Tarefas,
  verde: explosão SAI DO CARD na troca de coluna; atrás de um emoji da
  explosão a COLUNA se energiza — aura de elétrons circula em sentido
  HORÁRIO e, ao completar o círculo, a coluna acende verde pulsando.
  Mover card entre colunas inspirado no movimento do card do CRM.
- **74 (Tarefas)**: aura do donut MAIS VOLUMOSA, um pouco mais densa.

# ═══ RODADA 3 — pedidos 19/07 ═══

> 🧰 **CONVENÇÃO DE CONSTRUÇÃO (decisão do Guilherme, 19/07): REUSAR O
> KIT CEVICO.** Toda tela nova nasce das peças que já existem — DashKpi,
> TileAura, skeleton, board estilo CRM, abas em pílulas coloridas,
> KPI-cards com medalhão, frase de conversão POR EXTENSO, botões em
> linha, prévia antes de aplicar, modal de leitura serif+ouro. Inventar
> componente novo só quando o kit não resolve.

> ⏸️ **VÍDEO (92–94) ADIADO por decisão do Guilherme em 19/07** — retomar
> mais pra frente, quando ele decidir o caminho de infra (VPS × Bunny/Mux).

## 92. 🎬 Editor de vídeo por IA
Dentro do sistema: adicionamos referências e orientações, ele edita o
vídeo pra nós.

## 93. ▶️ Player de vídeo próprio + "delay" nas páginas
Player estilo Russell Brunson para o site. Delay de conteúdo: vídeo na
página e, após X minutos (parte certa do vídeo), a página "abre novas
informações" (oferta etc.).

## 94. 📦 Hospedagem de conteúdos próprios
Hospedar nossos vídeos/conteúdos através do sistema.

## 95. ✅ Tarefas/Conteúdos — renovar ambiente após 100% ✅ CONSTRUÍDO (19/07)
5 min após concluir todas as tarefas (e no Planejamento também): mover os
cards para uma COLUNA OCULTA e renovar o ambiente (tela limpa pro próximo
ciclo).
COMO FICOU: migration ADITIVA 20260719000004 (archived_at em tasks E
cevico_content_items = a coluna oculta; os index dos dois boards excluem
arquivados). Tarefas: no 100% aparece o chip "🧹 tela nova em 5:00"
(contagem ao vivo) + botão "Renovar agora"; entrou tarefa nova no meio →
cancela sozinho; renovação arquiva SÓ cards do board (consultas/cirurgias
da Agenda nunca entram). Planejamento: mesmo ciclo quando TODAS as peças
estão em Publicado (chip verde no header). Endpoints POST
tasks/archive_done e content_items/archive_published. Testado no Docker:
5 tarefas arquivadas, board renasceu limpo, 14 consultas preservadas.

## Atualização do item 63 (Radar)
Formato CARROSSEL pulsante (estilo Tarefas 100%). Botão "Atender agora":
-1 na contagem, remove o card, passa para o próximo, até zerar.

## 96. ✅ Balão da conversa DIRETO do card do Radar ✅ CONSTRUÍDO (20/07, não commitado)
Pedido do Guilherme: o card do Radar de Oportunidades ter o ícone de
"abrir conversa" e abrir o BALÃO (o mesmo do CRM) — a pessoa resolve dali
mesmo, sem nem ir até Conversas.
COMO FICOU (kit CEVICO, reusando o ConversationChatModal do CRM):
- Card do Radar no Meu Painel ganhou o ícone 💬 (message-circle-more azul)
  ao lado do medalhão do Espaço do Paciente — mesmo rodapé do card do CRM.
- Ícone, clique no corpo do card E "Atender agora" abrem o BALÃO por cima
  do Meu Painel (antes navegava pra tela de Conversas). "Atender agora"
  mantém os ✅ e o -1.
- Responder ou Resolver PELO balão também dá o -1 na fila e registra no
  attended_log (eficácia do item 83 continua contando; se abrir pelo ícone
  e só olhar, o aviso fica).
- Backend: home_controller#with_conversation_info enriquece os avisos na
  LEITURA (1 consulta em lote) com inbox_id/inbox_name/channel_type/status
  — o balão mostra a caixa e o botão de templates funciona; vale até para
  avisos antigos já salvos no estado.
Sem migration. Testado no Docker (conta 3): balão abriu com "Teste Local ·
Nº1" e 30 mensagens, resposta saiu, card sumiu da fila, attended_log
registrou; caminho do "Atender agora" idem. Popup "prioridade máxima"
(gênio da lâmpada) segue navegando — abrir balão por lá é possível se o
Guilherme quiser (aparece em qualquer tela).

## 97. ✅ PAINEL DO EMPRESÁRIO ✅ CONSTRUÍDO (20/07, não commitado)
Pedido do Guilherme (foto do quadro da parede "Quadro do Empresário"):
aba nova com as ferramentas de gestão e direcionamento do dono, no kit
CEVICO, dopamine, integrada aos dados existentes.
COMO FICOU: 3ª pílula "Painel do Empresário" (LARANJA, como o quadro
original) no Estratégico — SÓ ADMIN (backend não trafega o quadro p/
atendente: business=null no show + 403 no save, testado com a atendente
teste). Reproduz o desenho por inteiro:
- Semana do empresário: kanban A fazer→Fazendo→Feito (setas nos cards,
  Feito risca + explosão de ✅🎉💪 via EmojiFx, "limpar feitos");
- Continuar · Parar · Começar (blocos verde/vermelho/azul, chips);
- Matriz de Prioridades (importância×urgência: Agendar/Fazer agora/
  Eliminar/Delegar) e Matriz de Oportunidades (resultados×esforço:
  Fazer primeiro/Planejar/Encaixar/Evitar) — 2×2 com eixos, chips por
  quadrante;
- Pessoas Estratégicas (medalhão de iniciais + porquê);
- Objetivos do Ano / Metas Específicas / Atividades Estratégicas (5
  numerados, medalhão acende ao preencher);
- MÉTRICAS DA EMPRESA INTEGRADAS ao Financeiro real (GET finance preset
  mês): faturamento, volume de vendas (lançamentos de receita), ticket
  médio, custo mensal, lucro c/ margem, PONTO DE EQUILÍBRIO com barra
  ("mês pago — lucrando" / "% do caminho") + FRASE POR EXTENSO verde/
  âmbar + atalho "abrir Financeiro";
- Principais Problemas → Solução Imediata (post-its âmbar→verde
  levemente tortos, como na parede).
AUTOSAVE com debounce 900ms + chip "Salvo às HH:MM". Persistência em
agenda_config.business_board (SEM migration) via strategy_controller
(show + save_business_board c/ sanitização e caps). Componente novo
strategy/BusinessPanel.vue reusando DashKpi/EmojiFx/pílulas/medalhões.
Testado no Docker conta 3: todos os blocos + autosave + releitura pós-
reload + banco conferido + permissões. Dados de demonstração deixados
na conta 3 (kanban 1 card, 1 continuar, 1 prioridade, Dr. Henrique,
objetivo 1, 1 par problema→solução).

## 98. 🔴 HOTFIX: Meu Painel 500 ao bater recorde ✅ CORRIGIDO (20/07, não commitado — SUBIR URGENTE)
Bug DO LOTE EM PRODUÇÃO (item 53, Painel de Metas): records_json mutava
o agenda_config em memória (cfg['panel_records'] ||= {} + escrita no
hash do atributo) e chamava settings.with_lock logo depois — Rails
recusa lock com atributo sujo ("Locking a record with unpersisted
changes") → o crm/home devolve 500 na PRIMEIRA vez que qualquer métrica
do painel bate recorde. Com panel_records nascendo vazio no deploy de
20/07, qualquer número > 0 é recorde ⇒ Meu Painel quebra em produção
conforme o dia anda. FIX: deep_dup do hash antes de mexer (o registro
fica limpo; a gravação continua sob trava relendo fresco). Reproduzido
e corrigido no Docker (500 → 200 na mesma tela). PRIORIDADE MÁXIMA no
próximo push.

## 99. ✅ Tarefas automáticas COM RESPONSÁVEL por coluna do CRM ✅ CONSTRUÍDO (20/07, não commitado)
Pedido 20/07 (produção): tarefas dos robôs nasciam "sem responsável" —
cada menina cuida de colunas do CRM e precisa receber o aviso no nome
dela. COMO FICOU:
- Config: modal da coluna (Editar Kanban → engrenagem → Configurações)
  ganhou "👤 Responsável pelas tarefas desta coluna" (select do time;
  stage.settings.task_owner_id; merge preserva main_inbox_ids).
- Crm::TaskOwner.resolve: coluna atual do paciente → dona; fallback
  responsáveis da conferência (attendance_owners consulta/cirurgia);
  nada configurado → sem dono (como antes).
- Aplicado nos 3 pontos: Crm::AppointmentRecorder (criar + reagendar
  sem roubar dono manual), CrmAutomationFireJob "⚠️ Confirmar consulta"
  e Atendente Instagram (tarefa de revisão). Conferência já atribuía.
- Aviso dourado do Meu Painel já filtra por assignee ⇒ notificação cai
  no painel da responsável; TasksBoard já mostra/edita responsável.
- BACKFILL: bundle exec rails "cevico:assign_tasks[1]" (dry-run mostra
  a distribuição por pessoa; APPLY=1 grava; só tarefas abertas sem dono).
  ORDEM PÓS-DEPLOY: 1º configurar os responsáveis nas colunas, 2º rodar.
Testado Docker: resolve por coluna ("Atendente Teste"), fallback
conferência, task do Secretário nasceu com dona certa, rake dry-run +
APPLY, modal salvou e preservou caixas.

## 100. ✅ Conversas: filtros EVIDENTES que se recolhem ✅ CONSTRUÍDO (20/07, não commitado)
Pedido 20/07: mostrar todas as opções; depois de escolher, recolher e
deixar evidente só o selecionado. Estágios e etiquetas viraram CHIPS
com bolinha colorida (todos à vista, max-h c/ scroll); ao escolher,
recolhe numa pílula única na cor do estágio/etiqueta com ✕ (clique =
trocar/limpar). Ordenação virou 2 botões sempre visíveis ("↓ Recentes
primeiro" | "↑ Antigas primeiro", ativo destacado) no lugar do select.
"Não lidas no topo" mantido. ChatList.vue; lógica de filtro intocada.

## 101. ✅ Números de WhatsApp MINI c/ STATUS DA CONTA ✅ CONSTRUÍDO (20/07, não commitado)
Pedido 20/07: resumo pequenininho e discreto, e sobre "status da conta"
(não "funcionando"). Faixa de UMA linha no Meu Painel (admin): bolinha
por número colorida pela QUALIDADE da conta na Meta (verde saudável /
âmbar atenção / vermelho baixa-sinalizada / cinza indisponível) + nome
verificado + "limite N/dia" (messaging_limit_tier) + falhas 24h só se
houver + "precisa reautorizar" em vermelho. Backend: whatsapp_status_json
enriquecido c/ Whatsapp::HealthService NATIVO (Meta Graph) em cache de
10 min por número (falha tb cacheada — não trava o painel; canal fake
local caiu no fallback certinho). Detalhes completos seguem em
Relatórios → Saúde do WhatsApp.

## 102. ✅ Conversas CLEAN: filtros em JANELINHA + mobile sem barra ✅ CONSTRUÍDO (20/07 noite, não commitado)
Feedback do Guilherme em produção: a nuvem de chips do item 100 poluía.
COMO FICOU: dois botões discretos "Colunas CRM ▾ | Etiquetas ▾"; apertou,
abre a JANELINHA (painel flutuante com as 2 abas, chips coloridos,
rolável); escolheu, fecha sozinha e sobra a pílula colorida com ✕
(clique limpa). Fecha ao clicar fora (onClickOutside). Pílulas de caixa
de entrada deslizam SEM barra de rolagem aparente (scrollbar-width:none
+ webkit) — mobile clean. Testado: janelinha abre/fecha, filtro aplica,
pílula recolhe.

## 103. ✅ AMBIENTE DE TAGS DE PERDAS 🟥 ✅ CONSTRUÍDO (20/07 noite, não commitado)
Card "🟥 Perdas por motivo" no Dashboard CRM: padrão CEVICO de 6 motivos
(Não respondeu / Sem interesse / Valor / Convênio / Distância / Momento
futuro) → botão cria as 6 etiquetas VERMELHAS perda_* de uma vez (via API
nativa de etiquetas, sem backend novo); ranking de perdas do período em
barras vermelhas c/ % (fonte: by_label que o dashboard já calcula;
etiquetas perda_* extras criadas à mão entram sozinhas no ranking) +
frase de gestão ("o motivo campeão é onde o dinheiro está vazando").
Fluxo da atendente: lead esfriou → aplica perda_* no balão do card.
Testado: 6 etiquetas criadas no clique, empty state ok.

## 104. ✅ AMBIENTE DO MÉDICO (gestão e contratações) ✅ CONSTRUÍDO (20/07 noite, não commitado)
Dashboard dos Médicos ganhou abas "Desempenho | 🩺 Gestão do time médico"
(gestão SÓ ADMIN — profiles nem trafega p/ atendente [null] + save 403,
testado). Card por médico: medalhão nas cores oficiais da Agenda, status
em botões em linha (Ativo/Em contratação/Em avaliação/Pausado),
especialidade, números REAIS do período (consultas/conversão/NPS),
💪 Forças e 🧗 Pontos a desenvolver em chips (Enter adiciona), 📝
observações do gestor; card tracejado "Contratando?" adiciona candidato
(nasce Em contratação, removível). Autosave debounce c/ chip "Salvo às"
em agenda_config.doctor_profiles (SEM migration; backend
doctors_dashboards_controller#save_profiles + sanitização). Testado:
força no Dr. Gustavo, Dra. Camila Souza em contratação, persistência
pós-reload confirmada no banco.

## ⏳ Pendências de clarificação do lote (perguntar ao Guilherme)
- **Item 66**: script validado de fechamento — Guilherme vai fornecer
  (construir com campo editável/placeholder até lá).
- Deploy do lote 55/56: AINDA NÃO SUBIU (confirmado 18/07). Quando subir:
  backup → web → sidekiq; pós-deploy: 🛡️ acessos, 💰 tabela de preços,
  🎯 metas de julho. Reversão: imagem build 56 (7187c2de6).

## ═══ RODADA 22/07 (PR #5 NO AR — deploy confirmado pelo Guilherme) ═══

## 105. ✅ Conversas: caixas em VÁRIAS LINHAS + largura da lista AJUSTÁVEL ✅ CONSTRUÍDO E SUBIDO (22/07)
Pedido: todas as caixas à primeira vista + controle manual do tamanho da
lista. COMO FICOU (ChatList.vue): pílulas de caixa em flex-wrap (quantas
linhas precisar, sem rolagem escondida) + ALÇA na borda direita da lista
(trilho de 5px que acende dourado no hover; só desktop ≥768px): arrasta e
a largura (280–620px) fica salva no navegador (cevico_conversas_largura);
duplo clique volta ao automático (340/412). Testado: arrasto 340→505 com
persistência + reset por duplo clique.

## 106. ✅ Meu Painel: cores NEUTRAS até meio-dia + "Muito bom" VERDE ✅ CONSTRUÍDO E SUBIDO (22/07)
tileState: antes das 12h (hora do navegador) os status de RITMO 'bad' e
'warn' viram 'neutral' (cor padrão do painel, sem ⚠️, sem sinal vermelho
no "posso viajar") — meta batida e recorde continuam aparecendo (são
fatos, não julgamento de ritmo). Selo "Muito bom 🚀" saiu do lima/dourado:
chip #10B981 e o card da Taxa de agendamento ganha grad VERDE via
tile.chip.grad (tileVisual usa o grad do chip quando nenhum status de
meta manda). booking30Verdict idem.

## 107. ✅ METAS DO MÊS com leads REAIS do mês (fix da importação) ✅ CONSTRUÍDO E SUBIDO (22/07)
CAUSA do 10.191/2000: GoalPeriodHistoryService contava new_leads por
crm_contacts.created_at — e os ~10 mil CARDS nasceram juntos na janela da
importação (01–11/07). Os dashboards já usavam a data real
(contacts.created_at, por isso "Novas no período" mostrava 1.648). FIX:
new_leads agora conta por contacts.created_at (joins :contact) — mesma
fonte oficial p/ card "Metas do mês" do Meu Painel, selos do Dashboard
CRM (useCevicoGoals) e Painel de Metas (histórico mês a mês fica real).
AUDITORIA dos demais números: build_kpis/build_created_over_time/
reached_stage_count/leads_count já usavam contacts.created_at — ok.
cevico:fix_imported_dates continua disponível p/ higiene (dry-run 1º).

## 108. ✅ Tempo de atendimento: média COMERCIAL (08–17h) × FORA do horário ✅ CONSTRUÍDO E SUBIDO (22/07)
A meta só vale quando as meninas estão presentes: novo Crm::BusinessHours
(seg–sex 08h–17h SP, MENOS feriados nacionais — fixos + Carnaval/Sexta
Santa/Corpus via Páscoa calculada) gera a condição SQL; response_goal_rows
separa reply_time em comercial (meta, % na meta) e fora do horário
(noite/madrugada/fds/feriado — só informativo, sem julgamento). UI: 4
medidores (Tempo médio 08–17h · 🌙 Fora do horário · Dentro da meta ·
Respostas 08–17h) + chip "vale seg–sex · 08h–17h" + 🌙 nas linhas do
time. Testado na conta 3: 10 min comercial × 9,3 min fora; feriados de
2026 conferidos (16-17/02, 03/04, 04/06…).

## 109. ✅ Tratamento de dados: "por conteúdo" SÓ EM COLUNAS ESPECÍFICAS ✅ CONSTRUÍDO E SUBIDO (22/07)
"Etiquetar e/ou MOVER por conteúdo" ganhou chips das colunas do CRM
("Atuar só em quem está nestas colunas", opcional): a regra vale para o
card ATUAL do contato. Backend no matching_scope (vale p/ prévia E
aplicação; stage de outra conta não vaza; coluna apagada entre prévia e
aplicar = atua em NINGUÉM, nunca cai no funil inteiro). Testado: prévia
4 conversas sem filtro → 1 com "Novos Contatos"; id inválido → 0.
⚠️ DEPLOY: reimplantar WEB **E SIDEKIQ** juntos — sidekiq velho ignoraria
o filtro de colunas do job e aplicaria no funil inteiro. Sem migrations.

## 110. ✅ PRÉVIA DE RASCUNHO das Páginas ✅ CONSTRUÍDO (23/07, não commitado)
Pedido do Guilherme: ver a página antes de publicar. COMO FICOU: link
SECRETO por página (token assinado pelo segredo do servidor —
CevicoPage#preview_token / find_by_preview_token), rota GET
/p/rascunho/:token renderiza o show normal com TARJA "👁 RASCUNHO" no
topo (sticky navy+ouro), SEM contar visita, SEM A/B, beacon de rolagem
desligado e CTA apontando DIRETO pro destino (o redirecionador de
contagem só existe pra publicadas). Admin: preview_url no page_json;
botão "👁 rascunho" âmbar no card (substitui "abrir ↗" quando não
publicada) + "👁 Ver rascunho" no rodapé do editor (dica: salvar antes).
Testado conta 3: prévia 200 c/ tarja + CTA direto, público do rascunho
404, token falso 404, publicada sem tarja (sem regressão). Página de
teste "teste-previa-rascunho" deixada na conta 3.

## 111. ✅ Montar página com IA em SEGUNDO PLANO ✅ CONSTRUÍDO (23/07, não commitado)
Era o "internet error": a geração rodava com a conexão ABERTA e o proxy
derruba em ~60s. COMO FICOU: clique → POST generate_start agenda o
Crm::PageGenerateJob (novo) e devolve job_id; resultado fica no Redis
(Redis::Alfred, TTL 15min); o editor consulta generate_status a cada 3s
por até 5min e preenche as seções quando 'done' — nenhuma conexão longa.
Erro vira mensagem legível (testado: "IA não configurada..." apareceu no
alerta em ~4s). Endpoint síncrono antigo (generate) mantido por
compatibilidade. Testado conta 3: start 200 → status 200 c/ erro legível
(local sem chave); em produção c/ chave = 'done' + página. ⚠️ DEPLOY:
web E SIDEKIQ (job novo).

## 🎨 EDITOR DE RETOQUES nas seções ✅ CONSTRUÍDO (23/07, junto c/ 111, não commitado)
Pedido: edições simples no que a IA criou. Cada seção do editor ganhou:
COR (8 bolinhas + "nenhuma" → fundo suave degradê no público, hex
validado no backend) e IMAGEM (upload → POST pages/upload_image →
ActiveStorage blob avulso → caminho RELATIVO /rails/active_storage/...
salvo em sections[].image_url — só caminhos do nosso storage passam na
sanitização; render .sec-img no topo da seção, max 640px, sombra navy).
Título/texto/efeito/ordem/excluir já existiam. Testado: upload 200
(81KB png), prévia renderiza tint #0F5FA624 + imagem carrega 200,
editor mostra Efeito/Cor/Imagem + miniatura.

## 🔧 INFRA 23/07 (madrugada): MÍDIAS RESOLVIDAS + STORAGE PERSISTENTE ✅ NO AR
Saga do "áudio zerado"/"imagem não disponível": arquivos ERAM baixados
mas gravados no disco EFÊMERO do container (web e sidekiq cada um com o
seu; deploy zerava tudo — raio-X: blob 302 → disk 404). CONSERTO: pasta
/root/cevico-storage no VPS montada como Bind Mount em /app/storage nos
DOIS serviços (EasyPanel → Armazenamento; container roda como root, sem
ajuste de permissão). RESGATE prévio: 308kB do sidekiq (testes do
Guilherme) + 598MB/4.668 arquivos do ROBOMASTER (hipótese DELE: as
mídias antigas ficaram no storage do Robomaster na migração — docker cp
direto do container). Junto no mesmo deploy: FRONTEND_URL →
https://sistema.cevico.com.br + rodada 105-109 NO AR. CONFIRMADO pelo
Guilherme: imagens e áudios aparecendo (novos e antigos). DOMÍNIOS:
sistema.cevico.com.br (sistema, oficial do time) + clinica.cevico.com.br
(público das páginas) — www/raiz = site WordPress na Hostinger (82.25.72.201),
NUNCA apontar pra VPS. PENDÊNCIAS ABERTAS DESTA FRENTE: incluir
/root/cevico-storage no backup diário (script /root/backup_cevico.sh só
salva o banco!); cópia off-VPS (rclone) ganhou urgência; conferir se o
comando da MARCA (InstallationConfig) e Configurações → Domínio =
clinica.cevico.com.br foram executados; Robomaster segue de pé como
retaguarda (n8n/evolution moram no projeto dele — NÃO desligar o projeto
inteiro sem planejamento).

## 113. ✅ AMBIENTE DE MONTAGEM: a página nasce NA FRENTE da pessoa ✅ CONSTRUÍDO (23/07, não commitado)
Pedido do Guilherme refinando o 111: clicar em "Gerar/Montar página com
IA" ABRE A PRÓPRIA PÁGINA DE RASCUNHO em outra aba e a construção
acontece ali. COMO FICOU: clique → cria o rascunho na hora (se novo) →
generate_start c/ page_id → job escreve o resultado DIRETO na página
(apply_result_to_page + normalize_ai_sections) → a aba abre o
builder_url (prévia + ?edit=token de RETOQUE + construir=1) → AMPULHETA
⏳ girando ("Construindo a sua página…", consulta status a cada 2,5s) →
pronta = recarrega c/ CASCATA (seções sobem uma a uma) + selo verde
"✅ Página pronta! Clique nos textos para retocar" → RETOQUE INLINE
estilo clica-e-edita: todos os textos (título, subtítulo, h2 das seções,
parágrafos, itens, autor do depoimento, texto do CTA) contenteditable c/
moldura tracejada dourada, barra fixa "✏️ Clique em qualquer texto p/
editar | 💾 Salvar" c/ "Salvo às HH:MM ✓"; salva por POST
/p/rascunho/:token/retocar (token de EDIÇÃO separado do de visualização
— link compartilhado é só-leitura; 403 testado) e o merge preserva
tipo/efeito/cor/imagem/ordem (SÓ textos mudam — o resto é do editor).
Erro da IA = ampulheta vira "😕 Não consegui montar" + motivo legível.
FAQ abre e não fecha no modo retoque; CTA não navega ao editar; beacon
desligado. Lição: payload JSON livre em controller público =
UnfilteredParameters — permit! antes do to_h (sanitização no modelo).
Testado ponta a ponta conta 3: clique real → aba "Página em construção…"
→ ampulheta → erro legível (sem chave local); caminho feliz simulado
running→done → cascata + barra; retoque salvou título+seção e preservou
cor #0F5FA6 + imagem. ⚠️ DEPLOY: web E SIDEKIQ.

## 114. 🔴 HOTFIX: Construtor truncava páginas grandes ✅ CONSTRUÍDO (23/07, madrugada 2)
Caso real: landing de catarata trifocal (~13k chars de copy) saiu VAZIA.
Causa: teto de 8.192 tokens dividido entre RACIOCÍNIO (effort) e a
resposta (o JSON repete a copy inteira) → JSON cortado no meio → erro
"formato inesperado" (que expira do Redis em 15min — ele viu só o
esqueleto depois). FIX: max_tokens 30.000 no PageBuilderService e no
CopywriterService (modo página); prompt do Construtor agora DESCARTA
instruções de montagem/placeholders [FOTO: ...] do texto final (usa como
orientação); guarda-corpo no PageGenerateJob: pronta sem seções = erro
avisado, nunca sucesso vazio. PEDIDO DO GUILHERME anotado: ambiente do
Construtor mais CONTROLÁVEL (teto de tokens, esforço, etc. na mão do
admin) → incorporar ao item 112.

## 115. ✅ CONSTRUÍDO (24/07, não commitado): RASTREAMENTO DAS PÁGINAS (plano 100+ páginas c/ ads) + ANEXAR HTML PRONTO
Pedido do Guilherme 24/07: estender o rastreio de anúncios (CTWA) pras
PÁGINAS — Google no centro (Ads + SEO orgânico) — e poder anexar páginas
HTML feitas fora (com IA no computador) dentro do ambiente de Páginas.
DECISÕES: não existe API navegador→WhatsApp (verificado, "dark social");
a ponte é o PROTOCOLO no texto pré-preenchido + a parte por API é a CAPI
(MetaAdsConversionsService JÁ EXISTE; ligar gclid/fbclid nela = rodada 2
c/ Google offline conversions). Aba de resultados DENTRO do ambiente de
Páginas (escolha dele).
COMO FUNCIONA: (1) ORIGEM — Cevico::TrafficSource classifica cada visita
(google_ads por gclid/utm cpc; google_organico por referer/utm; meta_ads;
social; outros_ads; busca; funil; direto — padrão de utm dos anúncios:
utm_source=google|meta + utm_medium=cpc + utm_campaign) e agrega em
cevico_page_traffic (página×dia×origem×campanha, UPSERT atômico, aguenta
100+ páginas); snippet público (_tracking_snippet) guarda a origem na
sessão do navegador e a faz VIAJAR nos links internos (funil/cta/forms;
next_step repassa no servidor tb). (2) PROTOCOLO — clique no WhatsApp
gera CevicoPageRef (token 5 chars sem ambíguos p/ ler por telefone,
válido 90d) e anexa "Protocolo: XXXXX" ao texto (cta_click no servidor
p/ páginas montadas; POST /p/:slug/ref pro snippet nas anexadas);
1ª mensagem no WhatsApp com o código (Whatsapp::IncomingMessageBaseService
→ Crm::PageAttributionService) carimba page_ads no contato+conversa
(PRIMEIRO TOQUE, AttributeMerge, convive c/ meta_ads do CTWA) e liga
ref.contact_id. (3) ANEXAR HTML — cevico_pages.custom_html (só admin,
2MB, permit separado): público serve o arquivo COMO VEIO c/ snippet
injetado antes do </body>; prévia = tarja RASCUNHO sem rastreio; editor
(PagesHome) ganhou bloco "Página HTML anexada" (anexar/substituir/
remover; seções somem c/ anexo); index NÃO carrega o HTML (flag
has_custom_html via SELECT). (4) ABA RESULTADOS — menu Conteúdos →
"Resultados de tráfego" (TrafficResults.vue, rota pages/resultados,
concessão pages): pílulas de período 7/30/90 + pílulas de origem c/
contagem, 6 DashKpi (Visitas/Cliques/Leads/Agendaram/Cirurgias/Receita),
linhas por página c/ drill origem+campanha; endpoint crm/pages_report
(pages_reports_controller: traffic + contatos page_ads + agendou por
tasks consulta contact_id + cirurgias/receita na MESMA régua do
relatório de Anúncios [etapas cirurgia sem indicação / config] +
honestidade minted×matched dos protocolos). MIGRATION 20260724000001
(custom_html + 2 tabelas) — backup antes. TESTADO conta 3: classificador
13 casos ✅; visita gclid + organica → baldes certos; cta → redirect c/
"Protocolo: T4HMU" no wa.me; carimbo 1º toque + não-sobrescreve + texto
sem código = no-op; mint_ref; página anexada servida c/ snippet (prévia
c/ tarja sem snippet); origem viajou no link interno (URL levou os utm);
relatório real (leads 1/booked 1 no bucket google_ads, campanhas
catarata-julho/galaxy-teste); telas no browser OK (screenshots), 0 erros
console; rubocop baseline. ⚠️ DEPLOY: WEB + SIDEKIQ + migration.
PRÓXIMA RODADA (combinado): CAPI Meta c/ fbclid da página + Google Ads
offline conversions c/ gclid (avisar: precisa config/token dele);
GA4/Pixel opcionais nas páginas anexadas ele mesmo põe no HTML.

## 115B. ✅ CONSTRUÍDO (24/07, mesma rodada): HUB — PORTA DE ENTRADA na raiz do domínio
Pedido: hub padrão na raiz de clinica.cevico.com.br direcionando pra
"refrativa | catarata | lente trifocal". A home do domínio dedicado
virou HUB da marca (navy/ouro/Cinzel, logo dark-bg): frase de boas-vindas
configurável + botão dourado "Falar com a CEVICO no WhatsApp" + as 3
PORTAS (👓 Refrativa /refrativa|lasik|prk|miopia/, 👁️ Catarata
/catarata/, ✨ Lente Trifocal /trifocal|galaxy|premium/) — cada porta
acha sozinha a página PUBLICADA do assunto (slug/título); sem página
ainda, manda pro WhatsApp com o assunto no texto (entrada nunca fica sem
destino) + índice por categoria como antes. CONFIG em Configurações →
Domínio, card "🚪 Porta de entrada" (WhatsApp DDI, frase, mensagem do
botão; InstallationConfig CEVICO_HUB via PublicSite.save_hub!/hub_config,
endpoint update_public_hub só admin). RASTREIO: snippet parametrizado
(page nil = hub → POST /hub/ref), cevico_page_refs.cevico_page_id ficou
NULLABLE (migration 20260724000001 EDITADA antes do deploy), snapshot c/
slug='hub', relatório ganha linha "🚪 Porta de entrada (hub)" (leads/
agendou/cirurgias; sem visitas — hub não entra na cevico_page_traffic
v1, GA4 cobre depois); origem viaja do hub pras páginas (portas
reescritas no clique c/ utm). TESTADO conta 3: home 200 c/ Host header +
visual no browser (screenshot navy/ouro), portas acharam refrativa
(página PRK) e catarata, trifocal caiu pro Whats c/ assunto; protocolo
do hub PDCCX → carimbo google_ads → linha hub no relatório; utm viajou
hub→página; 0 console err; rubocop zero ofensas novas (45=45 no
settings). Local: CEVICO_PUBLIC_HOST limpo depois do teste.

## 117. ✅ CONSTRUÍDO (24/07, não commitado): RASTREAMENTO CENTRAL — Pixel da Meta + GA4 em todas as páginas
Pedido do Guilherme (24/07, PRIORIDADE — páginas sobem amanhã): adicionar
Pixel/tag/API da Meta e Google nas páginas "de forma simples, eficiente e
trackeando cada página". DESENHO: config UMA vez → card "📊 Rastreamento"
em Configurações → Domínio (Pixel ID + GA4 ID, só admin, InstallationConfig
CEVICO_TRACKING via PublicSite.tracking_config/save_tracking!, endpoint
update_public_tracking c/ validação amigável G-XXXX/só números) → partial
_analytics_snippet injetado sozinho em TODA página publicada (montada,
HTML anexada E hub; prévia de rascunho fica LIMPA): Pixel base + PageView
+ ViewContent{content_name: slug, content_category: categoria} + gtag
config{cevico_page} — UM pixel só, a página viaja DENTRO do evento (nos
relatórios da Meta/GA4 filtra por página). LEAD: window.cevicoLead dispara
Contact (Meta) + generate_lead (GA4) no clique pro WhatsApp — páginas
montadas via listener no /cta; anexadas/hub via gancho no snippet do
Protocolo, que passa o token como eventID = a MESMA chave que a CAPI
usará na rodada 2 (dedup automático). Sem migration. TESTADO conta 3:
salvar 200 + selos verdes; injeção conferida por curl nas 3 famílias
(montada content_name teste-previa-rascunho / anexada catarata / hub via
Host header clinica.cevico.com.br, depois host limpo); prévia 0 tags;
generate_lead no dataLayer c/ página+protocolo; 0 console err; rubocop
zero ofensas novas. Falta do Guilherme: Pixel ID e GA4 ID reais (camada
2) + rodada 2 (CAPI fbclid + Google offline gclid) segue na fila.

## 116. ✅ CONSTRUÍDO (24/07, não commitado): CRM MOBILE — navegar sem arrastar
Pedido do Guilherme (24/07): "no mobile não quero mover os cards
arrastando, quero navegar nas colunas" — o toque no card grudava no
arrasto do vuedraggable e brigava com o deslize horizontal do quadro.
FEITO em KanbanColumn.vue: `useWindowSize` do @vueuse (mesmo padrão do
Sidebar) → `isMobile = width < 768` (mesmo corte do navegador de chips)
→ `:disabled="isMobile"` no vuedraggable dos cards + `:key` por
breakpoint (vuedraggable 4 ignora mudança de prop pós-mount; o remount
garante a troca ao vivo se a janela cruzar 768px). Desktop intocado.
TESTADO conta 3 no browser: 375px → Sortable `disabled:true` nas 12
colunas, arrasto no card não move nada (clique continua abrindo o
painel do paciente), deslize/chips navegam normal; 1280px →
`disabled:false`; troca de breakpoint aplica na hora (evento resize).
Sem migration, só frontend.

## 112. ✅ FASE 1 CONSTRUÍDA (23/07 tarde, não commitado): CHAT DO CONSTRUTOR + CONSTRUTOR PRO
CONSTRUTOR PRO (card do agente em Automações → Agentes de IA): campo
"Referências de estilo" (textarea, injetada em TODA montagem/correção —
aceita chave references igual ao Copywriter) + "Teto de resposta
(tokens)" (1.000–60.000; vazio = 30.000) + botão "Salvar rédeas do
Construtor"; backend: permit no settings_controller + leitores
max_tokens_config/style_refs/style_refs_block no AiAgentConfig, usados
no PageBuilderService e no novo PageEditorService. CHAT DO CONSTRUTOR
(na página de rascunho, junto da barra de retoque): botão "💬
Construtor" abre painel navy/ouro c/ histórico (localStorage por
página), instruções tipo "FAQ pro final"/"seção dourada com brilho" →
POST /p/rascunho/:token/construtor (token de EDIÇÃO; 403 testado) →
PageEditJob → PageEditorService (página atual JSON + instrução →
página completa atualizada + "reply" pro chat) → aplica → aba recarrega
em cascata e o chat reabre com a resposta; retoques abertos são SALVOS
antes de enviar (senão a IA passaria por cima); erro = balão legível.
SCHEMA das seções ganhou color+image_url (enum/validação — o Construtor
agora PINTA páginas na montagem; normalize_ai_sections preserva).
Testado conta 3: painel/balões/⏳/erro legível no browser, 403, enqueue
+ sidekiq, EDIT_SCHEMA carrega, PRO salva e os services leem (40000 +
referências). ⚠️ DEPLOY: web E SIDEKIQ (service+job novos). PR #10
mergeado (5eda13c15), build VERDE 23/07 ~15:30.

## 112 FASE 2. ✅ CONSTRUÍDA (23/07 tarde, não commitada): FOTOS COM VISÃO no Chat do Construtor
No painel 💬 da página de rascunho: botão 📎 (input file image/*,
múltiplas) → sobe NA HORA via POST /p/rascunho/:token/foto (novo
endpoint público gated pelos DOIS tokens + rascunho; mesma validação do
upload do editor: só image/*, 8 MB; devolve caminho relativo) →
miniaturas 44px com × acima do input → enviar manda images:[caminhos]
junto da instrução (sem texto + foto = instrução padrão "posicione nas
melhores seções"). builder_chat sanitiza (só /rails/active_storage/,
máx. 3) → PageEditJob (4º arg image_urls, retrocompatível) →
PageEditorService(images:): resolve blob pelo signed_id do caminho,
foto >3MB vira variante JPEG 1600px só pra IA (página usa a original;
falhou variante → original; >5MB pós-tudo = descarta, limite da API),
conteúdo vira blocos [texto "Foto N — caminho" + imagem base64]* +
build_input com lista "FOTOS ANEXADAS PELA EQUIPE" — o agente VÊ cada
foto e preenche image_url da seção certa com o caminho EXATO (regra
nova no SYSTEM_PROMPT; reply conta onde pôs e por quê). Sem foto =
entrada texto puro idêntica à Fase 1. Testado conta 3: user_content c/
foto real (3 blocos, base64 ok) + inválida/externa filtradas; upload
403 sem edit token / 200 com / 422 não-imagem; chat só-foto enqueue →
job roda service com images e devolve status; UI com DataTransfer real
(chip aparece, envia, limpa, resposta volta no chat); 0 erros console;
rubocop = baseline (12 pré-existentes). ⚠️ DEPLOY: web E SIDEKIQ
(job/service mudaram). Fora do escopo desta fase: geração de imagem
(slot gemini_api_key segue reservado).

## (desenho original) 112: CHAT DO CONSTRUTOR no Ambiente de Montagem
ONDE: na própria página de rascunho (Ambiente de Montagem) — balão
flutuante "💬 Falar com o Construtor" ao lado da barra de retoque.
FASE 1 (uma sessão): (a) chat de correção por TEXTO — "deixa o título
mais direto", "FAQ por último", "seção 3 dourada com brilho", "adiciona
depoimentos" → PageEditorService recebe página atual (JSON) + instrução
→ devolve página atualizada no MESMO PAGE_SCHEMA (estendido c/
color/image_url/effect por seção) + campo "reply" (resposta do agente
no chat, incl. SUGESTÕES de imagens por seção) → PageEditJob aplica →
aba recarrega em cascata; histórico do chat em jsonb da página;
endpoints no CevicoPagesController gated pelo token de EDIÇÃO;
(b) CONTROLES DO CONSTRUTOR na tela do agente (Automações → Agentes de
IA): modelo, esforço, teto de tokens e instruções fixas de marca
(pedido do Guilherme).
FASE 2: IMAGENS no chat — anexa fotos (upload_image já existe) → agente
VÊ as fotos (visão da API, blocos de imagem) + página atual → decide em
qual seção cada foto entra (seta sections[].image_url) e responde o
porquê; só URLs do NOSSO storage passam (sanitização já existe). Logo
CEVICO já aparece automático no hero de toda página.

## (histórico) 112-original: CHAT DO CONSTRUTOR no editor de Páginas (combinado 23/07)
Ideia do Guilherme: conversar com o agente DENTRO do editor — manda
comentários e FOTOS, o agente atualiza o rascunho seção a seção; fotos
hospedadas no sistema entram na página; publicar continua manual (admin).
Decisão: construir DENTRO do sistema (equipe toda usa, fotos no lugar
certo, custo rastreado no Painel dos Agentes). Combina com item 110
(prévia) e com a montagem em segundo plano (111). AMPLIADO 23/07:
Guilherme quer o ambiente do Construtor mais CONTROLÁVEL — expor na
tela do agente (Automações → Agentes de IA) o teto de tokens, o esforço
e instruções extras por página, p/ landing pages caprichadas.
🔴 CAUSA REAL da landing vazia (descoberta 23/07 madrugada 3, prints de
produção): a IA GEROU a página (opus-4-8, 4.647 tokens de saída, status
done) mas apply_result_to_page lia o resultado com chaves SÍMBOLO e o
JSON.parse devolve chaves TEXTO → aplicava tudo nil/vazio (título ficava
o placeholder, sections []). FIX: deep_stringify_keys no apply. Lição:
resultado de JSON.parse = SEMPRE chave texto — testar o apply com o
payload real, não com hash montado à mão (o teste local usava símbolos
e passava).

## Estado atual (para retomar — atualizado 2026-07-14, madrugada)

**ONDE ESTAMOS (2026-07-15, manhã — TUDO NO AR ✅):** itens 14-36 EM
PRODUÇÃO (deploy web+sidekiq confirmado pelo Guilherme). Chave da
Anthropic CONECTADA (US$ 20 em créditos; "Testar conexão" ok) e o
Analista de Conversas TESTADO E FUNCIONANDO em produção. Dois hotfixes
pós-deploy já no ar (commits 8443b4563 + fe36ebc53): (1) schema do
Analista — API de structured outputs não aceita minItems>1; validador
rodado nos 7 agentes, todos ok; (2) robô de follow-up DOMESTICADO após
rajada das 6h13 (fix destravou âncoras antigas): expediente 08h-20h SP,
etapa vencida há +3h = descartada sem enviar ("momento perdido" ⏭️ no
registro), máx 1 cutucada por conversa por rodada. PRÓXIMOS PASSOS
sugeridos: configurar responsáveis/prazo da conferência, ligar demais
agentes gradualmente (colunas de atuação), acompanhar "Gasto com os
agentes", escolher tema no 🎨. Reversão: reimplantar a imagem
anterior no histórico do EasyPanel (migrations aditivas). Pós-deploy:
configurar responsáveis/prazo da conferência (Agenda → Janelas →
Conferência), ligar os agentes novos (opt-in, nascem desligados) e
escolher o tema no 🎨. — ⚠️ **4 migrations aditivas** (20260714000008/09/10 +
20260715000001); backup antes do deploy, inegociável. Item 33 = fix do
bug do follow-up (default_scope!) + registro de atividade do robô +
[nome] limpo + painéis por pessoa no Meu Painel + "Este ano" + Tarefas
(donut brilhante/anel Sonic/troféu 3D/badge sutil) + Agenda de Cirurgias
azul vítreo com locais (IOP). Itens 27-32: 27 = gatilho Mensagem criada + preço no card; 28 =
Analista c/ script + frases; 29 = Editar/Salvar/Publicar + lote no
Tratamento + valor→coluna; 30 = frases-chave + 📊 Resultados + caixa
por coluna + pílulas Conversas; 31 = Agenda operacional (conferência→
CRM, encaixe, PDF, backfill, reagendamento IA) + mover card na
conversa; 32 = Secretário v2 (registro de atividade + colunas de
atuação), Agenda de Cirurgias (trilho dourado), Agenda vertical
(semana em grade horária), multi-caixas em Conversas, CRM "Este mês"
padrão, Tarefas v2 (solicitações + troféu/confete + anel dourado +
badges verde/dourado + aviso no Meu Painel). **3 migrations aditivas:
…08 (crm_stages.settings), …09 (tasks attendance), …10 (tasks
comments)** — backup antes do deploy. NOMENCLATURA: interno =
"Secretário da Agenda"; N8N = "Atendente IA". Teste visual em
localhost:3000 (conversa #3 conta 3 = insight simulado; Agenda hoje
14h ×2 + 15h; tarefa "Teste solicitações"). Lembrete antigo (histórico):

**ONDE ESTÁVAMOS:** existe um LOTE GIGANTE NÃO COMMITADO no working tree
(~67 arquivos entre modificados e novos), cobrindo os itens 14 a 28 deste
backlog (o item 13/anúncios Meta já foi pushado antes — build `f9e8cae8c`).
TUDO testado no Docker local (rails/sidekiq/vite de pé, migrations
aplicadas, Vite compilando, smoke tests ok). AGUARDA: teste visual do
Guilherme em localhost:3000 → aprovação → commits temáticos → push.

**O que está no lote (resumo; detalhes nos itens 14–22):**
2. IA nativa Claude: 4 agentes (Conversas/Formulários/Agendamento/Radar),
   modelo+esforço por agente com recomendados pré-selecionados, trava
   operacional (nunca fala com paciente), uso de tokens + relatório de
   gastos (crm_ai_usages) — itens 14, 16, 18, 19
3. Radar de Oportunidades: VIGIAS (coluna + painel do atendente + janela
   6/12/24/48h cada), avisos direcionados por atendente (admin vê tudo),
   expediente 07:30–18h a cada 10 min + madrugada 20h/00h/04h, Radar
   PONTUAL em modal próprio (coluna + atendente, roda uma vez), avisos no
   Meu Painel + badge na sidebar, histórico p/ dashboard — itens 18, 19,
   21, 22, 23
4. Formulários typeform (builder + público) + 2 prontos via rake
   cevico:seed_forms: pre-operatorio e antes-da-avaliacao — itens 14, 19
5. Agenda de Consultas: visões Mês/Semana/Dia, ficha completa (nome/fone/
   problema/dia/hora/médico/unidade), 3 médicos (Gustavo azul, Henrique
   dourado, Roberta roxo), 7 janelas EDITÁVEIS, cadeado por horário E por
   dia inteiro, status Cancelada, sáb/dom bloqueados — itens 17, 19, 20, 22
6. Meu Painel v2 (tela inicial após login, p/ admin e agente): presets
   hoje/ontem/semana/mês/mês passado, 11 indicadores, saúde da agenda,
   avisos do Radar — itens 15, 19, 22
7. Dashboards: CEVICO repaginado + Campanhas + etiquetas (doughnut) +
   Radar×Consultas + cirurgias da planilha (Google Sheets) — itens 15, 16, 21
8. UI: sidebar gradiente, menu enxuto p/ agente (Meu Painel|CRM|Conversas|
   Agenda|Tarefas|Configurações→perfil), CRM board repaginado (pílulas de
   visualização, excluir funil oculto), robô follow-up com tipo de contagem
9. Fix local: docker/entrypoints/sidekiq.sh (sidekiq caía sem bundle install)

**⚠️ DEPLOY DESTE LOTE (quando aprovado):**
- **7 migrations**: 20260714000001–07 (ai_config, crm_forms, sheets_config,
  campos consulta em tasks, crm_ai_usages, agenda_config, cancel em tasks)
  → BACKUP DO BANCO ANTES, inegociável.
- Rodar em produção: `bundle exec rails cevico:seed_forms ACCOUNT_ID=1`
- Conferir FRONTEND_URL (links públicos dos formulários)
- Chave da Anthropic em Integrações → Claude (agentes só funcionam com ela)
- Reversão: reimplantar imagem anterior no EasyPanel (migrations só criam
  colunas/tabelas novas)

**Dados de teste no banco LOCAL (conta 3, podem ser apagados):** consulta
"Maria Silva" 15/07 14h (marcada como reagendada), campanha "Teste
Dashboard", aviso simulado do Radar, 3 linhas de uso de IA, horário 15/07
11h bloqueado, 2 detecções no histórico do radar.

**Infra local:** docker compose up -d rails sidekiq vite postgres redis;
sidekiq usa entrypoint próprio novo; crons crm_followup_bot_job e
crm_opportunity_radar_job registrados.

- Sistema migrado e no ar (4.15.1), banco `chatwoot_migrado` em produção.
  Corte final CONCLUÍDO (2026-07-10). CEVICO é o banco vivo.
- Último build verde em produção: `8935f3cde` (rodadas 1–9, item 12) —
  NADA das rodadas 13–22 está em produção ainda.
- Fluxo de trabalho: mudança → teste no Docker local → Guilherme testa em
  localhost:3000 → aprova → commits temáticos → push develop (--no-verify)
  → Actions builda (~10min) → Guilherme implanta no EasyPanel (web+sidekiq).
- Pendências conhecidas: Bloco 5 da auditoria (automação Instagram);
  Dashboard do Negócio fases B/C (item 9); backup off-VPS (rclone);
  fluxo N8N em JSON que o Guilherme vai enviar; ferramenta opcional
  "arquivar cards inativos".
- SMTP (Gmail) configurado para convites de equipe.

# ═══ RODADA 06/08 — item 126: CRM verdadeiro + dashboards remodelados ═══

## 126A. ✅ FIX "163 de 11024" no CRM (CONSTRUÍDO 06/08, não commitado)
- Causa: dois filtros brigando — servidor filtrava por ATIVIDADE (dias corridos)
  e o navegador refiltrava por DATA DE CRIAÇÃO do contato (que a rake de
  importação reescreveu p/ a data da 1ª conversa). "Este ano" só deixava
  passar os 163 contatos realmente criados em 2026.
- Solução: período 100% no SERVIDOR (contacts_controller scope=period, com
  date_from/date_to por calendário em São Paulo) + contagem VERDADEIRA por
  coluna (e R$ por coluna) no cabeçalho + entrega de 50 cards/coluna com
  "Carregar mais" (scope=stage_page) + alternador Ativos×Novos (date_mode
  activity/created). Board leve mesmo com 11k cards.
- CrmBoard: régua padrão (Hoje|Ontem|Últimos 7 dias|Este mês|Este ano|
  Personalizado), refiltro de datas no navegador REMOVIDO, contador honesto
  ("X no período · Y no funil · Z com conversa").

## 126B. ✅ RÉGUA DE PERÍODO PADRÃO em TODOS os dashboards
- Componente único components-next/cevico/PeriodRuler.vue + concern
  Crm::ResolvesPeriod (presets today/yesterday/last7/month/year/custom).
- Migrados: Meu Painel, Dashboard CRM, Campanhas, Funil de Tráfego, Anúncios
  Meta, Médicos, Agenda, Agentes, Financeiro, Google, Resultados de Tráfego,
  Agentes de IA, Central de Automações (aba Resultados). Presets legados
  seguem aceitos nos backends (compatibilidade).
- Agenda: "Este mês/ano" estendem até o FIM do calendário (consulta futura conta).
- Meu Painel: metas/recordes mapeados p/ last7 (base semana) e custom (sem recorde).

## 126C. ✅ FUNIL DE TRÁFEGO REMODELADO (4 visões do mesmo dado)
- Etapas do CRM agora RESPEITAM o período: contam quem ENTROU na coluna na
  janela (crm_contact_stage_logs) + retrato atual ao lado ("agora: N").
- Visões: Funil simétrico | Barras (3 maiores GARGALOS marcados em vermelho) |
  Tendência (linhas semanais chart.js, até 4 etapas, média 12 semanas
  tracejada com 1 etapa) | Mapa de calor (etapas × 12 semanas, tom único).
- Selo ▲/▼ média em cada etapa: ritmo semanal do período × média 12 semanas.
- KPIs migrados p/ DashKpi (kit CEVICO).

## 126D. ✅ DASHBOARD GOOGLE com PALAVRAS-CHAVE
- Crm::GoogleKeywordsService (herda auth do GoogleAdCostService — conta de
  serviço GA4, SEM developer token): keywords/termos de pesquisa/campanhas
  com cliques, custo, CPC, sessões e conversões (GA4 Data API, cache 10min).
- "Do termo à cirurgia": leads google_ads do page_ads agrupados por utm_term
  (fallback campanha) × agendou/compareceu/fechou cirurgia/receita (mesma
  régua do relatório de Páginas). Dica na tela: colocar utm_term={keyword}
  no modelo de acompanhamento do Google Ads quando faltar termo.
- Régua de período na tela; série de conversões enviadas respeita o período.

## 126E. ✅ PAINÉIS DO CONSTRUTOR NO SERVIDOR (salvar/atribuir/principal)
- agenda_config['custom_panels'] (máx 24, sanitizado, só admin) +
  agenda_config['main_panel'] via update_agenda — SEM migration.
- Construtor: "Painéis da conta" (salvar c/ nome, aplicar, ★ principal,
  👥 atribuir ao time, excluir); predefinições locais viraram "só neste navegador".
- Meu Painel: painéis custom viram pílulas (CustomPanelGrid renderiza os
  widgets; métricas do superset gestor); main_panel substitui o painel
  padrão; atribuição aceita 'custom:<id>' e trava o atendente.
- Catálogo único em helper/cevicoBuilderCatalog.js (Construtor + Meu Painel).

## 126F. ✅ FERRAMENTA "CIRURGIAS FEITAS FORA DO SISTEMA"
- Tratamento de dados → novo card: cola lista de telefones (aceita
  telefone;valor;data — cola do Excel), casa por sufixo 8/9 dígitos
  (com/sem 55, com/sem nono dígito), PRÉVIA (casados/ambíguos/não
  encontrados/já na coluna) → aplica em job (queue low, lotes de 200):
  move/cria card na coluna-alvo (padrão "Cirurgia Realizada"), valor via
  update_column (NÃO dispara automações/conversões p/ cirurgia antiga),
  etiqueta sugerida cirurgia_externa.
- external_surgeries_controller + Crm::ExternalSurgeryJob + rotas + UI.

## Estado/deploy da rodada 06/08
- SEM migrations. Deploy = Implantar WEB+SIDEKIQ juntos.
- Working tree também carrega o trabalho ANTERIOR de Meta Leads (webhook
  meta_leads_controller + jobs/services + MetaAds.vue) não commitado —
  separar na hora de commitar.
- Testado local (conta 3): scope=period/stage_page, traffic_report novo,
  google_dashboard novo, custom_panels ponta a ponta (salvar→principal→home),
  os 10 backends de régua com presets novos, preview de cirurgias externas —
  tudo 200. Lint: só regras de estilo já toleradas no padrão CEVICO.
- AGUARDANDO "pode subir". (129 idem — mesma rodada.)

---

# RODADA 10/08 — itens 127-128 (follow-up inteligente + sistema que age sozinho)

## 127. ✅ FOLLOW-UP COM REGRAS DE ETIQUETA POR ETAPA (fix "reaborda 100%")
- Problema: a cutucada de 24h reabordava TODO paciente em silêncio — inclusive
  quem já tinha dito "pode agendar" (etiqueta cta_agendamento).
- Cada ETAPA da cadência agora tem regras próprias: "PULAR quem tem" (skip_labels)
  e "SÓ para quem tem" (only_labels) — etapa protegida é marcada como tratada SEM
  enviar e a cadência segue (as etapas de 30d+ continuam valendo). Motivo novo no
  registro de atividade: protegida_por_etiqueta.
- Etiquetas olhadas no CONTATO **e** na CONVERSA (a cadeia automática etiqueta a
  conversa primeiro — o filtro do robô inteiro também passou a ver as duas).
- De quebra: permit do controller não aceitava delay_from (passos "desde a
  entrada na coluna" salvavam como silêncio) — corrigido.
- UI: FollowupBotModal → "Regras de etiqueta desta etapa" (sanfona por passo,
  chips vermelhos PULAR / azuis SÓ PARA, dica do caso cta_agendamento).
- CONFIG DELE pós-deploy: editar a régua de 24h → nas etapas curtas, PULAR quem
  tem cta_agendamento. Réguas de 30d+ (MessageAutomation) não mudam.
- Teste: 12/12 verde (etiqueta em conversa/contato, only/skip, fluxo completo
  sem envio + estado + evento, permit).

## 128A. ✅ 🌾 COLHEITADEIRA DA BASE (agente 'harvest')
- Cron horário (9h-17h SP, seg-sáb): no dia configurado do mês gera a PRÉVIA
  (pool SQL de leads frios → IA pontua em lotes de 25 c/ haiku → top N) e abre
  tarefa de aprovação; aprovada, envia por SendTemplateService respeitando teto
  DIÁRIO (padrão 50, anti-ban) em fatias horárias de 12.
- Pool: colunas abertas (fora realizada/pós/perda), telefone presente, frio há
  60d+, sem nao_perturbe/perda_*, sem colheita nos últimos 4 meses (etiqueta
  colheita_YYYY_MM aplicada no envio). Pontuação com último recado do paciente
  + ai_insight quando existe; heurística de reserva além do teto de 40 lotes.
- Personalização POR LEAD: IA escreve [gancho] (1 frase citando o histórico);
  [procedimento] também substitui nas variáveis do modelo aprovado do WhatsApp.
- Estado em ai_config['harvest_state'] (sem migration), com_lock, idempotente.
- Config: monthly_size/cold_days/daily_cap/day_of_month/inbox/template/
  require_approval (padrão exige aprovação) + prompt/modelo padrão dos agentes.
- Endpoints settings: harvest_status/preview/approve/pause/resume/skip_lead/
  send_now. Resultados: enviados, responderam (incoming pós-envio), pendentes.

## 128B. ✅ 📊 GESTOR AUTÔNOMO (agente 'manager')
- Cron diário útil 08:10 SP: semana atual (projetada por ritmo) e semana fechada
  vs MÉDIA de 12 semanas (GoalPeriodHistoryService) em 8 indicadores; desvio
  além do limiar (padrão 25%) vira ACHADO (máx 3, os piores).
- Guarda de volume (MIN_BASELINE por indicador; taxa julgada pelo volume que a
  alimenta) — base pequena não gera alarme falso. Começo de semana amortecido.
- AGE: abre tarefa (task_type gestao, prioridade alta, idempotente por dia) para
  o responsável certo (attendance_owners consulta/cirurgia → admin) + briefing
  diário de 4 frases pela IA (haiku) + estado em ai_config['manager_state'].
- Meu Painel: card "Briefing do Gestor" (admin) com brief + chips dos desvios.
- Endpoint run_manager (rodar agora). Config: drop_pct.
- Teste 128: 27/27 verde (pool/bloqueios/prévia/aprovação/pulos/envio sem caixa/
  personalização/fallbacks + desvios sintéticos/guarda de volume/idempotência) —
  na base local o Gestor detectou 1 desvio REAL e abriu a tarefa sozinho.

## 129. ✅ 📈 VISUALIZAÇÃO PRO MAX (Dashboard CRM)
- Responsividade: barras viraram CURVA DE QUEDA (chart.js Line, % acumulado
  por etapa — a inclinação mostra o vazamento; tooltip com contagens).
- Botão "✨ Visualização PRO MAX" no card → estúdio em tela cheia:
  - régua padrão de período + granularidade Dia/Semana/Mês;
  - 4 estilos: Linha, Área, Barras e CANDLES (OHLC do balde montado com
    barras flutuantes [min,max] do chart.js — sem lib nova; candle usa a
    1ª variável ligada, abre no 1º dia e fecha no último);
  - variáveis ligáveis: novas conversas, leads novos, ENTROU em cada etapa
    do funil (stage_logs por dia), faturamento fechado;
  - 📌 HISTÓRICO DE AÇÕES DA EMPRESA: admin registra "LP nova no ar",
    "campanha X", "sistema atualizado" (data+título+categoria+nota) →
    linhas verticais numeradas no gráfico (plugin inline) + legenda com
    gestão (add/remove). Persistência: agenda_config['company_actions']
    via update_agenda (sanitizado, máx 200, sem migration).
- Backend: GET pipelines/:id/dashboard/pro_series (séries DIÁRIAS; front
  agrega) — dashboards_controller#pro_series, cap 366 dias, TZ SP.
- API: getProSeries + updateCompanyActions; settings_json expõe company_actions.

## 129B. ✅ PRO MAX ESTENDIDO (conversas + faturamento por caixa)
- pro_series ganhou séries POR CAIXA DE ENTRADA: "Conversas · <caixa>" (dia a
  dia por inbox) e "Faturamento · <caixa>" (receita de cirurgia realizada
  atribuída pela caixa de ENTRADA do paciente — mesma régua entry_inbox_map
  do dashboard); paleta própria por caixa, group inbox_conv/inbox_rev.
- Botões "✨ PRO MAX" nos cards "Conversas ao longo do tempo" (foco timeline:
  abre com novas conversas + por caixa) e "Faturamento por caixa de entrada"
  (foco revenue: abre com o faturamento por caixa) — prop focus no estúdio.

## 130. ✅ 🎓 AUDITOR DE CONVERSAS (agente 'auditor') — coaching contínuo
- Cron diário 10:40 UTC (07:40 SP): audita as conversas de ONTEM (com >= 2
  mensagens, priorizando as mais ricas, teto diário padrão 150) em lotes de
  5 por chamada (haiku): nota 0-10 contra o script oficial (abertura →
  acolhimento → investigação → orçamento ancorado → quebra de objeção → CTA
  → confirmação), etapa alcançada, 1 acerto, 1-2 falhas acionáveis, próxima
  ação — gravado em conversation.additional_attributes['audit'].
- Agregado por ATENDENTE/dia em ai_config['auditor_state'] (30 dias, poda
  automática, with_lock); "atendente 0" = conversas do robô/fluxo.
- summary(days): ranking por média + falhas mais comuns do TIME → base do
  coaching contínuo (Mentor pode beber daqui numa rodada futura).
- Endpoints: run_auditor (pontual) + auditor_summary?days=N; card na aba
  Agentes com ranking e falhas do time. Idempotente por dia (days_done).
- Teste: 12/12 verde (fila de ontem, transcript, nota gravada, ranking com
  média/top_gaps, idempotência, poda).

## 131. ✅ 🎨 CRIATIVO PERPÉTUO (agente 'creative')
- Cron semanal seg 11:30 UTC (08:30 SP): acha os VENCEDORES por jornada REAL
  do banco (últimos 90d) — termos do Google (page_ads.utm_term) e anúncios do
  Meta (meta_ads.ad_name) ranqueados por cirurgias → compareceu → marcou →
  leads (vencedor exige >= 1 consulta marcada) — e gera N variações de copy
  por vencedor (sonnet/high) seguindo as REGRAS DE CRIATIVOS do Guilherme
  (1 frase/linha, gancho <=40 chars, rapport antes da oferta, sem "digite",
  sem promessa médica) + objeções reais do Mapa de Objeções nos ângulos.
- Fluxo: gera → tarefa "🎨 Criativos da semana prontos" → ele aprova/recusa
  na tela → APROVADAS entram no approved_log (cap 100) = despensa do Estúdio
  Criativo. Idempotente por semana (week_key = segunda SP).
- Estado em ai_config['creative_state'] (sem migration, with_lock).
- Endpoints: run_creative / creative_state / creative_review. Card na aba
  Agentes c/ jornada do vencedor + variações + copiar p/ Gerenciador.
- Teste: 13/13 verde (coleta c/ jornada completa, geração, idempotência
  semanal, aprovar/recusar/erros, despensa).

## 132. ✅ 📄 IMPORTAR PLANILHA DE FECHAMENTO (o sistema "entende" o .xlsx)
- Pedido 11/08: FECHAMENTO COMERCIAL.xlsx (26 abas mensais abr/24→jul/26,
  Status|Data|Paciente|Procedimento|Olho|valor total) entrando no sistema com
  leads atualizados na coluna Cirurgia Realizada COM VALOR E DATA REAIS.
- Crm::ClosingSheetReader: parser xlsx SEM gem nova (binário unzip da imagem
  + Nokogiri; IO.popen com array = sem shell), acha o cabeçalho por aliases,
  ignora duplicadas/canceladas/sem valor/linhas de total, datas em texto
  dd/mm/aaaa E serial do Excel. TESTE COM O ARQUIVO REAL: 25 abas, 877
  cirurgias válidas, R$ 3.675.205, 851 com data (166 pulos corretos).
- Casamento por NOME (normalizado sem acento/caixa/pontuação): 1 contato =
  casa; homônimos = ambíguo (fica de fora); não existe = opção CRIAR o
  paciente (additional_attributes.origem=planilha_fechamento, sem telefone).
- RETRODATAÇÃO: o StageLog recém-criado e o stage_moved_at recebem a data
  real da cirurgia → funis/PRO MAX/faturamento contam no MÊS CERTO (job não
  toca em log antigo; automações continuam sem disparar; valor por
  update_column como antes). Formato antigo [contact_id, valor] segue aceito.
- Fluxo: upload → preview_sheet (linhas em cache 2h por token) → prévia
  (meses, total R$, casados/criar/ambíguos/já na coluna/ignoradas) →
  apply_sheet recasa no servidor → ExternalSurgeryJob. UI dentro do card
  Cirurgias feitas fora (Tratamento de dados). Teste pipeline: 10/10 verde
  (casamento com acento/caixa, retrodatação 2024/2026, criação, etiqueta).

## 133. ✅ RODADA DE REFINO 11/08 (pedidos do Guilherme)
- ↩️ BOTÃO DESFAZER da importação: ExternalSurgeryJob grava RECIBO da última
  importação (agenda_config['surgery_import_undo']: prev_stage/prev_value/
  prev_stage_moved_at/log criado/contato criado, cap 5000) →
  ExternalSurgeryUndoJob reverte tudo (cards voltam, logs do import apagados,
  pacientes criados removidos, etiqueta removida) e limpa o recibo. Endpoints
  import_status/undo_last + banner âmbar na tela. Teste 9/9 verde.
- 🗂️ COLHEITADEIRA modo ORGANIZE (novo PADRÃO): em vez de enviar, etiqueta os
  aprovados como oportunidade_AAAA_MM (lista de trabalho no CRM via etiqueta);
  modo 'send' (mensagem modelo + teto) continua disponível. Nota: o envio JÁ
  era por mensagem modelo (dúvida dele respondida), mas organize é mais
  seguro como padrão. Config agents.harvest.mode. Teste verde.
- 🗃️ AGENTES POR CATEGORIA (16 agentes): aba Agentes agrupada em Atendimento /
  Vendas / Marketing / Gestão (AGENT_GROUPS).
- 💬 JANELINHAS DE CONVERSA (CRM + Radar): barra de ações com ETIQUETAS
  (add/remover) e MOVER COLUNA sem sair da janelinha.

## Estado/deploy da rodada 10/08
- SEM migrations. Crons novos (crm_harvest_job + crm_auto_manager_job +
  crm_conversation_auditor_job + crm_creative_job) → reimplantar SIDEKIQ
  junto do web. schedule_spec verde (22 crons, 0 duplicados).
- Agentes novos nascem DESLIGADOS (opt-in): ligar em Automações → Agentes.
- Working tree segue carregando Meta Leads não commitado — separar no commit.
- AGUARDANDO "pode subir".

## 134. ✅ SAÍDA DA GABRIELA + GRÁFICOS LEGÍVEIS (pedidos 11/08 pós-deploy)
- NOMES REMOVIDOS DO CÓDIGO: painéis do Meu Painel sem "who" (só temas
  Agendamento/Condução/Cirurgias), placeholders das predefinições por TEMA,
  prompt padrão do Analista ("encaminhar para a responsável pelo agendamento"
  em vez de Vaneide), comentários e exemplo do Financeiro. Zero ocorrências.
- DADOS DE PRODUÇÃO: script de console entregue ao Guilherme (prévia → apply)
  que renomeia as predefinições (Vaneide→Agendamento, Elizangela→Consultas,
  Gabriela→Cirurgias) e TRANSFERE tudo da Gabriela p/ Elizangela:
  attendance_owners, painel atribuído, dona de coluna (task_owner_id),
  vigias do Radar, cards e tarefas abertas, metas com responsável.
  ⚠️ rodar o script ANTES de remover a Gabriela dos agentes.
- GRÁFICOS DE PERÍODO LONGO: balde MENSAL acima de ~13 meses (conversas ao
  longo do tempo + faturamento por caixa, rótulos pt jan/25) + APARA os
  meses vazios da esquerda (era pré-sistema não espreme mais o gráfico).
  Testes: 6/6 verde. Sem migration, sem cron novo.
- AGUARDANDO "pode subir".

## 135. ✅ FILTRO "MOVIDOS" NO BOARD DO CRM (pedido 20/08)
- Problema relatado: filtrando julho, "Consulta Confirmada" mostrava paciente
  confirmado em agosto (lead de julho) e de outros meses. Não era bug do
  filtro: "Ativos" casa por atividade OU chegada OU movimentação — o que
  faltava era um modo que respondesse "quem ENTROU NESTA COLUNA no período".
- Alternador do período com 3 modos e NOMENCLATURA que o Guilherme escolheu
  (20/08) — rótulo "Mostrar quem:" + CHEGOU (contacts.created_at) ×
  ENTROU AQUI (novo: entrou na coluna atual — COALESCE(stage_moved_at,
  created_at)) × CONVERSOU (atividade, padrão; internamente segue
  activity/created/moved). "Consulta Confirmada · julho · Entrou aqui" =
  confirmou EM julho.
- Backend: date_mode=moved no period_scope (contacts_controller) — vale pro
  board (scope=period) E pro "Carregar mais" (scope=stage_page, herda).
  Front: 3 botões (Chegou dourado · Entrou aqui azul · Conversou verde) c/
  rótulo "Mostrar quem:", tooltips e frase da faixa por modo, localStorage
  cevico_crm_date_mode aceita 'moved'.
- NOTA DE USO: o card mora numa coluna só — quem confirmou em julho e já
  avançou pra Realizada aparece em Realizada (se o avanço foi no período),
  não em Confirmada. "Quem PASSOU por Confirmada em julho" = Funil de
  Tráfego (stage_logs), que já existe.
- Teste local ponta a ponta (conta 3, API real): card chegou-julho/confirmou-
  agosto some de julho·Movidos e aparece em agosto·Movidos + created;
  card chegou-junho/confirmou-julho aparece em julho·Movidos e some de
  julho·Novos. Vite compila; rubocop sem ocorrência nova; rastro limpo.
  Sem migration, sem cron novo. Working tree junto com a 134.
- AGUARDANDO "pode subir".

## 136. ✅ MEU PAINEL REPAGINADO + RESPONSÁVEL POR PAINEL + PRESETS NOVOS (pedidos 20/08)
- 🧑‍💼 RESPONSÁVEL POR PAINEL: ambiente novo Configurações → Painéis (só
  admin, padrão da tela Domínio): botões em linha p/ escolher quem responde
  por Agendamento/Condução/Cirurgias — o 1º nome volta às pílulas do Meu
  Painel ("Cirurgias · Elizangela"). Persistência agenda_config.panel_owners
  ({painel=>user_id}, sanitizado: só os 3 painéis, ids válidos), exposto no
  settings_json/update_agenda como {painel=>{user_id,name}} (nome resolvido
  no servidor). Substitui os nomes fixos que a 134 removeu do código —
  trocou a pessoa, troca na tela. Médicos/Gestor ficam sem responsável.
- ⏱ META DE TEMPO DE ATENDIMENTO saiu do Meu Painel → agora mora no
  Dashboard dos Agentes (Relatórios), entre o Radar e o desempenho por
  pessoa. Métodos extraídos p/ concern Crm::ResponseGoal (home continua
  SERVINDO response_goal no payload porque os widgets do Construtor bebem
  dele — só a tela do Meu Painel deixou de mostrar).
- 📆 PRESETS "SEMANA PASSADA" e "MÊS PASSADO" em TODO lugar: PeriodRuler
  padrão (todos os dashboards), Crm::ResolvesPeriod (last_week/last_month
  no servidor), board do CRM (DATE_PRESETS + ranges no cliente) e Meu
  Painel (goal_factor/record_period_key/record_basis/agenda_until tratam
  last_week; last_month já existia como legado).
- 📅 DASHBOARD DA AGENDA EMBUTIDO no Meu Painel, em TODAS as predefinições
  (agendamento/condução/cirurgias/médicos/gestor/custom): miolo extraído p/
  components-next/cevico/AgendaDashboardCore.vue (recebe period por prop);
  a página de Relatórios virou casca (header+régua+core). No Meu Painel o
  card "Dashboard da Agenda" segue o período da régua e tem botão
  "Relatório completo"; a SAÚDE DA AGENDA fica logo abaixo dele.
- Teste local conta 3 via API real: panel_owners salva/devolve nomes e
  REJEITA chave inválida (gestor) e valor nulo; home preset last_week/
  last_month resolve (jul=21 leads reais); agents_dashboard devolve
  response_goal (2 atendentes); agenda_dashboard last_month = 10 consultas.
  Vite compila tudo (7 arquivos). Sem migration, sem cron novo.
- AGUARDANDO "pode subir" (junto das rodadas 134+135).

## 137. ✅ 🛡️ IMPORTAÇÃO NÃO VOLTA QUEM JÁ AVANÇOU (pedido 20/08, pré-import)
- Antes de importar a planilha em produção, o Guilherme pediu: quem já está
  no Pós Operatório não pode ser "atualizado" — e o job de fato puxaria o
  card DE VOLTA pra Cirurgia Realizada.
- ExternalSurgeryJob.place_in_stage: card numa coluna com position MAIOR
  que a coluna-alvo (mesma pipeline) devolve :ahead → preservado por
  completo (não move, não retrodata, não mexe em valor, não etiqueta, fora
  do recibo do Desfazer). Vale pros DOIS caminhos (telefones colados e
  planilha). Contador "preservados" no log do job.
- Prévias (telefones + planilha) ganharam ahead_of_target (helper
  ahead_of_target_count via join crm_stages.position) e a tela mostra a
  linha verde "🛡️ N já estão ADIANTE — ficam exatamente como estão".
- Teste conta 3: card no Pós Operatório ficou intocado (coluna/valor/data/
  sem etiqueta) com o job tentando 9999; card no Agendamento moveu c/ valor
  2800 + retrodata 10/07 + etiqueta; recibo só com 1 entrada; prévia via
  API = 2 casados · 1 já na coluna · 1 adiante. Sem migration, sem cron.
- ⚠️ IMPORTANTE: importar a planilha SÓ DEPOIS desta rodada no ar (job roda
  no SIDEKIQ — implantar web+sidekiq juntos).
- AGUARDANDO "pode subir".

## 138. ✅ INÍCIO DO FUNIL DETALHADO + "MEU DESEMPENHO" (pedidos 20/08 noite)
- CARD 1 Novos contatos: total + quebra POR CAIXA embaixo ("Google 14 ·
  Instagram 10") — leads_by_inbox via caixas de captação do LeadsUniverse.
- CARD 2 Consultas agendadas: + TEMPO DE DECISÃO (dias entre o lead chegar
  e agendar): média + faixas no dia/1d/2-7d/8d+ (decision_time via
  booked_scope × contacts.created_at).
- CARD 3 virou "AGENDAMENTOS HOJE": número e COR = total do dia julgado
  contra a fatia diária da meta oficial (Painel de Metas ÷ dias do mês);
  embaixo as coortes "chegaram hoje: X de N (%)" e "chegaram ontem" —
  a taxa madura. booking_cohorts fixas hoje/ontem no servidor.
- 🎯 BLOCO "MEU DESEMPENHO" em todos os painéis do Meu Painel (decisões
  dele 20/08: EU + ATENDIMENTO IA, SEM ranking de colegas; nota do Auditor
  NÃO aparece — segue só com o gestor): conversas, mensagens, resposta
  média COMERCIAL 08-17h vs meta (+% na meta), 1ª resposta, resolvidas,
  consultas agendadas, cirurgias fechadas c/ R$ (assignee em Cirurgia
  Realizada por stage_moved_at), Radar respondidos + tempo, jornada (1ª/
  última msg + maiores pausas) e 🌙 DIAS FORA DO HORÁRIO (fds ou <8h/≥17h,
  chips c/ os dias); VOCÊ×VOCÊ: setinhas ▲▼ vs período anterior de mesmo
  tamanho (my_previous_snapshot).
- Backend: concern Crm::AgentPerformance (agents_rows/workday_stats/
  radar_stats extraídos do Dashboard dos Agentes, agora c/ filtro user_ids)
  + response_goal_rows(user_ids:) + my_performance_json no home.
  ATENDIMENTO IA = agenda_config.ai_user_id, configurado na seção nova 🤖
  de Configurações → Painéis (o robô responde pelo login escolhido).
- Teste conta 3 API real: leads_by_inbox 2 caixas; decision_time jul (23d);
  cohorts hoje/ontem; my_performance me+ai c/ previous real (17 msgs jul);
  agents_dashboard intacto pós-refactor (Guilherme 17 · Atendente 8).
  Sem migration, sem cron novo.
- AGUARDANDO "pode subir" (junto da 137).

## 139. ✅ "MEU DESEMPENHO" POR FUNÇÃO — métricas propostas pelo admin (20/08)
- Pedido: cada pessoa tem um papel (Elizangela agenda CIRURGIAS, Natália
  confirma consultas e cuida do COMPARECIMENTO) → o bloco "Meu desempenho"
  precisa de métricas POR PESSOA, propostas pelo Guilherme.
- CATÁLOGO de 11 métricas individuais (Crm::AgentPerformance::METRIC_KEYS):
  touched (conversas em que ATUOU, independente de atribuição — novo),
  assigned, messages, reply_commercial (08-17h + % na meta), first_response,
  resolved, appointments, surgeries_created (cirurgias agendadas POR ELA —
  novo, tasks cirurgia por creator), surgeries_closed (+R$), attendance
  (comparecimento da clínica no período — novo, p/ quem confirma) e
  days_worked (dias trabalhados). Padrão sem config: touched +
  reply_commercial + days_worked + resolved + appointments +
  surgeries_closed.
- CONFIG: Configurações → Painéis, seção "🎯 Métricas do Meu desempenho":
  escolhe a pessoa → chips liga/desliga (1º clique parte do padrão; botão
  "voltar ao padrão"; nunca zera). agenda_config.performance_metrics
  {user_id=>[chaves]}, sanitizado (só usuários da conta + chaves do
  catálogo). Payload my_performance ganhou metrics por pessoa + clinic
  (comparecimento) + previous.conversations_touched.
- Front: tiles do bloco montados pelo catálogo (perfTilesFor) — setinhas
  você×você continuam onde há base (touched/messages/resolved/appointments/
  reply). AI usa a config do próprio login.
- Teste conta 3 API real: config salva c/ sanitização (user 99 e chave
  inválida descartados), me c/ 5 métricas escolhidas (touched 2 · cirurgias
  agendadas 5 · 4 dias · comparecimento 100%), previous.touched ok.
  Sem migration, sem cron novo.
- + CONVERSÃO POR CAIXA no card 1 (pergunta dele 20/08): leads_by_inbox
  ganhou booked/rate (universo da caixa × avançou até Agendamento) e o card
  mostra a 2ª linha "agendaram: Google 50% · Instagram 87,5%" — agora o
  card compara VOLUME e QUALIDADE de cada porta de entrada. Testado julho
  local (Google 14→7 · Insta 8→7).
- AGUARDANDO "pode subir" (junto de 137+138).

## 140. ✅ CARDS MACRO + POPUP DE DETALHES + PALETA POR PAINEL + EQUIPE NO GESTOR (feedback 20/08 com print de produção)
- Problema: as linhas extras dos cards (conversão por caixa, decisão, coortes)
  ficavam TRUNCADAS. Solução dele: card mostra só o MACRO; botão 🔍 (canto do
  card) abre POPUP com as linhas completas + "como é calculado" (about).
  Tiles ganharam details[] + about; modal Teleport com cabeçalho na cor do
  card. Visível: card 1 = total + leads POR CAIXA (ele quis manter); card 2
  = total + "registradas no período"; card 3 "Agendamentos hoje" = número +
  chip + "hoje X% · ontem Y% agendaram" (as TAXAS que faltavam); card 4 =
  igual. Conversão por caixa, decisão média/faixas, coortes completas e
  taxa do período foram pro popup.
- 🎨 PALETA (recomendação adotada): uma FAMÍLIA de cor por painel em degraus
  escuro→claro (agendamento azul-marinho, condução teal, cirurgias vinho,
  médicos céu, gestor marinho+ouro) e a cor SEMÂNTICA (verde/âmbar/vermelho)
  só no card JULGADO (chip de veredito / status de meta) — acabou o
  arco-íris, o olho vai no que importa. OPÇÃO ADMIN "separar os temas":
  Configurações → Painéis → "Cores de cada painel": Padrão ou um tema CEVICO
  (Santorini, Flor del Mar, Flamingo, Caribe, Aloe Vera) por painel;
  agenda_config.panel_themes sanitizado (5 painéis, chave [a-z_]).
  Painéis do Construtor mantêm a paleta própria.
- 👥 GESTOR: bloco vira "Desempenho da equipe" — todas as pessoas que
  trabalharam no período (team_performance_rows em lote: agents_rows +
  comercial + fora do horário + cirurgias + métricas propostas de cada um),
  robô marcado 🤖; grade 3 colunas. Só admin e só no painel gestor.
- Teste conta 3: panel_themes salva e descarta painel inválido/valor sujo;
  team do gestor = 2 pessoas c/ configs próprias e is_ai; agendamento sem
  team. Vite compila. Sem migration, sem cron.
- LEMBRETE p/ ele: o chip "defina a meta no Painel de Metas" some quando a
  meta mensal de consultas agendadas existir — é ela que colore o card 3.
- AGUARDANDO "pode subir".

## 141. ✅ GRÁFICOS NOS POPUPS + BOTÃO "+" DE INDICADORES (prontos, FÓRMULAS, histórico, cor) (pedido 21/08)
- 🧺 CESTO DE INDICADORES: Crm::KpiBagService + GET crm/home/kpis
  (preset/from/to): ~19 números-base do período c/ SÉRIE (dia ≤45d,
  semana ≤400d, mês) e PERÍODO ANTERIOR de mesmo tamanho — leads
  (LeadsUniverse), conversas novas, consultas agendadas/presença/faltas,
  cirurgias agendadas/realizadas (Agenda), "Entrou em <cada coluna>" e
  faturamento (stage_logs, mesma fonte do PRO MAX). Totais batem c/ séries.
- 📊 POPUP COM GRÁFICO: MiniBars.vue (SVG, sem lib — barras do período,
  maior barra em destaque, linha tracejada = média do período anterior,
  rótulos nas pontas, tooltip nativo) + linha "▲ 24% vs 30/05–30/06 (17)".
  Cards fixos ganharam chartKey (leads, consultas, cirurgia agendada por
  nome da coluna); card 1 tem barras por caixa; card 3 barras comparativas
  hoje/ontem/período.
- ➕ CARD "NOVO INDICADOR" (admin, fim da fileira): construtor em popup —
  nome; modo INDICADOR PRONTO (catálogo do cesto c/ valor ao vivo) ou
  FÓRMULA (textarea + chips que inserem a chave; + − × ÷ parênteses; %
  = ×100); formato Número/%/R$; "Aparece em" (todos ou 1 painel); COR
  (automática = degrau da família do painel, 4 degraus, 6 temas CEVICO,
  verde/ouro/vermelho, ou hex livre); nota; PRÉVIA VIVA no cabeçalho
  (valor + variação vs anterior). Editar/Remover pelo popup do card.
  Persistência agenda_config.custom_kpis (≤40, sanitizado: expr só
  [a-z0-9_+-*/(). ], formato/painel/ícone validados).
- 🔒 helper/cevicoFormula.js: avaliador SEGURO (tokenizer + shunting-yard,
  sem eval) — 9/9 no teste: math certa, "alert(1)", "x; drop", chave
  desconhecida, divisão por zero e parêntese aberto → null ("—").
- Card-fórmula no painel: valor, "▲/▼ x% vs período anterior", série
  balde a balde da fórmula no popup, histórico = mesmo cesto.
- Testado VISUALMENTE no local (usuário temporário criado/removido, sessão
  via API): popup do card 1 c/ gráfico diário + barras por caixa + 24% vs
  anterior; construtor criou "Ticket médio por cirurgia" = revenue /
  appointments_booked → R$ 3.610 em ouro; "Taxa de agendamento" = 38,1%.
  Sem migration, sem cron. ⚠️ routes.rb ficou MISTO c/ Meta Leads (rota
  get :kpis) — separar no commit como settings_controller/api.
- AGUARDANDO "pode subir" (junto da 140).

## 142. ✅ ORGANIZAR A FILEIRA DE INDICADORES — arrasto magnético + ocultar (pedido 23/08)
- Pedido: remover indicadores e ajustar posições (lado/cima/baixo) com
  drag and drop "magnético" como nas colunas; existe uma ordem padrão e o
  admin reorganiza.
- Botão "⠿ Organizar" (junto do "+", admin): cards ganham anel tracejado,
  cursor de arrasto e ✕ no cabeçalho; arrasto via vuedraggable (mesmo das
  colunas do CRM, animation 220, ghost) na grade 4 colunas — soltar salva a
  ORDEM; ✕ OCULTA (qualquer card, fixo ou do "+"); bandeja "ocultos: + Nome"
  restaura em 1 clique; "voltar à ordem padrão" zera. "✓ Pronto" sai do modo.
- IDs ESTÁVEIS por card: gk do indicador (new_leads…), slug do nome
  (agendamentos_hoje) ou "kpi:<id>" dos cards do "+" — por painel.
  Persistência agenda_config.kpi_layout {painel => {order[], hidden[]}}
  (sanitizado, ≤40 ids de ≤40 chars, só os 5 painéis). Vale pra TODO MUNDO
  que vê o painel (ordem padrão do sistema quando vazio; card novo entra no
  fim); painéis do Construtor ficam fora.
- 🐛 LIÇÃO NOVA (2 horas de caça): watch(computedX) no setup AVALIA o getter
  na hora pra rastrear dependências — se o computed toca numa const
  declarada mais abaixo no <script setup> dá TDZ e o computed fica
  "envenenado" com undefined (erros "reading 'filter'" em cascata, página
  branca). Solução: registrar o watch DENTRO do onMounted (ou declarar tudo
  antes). Também: import novo (vuedraggable) no Meu Painel fez o Vite
  reotimizar deps → reiniciar o container vite resolve os 404 de chunk.
- Testado VISUALMENTE (usuário temporário removido): ocultar → bandeja;
  arrasto "Taxa de agendamento" → 1º card; kpi_layout salvo no servidor
  com a ordem e o oculto; reset deixou o local limpo.
- AGUARDANDO "pode subir" (junto de 140+141).
- + ESTENDIDO A TODOS OS PAINÉIS (23/08): cards fixos de Condução, Cirurgias,
  Médicos e Gestor ganharam chartKey/compare/details/about → popup c/ gráfico
  do período (consultas pela data, presenças, indicações, cirurgias
  agendadas/realizadas), barras comparativas (compareceram×faltaram,
  indicações×agendadas×realizadas, com×sem indicação, leads×avançaram) e
  texto "como é calculado". Cesto ganhou appointments_due, indications e
  surgeries_missed (23 métricas). "+", Organizar e paleta já valiam em todos.
  Médicos: número é do médico, gráfico é da clínica (nota no popup).

## 143. ✅ CUSTOMIZAÇÃO TOTAL DO MEU PAINEL (pedidos 23/08 c/ print do % de agendamento)
- Pedidos dele: (a) editar a COR de qualquer card num modo edição; (b)
  indicadores prontos JÁ FORMULADOS (taxas importantes) separados por
  categoria; (c) o "% de agendamento" do print em evidência perto dos
  primeiros indicadores; (d) TODOS os blocos do Meu Painel móveis com o
  arrasto magnético. Tema da rodada: "possibilidade de customização".
- 🎨 COR POR CARD: no modo "⠿ Organizar", cada card ganha o pincel 🖌 ao
  lado do ✕ → popup com "automática" + palheta (4 degraus da família do
  painel, temas CEVICO, verde/ouro/vermelho, hex livre). A cor vale pra
  todo mundo que vê o painel; o julgamento de meta (vermelho/âmbar/verde)
  continua por cima da cor escolhida (semântica preservada). Persistência
  em agenda_config.kpi_layout[painel].colors {id => grad}, sanitizada no
  servidor (sanitize_kpi_colors: só chars de cor/gradiente, nada escapa do
  style). "voltar ao padrão" agora limpa ordem+ocultos+cores+blocos.
- 📚 INDICADORES FORMULADOS POR CATEGORIA: o modo "Indicador pronto" do
  construtor "+" abre com TAXAS PRONTAS por categoria — 🎯 Taxas do funil
  (taxa de agendamento, comparecimento, taxa de indicação, fechamento,
  lead→cirurgia), 💰 Financeiro (ticket médio por cirurgia, faturamento
  por lead/por consulta), 📅 Agenda (faltas %, realização, cirurgias
  perdidas %) — cada uma com valor AO VIVO do período; 1 clique preenche
  nome/fórmula/formato/nota. Os números-base do cesto também ganharam
  categorias (👥 Chegada · 📅 Consultas · 🔪 Cirurgias · 🧭 Funil · 💰).
  Catálogo READY_FORMULAS no frontend (sem backend novo).
- 🌟 % DE AGENDAMENTO EM EVIDÊNCIA: o card da linha compacta da Saúde da
  Agenda foi PROMOVIDO pra fileira principal do painel Agendamento (id
  booking_rate_30, 2º card por padrão): 77,8% grande, chip julgado pela
  referência (15% muito bom · 10% bom · 5% fraco), sub "X consultas ÷ Y
  leads · 30 dias", popup c/ barras leads×consultas 30d + fórmula +
  referência + "como é calculado". Fixo em 30 dias (não segue a régua)
  pra taxa ser madura. A linha compacta da Saúde da Agenda saiu (evitar
  duplicata). Como é card da fileira: dá pra mover, ocultar e colorir.
- ⠿ TODOS OS BLOCOS MÓVEIS: no modo Organizar, CADA bloco do Meu Painel
  ganha barrinha "⠿ nome do bloco" e anel tracejado — WhatsApp, Briefing,
  Radar, Tarefas, Feedback da semana (área de AVISOS, acima do seletor) e
  Indicadores, Meu desempenho, Dashboard da Agenda, Saúde da Agenda,
  Metas·Rotinas·Ferramentas, Acesso rápido, Termômetro (área de CONTEÚDO)
  — vuedraggable com group compartilhado: dá pra reordenar E cruzar bloco
  de uma área pra outra. Bloco sem conteúdo no momento aparece só como
  barrinha (dá pra mover mesmo assim). Persistência em
  agenda_config.block_layout {painel => {top: [], main: []}} (sanitizado,
  só os 5 painéis fixos); vale pra todo mundo; bloco novo do sistema entra
  no lugar padrão. Seletor de painel + régua + veredito do gestor +
  grade do Construtor ficam fixos.
- ✏️ REFINO "MODO EDIÇÃO" (feedback dele 23/08: "a ideia é essa mas não
  está funcionando muito bem — botão no topo, estável e funcional"):
  (1) botão "✏️ Modo edição" AGORA NO TOPO, no cartão de boas-vindas ao
  lado de "Reportar problema" (admin; vira "✓ Concluir edição") — saiu do
  card do "+" onde ficava escondido e pulava de lugar; (2) BARRA GRUDADA
  (sticky top-0) enquanto o modo está ativo: dicas, "salva sozinho",
  cards ocultos restauráveis, "voltar ao padrão" e "✓ Concluir" sempre à
  vista em qualquer rolagem (a bandeja antiga sob a fileira saiu);
  (3) blocos RECOLHEM em barrinhas compactas no modo edição (só a fileira
  de indicadores fica aberta, que é onde se edita card) — arrasto curto e
  preciso, sem rolagem infinita no meio do movimento; (4) AUTO-REFRESH DE
  2min PAUSA durante a edição (um refresh no meio do arrasto trocava as
  listas do vuedraggable e quebrava o movimento — causa real da
  instabilidade); ao concluir, refreshAll() busca o que ficou preso;
  (5) SEM CRUZAR DE ÁREA: cada área (avisos × conteúdo) só aceita os seus
  blocos (groups separados no vuedraggable) — cruzar deixava a barrinha
  sem conteúdo na outra área (o template do bloco só existe na área dele);
  orderedBlocks agora filtra por área e SE AUTO-CORRIGE se o banco tiver
  bloco na área errada (dado antigo).
- Testado visualmente no local (conta 3, admin): botão do topo liga/desliga
  (label muda); barra sticky segue a rolagem; blocos viram barrinhas;
  arrasto "Indicadores do período" do fim pro meio da área → block_layout
  salvo E auto-corrigido (indicadores tinha ido parar no top por dado de
  teste antigo — voltou pro main sozinho); pincel no card % de agendamento
  → dourado aplicado e salvo (kpi_layout.colors confirmado no banco);
  construtor com taxas prontas → "Taxa de agendamento" preencheu tudo e
  mostrou prévia 16,3% (Este ano); popup do card promovido c/ cabeçalho na
  cor escolhida; Concluir → blocos reabrem na ordem nova. update_agenda 200
  em todos os saves. Sem migration, sem cron. routes.rb não mudou nesta
  rodada; settings_controller/api crm.js seguem MISTOS c/ Meta Leads
  (separar no commit como sempre). Nota local: crm/home demora ~10s no
  dev porque o health do WhatsApp bate na Meta c/ token inválido —
  pré-existente, não é desta rodada.
- PRÓXIMO combinado da conversa: rodada de SEGURANÇA (hardening contra
  invasão) depois desta.
- AGUARDANDO "pode subir".

## 144. ✅ POPUP DOS INDICADORES v2 — análise, não só número (aprovado 23/08: "vamos avançar neste sentido")
- Minha proposta aceita por ele: mini-régua no popup, período anterior
  sobreposto, linha de meta, decomposição das taxas, ações da empresa no
  gráfico e tooltip próprio. ("Ver na barra → lista" e modo "ver tudo" +
  diagnóstico por IA ficaram pra rodada futura.)
- 🧺 BACKEND (Crm::KpiBagService): cada métrica ganhou prev_series (série
  do período ANTERIOR balde a balde, baldes próprios em prev_points) e o
  serviço aceita granularity forçada (day/week/month, validada; sem ela
  vale o automático). GET home/kpis repassa params[:granularity].
  bucket_keys parametrizado (since/until). Sem migration, sem cron.
- 📊 MiniBars v2: série anterior como LINHA tracejada balde a balde
  (substitui a média reta quando existe), linha de META pontilhada OURO,
  marcadores 📌 (linha vertical + bolinha no balde da ação) e TOOLTIP
  PRÓPRIO (hover no mouse, toque no celular — pointerdown só age no touch,
  senão o clique desmarcava o hover; box com rótulo, valor, anterior c/
  ▲/▼ e o título da ação 📌). Área de toque = balde inteiro.
- 🎛 MINI-RÉGUA DO POPUP: chips "Régua de cima · 7 dias · Este mês · Este
  ano" + balde "Auto · Dia · Semana · Mês" — muda só o gráfico do popup
  (cesto próprio kpiModalBag), a régua da página fica intacta; delta "▲/▼
  vs anterior" recalculado pro recorte (deltaLine ganhou o bag como parâm).
- ⭑ LINHA DE META: fatia da meta MENSAL oficial pela granularidade
  (dia = meta÷dias do mês; semana = ×7; mês = inteira) nos cards de
  contagem c/ meta definida (gk em OFFICIAL_GK, não-% só).
- 🧩 DECOMPOSIÇÃO ("de onde vem"): cards de FÓRMULA mostram as séries das
  variáveis da conta (variablesIn, até 3); cards fixos de taxa ganharam
  components[] (Comparecimento = presenças×faltas; Taxa de fechamento e
  Fechamento de cirurgias = indicações×agendadas; Taxa de agendamento
  gestor = leads×consultas) — mini-gráficos c/ série anterior junto.
- 📌 AÇÕES DA EMPRESA (company_actions do PRO MAX, já no settings payload):
  mapeadas pro balde certo (dia exato / semana / mês) e plotadas em
  qualquer indicador com série — conecta causa e efeito fora do estúdio.
- Testado visualmente no local (conta 3, régua Este ano): popup "Novos
  contatos" por semana c/ linha fantasma + 📌 da ação semeada (10/08);
  recorte "Este mês" → por dia, curva fantasma do mês anterior dia a dia,
  delta "▼ 88% vs 08/07–31/07" recalculado; tooltip no balde 10/08 =
  "10/08 · 0 · anterior: 0 · 📌 Campanha refrativa nova no ar"; card de
  fórmula "Taxa de agendamento" → decomposição c/ consultas (8) × leads
  (49). Rubocop: só ParameterLists nova → disable inline no método (já
  tinha AbcSize/MethodLength). kpis 200 em todos os recortes.
- AGUARDANDO "pode subir" (junto da 143).

## 145. ✅ DASHBOARD CRM — do número pra AÇÃO (aprovado 23/08: "vamos neste sentido")
- Minha proposta aceita (itens 1+2+3 da análise): tecnologia 143/144 nos
  KPIs, dinheiro parado no funil com atalho pro board, perdas com valor/
  tendência/lista de resgate. (Coortes por safra, comparar períodos,
  semáforo de desvios, custo por resultado e índice/lazy ficaram pra
  rodadas futuras.)
- 🔍 KPIs CLICÁVEIS: componente NOVO reutilizável
  components-next/cevico/KpiDetailPopup.vue — o motor do popup 144
  empacotado (busca o próprio cesto no período da tela, mini-régua "Régua
  da tela · 7d · mês · ano" + balde, MiniBars v2 c/ série fantasma, linha
  de meta via goalTarget, 📌 company_actions, decomposição via
  components[], details/about). No Dashboard CRM: "Novas no período"
  (new_leads + meta), "Valor fechado" (revenue, nota honesta de que card =
  coorte e gráfico = registrado), "Fechamentos" (match "cirurgia agendada"
  + meta + indicações) e "Taxa de fechamento" (match + leads/indicações).
  "Total no funil" e "Tempo médio" ficam sem popup (não têm série).
  ⚠️ InicioPage mantém a implementação própria do 144 — unificar no
  componente é refino futuro.
- 💰 DINHEIRO PARADO: value_by_stage ganhou count/stalled_count/
  stalled_value (cards c/ COALESCE(stage_moved_at, created_at) > 15 dias —
  STALLED_AFTER_DAYS). Banner dourado antes do bloco Funil: "R$ X parados
  em <coluna> · N pacientes há mais de 15 dias" + "Ver no board →" →
  crm_board?focus_stage=<id>. O board: aplica o período "Este ano" (a
  janela padrão de 7d esconderia os parados), rola até a coluna
  (data-stage-id no KanbanColumn via fallthrough, tentativas até as
  colunas montarem + reforço 1,5s contra reset de re-render) e dá o brilho
  .cevico-stage-flash (style global no CrmBoard). Colunas
  realizada/pós/sem indicação ficam fora do aviso (dinheiro lá não está
  "parado").
- 🟥 PERDAS v2: payload novo `losses` (build_losses): por etiqueta perda_*
  → count, prev (período anterior de mesmo tamanho), value (SÓ dos cards
  c/ valor preenchido — sem estimativa inventada) e value_count; bloco
  próprio, não disputa o top-12 do by_label. Na tela: ▲/▼ vs anterior
  (perda subir = vermelho), "% dos leads" (sobre kpis.cohort_total), R$
  por motivo e total no header. Linha clicável → 🛟 LISTA DE RESGATE:
  GET pipelines/:id/dashboard/loss_contacts?label=perda_* (rota nova em
  routes.rb; respeita período + filtro de caixa; até 100, ordem por valor)
  → modal c/ nome/telefone/coluna/dias parado/valor, clique abre o Espaço
  do Paciente; dica da Colheitadeira/Tratamento como próximo passo.
- Testado visualmente no local (conta 3, Este mês): popup "Fechamentos" c/
  fantasma + 📌 + decomposição de indicações; banner "R$ 3.200 parados em
  Cirurgia Agendada" → Ver no board abriu Este ano, rolou até a coluna
  (16 cards, R$ 113.790); perda_valor semeada na Gabriela Almeida (teste)
  → linha Valor ▲ · 33,3% dos leads · R$ 4.800 → lista de resgate c/ "37d
  parado". Rubocop: disables inline só nos métodos novos (o arquivo já
  tinha 79 ofensas pré-existentes). Sem migration, sem cron. ⚠️ routes.rb
  MEXIDO nesta rodada (rota loss_contacts) — na hora do commit, separar
  do Meta Leads como sempre (routes/settings_controller/api crm.js).
- Seeds de teste deixados no local: ação "Campanha refrativa nova no ar"
  (10/08) e perda_valor na Gabriela Almeida teste (R$ 4.800).
- AGUARDANDO "pode subir" (junto da 143+144).

## 146. ✅ COMPARECIMENTO POR UNIDADE + CONSULTA DE 5 MIN (pedidos 26/08: "comparecimento é uma chave")
- Pedidos dele: (a) filtrar consultas agendadas e comparecimento por
  UNIDADE (Paulista × Tatuapé); (b) "abrir mais agenda" no Tatuapé:
  consulta de 5 min em vez de 15, ajustando os agentes; (c) ideias de
  automação pra subir a taxa de comparecimento.
- 🏥 POR UNIDADE: home_controller ganhou unit_breakdown(periodo) —
  group(:unit, :attendance) das consultas do período (tasks.unit) →
  by_unit: [{unit, label, consultations, attended, missed, show_rate}]
  nos painéis CONDUÇÃO e GESTOR (UNIT_LABELS = mesmos do AgendaSlots).
  Nos popups dos cards "Consultas no período" e "Comparecimento"
  (condução) + "Comparecimento" (gestor): seção "🏥 por unidade" com
  cartão por casa — chip semafórico (≥80% verde · ≥60% ouro · <60%
  vermelho), ✓ vieram / ✗ faltaram / sem conferência e barra da taxa.
  Teste local: Av. Paulista 94,1% × Tatuapé 57,1% lado a lado.
- ⏱ CONSULTA DE 5 MIN: a duração JÁ era por janela (windows[].block) e os
  prompts dos agentes JÁ nascem das janelas (Crm::AgendaSlots.free_slots
  → free_slots_text no prompt do Secretário/Atendente) — faltava só a
  OPÇÃO no editor: "5 min" adicionado ao seletor de blocos das Janelas
  dos médicos (AgendaBoard). Sanitizer do windows já aceita (permit
  :block). Teste ponta a ponta local: janelas do Tatuapé → 5 min →
  free_slots_text passou a oferecer "Tatuapé: 10:30, 10:35, 10:40…"
  enquanto Paulista segue 08:30, 08:45… — ou seja, os agentes se ajustam
  SOZINHOS, sem mexer em prompt.
- ⚠️ PÓS-DEPLOY (ELE): Agenda → Janelas dos médicos → Editar → janelas do
  Tatuapé → blocos de 5 min → Salvar. E ATENÇÃO: o Atendente IA do
  WhatsApp (N8N, externo) tem grade PRÓPRIA no prompt do supervisor —
  se ainda estiver com a grade de 15 min escrita, precisa ajustar lá no
  N8N também (o interno segue as janelas sozinho).
- 📦 N8N ENTREGUE (26/08): ele mandou o JSON do workflow (v19 em uso;
  Tatuapé estava em 10min nas janelas 5 e 7) → gerei os prompts prontos
  em ~/Downloads/TATUAPE 5MIN/ (SUPERVISOR systemMessage + CALENDAR_AGENT
  systemMessage c/ Tatuapé 5min: grade, exemplo de blocos, duração e
  "fim do evento = início + 5 min"; toolDescription e nodes do Google
  Calendar NÃO mudam — o fim do evento vem do prompt). LEIA-ME junto:
  2 colagens no N8N + teste real numa quarta no Tatuapé.
- Ideias de automação p/ comparecimento entregues na conversa (D-1/D-0,
  resgate no dia da falta, etiqueta risco_falta etc.) — viram itens
  quando ele escolher.
- Sem migration, sem cron. Testado local conta 3 (seeds Teste146
  paulista/tatuape deixados no banco local).
- ✅ SUBIDA 29/08 junto de 147+148 (develop; Meta Leads separado como sempre).
  Aguarda build verde → implantar WEB+SIDEKIQ (pula a 785fa58 — esta etiqueta
  carrega 140–148); reversão = 781aa6b.

## 147. ✅ 🕐 HORÁRIO DE ENVIO DO FOLLOW-UP CONFIGURÁVEL + MEU PAINEL SEM TRAVA DO WHATSAPP (pedidos 28/08)
- Pedido dele: "quero que ele envie mensagens durante a janela de 24h do
  dia, não quero que empilhe tudo pro dia seguinte" — controle mais
  preciso da cadência. (Contexto: o expediente fixo 08h–20h fazia etapa
  vencida à noite esperar as 08h e sair empilhada de manhã, às vezes já
  fora da janela de 24h do WhatsApp.)
- 🕐 EXPEDIENTE VIROU JANELA CONFIGURÁVEL por conta: Automações → Robôs →
  cartão "Horário de envio das cutucadas" (só admin): selects das/às +
  chips "Padrão 08h–20h" e "24 horas". Persistência
  agenda_config.followup_hours {start 0–23, end 1–24}, sanitizada no
  update_agenda (start >= end não salva; lixo cai no padrão — o robô nunca
  fica sem janela). FollowupBotJob.send_hours(account) cacheado por rodada;
  effective_overdue_hours passou a usar a janela da conta (etapa que vence
  fora espera a janela REABRIR — o atraso conta a partir dali, nada é
  descartado por vencer de madrugada). Com 0–24, o "empilhamento" some:
  cada etapa sai na hora certa. As demais travas (piso 30min, teto 4/dia,
  momento perdido 3h, 1 por rodada) continuam valendo.
- Rótulo "fora do expediente 08h–20h" da aba Robôs agora mostra a janela
  configurada. Aviso no cartão: texto simples só chega dentro da janela de
  24h do WhatsApp — madrugada/cadência em dias pede mensagem modelo.
- ⚡ MEU PAINEL DESTRAVADO: timeout de 5s no Whatsapp::HealthService
  (HTTParty sem timeout = Net::HTTP espera 60s+60s; quando a Meta
  demorava, o payload do crm/home inteiro ficava preso atrás do health —
  a 1ª carga a cada 10min de cache pagava o pato). Falha segue caindo no
  cache de 10 minutos do home_controller — errar rápido é barato.
- Testes: runner (sem config=8...20, 24h=0...24 cobre 3h, 07–22, inválida
  22→10 cai no padrão, overdue 2.0h certinho na janela 24h), HTTP na conta
  3 (salva 24h, GET devolve, inválida mantém a anterior, volta ao padrão)
  e VISUAL (cartão na aba Robôs, chip 24 horas → toast "liberadas 24 horas
  por dia" + banco confirmado, chip Padrão restaura). Sem migration, sem
  cron. Banco local deixado no padrão 08–20.
- ⚠️ settings_controller/api crm.js seguem MISTOS c/ Meta Leads — separar
  no commit como sempre.
- Na MESMA conversa (28/08): varredura do follow-up explicada (precisão
  ~2–4min, 5 travas) + diagnóstico do Secretário da Agenda "não pega todo
  mundo" — virou a RODADA 148 na sequência.
- ✅ SUBIDA 29/08 junto de 146+148 (mesmo commit; ver nota de deploy no 146).

## 148. ✅ 🎯 AGENDAMENTO 100% — Secretário v2 (releitura, reagendamento, cancelamento) (direção dele 28/08)
- Direção dele: "preciso favorecer que o agendamento fique redondo e 100%
  preciso, inclusive reagendamentos — a conferência da agenda depende
  disso; hoje o agente interno só 'duplica a agenda' do N8N". FUTURO
  ANOTADO (conversa grande a ter): CENTRALIZAÇÃO da operação no sistema,
  com agenda PRÓPRIA como fonte da verdade (aposentar o Google Calendar).
- CAUSA RAIZ corrigida: o Secretário lia a conversa UMA vez ("Entrou na
  coluna"), geralmente ANTES de dia/hora estarem confirmados → tarefa de
  revisão e a confirmação posterior nunca era lida.
- 🧠 Crm::AppointmentApplier NOVO — caminho ÚNICO do Secretário (usado
  pela automação de coluna E pela releitura): extrai → cria/REAGENDA/
  CANCELA/tarefa de revisão + nota privada + linha no registro. Trava
  MIN_GAP 2min (leituras quase simultâneas não gastam IA 2x).
  CrmAutomationFireJob#schedule_appointment virou delegação de 8 linhas.
- 👂 AUTOMAÇÃO-IRMÃ por coluna de atuação: sync_scheduler_stages e
  sync_agent_stages(scheduler) agora criam/removem JUNTO uma automação
  "Secretário da Agenda (mensagens)" (message_created incoming, delay 1min
  junta mensagens picadas, throttle 3min) — o card entra E cada mensagem
  do paciente na coluna redispara a leitura. Config ZERO pra ele: basta
  salvar as colunas de atuação (que ele já tem) — resincronizar 1x após o
  deploy pra criar as irmãs.
- 🔁 RELEITURA FORA DAS COLUNAS (CrmListener → Crm::SchedulerRecheckJob
  novo, wait 20s, throttle 10min/paciente): (a) quem tem tarefa
  "⚠️ Confirmar consulta"/"⚠️ Pediu cancelar" aberta → QUALQUER mensagem
  dele relê (é a confirmação chegando); (b) mensagem c/ remarcar/
  reagendar/desmarcar/cancelar/adiar/"mudar o horario"/etc (sem acento,
  RECHECK_TERMS) de quem TEM consulta futura → relê. Roda mesmo sem card.
- ❌ CANCELAMENTO: campo cancelamento no schema da extração (regra: SÓ
  sem novo horário; remarcou = reagendamento) → Recorder.cancel_future
  seta canceled_at na consulta futura + rastro na descrição + nota
  "CANCELADA a pedido do paciente"; sem consulta futura achada → tarefa
  "⚠️ Pediu cancelar/remarcar: nome" (pode estar só no Google Calendar).
- 🧾 ANTI-DUPLICATA da tarefa de revisão POR CONTATO (bug antigo: dedup
  por título — dois pacientes sem nome = "Paciente" e o 2º era pulado em
  silêncio; título exato agora só segura tarefas antigas sem contact_id).
- 👁 VISIBILIDADE: erro da IA e "sem dia/hora" (1ª detecção) agora entram
  no scheduler_log — outcomes novos canceled/cancel_no_match/erro c/
  rótulos no card do agente; banner do card reescrito (relê mensagens,
  cancela, releitura fora das colunas).
- Testes (extração STUBADA, sem IA): 15/15 ✅ — revisão+log, MIN_GAP,
  não-duplica, homônimo "Paciente" destravado, criação c/ nota,
  reagendamento sem duplicar, cancelamento c/ canceled_at+nota, cancelar
  sem consulta → tarefa, log c/ 5 desfechos, gatilhos do listener (a/b,
  acento, negativo, freio 10min); HTTP: sync cria/remove o PAR; visual:
  banner novo no card. Limpeza completa (contatos/tarefas/log de teste).
- Sem migration, sem cron. PÓS-DEPLOY (ELE): abrir o card do Secretário →
  Salvar colunas de atuação (recria e já cria as irmãs "mensagens").
- ⚠️ settings_controller segue MISTO c/ Meta Leads — separar no commit.
- ✅ SUBIDA 29/08 junto de 146+147 (mesmo commit; ver nota de deploy no 146).

# RODADA 01/09 — item 149 (formulários oficiais: link amigável + atrelamento por telefone)

## 149. ✅ 📋 FORMULÁRIOS: LINK LIMPO + IDENTIFICAÇÃO POR TELEFONE + AÇÃO "ENVIAR MENSAGEM MODELO" (pedidos 01/09)
- Pedidos dele: (a) o link do formulário tinha um token gigante e feio
  ("precisamos construir essa extensão do link de uma forma mais amigável
  pra enviar pro paciente"); (b) pedir o telefone pra "relacionar e atrelar
  o formulário ao card e deixar no ambiente do paciente" (aprovado:
  obrigatório nome + WhatsApp); (c) ação "Enviar mensagem modelo" no
  "O que fazer?" das automações de coluna (print da tela Nova automação).
  Contexto do uso: automação envia o link só pra quem JÁ decidiu agendar.
- 🔗 LINK LIMPO: rotas novas sem token (GET/POST /forms/:slug + POST
  /forms/:slug/track ANTES das rotas c/ :token — 'track' literal primeiro
  senão o Rails leria "track" como token). Editor ganhou campo "Endereço
  do link" (…/forms/ + slug editável; normalize_slug parameteriza
  "Avaliação Teste" → avaliacao-teste; validação só [a-z0-9-] c/ unicidade;
  em branco no criar = ensure_slug gera). form_json devolve short_link
  (Cevico::PublicSite.base_url — produção sai clinica.cevico.com.br) e a
  tela tem botão dourado "Copiar link do paciente" ao lado do de teste.
  Link ASSINADO continua funcionando (disparos automáticos personalizados
  pulam a identificação; token genérico antigo TAMBÉM pede identificação).
- 🙋 IDENTIFICAÇÃO: card novo (type 'identity') como 1º passo quando não
  há paciente no token — nome + WhatsApp obrigatórios (validação leve no
  JS, real no servidor: nome + 10-13 dígitos). No submit:
  resolve_identity_contact acha o paciente pelos últimos 8 dígitos +
  same_phone_line? do AppointmentRecorder (mesma máscara do resto do
  CEVICO); achou → resposta atrela ao contato (nome só COMPLETA cadastro
  sem nome); não achou → cria contato (E.164 +55) + card na coluna
  "AGENDAMENTO DE CONSULTA" (booking_stage por ILIKE, fallback 1ª coluna;
  origin 'formulario') — decisão dele 01/09. Corrida/duplicata → re-busca
  antes de 422. Erro de identidade → volta pro card c/ mensagem (não
  agradece em falso).
- 📨 AÇÃO "ENVIAR MENSAGEM MODELO" (send_template): ACTION_TYPES +
  despacho no CrmAutomationFireJob → TemplateSource leve (account/inbox/
  sender nil/template_params/message_preview) no Crm::SendTemplateService
  (o MESMO das Campanhas — cria conversa + mensagem c/ template_params,
  entrega via webhook). Trava anti-rajada: cooldown 7d POR automação/
  contato (additional_attributes.cevico_templates_sent, mesmo padrão do
  send_form). Modal: caixa WhatsApp → templates da Meta (mesmo
  fetchWhatsappTemplates das Campanhas) → variáveis {{n}} c/ prévia →
  save valida tudo preenchido; aviso da trava no card. FIX de quebra:
  resposta não-array do endpoint de templates (token inválido) quebrava o
  modal — coerção Array.isArray + aviso.
- 🛡️ THROTTLES Rack::Attack (da rodada de segurança, viraram requisito):
  cevico/form_submit 10/min por IP (POST /forms/* cria registros/paciente),
  cevico/public_beacons 90/min (track/ref/hub_ref) e cevico/builder 6/min
  (construtor gasta IA). Rack::Attack já vem ligado em produção.
- Testes: runner 7/7 (slug normaliza, short_link, send_template dispara 1x
  c/ variável renderizada + template_params na mensagem, 2º disparo
  BLOQUEADO pelo cooldown, marcador no contato) + HTTP 8/8 (GET limpo 200
  c/ ASK_IDENTITY, POST telefone EXISTENTE atrela sem duplicar, telefone
  NOVO cria paciente E.164 + card em Agendamento de Consulta origem
  formulario, reenvio REUSA paciente, identidade inválida 422, track 204,
  404, link assinado 200 c/ "Olá, Guilherme") + VISUAL conta 3 (card de
  identificação dopamine c/ validação, editor c/ campo endereço salvando
  normalizado, botão Copiar link do paciente [toast de erro no teste =
  clipboard bloqueado no browser automatizado, não é bug], modal c/ ação
  nova + caixa + "Selecione o template…" + validação do salvar). Limpeza
  completa (respostas 14-16, pacientes e automações de teste removidos;
  slug revertido). Rubocop: só ofensa pré-existente (InverseOf).
- Sem migration, sem cron — deploy só WEB. ⚠️ routes.rb segue MISTO c/
  Meta Leads (minhas rotas de forms + as de meta_leads) — separar no
  commit como sempre.
- LEMBRETE p/ ele: a mensagem modelo c/ o link do formulário precisa estar
  APROVADA no Gerenciador da Meta antes de ligar a automação.
- AGUARDANDO "pode subir".

## 149B. ✅ AJUSTE: "ENVIAR FORMULÁRIO" MANDA O LINK LIMPO (decisão dele 01/09: "quero sem token")
- Na conversa pós-149 ele cravou: o {{link}} da ação "Enviar formulário"
  deve ser o link LIMPO (clinica.cevico.com.br/forms/pre-avaliacao), sem
  token nenhum (proposta de código curto /i/<código> foi REJEITADA no meio
  da construção e revertida por completo — nada dela ficou no código).
- Mudança: send_form no CrmAutomationFireJob usa form.public_short_link
  (todo paciente recebe o mesmo link bonito; identifica-se com nome +
  WhatsApp no 1º card e a resposta atrela pelo telefone). Texto do modal
  atualizado. Link ASSINADO antigo continua aceito (mensagens já enviadas
  não quebram). Travas mantidas (não reenvia a quem respondeu + cooldown 7d).
- Testes: runner 4/4 (mensagem criada, link limpo no texto, SEM token,
  {{nome}} renderizado) + regressão HTTP (limpo 200, assinado antigo 200,
  identidade inválida 422). Limpeza completa.
- Arquivos: crm_automation_fire_job.rb + ColumnAutomationsModal.vue +
  comentário em routes.rb. Sem migration, sem cron; WEB+SIDEKIQ juntos
  (a ação roda no sidekiq).
- ⚠️ A etiqueta fbfc8e5 (149 pura) fica SUPERADA — implantar direto a
  etiqueta deste ajuste quando o build ficar verde.
- AGUARDANDO "pode subir".

## 150. ✅ 🏷️ CONDIÇÃO DE ETIQUETA EM QUALQUER GATILHO das automações de coluna (pedido 01/09 c/ print)
- Pedido dele: "automação que reconheça na coluna, quando o card entrar,
  SE tiver uma etiqueta XYZ, dispare e mova o card para a coluna que eu
  escolher" — card entrou + contém etiqueta → ação.
- Motor: should_fire? do CrmAutomationFireJob ganhou
  required_label_matches? — action_config.required_label (opcional); sem
  a etiqueta no paciente, a automação NÃO dispara (nem gera log).
  Checagem NA HORA DO DISPARO (case-insensitive via label_list) — vale
  também p/ automação com tempo de espera (etiqueta saiu no meio do
  caminho = não dispara mais). Vale pra QUALQUER gatilho e QUALQUER ação
  (mover coluna, enviar formulário, mensagem modelo...).
- Modal: bloco novo "🏷️ Só dispara se o paciente tiver a etiqueta
  (opcional)" na seção Quando disparar? (select das etiquetas da conta +
  "Sem exigência — dispara para qualquer card" + explicação). required_label
  no emptyForm/hydrate; action_config: {} do backend já permitia.
- Testes: runner 5/5 (SEM etiqueta: card não move + zero log; COM
  etiqueta: move pra coluna alvo + log fired; MAIÚSCULA casa) + visual
  conta 3 (bloco no modal, select c/ etiquetas reais da conta). Limpeza
  completa. Sem migration, sem cron; WEB+SIDEKIQ juntos (motor no sidekiq).
- Nota de uso: mover card por automação dispara as automações da coluna
  DESTINO (encadeamento é proposital) — evitar pares A→B e B→A.
- AGUARDANDO "pode subir".

## 151. ✅ 📱 PLANILHA DE FECHAMENTO CASA PELO TELEFONE (pedido 01/09: "case pelo telefone, não pelo nome")
- FATO IMPORTANTE descoberto ao espiar a planilha REAL dele (10_2025 até
  07_2026.xlsx): as colunas são Status·Data·Paciente·Procedimento·Olho·
  valor total·Comissão·FIXO·REPASSE TOTAL — NÃO EXISTE coluna de telefone.
  O casamento por nome era o único possível com o dado disponível.
- Solução: o leitor agora reconhece a coluna Telefone/Celular/WhatsApp/
  Fone QUANDO ELA EXISTIR e o casamento vira TELEFONE PRIMEIRO (últimos 8
  dígitos + same_phone_line?, mesmo critério do resto do CEVICO — resolve
  homônimos), nome normalizado como RESERVA pra linha sem telefone.
  Planilha sem a coluna = comportamento idêntico ao de antes.
- ClosingSheetReader: HEADER_ALIASES + parse_phone (célula numérica
  '11987654321.0'/notação científica normalizada p/ dígitos; <8 dígitos =
  nil) + status_skip extraído (AbcSize). Controller: match_rows_by_name c/
  phone_index + phone_match_ids (2+ contatos na mesma linha = ambíguo);
  payload novo matched_by_phone + has_phone_column. Job: paciente criado
  da planilha agora NASCE COM phone_number E.164 (+55) quando a linha tem
  telefone — alcançável no WhatsApp. UI: prévia mostra "X pelo 📱 telefone
  e Y pelo nome" + dica azul quando a planilha não tem a coluna.
- Testes: leitor 5/5 (numérico, formatado "(11) 93333-4444", sem fone=nil,
  planilha real 550 linhas sem phone) + preview HTTP conta 3 c/ planilha
  sintética (matched 2 = 1 por fone [nome diferente de propósito] + 1 por
  nome; 1 unmatched; has_phone_column true) + job criou paciente c/
  +5511933334444 e card na coluna c/ valor + regressão da planilha real
  (has_phone_column false). Limpeza completa (contato/card/recibo undo).
  Rubocop: só pré-existentes.
- AÇÃO DELE: adicionar a coluna "Telefone" (com DDD) na planilha de
  fechamento — daí em diante o casamento é por número.
- Sem migration, sem cron; WEB+SIDEKIQ juntos. AGUARDANDO "pode subir"
  (junto do 150).

## 152. ✅ ✨ POPUP DOS INDICADORES "PADRÃO APPLE" — varredura de usabilidade (pedido 02/09)
- Pedido dele: "melhorar a expansão de indicadores dos cards do Meu Painel,
  varredura com carinho, usabilidade padrão Apple". Varredura AO VIVO achou
  problemas reais: popup MAIOR QUE A TELA (cabeçalho e botões cortados, sem
  rolagem própria), gráfico vazio mudo, fórmula em tecniquês
  (appointments_booked / new_leads * 100), legenda ilegível, chips
  minúsculos, sem Esc, fundo rolava junto, abertura seca sem transição.
- 🍎 REFORMA (InicioPage.vue, popup dos itens 140/144):
  (1) NUNCA maior que a tela: max-h 88vh + corpo c/ rolagem própria
  (overscroll-contain) e cabeçalho fixo; (2) TRANSIÇÃO tipo folha: fundo em
  fade c/ leve blur, cartão sobe c/ escala (cubic-bezier suave; saída mais
  rápida; prefers-reduced-motion = só fade); (3) Esc FECHA + clique no
  fundo + rolagem da página TRAVA enquanto aberto (watch kpiModal →
  body.overflow; listener no ciclo de vida); (4) FÓRMULA EM PORTUGUÊS:
  prettyFormula troca as chaves pelos nomes do cesto ("Consultas agendadas
  (registradas) ÷ Novos contatos (leads) × 100") — chaves ordenadas por
  tamanho p/ não colidir; linha de detalhe quebra em vez de estourar;
  (5) ESTADO VAZIO gentil: série toda zero → "Sem movimento neste recorte —
  experimente Este mês ou Este ano"; some sozinho quando o recorte tem
  dado; (6) LEGENDA VISUAL: tracinho tracejado + "período anterior", ⭑
  meta, 📌 ação da empresa (substitui o "tracejado = ..." escondido);
  (7) MINI-RÉGUA com grupos NOMEADOS "Período" e "Ver por" em linhas
  separadas, chips h-7 maiores; (8) carregamento SUAVE (gráfico esmaece a
  40% enquanto busca o recorte); (9) toques: ✕ redondo 32px c/ aria-label
  "Fechar (Esc)", role=dialog/aria-modal, títulos de seção legíveis
  ("🧩 De onde vem este número", "🏥 Por unidade", "📥 Leads por caixa"),
  valor grande tabular-nums, botões admin h-9.
- Testes AO VIVO (conta 3): popup cabe na tela c/ rolagem própria; body
  trava/destrava; Esc e fundo fecham c/ transição completando (classes
  enter/leave limpas); fórmula traduzida na tela; vazio aparece na régua
  curta e some no "Este ano" (dados carregam c/ 📌 e decomposição 8×49);
  chips 28px; grupos rotulados. ⚠️ LIÇÃO DE AMBIENTE: o browser pane de
  teste roda como aba OCULTA (document.hidden) → requestAnimationFrame
  congela e a <Transition> do Vue fica presa no 1º frame — NÃO é bug do
  produto (usuário real tem aba visível); p/ testar ciclo completo, stub
  rAF→setTimeout na sessão de teste.
- Refino futuro anotado: aplicar o mesmo pacote UX no KpiDetailPopup.vue
  (Dashboard CRM) quando unificar o popup 144 (já estava na lista).
- Sem migration, sem cron; deploy WEB. AGUARDANDO "pode subir" (junto de
  150+151).

## 153. ✅ 🏥 INDICADORES POR UNIDADE no cesto (pedido 02/09: "separar as consultas da Paulista e do Tatuapé")
- Pedido dele: visualização das métricas cada vez mais fácil + dados
  relevantes; indicador que SEPARE as consultas por unidade.
- KpiBagService: 6 métricas novas com série + período anterior, geradas de
  Crm::AgendaSlots::UNIT_LABELS (tasks.unit, mesma fonte do 146) —
  Consultas · Av. Paulista/Tatuapé (pela data), Presenças · cada casa,
  Faltas · cada casa. Categoria "📅 Consultas" no construtor é automática
  (prefixo appointments_). Cesto foi de 29 p/ 35 métricas.
- READY_FORMULAS: categoria nova "🏥 Por unidade" c/ 2 taxas prontas de 1
  clique — Comparecimento · Av. Paulista e · Tatuapé (presenças ÷
  (presenças+faltas) × 100) — coloca os 2 cards lado a lado e compara as
  casas no mesmo olhar.
- Testes: runner 6/6 (labels/séries; soma paulista+tatuape = total 21 ✅) +
  visual conta 3 ponta a ponta (construtor lista a categoria e os 6
  números-base; 1 clique na taxa pronta → prévia viva 94,4% na régua Este
  ano → Salvar card → card na fileira c/ 94,4% → popup → Remover [limpeza]).
  Nota: prévia mostra "—" quando o recorte da régua não tem consulta
  (divisão por zero protegida) — comportamento correto.
- Sem migration, sem cron; deploy WEB. AGUARDANDO "pode subir" (junto de
  150+151+152).
