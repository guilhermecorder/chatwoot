# 📞 CHAMADAS NATIVAS DE WHATSAPP — contrato de construção (item 167, rodada 1)

Módulo 100% CEVICO (nada de `enterprise/`). Escrito a partir da documentação oficial
da Meta (WhatsApp Business Calling API). Branch `feat/chamadas-nativas`.

## Regras de ouro
- Nenhum `require`/`import`/chamada a código de `enterprise/`. Não usar `Call`,
  `Voice::*`, `Whatsapp::CallService`, `useCallsStore`, `useWhatsappCallSession`,
  `whatsapp_calls` API, eventos `voice_call.*`. Tudo nosso tem prefixo **cevico**.
- Toque mínimo em arquivos do upstream (lista no fim). Tudo o mais em arquivos novos.
- Textos em pt-BR direto no código (padrão CEVICO), tom humano, sem jargão.
- Rubocop limpo nos .rb novos; ESLint sem erros novos nos .vue/.js (regras de i18n e
  inline-style são baseline do fork — ignorar).

## 1. Dados

### Tabela `cevico_calls` — migration `db/migrate/20260917000001_create_cevico_calls.rb`
Model `Crm::Call` em `app/models/crm/call.rb` (`self.table_name = 'cevico_calls'`).
```
account_id        references accounts, null: false, index
inbox_id          references inboxes,  null: false
contact_id        references contacts, null: true
conversation_id   references conversations, null: true
user_id           references users (atendente que atendeu/ligou), null: true
message_id        bigint null (mensagem-card na conversa)
meta_call_id      string null:false; unique index [account_id, meta_call_id]
direction         integer null:false default 0   # enum { inbound: 0, outbound: 1 }
status            integer null:false default 0   # enum { ringing: 0, accepted: 1, completed: 2, missed: 3, rejected: 4, failed: 5, canceled: 6 }
wa_id             string   # número do paciente (dígitos, como vem da Meta)
display_name      string   # profile.name do WhatsApp
started_at, answered_at, ended_at   datetime
duration          integer  # segundos (terminate.duration da Meta; fallback ended-answered)
end_reason        string   # completed | not_answered | rejected | outside_hours | failed | canceled | hangup
error_code        string; error_message text
sdp_offer         text     # inbound: oferta da Meta (apagar após accept/terminate)
sdp_answer        text     # outbound: resposta da Meta (apagar após uso)
events            jsonb default []   # linha do tempo crua: [{at, event, status, raw...}]
recording_duration integer; recording_mime string
transcript        text; transcript_status string # nil|pending|processing|done|failed|skipped
transcript_error  text; summary text; transcribed_at datetime
simulated         boolean default false  # chamada de simulação local (rake) — pula Meta/WebRTC
timestamps
index [account_id, started_at], [account_id, status], [contact_id], [user_id]
```
`has_one_attached :recording`. Scopes: `in_period(since, until)`, `inbound`, `outbound`,
`answered` (accepted+completed), `missed`.
Métodos: `talk_seconds` (duration || ended-answered || 0), `wait_seconds`
(answered-started), `to_payload` (hash p/ JSON e cable, ver §4), `card_content` (texto
humano: "📞 Chamada recebida · atendida por Dani · 3 min 42 s" / "📵 Chamada perdida" /
"📞 Ligação para o paciente · 2 min 10 s").

### Configuração — `crm_settings.agenda_config['calls']`
**Várias caixas (18/09):** `inboxes: [{ inbox_id, ring_user_ids, ring_first_user_ids, ring_cascade_seconds (5–60),
meta: { calling_status, callback_permission_status, checked_at, error } }]` — cada caixa com seus atendentes, sua
linha de frente (toca primeiro; os demais após a espera) e seu estado na Meta. `inbox_id`/`ring_*`/`meta` soltos =
espelho da PRIMEIRA caixa (compatibilidade; a config antiga de 1 caixa migra sozinha em `Crm::Calls::Settings#inboxes`).
Ligar PARA o paciente: `Settings#outbound_inbox_for(contact:, preferred_id:)` = caixa da conversa aberta (o botão manda
`inbox_id`) → caixa da última conversa dele entre as configuradas → primeira.
```
{ enabled: bool, inbox_id: int, ring_user_ids: [int] (vazio = todos os membros da caixa),
  business_hours_only: bool, hours: { start: "08:00", end: "19:00" } (fallback agenda_config.followup_hours / 8..20),
  permission_message: text (pedido de permissão p/ ligar),
  record: bool (default true), transcribe: bool (default true),
  meta: { calling_status, callback_permission_status, checked_at, error } (último GET/POST /settings na Meta),
  updated_at }
```
Exposto em `settings_json` como `calls` (com defaults preenchidos). Endpoints (admin,
`require_capability(:settings)`), em `resource :settings`:
- `POST crm/settings/update_calls` (salva; params permitidos acima)
- `POST crm/settings/enable_calls_at_meta` → MetaClient.update_settings(ENABLED, callback ENABLED) + GET p/ confirmar; devolve `{ ok, meta: {...}, error }`. Erro da Meta vem em texto humano + o `message` cru (p/ o Henrique). Dica fixa quando falhar: "A Meta exige limite de 2.000 mensagens/dia ou mais neste número".
- `GET crm/settings/calls_meta_status` → GET /settings (calling) + `messaging_limit_tier`/`quality_rating` do `channel.phone_number_health` se existir.

