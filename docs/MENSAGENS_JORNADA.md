# 🗺️ MENSAGENS DA JORNADA — contrato de construção (item 168, rodada 171)

Motor NATIVO de mensagens-modelo por gatilho de data/etapa ao longo da jornada do
paciente. Substitui o N8N "CONFIRMACAO CIRURGICA - IOP" e vira a porta de entrada para as
"centenas" de mensagens da jornada. Tela: **Jornada do paciente** (`/crm/jornada`).

## Dados
- `cevico_journey_messages` (`Crm::JourneyMessage`): name, active, step (lead|consulta|orcamento|
  cirurgia|pos_op|retorno), inbox_id, `trigger` {kind: surgery|appointment|stage|label|call_missed,
  offset_days (−1 véspera, 0 no dia, +N depois), at 'HH:MM', stage_id, label}, `audience` (mesmas
  chaves da Campanha WhatsApp), `content` {mode template|text, template_params, message_preview,
  text}, approval auto|review, expects_reply, confirm_label, decline_alert, respect_quiet, position.
- `cevico_journey_sends` (`Crm::JourneySend`): 1 por paciente × evento (`event_key` único por
  mensagem: `surgery:<id>`, `task:<id>`, `stage:<crm_contact_id>:<data>`, `label:<tagging_id>`,
  `call:<id>`); status queued|pending_review|sent|skipped|failed|expired; reply confirmed|declined;
  preview (texto final), variables (tokens usados), conversation_id, source polimórfico.
- Configuração geral em `agenda_config['journey']`: places {default, tatuape, paulista, clinics
  {'IOP' => {unidade, endereco}}}, hours (08:00–20:00), daily_cap (300), quiet_labels extras.

## Motor (`Crm::JourneyRunJob`, cron 3,18,33,48 * * * *, lock Redis por conta)
1. **Planner** — para cada mensagem ativa acha os eventos de HOJE pelo gatilho (cirurgia
   agendada no espelho OftalmoFácil com `surgery_date = hoje − offset`; consulta na Agenda;
   card que entrou na coluna; etiqueta recebida; ligação perdida sem retorno), filtra pelo
   público e cria o send com a hora da regra (review → pending_review; senão queued).
2. **Dispatcher** — envia os queued cuja hora chegou, dentro da janela, respeitando silêncio
   (nao_perturbe/perda_*/lista) e teto diário. Modelo aprovado sai pelo `Crm::SendTemplateService`
   (chega com a janela de 24h fechada); texto livre só se `conversation.can_reply?`. Envio
   pendente há mais de 12 h → expired. `dispatch(send)` é o mesmo caminho da aprovação manual.
3. **Variables** — tokens `{{nome}} {{primeiro_nome}} {{data}} {{dia_semana}} {{hora}} {{unidade}}
   {{endereco}} {{procedimento}} {{medico}}` trocados nos VALORES das variáveis do modelo (ou no
   texto) antes do Liquid; unidade/endereço vêm de `places` (por `task.unit` ou `clinic_name`).
4. **ReplyService** (CrmListener, toda mensagem recebida) — quem tem send `sent` com
   `expects_reply` nos últimos 3 dias: "confirmo/sim/👍" → reply confirmed + etiqueta
   `confirm_label` + nota ✅; "não/remarcar/cancelar" → reply declined + nota ⚠️ + conversa
   aberta + aviso no Radar (`Crm::Journey::RadarAlert`, kind journey_reply, some quando a clínica
   responde). "Não" vence "sim" na mesma frase.

## API (namespace crm; escrita = área `campaigns`)
`journey_messages` index (mensagens + stats + steps/kinds/tokens + settings + fila de hoje) ·
create/update/destroy · POST preview (prévia com paciente real do próximo evento) · POST :id/test_send
{phone} · POST :id/plan_now · GET settings · POST update_settings {places, hours, daily_cap, quiet_labels}.
`journey_sends` index (?message_id&status&contact_id&page) · GET queue (?date) · POST :id/approve ·
:id/skip · :id/retry · POST approve_all (?date&message_id).

## Frontend
`crm/CrmJourney.vue` (Fila de hoje, linha do tempo por etapa, histórico, teste, locais/horário) +
`crm/components/JourneyWizard.vue` (3 passos: Quando / Para quem / O quê) + `api/cevicoJourney.js`.
Sidebar "Jornada do paciente" (grant campaigns). Fluxograma `Crm::FlowMap::Flows::Journey`.

## Compartilhado
`Crm::TemplateSource` (fonte leve do SendTemplateService) substituiu as 3 cópias do Struct
(lembretes, automações de coluna, assistente virtual).

## Fora desta rodada
Migrar Lembretes D-1/D-0, Régua de mensagens e Automações de coluna para o motor novo (a tela
mostra links para elas); modelos com botões/mídia e resposta por botão; estatísticas de entrega
(delivered/read) por mensagem.

## Mapa da jornada (item 173)

`GET crm/journey_messages/map` (`Crm::Journey::MapService`) devolve, por etapa,
tudo o que já age no paciente além das mensagens da jornada: lembretes D-1/D-0,
follow-ups, réguas de mensagens, automações de coluna, campanhas e agentes
(ligado/desligado, quando, detalhe, link para onde se edita). Coluna do CRM →
etapa é adivinhada pelo nome e ajustável. Personalização em
`agenda_config.journey.map` (`stage_steps`, `overrides`, `hidden`, `show`,
`step_order`, `step_labels`, `density`, `queue`), salva por
`POST update_settings { map }`. A tela `crm/CrmJourney.vue` mostra tudo numa
grade que embrulha (sem rolagem lateral), com a Fila de hoje ao lado, em cima
ou oculta.
