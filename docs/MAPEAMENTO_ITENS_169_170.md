# Mapeamento do código p/ os itens 169 (Agente de Ligação IA) e 170 (Mapa de Fluxos) — 17/09

Gerado por agente de exploração; caminhos absolutos em ~/chatwoot-upgrade.

## 1. Scheduling AI agent ("Secretário da Agenda")

**Agent key: `scheduler`**, stored at `crm_settings.ai_config['agents']['scheduler']`.

**Registry of all agent keys** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/services/crm/ai_agent_config.rb` (module `Crm::AiAgentConfig`, 200 lines):

```ruby
DEFAULT_MODEL = 'claude-opus-4-8'.freeze
MODELS  = %w[claude-opus-4-8 claude-sonnet-5 claude-haiku-4-5].freeze
EFFORTS = %w[low medium high xhigh max].freeze

RECOMMENDED = {
  'conversation' => { 'model' => 'claude-opus-4-8',  'effort' => 'high' },
  'form'         => { 'model' => 'claude-sonnet-5',  'effort' => 'high' },
  'scheduler'    => { 'model' => 'claude-sonnet-5',  'effort' => 'medium' },
  'opportunity'  => { 'model' => 'claude-haiku-4-5', 'effort' => nil },
  'closing'      => { 'model' => 'claude-sonnet-5',  'effort' => 'medium' },
  'nps'          => { 'model' => 'claude-haiku-4-5', 'effort' => nil },
  'sales'        => { 'model' => 'claude-opus-4-8',  'effort' => 'high' },
  'instagram'    => { 'model' => 'claude-sonnet-5',  'effort' => 'medium' },
  'copywriter'   => { 'model' => 'claude-opus-4-8',  'effort' => 'high' },
  'pagebuilder'  => { 'model' => 'claude-sonnet-5',  'effort' => 'medium' },
  'mentor'       => { 'model' => 'claude-sonnet-5',  'effort' => 'high' },
  'sheet_match'  => { 'model' => 'claude-sonnet-5',  'effort' => 'medium' },
  'comments'     => { 'model' => 'claude-sonnet-5',  'effort' => 'medium' },
  'harvest'      => { 'model' => 'claude-haiku-4-5', 'effort' => nil },
  'manager'      => { 'model' => 'claude-haiku-4-5', 'effort' => nil },
  'auditor'      => { 'model' => 'claude-haiku-4-5', 'effort' => nil },
  'creative'     => { 'model' => 'claude-sonnet-5',  'effort' => 'high' }
}.freeze

RESPONDER_AGENTS = %w[instagram comments].freeze
PRICING = { 'claude-opus-4-8' => [5.0, 25.0], 'claude-sonnet-5' => [3.0, 15.0], 'claude-haiku-4-5' => [1.0, 5.0] }.freeze
```

`AGENT_KEY` constants actually declared in services (`grep "AGENT_KEY = "`): `scheduler, manager, calls_transcription, comments, auditor, conversation, copywriter, creative, form, harvest, instagram, nps, sales` (objection_map + sales_coach both use `sales`), `opportunity, pagebuilder` (page_builder + page_editor), `sheet_match, closing, mentor`. Note `calls_transcription` (`app/services/crm/calls/transcription_service.rb`) exists but is **not** in `RECOMMENDED`/`AGENT_META` — precedent for adding a key without registering it everywhere.

**Guardrails** (same file, lines 56–84) — `OPERATIONAL_GUARDRAIL` (internal read-only agents) and `RESPONDER_GUARDRAIL` (agents that talk to patients). Key lines of `RESPONDER_GUARDRAIL`:

```
- Suas mensagens SÃO enviadas ao paciente. Use APENAS informações que
  estão neste prompt ou na conversa — NUNCA invente valores, horários, ...
- NUNCA forneça diagnóstico médico nem prometa resultado de cirurgia.
- Só ofereça horários que constem na lista de HORÁRIOS DISPONÍVEIS
- Urgência (dor intensa, perda súbita de visão, trauma): ... marque chamar_humano.
```

**How the prompt is assembled** (`Crm::AiAgentConfig#system_prompt`, lines 114–123):