## 2. Backend — arquivos
- `config/initializers/zz_cevico_calls.rb`: `Rails.application.config.to_prepare { Webhooks::WhatsappEventsJob.prepend(Cevico::WhatsappCallsWebhook) }`.
- `app/services/cevico/whatsapp_calls_webhook.rb` (module): sobrescreve
  `handle_message_events(channel, params)` e `contact_sender_id(params)`:
  - `field == 'calls'` → `Crm::Calls::WebhookService.new(channel:, value:).perform` (se
    módulo ligado p/ a conta e `channel.inbox_id == cfg.inbox_id`; senão `super`).
  - `value.messages[0].interactive.type == 'call_permission_reply'` → `Crm::Calls::PermissionReplyService` e NÃO chama super (evita mensagem "não suportada").
  - `contact_sender_id`: p/ eventos de chamada devolve `"call:#{call_id}"` (mutex por chamada).
- `app/services/crm/calls/meta_client.rb` — `Crm::Calls::MetaClient.new(channel)`:
  base `ENV.fetch('WHATSAPP_CLOUD_BASE_URL','https://graph.facebook.com')`, versão `v23.0`
  (constante), `phone_number_id`/`api_key` do `provider_config`. Métodos: `pre_accept(call_id, sdp)`,
  `accept(call_id, sdp)`, `reject(call_id)`, `terminate(call_id)`, `connect(to:, sdp:, callback_data:)`
  → call_id, `settings` (GET), `update_settings(hash)`, `call_permissions(wa_id)`,
  `send_permission_request(to:, text:)` (POST /messages interactive call_permission_request).
  Corpo exato da doc: `{messaging_product:"whatsapp", call_id, action, session:{sdp_type:"answer", sdp}}`.
  Timeout 10 s. Erros → `Crm::Calls::MetaError(message, code)`. **Simulação:** se
  `call.simulated` ou `ENV['CEVICO_CALLS_SIMULATE']=='1'`, não chama a Graph e devolve sucesso.
- `app/services/crm/calls/webhook_service.rb` — `perform`: p/ cada `value['calls']`:
  `connect`+offer (USER_INITIATED) → `handle_inbound_connect`; `connect` c/ `sdp_type: 'answer'`
  (BUSINESS_INITIATED) → `handle_outbound_answer`; `terminate` → `handle_terminate`. P/ cada
  `value['statuses']` c/ `type == 'call'` → `handle_status` (RINGING/ACCEPTED/REJECTED…).
  - `handle_inbound_connect`: find_or_create `Crm::Call` por meta_call_id (idempotente);
    contato = `inbox.contact_inboxes.find_by(source_id: wa_id)&.contact` || `Task.match_contact(account, wa_id)`
    || cria (`name: profile.name || "WhatsApp #{wa_id}"`, `phone_number: "+#{wa_id}"`) + `ContactInboxBuilder`;
    conversa = última da caixa p/ o contato (qualquer status) ou cria (padrão `Crm::SendTemplateService#find_or_create_conversation`);
    reabre se resolved. Grava sdp_offer/started_at/display_name/status ringing; anexa evento.
    Se `business_hours_only` e fora do horário → `MetaClient.reject`, status rejected,
    end_reason outside_hours, card na conversa, broadcast `cevico_call.missed` (motivo fora do horário) e fim.
    Senão broadcast `cevico_call.ringing` c/ `to_payload(include_sdp: true)` + `ring_user_ids` resolvidos
    (cfg.ring_user_ids ou `inbox.members.pluck(:id)`).
  - `handle_terminate`: status final (answered_at? completed : (rejected? rejected : missed)),
    duration/ended_at/end_reason/errors; limpa sdp_offer; `Crm::Calls::CardMessageBuilder.new(call).perform`
    (cria/atualiza a mensagem-card); se missed → conversa `status: :open` + broadcast `cevico_call.missed`;
    sempre broadcast `cevico_call.ended`.
  - `handle_status`: anexa evento; ACCEPTED sem answered_at → seta; REJECTED → status rejected.
