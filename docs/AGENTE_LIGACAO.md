# 🤖📞 AGENTE DE LIGAÇÃO (IA que atende e faz ligações) — contrato de construção (item 169, rodada 1)

Plataforma de voz: **ElevenLabs Agents** (Conversational AI). Tudo o que é nosso fica no
namespace **`Crm::VoiceAgent`** (backend) e prefixo **`voice`** (settings/eventos/rotas).
Nenhum toque em `enterprise/`. Textos em pt-BR direto no código (padrão CEVICO).

## 0. Decisões (17/09, Guilherme)
- Os números EXISTENTES continuam com as ligações no navegador (item 167, Graph API/WebRTC).
- O agente de IA usa um **NÚMERO PRÓPRIO** da clínica, importado na ElevenLabs.
- **Conexão: integração NATIVA ElevenLabs ↔ WhatsApp Business** (descoberta 17/09: a ElevenLabs
  importa a conta WhatsApp pelo painel dela via autorização da Meta, atende ligações e faz
  ligações de saída pela API — sem SIP/TLS/codec). O caminho SIP (Meta `calling.sip` →
  `sip.rtc.elevenlabs.io:5061`, G711/G722) fica **documentado como plano B** (§9), não construído.
- A IA se apresenta como **assistente virtual** logo na primeira frase (LGPD/boa prática).
- Mensagens de texto no número da IA: `enable_messaging: false` na ElevenLabs (ela só cuida
  de LIGAÇÕES). Toda conversa escrita com o paciente sai pela **caixa WhatsApp da clínica**
  (ferramenta `enviar_whatsapp`), onde o time já atende.

## 1. Pré-requisitos (amanhã, 18/09)
1. Conta ElevenLabs (plano com Agents) → **chave de API** (`xi-api-key`).
2. Número novo no WhatsApp Manager da CEVICO (WABA da clínica; não pode estar no app WhatsApp
   Business nem em outro provedor) → na ElevenLabs: WhatsApp → **Import account** →
   autorização da Meta → escolher o número → **desligar "Enable messaging"**.
   Em WhatsApp Manager → número → **Call settings**: ligar chamadas.
3. Um **modelo (template)** aprovado com componente **`call_permission_request`** (Meta) para as
   ligações de saída — nome + idioma (ex.: `pedido_ligacao`, `pt_BR`).
4. O sistema no ar com `FRONTEND_URL` público (as ferramentas e o webhook pós-chamada apontam
   para lá).

## 2. Dados

### Configuração — `crm_settings.ai_config['voice']`
```
{ enabled: bool,
  api_key: string (ElevenLabs; só gravada se enviada; nunca devolvida — `api_key_set`),
  webhook_secret: string (HMAC do webhook pós-chamada; criado por nós via API ou colado; `webhook_secret_set`),
  webhook_id: string,
  tools_token: string (SecureRandom.hex(24), gerado no 1º save; protege as ferramentas),
  agent_id: string, agent_name: 'Assistente virtual da CEVICO',
  tool_ids: { buscar_paciente:, horarios_livres:, marcar_consulta:, minha_consulta:, enviar_whatsapp:, registrar_resultado: },
  whatsapp_phone_number_id: string (id da conta WhatsApp NA ELEVENLABS), whatsapp_number: string (E.164, só exibição),
  connection: 'whatsapp' (padrão) | 'sip',
  voice_id: string, voice_name: string,
  llm: string (padrão 'gemini-2.5-flash'; opções: gemini-2.5-flash, gemini-3.5-flash, claude-haiku-4-5, claude-sonnet-4-5, gpt-4.1-mini),
  language: 'pt-br' (opções pt-br | pt), tts_model: 'eleven_flash_v2_5',
  first_message: text (padrão em Script::FIRST_MESSAGE), prompt: text (nil = Script::SYSTEM_PROMPT),
  transfer_number: string E.164 (vazio = sem transferência), transfer_condition: text,
  handoff_inbox_id: int (caixa WhatsApp da clínica p/ mensagens e p/ a conversa/card),
  handoff_template_params: {} (template p/ abrir conversa fora da janela de 24h; vazio = só texto livre),
  permission_template: { name:, language: } (call_permission_request p/ ligar),
  max_duration_seconds: 600, daily_limit: 200,
  hours: { start: '08:00', end: '19:00' } (campanhas só ligam nesta janela; recebidas: sempre),
  state: { synced_at, last_error, last_sync_log: [strings], webhook_created_at, whatsapp_assigned_at, last_call_at },
  updated_at }
```
Espelho p/ o Painel dos agentes: ao salvar, gravar também `ai_config['agents']['voice']['enabled']`.
Exposto em `settings_json` como `voice` (via `Crm::VoiceAgent::Settings#to_h`, com defaults,
sem segredos, e com `tools_base_url`/`post_call_url`/`initiation_url` prontos p/ copiar).