```ruby
def system_prompt
  base = agent_config['prompt'].presence || self.class::SYSTEM_PROMPT
  if base.include?('{{TABELA_DE_PRECOS}}')
    base = base.gsub('{{TABELA_DE_PRECOS}}', Cevico::PriceList.prompt_block(@account))
  end
  guard = RESPONDER_AGENTS.include?(self.class::AGENT_KEY) ? RESPONDER_GUARDRAIL : OPERATIONAL_GUARDRAIL
  base + guard
end
```

**LLM client** — there is no separate wrapper class; `Crm::AiAgentConfig#client` is the single entry point:

```ruby
def client
  @client ||= Anthropic::Client.new(api_key: api_key, timeout: 300)   # official anthropic ruby SDK
end
def api_key      = ai_config['api_key']                  # crm_settings.ai_config['api_key']
def agent_config = (ai_config['agents'] || {})[self.class::AGENT_KEY] || {}
def agent_paused?= agent_config['enabled'] != true       # opt-in kill switch
def model  # agent choice > RECOMMENDED > global ai_config['model'] > DEFAULT_MODEL
def effort # agent choice > RECOMMENDED > global; nil allowed
def output_config_for(format)  # { format:, effort: } — effort omitted for haiku
def record_usage(message)      # → Crm::AiUsage.create!(account:, agent_key:, model:, input_tokens:, output_tokens:, cost_usd:)
```

Only `lib/llm_constants.rb` otherwise mentions anthropic (core Chatwoot).

**Scheduler service** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/services/crm/appointment_extraction_service.rb` (`Crm::AppointmentExtractionService`, `AGENT_KEY = 'scheduler'`, `MAX_MESSAGES = 60`, `TZ = America/Sao_Paulo`). It is an **extractor, not a responder** — reads the transcript, returns JSON:

```ruby
message = client.messages.create(
  model: model, max_tokens: 1024, system_: system_prompt,
  output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
  messages: [{ role: 'user', content: transcript }]
)
record_usage(message)
{ found:, name:, phone:, starts_at:, unit:, procedure:, doctor:, notes:, price:, reschedule:, cancel:, gender:, model: }
```
`initialize(conversation:)`. Applied by `app/services/crm/appointment_applier.rb`.

**The actual conversational persona/script** (what you want to reuse for voice) lives in `/Users/guilhermemartinscorder/chatwoot-upgrade/app/services/crm/instagram_agent_service.rb` — `Crm::InstagramAgentService`, `AGENT_KEY = 'instagram'`, a RESPONDER. Its `SYSTEM_PROMPT` (lines 58–140) is the CEVICO script distilled from the N8N WhatsApp flow: persona "Guilherme", message-format rules, FLUXO (recepção → sondagem → autoridade → orçamento → objeções → agendamento), AUTORIDADE (doctors, Excimer Schwind Amaris 1050RS, IOP), UNIDADES (addresses + map links), VALORES with `{{TABELA_DE_PRECOS}}` placeholder, OBJEÇÕES, AGENDAMENTO golden rule. Output schema: `mensagens[≤3], etapa (enum of 11 script stages), agendar, agendamento{nome,telefone,dia,hora,unidade,procedimento}, pausar, chamar_humano`. Live context injected per call:

```ruby
def context_block
  <<~CTX
    CONTEXTO (gerado pelo sistema agora):
    - Agora: #{WEEKDAYS[now.wday]}, #{now.strftime('%d/%m/%Y %H:%M')} (São Paulo)
    - Paciente (perfil): #{contact&.name} · telefone cadastrado: #{contact&.phone_number}
    HORÁRIOS DISPONÍVEIS (próximos dias — ofereça no máx. 2 por vez):
    #{Crm::AgendaSlots.free_slots_text(@account)}
  CTX