- `app/services/crm/calls/card_message_builder.rb`: cria (ou atualiza, via call.message_id)
  `conversation.messages.create!(account_id, inbox_id, message_type: :activity, private: false,
  content: call.card_content, content_attributes: { cevico_call: call.to_payload })`. Atualiza o
  content_attributes quando gravação/transcrição chegam (frontend re-renderiza pelo cable de message.updated).
- `app/services/crm/calls/broadcaster.rb`: `Crm::Calls::Broadcaster.push(account, event, data)` →
  `ActionCableBroadcastJob.perform_later(["account_#{account.id}"], event, data.merge(account_id: account.id))`.
- `app/services/crm/calls/permission_reply_service.rb`: grava em
  `contact.additional_attributes['cevico_call_permission'] = { status: accept|reject, permanent, expires_at, replied_at }`
  (via `Cevico::AttributeMerge`), nota privada na conversa ("✅ Paciente autorizou ligações até dd/mm hh:mm"),
  broadcast `cevico_call.permission` {contact_id, status, expires_at}.
- `app/services/crm/calls/transcription_service.rb` + `app/jobs/crm/calls/transcription_job.rb` (queue low):
  lê a gravação; se `ffmpeg` existir no PATH e mime webm → remuxa p/ ogg (`ffmpeg -y -i in.webm -c copy out.ogg`);
  Gemini `POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=`
  com `inline_data` (base64, mime audio/ogg ou audio/webm) + prompt pt-BR pedindo JSON
  `{ "transcricao": "Atendente: …\nPaciente: …", "resumo": "2 frases", "proximo_passo": "…" }`;
  chave = `crm_settings.ai_config['gemini_api_key']` (sem chave → transcript_status 'skipped',
  transcript_error "Configure a chave do Gemini em Integrações → IA"). Limite 18 MB (acima → skipped).
  Atualiza call + card message. Registra uso em `Crm::AiUsage` se o modelo existir com esse contrato (senão pular).
- `app/controllers/api/v1/accounts/crm/calls_controller.rb` — `Api::V1::Accounts::Crm::CallsController`
  (`include Crm::ResolvesPeriod`; leitura aberta ao time; `dashboard` exige `require_capability(:reports)`):
  ```
  GET  crm/calls?preset=|since=|until=|status=|direction=|user_id=|contact_id=|page=  → { calls: [payload], meta: {total} } (50/pág)
  GET  crm/calls/:id                                                                   → payload (sdp_offer só se ringing)
  POST crm/calls/:id/accept   { sdp_answer }  → with_lock; 409 {error:'já atendida por X'} se não ringing;
                                                 MetaClient.accept; status accepted, user_id, answered_at; broadcast cevico_call.taken {call_id,user_id,user_name}; → payload
  POST crm/calls/:id/reject                   → MetaClient.reject; rejected/end_reason rejected; card; broadcast ended
  POST crm/calls/:id/hangup                   → MetaClient.terminate; ended_at provisório; (terminate webhook fecha)
  POST crm/calls/:id/recording  multipart { recording, duration } → attach; recording_mime/duration; card; se cfg.transcribe → TranscriptionJob; → payload
  POST crm/calls/:id/transcribe               → reenfileira a transcrição
  GET  crm/calls/dashboard?preset=            → ver §5
  POST crm/calls/initiate       { contact_id, sdp_offer } → permissão (MetaClient.call_permissions) → sem permissão: 422 {error, permission:{...}};
                                                 MetaClient.connect → cria Crm::Call outbound ringing (meta_call_id da resposta) → payload
  POST crm/calls/request_permission { contact_id } → MetaClient.send_permission_request(cfg.permission_message); nota na conversa; → {ok}
  GET  crm/calls/permission_status?contact_id= → { status: temporary|permanent|no_permission|unknown, expires_at, can_call, can_request }
  ```
  Rotas em `config/routes.rb` DENTRO do `namespace :crm` (bloco CEVICO), sem tocar fora dele.