### Migration `db/migrate/20260917173000_add_voice_agent_to_cevico_calls.rb` (timestamp real)
`cevico_calls` +: `handled_by string null:false default 'human'` (human | ai), `provider string`
('elevenlabs'), `provider_call_id string` (conversation_id da ElevenLabs; index [account_id, provider_call_id]),
`outcome string` (agendou | remarcou | cancelou | quer_whatsapp | sem_interesse | recado | transferido | nao_atendeu | outro),
`campaign_id bigint` (index), `analysis jsonb default {}` (resumo/critérios/data_collection crus), `cost_usd decimal(12,6)`.
`meta_call_id` das ligações da IA = `"el:#{conversation_id}"` (a coluna é obrigatória e única).

Novas tabelas (mesma migration):
```
cevico_call_campaigns: account_id (fk cascade), name, status int (draft 0 | scheduled 1 | processing 2 | paused 3 | completed 4 | failed 5),
  audience jsonb {} (MESMAS chaves da Campanha WhatsApp), objective text, first_message text, apply_label string,
  hours jsonb, daily_cap int default 50, concurrency int default 2, scheduled_at, started_at, finished_at,
  stats jsonb {} {total, called, done, failed, skipped, outcomes:{}}, created_by_id bigint, timestamps
cevico_call_campaign_contacts: call_campaign_id (fk cascade), contact_id (fk cascade), status string 'queued'
  (queued | calling | done | failed | skipped | no_permission), provider_conversation_id (index), call_id bigint,
  outcome string, error text, attempts int default 0, called_at, timestamps; unique [call_campaign_id, contact_id]
```
Models: `Crm::CallCampaign` (`resolve_audience` = `Crm::Campaign.new(account:, audience:).resolve_audience`;
`scope :due`; `progress`), `Crm::CallCampaignContact`.

## 3. Backend — arquivos (todos novos, salvo indicado)
- `app/services/crm/voice_agent/settings.rb` — leitor com defaults (`enabled?`, `configured?` = api_key + agent_id,
  `within_hours?`, `handoff_inbox`, `tools_base_url` = `#{ENV['FRONTEND_URL']}/webhooks/cevico/voice/#{account.id}`, `to_h`).
- `app/services/crm/voice_agent/client.rb` — HTTParty p/ `https://api.elevenlabs.io` (header `xi-api-key`, timeout 20 s):
  `user` (GET /v1/user), `whatsapp_accounts` (GET /v1/convai/whatsapp-accounts), `update_whatsapp_account(id, assigned_agent_id:, enable_messaging:)`
  (PATCH /v1/convai/whatsapp-accounts/{id}), `create_webhook(name:, url:)` (POST /v1/workspace/webhooks `{settings:{auth_type:'hmac', name, webhook_url}}`
  → `{webhook_id, webhook_secret}`), `create_tool(cfg)` / `update_tool(id, cfg)` (POST /v1/convai/tools, PATCH /v1/convai/tools/{id}, corpo `{tool_config: cfg}`),
  `create_agent(body)` / `update_agent(id, body)` / `agent(id)` (POST /v1/convai/agents/create, PATCH|GET /v1/convai/agents/{id}),
  `whatsapp_outbound_call(...)` (POST /v1/convai/whatsapp/outbound-call), `conversation(id)`, `conversation_audio(id)`,
  `voices(search:)` (GET /v2/voices?language=pt&page_size=30&search=). Erros → `Crm::VoiceAgent::Error(message, status, body)`.
  **Simulação:** `ENV['CEVICO_VOICE_SIMULATE']=='1'` devolve ids falsos (`sim_agent_…`) sem chamar a rede.