end
```

**"Personalização" / editable context**: there is no separate clinic-context field. The admin edits the **whole prompt per agent** (`ai_config['agents'][key]['prompt']`, with `draft` staging) in the *Agentes de IA* tab. Extra free-text context exists only for `copywriter`/`pagebuilder` via `agent_config['style_refs'] || agent_config['references']` → `style_refs_block`. Units/doctors/prices are **structured** config, not free text (see §2). Default prompts are echoed to the UI by `ai_json` in `app/controllers/api/v1/accounts/crm/settings_controller.rb:~1375` (`default_prompts` hash mapping each key → `Service::SYSTEM_PROMPT`).

---

## 2. Agenda tools you can expose to a voice agent

**`/Users/guilhermemartinscorder/chatwoot-upgrade/app/services/crm/agenda_slots.rb`** — `module Crm::AgendaSlots` (`module_function`):

| Method | Signature | Returns |
|---|---|---|
| `windows(account)` | — | array of `{'dow','unit','doctor','start','end','block'}` from `agenda_config['windows']` or `DEFAULT_WINDOWS` |
| `free_slots(account, days: 10, per_window: 3)` | — | `[{ date: Date, time: "08:30", unit: 'tatuape'|'paulista', doctor: 'Dr. ...' }]` |
| `free_slots_text(account, days: 10, per_window: 3)` | — | prompt string `"quarta 22/07 · Tatuapé · Dr. Gustavo Bittar: 08:30, 08:40"` |
| `slot_available?(account, date:, time:, unit:)` | — | boolean (scans `days: 30, per_window: 100`) |
| `agenda_config(account)` | — | `CrmSetting.find_by(account:)&.agenda_config \|\| {}` |

There is **no `free_slots(account, unit, date)` overload** — filter the returned array yourself. Constants: `TZ`, `UNIT_LABELS = { 'tatuape' => 'Tatuapé', 'paulista' => 'Av. Paulista' }`, `WEEKDAYS`, `DEFAULT_WINDOWS` (7 entries mirroring frontend `cevicoAgenda.js`). Occupancy comes from `account.tasks.where(task_type: 'consulta', canceled_at: nil)`; blocks from `agenda_config['blocked']` (`{date,time,unit}`) and `agenda_config['blocked_days']`.

**`/Users/guilhermemartinscorder/chatwoot-upgrade/app/services/crm/appointment_recorder.rb`** — `Crm::AppointmentRecorder` (all class methods):

```ruby
def self.record(account:, result:, contact: nil, conversation: nil, default_unit: nil)
# result hash keys read: :found, :starts_at, :name, :phone, :unit, :doctor,
#                        :procedure, :price, :notes, :gender
# returns :skipped | :already | :rescheduled | :created
def self.cancel_future(account:, result:, contact: nil, conversation: nil) # → :no_future | :canceled
def self.future_appointment(account, phone, _name, contact = nil)          # → Task or nil
def self.log_activity(account, result, contact, conversation, outcome)     # → agenda_config['scheduler_log'] (cap 100)
def self.same_phone_line?(a_digits, b_phone)
```
Creates `account.tasks.create!(title: "Consulta: #{name}", due_at:, unit:, phone:, contact:, procedure:, doctor:, task_type: 'consulta', priority: :medium, status: :todo, creator:, assignee: Crm::TaskOwner.resolve(...))`.

**Contact matching** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/models/task.rb:86`:

```ruby
def self.match_contact(account, phone)
  digits = phone.to_s.gsub(/\D/, '')
  return nil if digits.length < 8
  account.contacts
         .where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
         .order(:id).first
end
```

**TOCTOU lock pattern to copy** (`app/jobs/crm/instagram_agent_job.rb#handle_scheduling`): `Redis::LockManager.new.lock("CRM_SLOT_LOCK::#{account.id}::#{date}::#{time}::#{unit}", 30.seconds)` around `slot_available?` + `record`, with a fallback `⚠️ Confirmar consulta` task when validation fails.

