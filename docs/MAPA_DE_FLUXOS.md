# 🗺️ MAPA DE FLUXOS DOS AGENTES — contrato de construção (item 170)

Tela **"Fluxos"** dentro de Automações: um fluxograma por agente/automação, gerado a partir
de uma **descrição declarativa em código** (cada agente declara gatilho → condições → ações →
saídas), renderizado no navegador com **Mermaid** (npm), com o **estado ao vivo** (ligado/
desligado, última execução, contadores) e clique no nó → abre a configuração.

## Regra de trabalho (vale a partir de agora)
> **Toda rodada que cria ou muda um agente/automação entrega também o fluxograma**: o arquivo
> `app/services/crm/flow_map/flows/<key>.rb` atualizado (no sistema) e o Mermaid no resumo da
> rodada. A spec `spec/services/crm/flow_map/registry_spec.rb` falha se um agente do
> `AGENT_META` (Painel dos agentes) ou um job CEVICO do `config/schedule.yml` não tiver fluxo.

## 1. Backend

### DSL — `app/services/crm/flow_map/flow.rb`
```ruby
Crm::FlowMap::Flow.define(:radar) do
  name  'Radar de Oportunidades'
  group 'Atendimento ao paciente'      # mesmos grupos do AutomationsHub (+ 'Infraestrutura')
  icon  'i-lucide-radar'; color '#DC2626'
  what  'vigia colunas do CRM e avisa o painel quando um lead esfria'
  config tab: 'agentes', anchor: 'opportunity'   # onde abrir ao clicar (ou route:/query:)
  trigger :cron, 'a cada 10 min (07:30–18:00)'   # :cron | :event | :webhook | :manual
  node :ligado?,   'Agente ligado?',            kind: :decision
  node :vigias,    'Para cada vigia (coluna + atendente + janela)', kind: :loop
  node :esfriou?,  'Lead sem resposta há mais que a espera?', kind: :decision
  node :ia,        'IA classifica a oportunidade',            kind: :ai
  node :alerta,    'Aviso no Radar do painel',                kind: :output
  node :fim,       'Fim',                                     kind: :end
  edge :trigger, :ligado?
  edge :ligado?, :vigias, 'sim'
  edge :ligado?, :fim, 'não'
  edge :vigias, :esfriou?
  edge :esfriou?, :ia, 'sim'; edge :esfriou?, :fim, 'não'
  edge :ia, :alerta; edge :alerta, :fim
  live do |account|   # estado ao vivo: tudo opcional
    st = ai(account).dig('opportunity_state') || {}
    { enabled: agent_enabled?(account, 'opportunity'), last_run_at: st['last_run_at'],
      counters: { 'alertas hoje' => (st['alerts'] || []).size }, note: nil }
  end
end
```
Tipos de nó → forma Mermaid: `:trigger` `([ ])` · `:decision` `{ }` · `:action` `[ ]` · `:ai` `[[ ]]` ·
`:loop` `[/ /]` · `:output` `[( )]` · `:external` `>[ ]` (ex.: N8N, Meta, ElevenLabs) · `:end` `(( ))`.
`to_mermaid` gera `flowchart TD` com ids estáveis (`<key>_<node>`), rótulos escapados (aspas), `classDef`
por tipo e `class … off` quando desligado. Helpers dentro do bloco `live`: `ai(account)`, `agenda(account)`,
`agent_enabled?(account, key)`, `usage_last(account, key)` (`Crm::AiUsage`), `usage_count(account, key, since)`.

### Registro — `app/services/crm/flow_map/registry.rb`
Carrega `flows/*.rb` (cada arquivo chama `Flow.define`), `all(account)` devolve na ordem dos grupos
`[{ key, name, group, icon, color, what, trigger: {kind, label}, config, mermaid, nodes: [{id, label, kind}], live: {enabled, last_run_at, counters, note} }]`;
`find(account, key)`. Erro num `live` não derruba a lista (`note: 'estado indisponível: …'`).