- `app/services/crm/voice_agent/script.rb` — `SYSTEM_PROMPT` (persona "assistente virtual da CEVICO", regras de VOZ:
  frases curtas, sem listas/emoji/markdown, números e datas por extenso, confirmar telefone e dia/hora repetindo, no máximo 2 horários por vez;
  FLUXO: apresentação → motivo → `buscar_paciente` (já vem no contexto) → dúvidas com a tabela de preços/unidades →
  `horarios_livres` → `marcar_consulta` → `enviar_whatsapp` (confirmação) → `registrar_resultado` → despedida;
  quando transferir (pede humano, urgência, assunto fora do escopo); nunca diagnóstico; blocos `{{TABELA_DE_PRECOS}}`,
  UNIDADES/MÉDICOS copiados de `Crm::InstagramAgentService::SYSTEM_PROMPT`), `FIRST_MESSAGE`, `RESPONDER_GUARDRAIL`
  reaproveitado de `Crm::AiAgentConfig`, `build(account, settings)` (prompt custom || padrão) + preços + guardrail.
  Variáveis dinâmicas usadas: `{{paciente_nome}}`, `{{proxima_consulta}}`, `{{campanha_objetivo}}`, `{{system__caller_id}}`.
- `app/services/crm/voice_agent/tool_definitions.rb` — `all(account, settings)` → 6 `tool_config` (type 'webhook', method POST,
  `api_schema.url = "#{tools_base_url}/tools/<nome>"`, `request_headers: {'X-Cevico-Token' => tools_token}`, `response_timeout_secs: 20`,
  `request_body_schema` com `properties` descritas em pt-BR; `telefone` = `{ type:'string', dynamic_variable:'system__caller_id' }` onde couber,
  `conversa_id` = `dynamic_variable:'system__conversation_id'`):
  | nome | entradas | devolve |
  |---|---|---|
  | `buscar_paciente` | telefone | `{encontrado, nome, primeiro_nome, telefone, proxima_consulta (texto), etapa_funil, unidade_preferida}` |
  | `horarios_livres` | unidade? (tatuape/paulista), medico?, dias? (padrão 7) | `{horarios:[{data,dia,hora,unidade,medico}], texto}` (máx. 6) |
  | `marcar_consulta` | nome, telefone, data (AAAA-MM-DD), hora (HH:MM), unidade, medico?, procedimento?, observacoes? | `{ok, resultado: marcada/remarcada/ja_existia/horario_indisponivel, mensagem, consulta}` |
  | `minha_consulta` | telefone | `{encontrada, quando (texto), unidade, medico, data, hora}` |
  | `enviar_whatsapp` | telefone, tipo (confirmacao/continuar/resumo), texto? | `{ok, motivo?}` |
  | `registrar_resultado` | resultado (enum §2), resumo, conversa_id | `{ok}` |