- Rake `lib/tasks/cevico_calls.rake`: `cevico:calls_simulate ACCOUNT_ID= [CONTACT_ID=|PHONE=] [SCENARIO=ringing|missed]`
  cria uma chamada `simulated: true` e dispara o mesmo caminho do webhook (connect com SDP fake
  "v=0 simulated"); com `SCENARIO=missed` dispara terminate 20 s depois. `cevico:calls_end CALL_ID=`
  simula o terminate. Serve p/ testar popup/card/dashboard sem a Meta.
- `docker/Dockerfile`: adicionar `ffmpeg` ao `apk add` de runtime (menor toque possível, comentário CEVICO).
- Specs (rspec): `spec/services/crm/calls/webhook_service_spec.rb` (connect cria call+contato+conversa e
  broadcast; terminate sem atender → missed + card + conversa open; terminate após accept → completed c/ duration)
  e `spec/controllers/api/v1/accounts/crm/calls_controller_spec.rb` (accept feliz, accept 409 na segunda,
  reject, dashboard 200). Stub `Crm::Calls::MetaClient` com `allow_any_instance_of` ou `simulated: true`.

## 3. Eventos em tempo real (ActionCable, stream `account_<id>`)
| evento | payload |
|---|---|
| `cevico_call.ringing` | `{ call: payload(+sdp_offer), ring_user_ids: [..] }` |
| `cevico_call.taken` | `{ call_id, user_id, user_name }` (os outros fecham o card) |
| `cevico_call.ended` | `{ call: payload }` |
| `cevico_call.missed` | `{ call: payload, reason }` |
| `cevico_call.outbound_answer` | `{ call_id, sdp_answer }` |
| `cevico_call.status` | `{ call_id, status }` |
| `cevico_call.permission` | `{ contact_id, status, expires_at }` |

## 4. `Crm::Call#to_payload(include_sdp: false)`
```
{ id, meta_call_id, direction, status, end_reason, started_at, answered_at, ended_at,
  duration (segundos), wait_seconds, contact: { id, name, phone_number, thumbnail }, conversation_id, inbox_id,
  user: { id, name, avatar_url } | null, recording_url (rails_blob_path se anexada) | null,
  recording_duration, transcript_status, has_transcript, summary, simulated, sdp_offer (só se include_sdp) }
```

## 5. `GET crm/calls/dashboard` (período via Crm::ResolvesPeriod)
```
{ period, kpis: { received, answered, missed, rejected, outbound, answer_rate (0-100),
                 avg_wait_seconds, avg_talk_seconds, total_talk_seconds },
  by_agent: [{ user_id, name, answered, total_talk_seconds, avg_talk_seconds, missed_while_ringing? }],
  by_day: [{ date, received, answered, missed }],
  by_hour: [24 ints] (recebidas por hora do dia, TZ São Paulo),
  by_reason: [{ reason, count }],
  recent: [payload × 30] }
```

## 6. Frontend — arquivos novos
- `app/javascript/dashboard/api/cevicoCalls.js` (ApiClient `crm/calls`): list, show, accept, reject,
  hangup, uploadRecording(FormData), transcribe, dashboard, initiate, requestPermission, permissionStatus.
- `app/javascript/dashboard/api/crm.js`: + `updateCalls`, `enableCallsAtMeta`, `callsMetaStatus`;
  `store/modules/crm.js`: + ações correspondentes (commit em `settings.calls`).
- `app/javascript/dashboard/stores/cevicoCalls.js` (Pinia): `calls` (map por id), `ringing`, `active`,
  `missedBanner`; ações `onRinging(payload)`, `onTaken`, `onEnded`, `onMissed`, `onOutboundAnswer`,
  `accept(id)`, `reject(id)`, `hangup(id)`, `dismiss(id)`, `startOutbound(contactId)`.
  Filtra `ring_user_ids` pelo usuário atual; ignora se `availability === 'offline'`.
- `app/javascript/dashboard/composables/useCevicoCallSession.js`: WebRTC puro:
  `answer(sdpOffer)` → getUserMedia({audio:true}) → RTCPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}]})
  → setRemoteDescription(offer) → createAnswer → setLocalDescription → esperar `iceGatheringState==='complete'`
  (timeout 3 s) → devolve `pc.localDescription.sdp`; `offer()` idem p/ outbound; `applyAnswer(sdp)`;
  remoto num `<audio autoplay>`; `mute()/unmute()`; `hangup()` fecha tudo; gravação: AudioContext mistura
  mic + remoto → MediaStreamDestination → MediaRecorder `audio/webm;codecs=opus` (fallback `audio/ogg;codecs=opus`)
  → blob no fim → `uploadRecording`. Se `call.simulated`: não abre WebRTC, só timer.
  Toque de chamada: WebAudio (2 osciladores, padrão "tum-tum … tum-tum"), para ao atender/fechar.
  `Notification` do navegador (se permitido) "📞 Fulano está ligando".