**Price table** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/services/cevico/price_list.rb`, `Cevico::PriceList`: `items(account)`, `effective_price(item)`, `price_by_name(account)`, `prompt_block(account)`, `format_money`, `normalize`. Stored at `agenda_config['price_table']['items']` (`{group,name,price,promo_price}`), falling back to `DEFAULT_ITEMS`.

**Units / doctors config keys** (all under `crm_settings.agenda_config`): `windows`, `blocked`, `blocked_days`, `closed_doctors`, `surgery_locations`, `surgery_windows`, `attendance_stages`, `attendance_owners`, `price_table`, `theme`. Canonical doctor names: `/Users/guilhermemartinscorder/chatwoot-upgrade/app/services/crm/doctor_names.rb` — `Crm::DoctorNames::OFFICIAL` (`Dr. Gustavo Bittar`, `Dr. Henrique Gemelli`, `Dra. Roberta Negri`), `.canonical(raw)`, `.filter(scope, name)`.

---

## 3. Automações UI

Folder `/Users/guilhermemartinscorder/chatwoot-upgrade/app/javascript/dashboard/routes/dashboard/cevicoAutomations/` contains exactly three files: `AutomationsHub.vue` (4214 lines), `AiAgentsDashboard.vue` (408 lines), `routes.js`.

`routes.js` — single route, all tabs are `?tab=` on it:

```js
{ path: frontendURL('accounts/:accountId/cevico-automations'),
  name: 'cevico_automations',
  meta: { permissions: ['administrator', 'agent'] },
  component: AutomationsHub }
```
Registered in `app/javascript/dashboard/routes/dashboard/dashboard.routes.js:24,59`.

**Adding a tab** (3 edits in `AutomationsHub.vue`):
1. `const TABS = ['robos','regras','agentes','painel_ia','programacao','resultados','tratamento'];` (line 33) — append your key.
2. `visibleTabs` computed (lines 43–49) — permission rule (`canSee('automations') | canSee('data_tools') | isAdmin`).
3. A `<button>` pill (lines 1884–1936) + a `<div v-else-if="activeTab === '...'">` panel.

**Pill classes to match** (line 1886–1890):
```html
class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
:class="activeTab === 'robos' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
:style="activeTab === 'robos' ? { background: 'linear-gradient(135deg, #0F5FA6, #3B82F6)' } : {}"
```
Gradients per tab: robos `#0F5FA6→#3B82F6`, regras `#0E7490→#22D3EE`, agentes `#7C3AED→#5B21B6`, painel_ia `#9D174D→#DB2777`, programacao `#D97706→#F59E0B`, resultados `#65A30D→#84CC16`, tratamento `#0F766E→#14B8A6`. Container: `<div class="flex gap-1 mt-3 flex-wrap">`.

**Data loading**: `settings` comes from the Vuex getter `crm/getSettings`; per-tab lazy loads use `watch(activeTab, tab => { if (tab === 'resultados' && !resultsData.value) loadResults(); })` (line 1491). Everything else is `CrmAPI.*` from `dashboard/api/crm` (`radarScan`, `getAiUsage`, `getAutomations`, `getAutomationsDashboard`, `updateAi`, `getHarvestStatus`, `runManager`, `runAuditor`, `getCreativeState`, `agendaBackfill`, …). URL→tab sync via `watch(() => route.query.tab, ...)` (line 55) — the sidebar reuses the same route.

**Sidebar** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/javascript/dashboard/components-next/sidebar/Sidebar.vue:973–1040`: parent `{ name: 'Automations Hub', label: 'Automações', icon: 'i-lucide-workflow', children: [...] }`, gated by `canSee('automations') || canSee('data_tools')`. Children names/labels/icons: `Automations Robos`/Robôs de follow-up/`i-lucide-bot`; `Automations Rules`/Regras da caixa de entrada/`i-lucide-repeat`; `Automations AI Agents`/Agentes de IA/`i-lucide-sparkles`; `Automations AI Panel`/Painel dos agentes/`i-lucide-activity`; `Automations Programming`/Modo Programação/`i-lucide-zap`; `Automations Results`/Resultados/`i-lucide-bar-chart-3`; `Automations Treatment`/Tratamento de dados/`i-lucide-database`. Each is `to: accountScopedRoute('cevico_automations', {}, { tab: '...' })`.

**Route grants** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/javascript/dashboard/routes/index.js:21–38`: `CEVICO_GRANTED_ROUTES = { ..., cevico_automations: ['automations', 'data_tools'], crm_campaigns: ['campaigns'], ... }`; guard `cevicoRouteAllowed(to, isAdminRole)` reads `settings.agent_permissions.grants[userId]`.