### Fluxos obrigatórios (um arquivo por chave em `app/services/crm/flow_map/flows/`)
Atendimento: `scheduler` (Secretário da Agenda + releitura), `instagram`, `comments`, `nps`, `conversation`,
`calls` (📞 item 167: recebida/perdida/fora do horário/ligar c/ permissão), `voice` (🤖 item 169: IA atende / campanha liga),
`reminders` (Lembretes D-1/D-0 + confirmação), `followup_bots` (robôs c/ janela 24h, etiquetas de parada, sem empilhamento).
Vendas: `sales`, `closing`, `opportunity` (Radar), `form`, `column_automations` (gatilhos × ações), `campaigns` (Campanha WhatsApp + réguas).
Marketing: `copywriter`, `pagebuilder`, `creative`, `harvest` (Colheitadeira c/ aprovação).
Gestão: `manager`, `auditor`, `mentor`, `stalled_cards`.
Infraestrutura: `oftalmofacil` (sync), `surgery_confirmation` (N8N externo hoje → item 168; nós `:external`).
O conteúdo dos passos vem do código real (jobs/services) — não inventar condições: cada nó de decisão
corresponde a um `if/return` do job.

### API — `app/controllers/api/v1/accounts/crm/flows_controller.rb`
`GET crm/flows` → `{ flows: [...], groups: [...] }` (`require_capability(:automations)`; rota já adicionada);
`GET crm/flows/:key` → um fluxo (usado no refresh do estado a cada 60 s na tela).

### Spec — `spec/services/crm/flow_map/registry_spec.rb`
Todas as chaves de `Api::V1::Accounts::Crm::AiDashboardsController::AGENT_META` têm fluxo; todos os jobs
`Crm::*` de `config/schedule.yml` estão citados em algum `trigger`/nó (mapa explícito na spec); cada
`to_mermaid` é não vazio e sem `undefined`; `live` roda sem erro numa conta de teste.

## 2. Frontend
- `mermaid` (npm, v11) — **importado só sob demanda** (`await import('mermaid')`) dentro do componente do diagrama;
  a aba usa `defineAsyncComponent` p/ não entrar no bundle das outras abas.
- `routes/dashboard/cevicoAutomations/FlowsMap.vue` — aba `fluxos` do `AutomationsHub` (pílula "Fluxos", ícone
  `i-lucide-git-branch`, gradiente `#1D4ED8→#60A5FA`; visível p/ `canSee('automations')`; item "Fluxos" no Sidebar
  filho de Automations Hub). Layout no kit `cv-*` como `AiAgentsDashboard.vue` (`useCevicoPalette({ scope: 'report:fluxos' })`, sem Hero):
  coluna esquerda = lista agrupada (chip ligado/desligado, "última execução há …", contadores em pílulas); área principal =
  cabeçalho do fluxo (nome, o que faz, gatilho, botão **Abrir configuração** → `router.push` p/ `cevico_automations?tab=…` ou a
  rota indicada em `config`) + `FlowDiagram` + rodapé c/ contadores/nota. Atualiza o estado a cada 60 s (`GET crm/flows/:key`).
  `?flow=<key>` na URL seleciona o fluxo (deep link a partir dos cards dos agentes: botão "Ver fluxo" no card da aba Agentes).
- `components-next/cevico/FlowDiagram.vue` — props `definition` (string Mermaid), `flowKey`; `mermaid.initialize({ startOnLoad:false,
  securityLevel:'strict', theme: escuro ? 'dark' : 'neutral', flowchart: { curve:'basis', htmlLabels:false, useMaxWidth:true } })`;
  `mermaid.render('cv-flow-'+key+'-'+n, definition)` → `svg` no innerHTML; depois liga clique nos `g.node` (id contém `<key>_<node>`)
  → `emit('node-click', nodeId)`; botões zoom −/100%/+ e "Baixar PNG" (`html-to-image`, já no package.json). Skeleton enquanto carrega;
  erro de sintaxe vira aviso legível (nunca quebra a tela).
- Painel dos agentes/aba Agentes: link "Ver fluxo" por agente (`?tab=fluxos&flow=<key>`).

## 3. Toques em arquivos existentes (só estes)
`AutomationsHub.vue` (TABS, visibleTabs, pílula, painel `v-else-if`, botão "Ver fluxo" nos cards), `Sidebar.vue` (1 filho),
`config/routes.rb` (já feito), `package.json`/`pnpm-lock.yaml` (mermaid), `api/crm.js` + `store/modules/crm.js` (já feito: `getFlows`, `getFlow`).
