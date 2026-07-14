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

## Estado atual (para retomar — atualizado 2026-07-14, madrugada)

**ONDE ESTAMOS:** existe um LOTE GIGANTE NÃO COMMITADO no working tree
(~67 arquivos entre modificados e novos), cobrindo os itens 14 a 24 deste
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
