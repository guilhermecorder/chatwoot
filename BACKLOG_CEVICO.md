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

---

## Estado atual (para retomar)
- Sistema migrado e no ar (4.15.1), banco `chatwoot_migrado` em produção.
  Corte final CONCLUÍDO (2026-07-10): número WhatsApp e N8N já apontam pro
  CEVICO. CEVICO é o banco vivo — sem mais resync geral.
- **2026-07-13: rodadas 1–9 completas (ver item 12).** Último build verde:
  `8935f3cde`. Guilherme implanta pelo EasyPanel (web+sidekiq juntos — o
  sidekiq precisa reiniciar pro cron */2 do robô valer).
- Fluxo de trabalho: mudança → teste no Docker local (docker compose up
  rails sidekiq vite) → Guilherme testa em localhost:3000 → aprova → commits
  temáticos → push develop (--no-verify, hooks exigem npx que não há no host)
  → Actions builda (~10min) → Guilherme implanta.
- Pendências conhecidas: Bloco 5 da auditoria (automação Instagram direct/
  comentário, decidido deixar p/ depois); Dashboard do Negócio fases B/C
  (item 9); ferramenta opcional "arquivar cards sem conversa/inativos".
- SMTP (Gmail) configurado para convites de equipe.
