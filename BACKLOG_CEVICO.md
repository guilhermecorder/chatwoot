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

---

## Estado atual (para retomar)
- Sistema migrado e no ar (4.15.1), banco `chatwoot_migrado` em produção.
  Corte final CONCLUÍDO (2026-07-10): número WhatsApp e N8N já apontam pro
  CEVICO. 42 conversas do intervalo pós-migração ficaram só no Robomaster
  (perda aceita). CEVICO é agora o banco vivo — sem mais resync geral.
- Feito recentemente: board rápido (N+1 resolvido), Tratamento de dados leve
  (sem saturar CPU), busca sem acento + aspas + multi-termo, mover colunas
  sem modo edição, dashboard com data histórica real + períodos até 3 anos,
  filtro De/Até no CRM, Academia com card TACOH.
- SMTP (Gmail) configurado para convites de equipe.