**AiAgentsDashboard.vue** (`?tab=painel_ia`): loads `CrmAPI.getAiDashboard({preset, from, to})`, renders per agent: `key, name, icon, color, what, enabled, responder, model, calls, cost_usd, tokens, last_call_at, daily[14]`. Uses `SkeletonScreen, PeriodRuler, DashKpi, MiniBars, HBars, ShareBar, CevicoPalettePicker` from `components-next/cevico/` + `useCevicoPalette({ scope: 'report:agentes', blocks: [...] })`. Computeds: `totals, agents, teamDaily, rankingRows, costSlices, agentsOn, agentsOff`, helper `ago(iso)`.

---

## 4. Central agent/automation registry

**Backend registry (authoritative for the panel):** `/Users/guilhermemartinscorder/chatwoot-upgrade/app/controllers/api/v1/accounts/crm/ai_dashboards_controller.rb` — `AGENT_META` maps 16 keys → `{ name:, icon:, color:, what: }` (e.g. `'scheduler' => { name: 'Secretário da Agenda', icon: 'i-lucide-calendar-check', color: '#0F5FA6', what: 'lê confirmações de agendamento e anota as consultas na Agenda' }`). `show` joins it with `Crm::AiUsage`:

```ruby
enabled: agent_enabled?(key),                    # ai_config['agents'][key]['enabled'] == true
responder: Crm::AiAgentConfig::RESPONDER_AGENTS.include?(key),
model: resolved_model(key), calls:, cost_usd:, tokens:, last_call_at:, daily: daily_series[key]
extras: { mentor_feedbacks_30d:, radar_last_run: ai_config['opportunity_last_run'] }
```
`Crm::AiUsage` (`app/models/crm/ai_usage.rb`, table `crm_ai_usages`: `account_id, agent_key, model, input_tokens, output_tokens, cost_usd, created_at`) is the universal "last_run/volume" source — **write one row per voice-agent call and the panel picks it up automatically** once you add the key to `AGENT_META`.

**Frontend registry (cards/copy):** `AutomationsHub.vue:986` `const AGENT_META = { key: { title, icon, gradient, color, tag, description, triggers:[{icon,label}], suggestion } }` and `AutomationsHub.vue:1221` `AGENT_GROUPS = [{title:'Atendimento ao paciente', icon:'🗣️', keys:['conversation','scheduler','instagram','comments','nps']}, {'Vendas e fechamento' …}, {'Marketing e aquisição' …}, {'Gestão e evolução do time' …}]`; unknown keys fall into an auto "Outros" group (`agentGroups` computed) — future-proof.

**Per-agent state keys:**

| Agent / automation | enabled flag | last_run / result |
|---|---|---|
| opportunity radar | `ai_config['agents']['opportunity']['enabled']` (+ `watchers[]`, `wait_minutes`, `response_goal_minutes`, `stage_ids`) | `ai_config['opportunity_state']['last_run_at' \| 'last_run' \| 'alerts' \| 'attended_log']` (also legacy `ai_config['opportunity_last_run']`) |
| scheduler | `ai_config['agents']['scheduler']['enabled']` | `agenda_config['scheduler_log']` (100 entries: `at,name,when,outcome,conversation_id`), `agenda_config['backfill_last_run']` |
| instagram | `...['instagram']['enabled']` + `inbox_ids[]` | `ai_config['instagram_state']['events']` |
| comments | `...['comments']['enabled']` + `page_access_token, fb_page_id, ig_user_id` | `ai_config['comments_state']['last_run_at' \| 'events']` |
| harvest | `...['harvest']['enabled']` + `mode, monthly_size, cold_days, daily_cap, day_of_month, inbox_id, require_approval, message_preview, template_params, stage_ids` | `ai_config['harvest_state']` → `month_key, status, generated_at, approved_at, stats, last_error` |
| auto manager | `...['manager']['enabled']` + `drop_pct` | `ai_config['manager_state']` → `last_run_date, last_run_at, brief, findings, tasks_opened` |
| conversation auditor | `...['auditor']['enabled']` + `daily_cap` | `ai_config['auditor_state']` → `last_run_at, days_done{}` |
| creative | `...['creative']['enabled']` + `winners_count, variations_count` | `ai_config['creative_state']` → `week_key, generated_at, winners[], approved_log` |
| weekly mentor | `...['mentor']['enabled']` | `Crm::WeeklyFeedback` records |
| followup bots | `crm_followup_bots.active` column | `crm_followup_bots.last_run_at` + `activity_log['last_run']`/`['events']` |
| appointment reminders | `agenda_config['appointment_reminders']['d1'\|'d0']['enabled']` (+`hour, inbox_id, template_params, message_preview`) | per-task marker |
| oftalmofacil sync | `agenda_config['oftalmofacil']['enabled']` | `['last_sync_at']`, `['last_run_at']`, `['last_result']` |
| **calls (native)** | `agenda_config['calls']['enabled']` | `agenda_config['calls']['meta']` = `{calling_status, callback_permission_status, checked_at, error}` |