- `app/services/crm/voice_agent/tools_service.rb` — `new(account:, tool:, params:, conversation_id:).perform` → Hash (strings pt-BR).
  Reusa: `Task.match_contact`, `Crm::AgendaSlots.free_slots/slot_available?`, `Redis::LockManager` (`CRM_SLOT_LOCK::…`, como
  `instagram_agent_job.rb:106`), `Crm::AppointmentRecorder.record/log_activity`, `Crm::Calls::ConversationFinder` (caixa handoff),
  `Crm::SendTemplateService` c/ `TemplateSource = Struct.new(:account, :inbox, :sender, :template_params, :message_preview, :name)`
  (texto livre só se `conversation.can_reply?`; senão template; senão `{ok:false, motivo:'janela fechada'}`; mensagens marcadas
  `additional_attributes: { cevico_ia_agent: 'voice' }`). Toda chamada de ferramenta faz `upsert_call` (Crm::Call por
  `provider_call_id`, `handled_by:'ai'`, `status: accepted`, `started_at ||= now`, contato pelo telefone) e nota privada curta na conversa.
- `app/services/crm/voice_agent/agent_body.rb` — corpo de create/patch do agente:
  `conversation_config: { agent: { first_message, language, prompt: { prompt, llm, temperature: 0.3, tool_ids, built_in_tools: { end_call: {type:'system', name:'end_call', params:{system_tool_type:'end_call'}}, transfer_to_number: (se transfer_number) {type:'system', name:'transfer_to_number', params:{system_tool_type:'transfer_to_number', transfers:[{transfer_destination:{type:'phone', phone_number}, condition, transfer_type:'conference'}]}} } } , tts: { voice_id, model_id: tts_model, stability: 0.5, similarity_boost: 0.8 }, turn: { turn_timeout: 7 }, conversation: { max_duration_seconds } }`,
  `platform_settings: { workspace_overrides: { webhooks: { post_call_webhook_id, events: ['transcript','audio'] }, conversation_initiation_client_data_webhook: { url: initiation_url, request_headers: {'X-Cevico-Token' => tools_token} } }, overrides: { conversation_config_override: { agent: { first_message: true, language: true, prompt: { prompt: true } } }, enable_conversation_initiation_client_data_from_webhook: true }, call_limits: { daily_limit } }`, `name: agent_name`.
- `app/services/crm/voice_agent/sync_service.rb` — `new(account).perform` idempotente, em ordem, com log humano:
  (1) `webhook_secret` vazio → `create_webhook` e guarda id+segredo; (2) ferramentas: cria as que não têm id, atualiza as que têm;
  (3) agente: cria ou atualiza; (4) `whatsapp_phone_number_id` presente → `update_whatsapp_account(assigned_agent_id, enable_messaging:false)`.
  Grava `state.synced_at`/`last_sync_log`/`last_error`. Devolve `{ ok, log, error, voice }`.
