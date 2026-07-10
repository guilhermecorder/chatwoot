# Backlog CEVICO — próximas funcionalidades

> Requisitos combinados com o Guilherme para as próximas sessões.
> Contexto: fork Chatwoot em `~/chatwoot`, produção na VPS (EasyPanel,
> projeto `sistema_cevico`), banco migrado do Robomaster (~20k contatos).
> Fluxo: código → push `develop` → GitHub Actions build → Implantar web+sidekiq.

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

## 6. Corte final com RESSINCRONIZAÇÃO (prioridade — fazer em sessão acompanhada)

Leads novos chegaram no Robomaster depois da migração. O corte final deve
ressincronizar + virar o webhook NUMA JANELA SÓ (noite/domingo, ~30min):

1. Pausar atendimento no Robomaster
2. Novo dump completo → banco `chatwoot_v2` no postgres do CEVICO
3. Copiar tabelas `crm_*` do `chatwoot_migrado` para o v2 (preserva funil,
   campanhas, automações, cards — contact_ids são idênticos entre os dois).
   ATENÇÃO no script: também inserir em schema_migrations do v2 as versions
   das NOSSAS migrations (senão o boot tenta recriar tabelas crm_* e falha)
   + `CREATE EXTENSION IF NOT EXISTS unaccent;` (a migration constará como
   executada). Labels custom (cores) e tags do tratamento não vêm na cópia —
   re-rodar o Tratamento recria.
4. Trocar POSTGRES_DATABASE=chatwoot_v2 em web+sidekiq → Implantar
5. Re-rodar as regras do Tratamento de dados (re-etiqueta tudo, incl. novos)
6. Clicar "Cadastrar Webhook" (Saúde da Conta) → número passa ao CEVICO;
   Robomaster vira backup permanente
- Regra até lá: NADA de trabalho manual pesado em cards no CEVICO (se perde
  no v2); trabalho por regras é seguro (re-executável).

## 7. Caixas de entrada por atendente ("selecionar e ocultar")

Primeiro testar o NATIVO: atendentes como papel Agente + colaboradores por
caixa (Config → Caixas → Colaboradores). Agente só vê as caixas em que está;
para "cobrir a parceira", ambas nas duas caixas e cada uma filtra clicando
na sua na sidebar. Se o fluxo nativo não bastar, construir preferência
por usuária de mostrar/ocultar caixas na sidebar.

---

## Estado atual (para retomar)
- Sistema migrado e no ar (4.15.1). 20.279 contatos, 10.848 conversas,
  428.829 mensagens no banco `chatwoot_migrado`.
- WhatsApp principal (GREEN) migrado; webhook AINDA aponta para o Robomaster
  (corte final = clicar "Cadastrar Webhook" quando for virar de vez).
- Feito recentemente: board rápido (N+1 resolvido), Tratamento de dados leve
  (sem saturar CPU), busca sem acento + aspas + multi-termo, mover colunas
  sem modo edição, dashboard com data histórica real + períodos até 3 anos,
  filtro De/Até no CRM, Academia com card TACOH.
- SMTP (Gmail) configurado para convites de equipe.