- `app/javascript/dashboard/components-next/cevico/calls/CevicoCallPopup.vue`: cards empilhados no canto
  inferior direito (z-index alto), 3 estados: **tocando** (iniciais/avatar, nome, telefone formatado,
  "ver conversa", Atender verde / Recusar vermelho, animação de pulso), **em chamada** (timer mm:ss, mudo,
  desligar, "ir para a conversa", ponto vermelho REC quando gravando), **encerrada** (resumo 6 s e some),
  **perdida** (banner "📵 Chamada perdida de X · há 2 min" + "Abrir conversa" + fechar). Vários cards ao
  mesmo tempo. Estilo do kit CEVICO (vidro, cantos 16px, sombra suave), claro/escuro.
  Montado em `routes/dashboard/Dashboard.vue` ao lado de `<RadarPriorityPopup />`.
- `app/javascript/dashboard/components-next/message/bubbles/CevicoCall.vue`: card na conversa a partir de
  `contentAttributes.cevico_call`: ícone por direção/status, título, "atendida por", duração, player de
  áudio (`recording_url`), transcrição (dobrável, "Atendente:/Paciente:"), resumo, botão "Transcrever" se
  status failed/skipped. Dispatch: 1 linha em `components-next/message/Message.vue#componentToRender`
  ANTES do `VOICE_CALL`: `if (props.contentAttributes?.cevico_call) return CevicoCallBubble;`.
- `helper/actionCable.js`: registrar os 7 eventos `cevico_call.*` → ações da store Pinia.
- Painel da conversa `routes/dashboard/conversation/contact/ConversationSummaryCard.vue`: bloco
  "📞 Ligações" (busca `crm/calls?contact_id=&limit=5`): total, tempo total falado, última chamada,
  lista curta; botão "Ligar" (se `settings.calls.enabled`): consulta `permission_status` → se pode ligar,
  `startOutbound`; senão oferece "Pedir permissão" (envia o pedido) e mostra o estado.
- Espaço do Paciente `routes/dashboard/patient/PatientSpace.vue`: card "Ligações" (componente novo
  `components-next/cevico/calls/CevicoCallsCard.vue` reutilizado no painel e no espaço) na fileira de cards.
- Relatório `routes/dashboard/settings/reports/CallsDashboard.vue` no kit iMac G3 (CevicoHero, PeriodRuler,
  DashKpi, HBars, ShareBar, useCevicoPalette scope `report:calls`, blocos kpis/agentes/dias/horas/recentes):
  rota `calls_dashboard_reports` (`reports.routes.js`, path `calls_dashboard`), item na Sidebar (array CEVICO:
  `{ name: 'Calls Dashboard', key: 'calls_dashboard', label: 'Dashboard de Ligações', route: 'calls_dashboard_reports' }`),
  `CEVICO_GRANTED_ROUTES.calls_dashboard_reports = ['reports']` em `routes/index.js`.
- Configuração: card "Ligações (WhatsApp)" em `settings/integrations/Index.vue` (cards CEVICO) → página
  `settings/integrations/CevicoCalls.vue` (rota `crm_integrations_calls`): toggle "Ativar ligações"
  (chama `enableCallsAtMeta` e mostra resultado/erro cru p/ o Henrique), caixa (só whatsapp_cloud), quem
  atende (multi-select de agentes; vazio = todos da caixa), só no horário, gravar, transcrever, mensagem de
  permissão; painel "Estado na Meta" (calling_status, callback, limite de mensagens/dia).

## 7. Toques em arquivos do upstream (só estes)
`config/routes.rb` (dentro do namespace :crm), `components-next/message/Message.vue` (1 linha + import),
`routes/dashboard/Dashboard.vue` (import + tag), `helper/actionCable.js` (eventos), `components-next/sidebar/Sidebar.vue`
(1 entrada no array CEVICO), `routes/index.js` (1 chave), `settings/reports/reports.routes.js`, `docker/Dockerfile` (ffmpeg).
Arquivos CEVICO já nossos: settings_controller.rb, ConversationSummaryCard.vue, PatientSpace.vue, integrations/Index.vue, api/crm.js, store/modules/crm.js.

## 8. Fora desta rodada
Transferência entre atendentes, correio de voz, SIP, canal Twilio, chamadas simultâneas na mesma conversa.