Cron (`config/schedule.yml`): `Crm::SchedulerJob */5`, `Crm::FollowupBotJob */2` (queue `high`), `Crm::AttendanceReminderJob */30`, `Crm::OpportunityRadarJob */10`, `Crm::WeeklyMentorJob 0 11 * * 1`, `Crm::MonthlyMentorJob 30 11 1 * *`, `Crm::CommentsAgentJob */5`, `CrmStalledCardsJob */30`, `Crm::HarvestJob 10 12-20 * * 1-6`, `Crm::AutoManagerJob 10 11 * * 1-5`, `Crm::ConversationAuditorJob 40 10 * * *`, `Crm::CreativeJob 30 11 * * 1`, `Crm::AppointmentReminderSendJob */15`, `Crm::OftalmofacilSyncJob 7,22,37,52 * * * *`.

Config write path: `PATCH .../crm/settings/update_ai` — `app/controllers/api/v1/accounts/crm/settings_controller.rb:332` (`def update_ai`). Per-agent permit list at lines 351–387; **you must add your new key there** (`agent_fields = [:enabled, :prompt, :model, :effort, { draft: {} }]` plus your extras) or the save is silently dropped. Deep-merge semantics let the UI PATCH `{ agents: { calls_agent: { enabled: true } } }` alone.

---

## 5. Campaign audience + throttling

**`/Users/guilhermemartinscorder/chatwoot-upgrade/app/models/crm/campaign.rb:75`**

```ruby
def resolve_audience
  contacts = included_contacts
  contacts = contacts.where.not(id: excluded_contact_ids) if excluded_contact_ids.any?
  contacts = apply_period_filter(contacts)
  contacts.where.not(phone_number: [nil, '']).distinct
end
```
`audience` jsonb keys: `include_label_ids[]`, `include_stage_ids[]`, `exclude_label_ids[]`, `exclude_stage_ids[]`, `period_field` (`''` | `'contact_created'` | `'label_applied'`), `period_from`, `period_to`.
- labels → `account.labels.where(id:).pluck(:title)` then `account.contacts.tagged_with(titles, any: true)`
- stages → `Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: }, stage_id: stage_ids).pluck(:contact_id)`
- `period_field == 'label_applied'` → `ActsAsTaggableOn::Tagging.where(tag_id:, taggable_type: 'Contact', context: 'labels', created_at: range)`