- `app/services/crm/voice_agent/post_call_service.rb` + `app/jobs/crm/voice_agent/post_call_job.rb` (queue low) —
  `post_call_transcription`: upsert `Crm::Call` (`meta_call_id "el:…"`, `provider_call_id`, `handled_by 'ai'`, direction por
  `metadata.whatsapp.direction` / `metadata.phone_call.direction` / contato de campanha, `wa_id` por `metadata.whatsapp.whatsapp_user_id`
  ou dynamic var `telefone`/`system__caller_id`, `started_at` = start_time_unix_secs, `duration` = call_duration_secs, `status`
  completed (ou `missed` se duração 0/`failed`), transcript "Assistente: …\nPaciente: …" (role agent/user), `summary` =
  `analysis.transcript_summary`, `outcome` ||= `analysis.data_collection_results['resultado']`, `analysis` cru (sem transcript),
  `cost_usd` = `metadata.cost_fiat`, contato+conversa via `ConversationFinder` (caixa handoff), `CardMessageBuilder`, broadcast
  `cevico_call.ended`, `Crm::AiUsage.create!(agent_key:'voice', model: llm, cost_usd:)`, atualiza `CallCampaignContact`
  por `provider_conversation_id` (done + outcome + call_id) e `stats` da campanha. `post_call_audio`: base64 mp3 → `recording`
  (`audio/mpeg`) + card. `call_initiation_failure`: contato da campanha → failed.
- `app/controllers/webhooks/cevico_voice_controller.rb` (`< ActionController::API`):
  - `POST /webhooks/cevico/voice/:account_id/tools/:tool` — header `X-Cevico-Token` == `tools_token` (secure_compare) → ToolsService → JSON 200 (erro → `{ok:false, erro}` 200 p/ a IA ler; 401 se token errado).
  - `POST /webhooks/cevico/voice/:account_id/initiation` — mesmo token; body `{caller_id, agent_id, called_number, call_sid}` →
    `{ type:'conversation_initiation_client_data', dynamic_variables:{ paciente_nome, primeiro_nome, proxima_consulta, telefone }, conversation_config_override:{ agent:{ first_message: (personalizada c/ nome) } } }`.
  - `POST /webhooks/cevico/voice/:account_id/post_call` — header `ElevenLabs-Signature: t=<ts>,v0=<hex>`; esperado
    `'v0=' + HMAC_SHA256(webhook_secret, "#{ts}.#{raw_body}")` (hex, `secure_compare`); rejeita `ts` com mais de 30 min; corpo lido com
    `request.raw_post` (memoizado). OK → `PostCallJob.perform_later(account_id, payload)` → `head :ok`.
  Rotas no bloco de webhooks de `config/routes.rb` (já adicionadas).
- `app/controllers/api/v1/accounts/crm/call_campaigns_controller.rb` — `require_capability(:campaigns)` p/ escrita:
  `GET crm/call_campaigns` (lista c/ progress), `GET :id` (c/ contatos paginados `?page=` 50), `POST` (create), `PATCH :id`, `DELETE :id`,
  `POST :id/start` (resolve público → cria `CallCampaignContact` queued p/ quem ainda não tem; status processing; `started_at`),
  `POST :id/pause`, `POST :id/resume`, `POST preview_audience` (`{count, sample}` como a Campanha WhatsApp).
- `app/jobs/crm/voice_agent/campaign_dialer_job.rb` — cron `*/5 * * * *` (queue low, `config/schedule.yml` `crm_voice_campaign_dialer_job`):
  p/ cada conta c/ `voice.enabled` e campanhas `processing` dentro de `hours`: fecha `calling` c/ mais de 30 min sem pós-chamada (→ failed 'sem retorno');
  respeita `concurrency` e `daily_cap`; p/ cada `queued` disponível → `client.whatsapp_outbound_call(whatsapp_phone_number_id:, whatsapp_user_id: dígitos,
  whatsapp_call_permission_request_template_name:, …language_code:, agent_id:, conversation_initiation_client_data: { dynamic_variables: { paciente_nome, primeiro_nome, telefone, campanha_objetivo, campanha_id, contato_id }, conversation_config_override: { agent: { first_message } } })`
  → grava `provider_conversation_id`, `status calling`, `called_at`, cria `Crm::Call` outbound ringing `handled_by 'ai'`; erro → failed + error.
  Campanha sem queued/calling → completed + `finished_at`. Lock Redis `CRM_VOICE_DIALER_LOCK::<account>` 4 min.
- `app/controllers/concerns/crm/voice_agent_settings.rb` (incluído no `SettingsController`; ações já na lista admin e nas rotas):
  `update_voice` (permit dos campos de §2; `api_key`/`webhook_secret` só se presentes; gera `tools_token` se vazio; espelha `agents.voice.enabled`;
  devolve `{voice: to_h}`), `test_voice` (`client.user` → `{ok, name, tier}`), `sync_voice` (SyncService), `voice_whatsapp_accounts`
  (lista da ElevenLabs), `voice_voices` (`?search=`), `voice_state` (state + últimas 10 ligações da IA).
  `settings_json` ganha `voice: voice_json(s)`; `update_ai` permite `voice: agent_fields`; `default_prompts['voice'] = Crm::VoiceAgent::Script::SYSTEM_PROMPT` (já feito).
- `app/services/crm/calls/dashboard_service.rb` (item 167, nosso): + `kpis.ai_answered`, `kpis.ai_outbound`, `by_handler`
  `[{handled_by, count, total_talk_seconds}]`, `by_outcome` `[{outcome, count}]`; `recent` já traz `handled_by/outcome` pelo payload.
- `app/models/crm/call.rb` (nosso): `to_payload` + `handled_by, outcome, provider, campaign_id, summary`; `card_content` p/ IA
  ("🤖 Ligação atendida pela assistente virtual · 2 min 10 s · agendou consulta" / "🤖 A assistente ligou para o paciente · …");
  `scope :by_ai`; `OUTCOME_LABELS`.
- Rake `lib/tasks/cevico_voice.rake`: `cevico:voice_simulate ACCOUNT_ID= [PHONE=] [OUTCOME=agendou] [DIRECTION=inbound]`
  (monta um payload `post_call_transcription` realista e passa pelo `PostCallService`), `cevico:voice_tools ACCOUNT_ID= PHONE=`
  (roda as 6 ferramentas localmente e imprime), `cevico:voice_sync ACCOUNT_ID=` (SyncService; com `CEVICO_VOICE_SIMULATE=1` não chama a rede).
- Specs: `spec/controllers/webhooks/cevico_voice_controller_spec.rb` (token ok/errado; assinatura ok/errada/velha),
  `spec/services/crm/voice_agent/tools_service_spec.rb` (buscar_paciente, horarios_livres, marcar_consulta cria Task, registrar_resultado),
  `spec/services/crm/voice_agent/post_call_service_spec.rb` (cria call + card + AiUsage; fecha contato de campanha).

## 4. Frontend
- `settings/integrations/CevicoVoiceAgent.vue` (rota `crm_integrations_voice_agent`, path `voice-agent`; card em `Index.vue`
  já adicionado): mesmo esqueleto de `CevicoCalls.vue` (SettingsLayout + BaseSettingsHeader, `inputClass`, `useAlert`, bloco de
  erro cru). Seções: **1 Conexão** (chave da API + "Testar"; segredo do webhook (opcional — o Sincronizar cria); URLs prontas p/
  copiar); **2 Número do WhatsApp** (botão "Buscar contas na ElevenLabs" → select `whatsapp_phone_number_id`; aviso do passo
  "Import account"); **3 Persona e voz** (nome, voz c/ busca `voice_voices`, modelo LLM, idioma, primeira frase, script
  (textarea c/ "Restaurar padrão"), transferir para (telefone + condição)); **4 WhatsApp da clínica** (caixa handoff, template
  de continuidade via `TemplatesPicker` como na Colheitadeira, template de permissão nome/idioma); **5 Limites** (horário das
  campanhas, duração máxima, teto diário); barra: Salvar · **Sincronizar com a ElevenLabs** (mostra o log passo a passo) ·
  Ligar/Desligar; painel **Estado** (`state`, últimas ligações da IA c/ link p/ a conversa); "Como usar" numerado.
- `api/crm.js` + `store/modules/crm.js` (já adicionados): `updateVoice`, `testVoice`, `syncVoice`, `voiceWhatsappAccounts`, `voiceVoices`, `voiceState`.
- `api/cevicoCallCampaigns.js` (ApiClient `crm/call_campaigns`): list, show, create, update, destroy, start, pause, resume, previewAudience.
- `crm/CrmCampaigns.vue`: 4ª aba **`calls` "Ligações"** (pílula gradiente `#7C3AED→#DB2777`, ícone `i-lucide-phone-call`) → componente novo
  `crm/components/CallCampaignsTab.vue` (props `labelOptions`, `stageOptions`): lista (nome, status, progresso `done/total`, resultados por
  tipo) + formulário (nome, objetivo, primeira frase, público via `ChipPicker` ×4 + período, horário, teto/dia, simultâneas, etiqueta pós,
  agendar p/ data ou "Começar agora") + detalhe c/ tabela de contatos (status, resultado, duração, link p/ a conversa). Aviso fixo quando
  `voice.enabled` é falso ou falta `permission_template`.
- `components-next/message/bubbles/CevicoCall.vue` e `cevico/calls/CevicoCallsCard.vue`: quando `handled_by === 'ai'` mostrar 🤖
  "assistente virtual" no lugar do atendente + chip do `outcome` (labels pt-BR) + resumo.
- `settings/reports/CallsDashboard.vue`: bloco "Humanos × assistente virtual" (`by_handler`) + "Resultados das ligações da IA" (`by_outcome`) c/ `HBars`/`ShareBar`.
- Registro do agente: `AGENT_META.voice` em `ai_dashboards_controller.rb` e `AutomationsHub.vue` + grupo "Atendimento ao paciente" (já feito).

## 5. Toques em arquivos existentes (só estes)
`config/routes.rb` (crm: `voice_*` no `resource :settings`, `resources :call_campaigns`; webhooks públicos `webhooks/cevico/voice/...`),
`settings_controller.rb` (lista admin, `include Crm::VoiceAgentSettings`, `voice_json`, `update_ai` permit, `default_prompts`),
`ai_dashboards_controller.rb` (AGENT_META), `AutomationsHub.vue` (AGENT_META + grupo), `api/crm.js`, `store/modules/crm.js`,
`integrations/Index.vue`, `integrations.routes.js`, `config/schedule.yml`, `db/schema.rb`, e os nossos do item 167
(`crm/call.rb`, `calls/dashboard_service.rb`, `CevicoCall.vue`, `CevicoCallsCard.vue`, `CallsDashboard.vue`), `crm/CrmCampaigns.vue`.

## 6. Fluxo ponta a ponta (recebida)
Paciente liga p/ o número da IA → Meta → ElevenLabs atende c/ o agente → (opcional) webhook `initiation` devolve nome/próxima
consulta → IA conversa usando as ferramentas (`X-Cevico-Token`) → cada ferramenta grava/atualiza a `Crm::Call` (status accepted) →
fim: ElevenLabs manda `post_call_transcription` (+ `post_call_audio`) assinado → `PostCallService` fecha a ligação: card na conversa
da caixa da clínica, transcrição, resumo, resultado, custo → popup/Espaço do Paciente/Dashboard já mostram (mesma tabela do 167).

## 7. Fluxo ponta a ponta (campanha)
Admin cria campanha (público = etiquetas/etapas/período) → Começar → contatos `queued` → dialer a cada 5 min dentro do horário →
`whatsapp/outbound-call` (a ElevenLabs manda o template de permissão e liga quando o paciente aceita) → `calling` →
pós-chamada fecha o contato c/ `outcome` → campanha `completed` quando a fila esvazia. Sem permissão/recusa → `no_permission`/`failed`.

## 8. Fora desta rodada
Transferência quente com contexto (SIP REFER), voz clonada, agente por unidade, mensagens de texto no número da IA,
plano B SIP (§9), gravação no nosso Active Storage p/ ligações longas (>18 MB).

## 9. Plano B — SIP (documentado, não construído)
Meta: `POST /{PHONE_NUMBER_ID}/settings {calling:{sip:{status:'ENABLED', webhook_delivery:'ENABLED', servers:[{hostname:'sip.rtc.elevenlabs.io', port:5061}]}}}`
(TLS obrigatório; com SIP ligado a Graph de chamadas desliga no número). ElevenLabs: `POST /v1/convai/phone-numbers {provider:'sip_trunk', phone_number, label, agent_id, inbound_trunk_config:{media_encryption:'allowed', allowed_numbers/credentials}, outbound_trunk_config:{address:'wa.meta.vc', transport:'tls', media_encryption:'required', credentials:{username:<nº comercial>, password:<sip_user_password>}}}`.
Áudio: ElevenLabs fala G711/G722 → a Meta precisa de `audio.additional_codecs` PCMU/PCMA. Risco: ICE/DTLS da Meta × SDES da ElevenLabs — por isso o nativo é o caminho.