**Frontend picker** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/javascript/dashboard/routes/dashboard/crm/components/ChipPicker.vue`. Props: `options: [{id,label,color}]`, `modelValue: []`, `placeholder: String`, `accent: 'brand'|'red'|'green'|'purple'`. Emits `update:modelValue`. Used 4× in `CrmCampaigns.vue` (lines ~864–938) with `labelOptions` / `stageOptions`, accent `brand` for include and `red` for exclude. Payload builder (`CrmCampaigns.vue:299`):

```js
const audiencePayload = () => ({
  include_label_ids: includeLabelIds.value, include_stage_ids: includeStageIds.value,
  exclude_label_ids: excludeLabelIds.value, exclude_stage_ids: excludeStageIds.value,
  period_field: periodField.value, period_from: periodFrom.value, period_to: periodTo.value,
});
```
Preview: `store.dispatch('crm/previewAudience', audiencePayload())` → `{ count }`.

**`/Users/guilhermemartinscorder/chatwoot-upgrade/app/jobs/crm/campaign_run_job.rb`** — `Crm::CampaignRunJob`, `queue_as :low`:

```ruby
THROTTLE_SECONDS = 0.2     # ~5 msg/s
LOCK_TTL = 2.hours
lock_key = "CRM_CAMPAIGN_RUN_LOCK::#{campaign.id}"
lock_manager = Redis::LockManager.new
return unless lock_manager.lock(lock_key, LOCK_TTL)
begin run_campaign(campaign) ensure lock_manager.unlock(lock_key) end
```
Idempotency: `already_sent = campaign.campaign_contacts.pluck(:contact_id).to_set`; progress persisted every 10 contacts via `update_column(:stats, stats)`; stats hash `{'total','sent','skipped','failed'}`; `apply_label` adds a label after send.

---

## 6. Sending WhatsApp from a tool webhook

**Template send** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/services/crm/send_template_service.rb`, `Crm::SendTemplateService.new(source:, contact:).perform` → returns the `Conversation` or `nil`. `source` must respond to `account, account_id, inbox, inbox_id, sender, template_params, message_preview` (`Crm::Campaign` and `Crm::MessageAutomation` qualify — a `Crm::CallCampaign` can too). It runs `Whatsapp::LiquidTemplateProcessorService`, `ContactInboxBuilder.new(contact:, inbox:).perform`, then creates the outgoing message with `additional_attributes: { template_params: processed }`.

**Free-text send respecting `can_reply?`** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/jobs/crm/followup_bot_job.rb`:

```ruby
# l.484 — one query per conversation per round; MessageWindowService = 24h WhatsApp/IG window
def can_reply?(conversation)
  @can_reply ||= {}
  return @can_reply[conversation.id] if @can_reply.key?(conversation.id)
  @can_reply[conversation.id] = conversation.can_reply?
end
# l.235 — free-text steps are dropped outside the window, template steps still go
unreachable, due = due.partition { |d| text_step?(d[:step]) && !can_reply?(conversation) }

# l.557 — the actual send
conversation.messages.create!(
  account_id: bot.account_id, inbox_id: conversation.inbox_id,
  message_type: :outgoing, content: render_message(step['message'], conversation),
  sender: bot.sender, additional_attributes: attrs)
```
Simpler variant in `app/jobs/crm/instagram_agent_job.rb:84` (`additional_attributes: { 'cevico_ia_agent' => 'instagram' }`, no sender). Private internal notes: `message_type: :activity, private: true` (same file, lines 147/170). `Conversation#can_reply?` → `Conversations::MessageWindowService`.

---

## 7. Public / unauthenticated controllers & routing pattern

CEVICO public controllers inherit `ActionController::Base` directly (not `ApplicationController`, so no `authenticate_user!` at all):

- `/Users/guilhermemartinscorder/chatwoot-upgrade/app/controllers/cevico_forms_controller.rb` — `class CevicoFormsController < ActionController::Base` with `protect_from_forgery with: :null_session`, `layout false`, `before_action :load_form`. Token = **Rails signed message verifier**, not HMAC headers:
  ```ruby
  # app/models/crm/form.rb:68
  token = Rails.application.message_verifier(:cevico_form).generate({ form_id: id, account_id:, contact_id: })
  def self.verify_token(token)
    Rails.application.message_verifier(:cevico_form).verify(token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
  ```
- `/Users/guilhermemartinscorder/chatwoot-upgrade/app/controllers/cevico_pages_controller.rb` — same base class, draft preview also via signed token.
- **No `webhooks/meta_leads_controller.rb` exists on this branch**; `app/controllers/webhooks/` has only `instagram, line, shopify, sms, telegram, tiktok, whatsapp`.

**HMAC pattern to copy** — `/Users/guilhermemartinscorder/chatwoot-upgrade/app/controllers/concerns/meta_token_verify_concern.rb`:

```ruby
META_SIGNATURE_HEADER = 'X-Hub-Signature-256'.freeze
def verify_meta_signature!
  return unless meta_signature_verification_required?
  return if valid_meta_signature?
  head :unauthorized
end
def valid_meta_signature?
  signature = request.headers[META_SIGNATURE_HEADER]
  expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
  ActiveSupport::SecurityUtils.secure_compare(expected, signature)
end
```
Used by `Webhooks::WhatsappController < ActionController::API` (`include MetaTokenVerifyConcern`; `before_action :verify_meta_signature!, only: :process_payload`; enqueues `Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)` then `head :ok`).

**Routes outside the api namespace** — `config/routes.rb`: CEVICO public block at lines 52–76 (`post 'forms/:slug'`, `get 'p/:slug'`, …) and the core webhook block at lines 999–1009 (`post 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#process_payload'`). Add ElevenLabs tool + post-call webhooks in the 999–1009 block (e.g. `post 'webhooks/elevenlabs/:token', to: 'webhooks/elevenlabs#tool'`), with HMAC verify (ElevenLabs uses `ElevenLabs-Signature: t=…,v0=…` — same `secure_compare` shape).

**Existing calls plumbing to mirror** (feature A overlaps heavily):
- `app/services/cevico/whatsapp_calls_webhook.rb` — `module Cevico::WhatsappCallsWebhook`, prepended into `Webhooks::WhatsappEventsJob` via `config/initializers/zz_cevico_calls.rb`; intercepts `field == 'calls'` and `interactive.type == 'call_permission_reply'`, routes to `Crm::Calls::WebhookService` / `Crm::Calls::PermissionReplyService`.
- `app/services/crm/calls/` — `outbound_service.rb` (`Crm::Calls::OutboundService#initiate(sdp_offer)`, `#request_permission`, `#permission_status`; `connect(to:, sdp:, callback_data: "cevico:#{account.id}:#{contact.id}")`), `meta_client.rb`, `webhook_service.rb`, `settings.rb`, `conversation_finder.rb`, `broadcaster.rb`, `transcription_service.rb` (`AGENT_KEY = 'calls_transcription'`), `dashboard_service.rb`, `card_message_builder.rb`.
- Authenticated routes: `config/routes.rb:435-449` — `resources :calls, controller: 'calls'` with members `accept/reject/hangup/recording/transcribe` and collection `dashboard/initiate/request_permission/permission_status`.
- `ENV['CEVICO_CALLS_SIMULATE'] == '1'` (`Crm::Calls::Settings.simulate_env?`) + `rake cevico:calls_simulate` for local testing without Meta.

---

## 8. Frontend diagram/chart dependencies

**No `mermaid`, no `@vue-flow/*`, no `d3`, no `dagre`/`elkjs`/`cytoscape`.** Chart-related deps in `package.json`:

- `"chart.js": "~4.4.4"` (line 43) + `"vue-chartjs": "5.3.1"` (line 103)
- `"@chatwoot/viz": "^0.1.5"` (line 42) — exports `BarChart, LineChart, PercentageChart, **SankeyChart**` (used in `components-next/captain/pageComponents/overview/v2/ResolutionFlowCard.vue`). SankeyChart is the closest thing to a flow renderer already installed.
- Adjacent/useful: `html-to-image`, `html2canvas`, `vuedraggable` (`^4.1.0`), `@vueuse/core`.

CEVICO's own hand-rolled SVG chart kit (no deps) lives in `/Users/guilhermemartinscorder/chatwoot-upgrade/app/javascript/dashboard/components-next/cevico/`: `MiniBars.vue`, `HBars.vue`, `ShareBar.vue`, `DashKpi.vue`, `PeriodRuler.vue`, `SkeletonScreen.vue`, `CevicoPalettePicker.vue`, `CustomPanelGrid.vue`, `KpiDetailPopup.vue`, `EmojiFx.vue`, plus `calls/CevicoCallPopup.vue`, `calls/CevicoCallsCard.vue`. For "Mapa de Fluxos", the house style would be an inline-SVG component here rather than a new dependency; if you do add one, `@vue-flow/core` or `mermaid` would be net-new to `package.json`.