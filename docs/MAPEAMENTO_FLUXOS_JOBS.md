# Passo a passo real dos agentes/automações CEVICO — insumo do Mapa de Fluxos (item 170)

Gerado 17/09 por agente de exploração lendo o código. Cada bloco = um fluxograma. Os passos são os
`if/return` REAIS dos jobs (cada decisão vira um losango). Caminhos relativos a `~/chatwoot-upgrade`.

## Cron CEVICO (`config/schedule.yml`)
| chave | cron | classe | queue |
|---|---|---|---|
| crm_scheduler_job | */5 | Crm::SchedulerJob (despacha campanhas + réguas) | scheduled_jobs |
| crm_followup_bot_job | */2 | Crm::FollowupBotJob | high |
| crm_attendance_reminder_job | */30 | Crm::AttendanceReminderJob | scheduled_jobs |
| crm_opportunity_radar_job | */10 | Crm::OpportunityRadarJob | scheduled_jobs |
| crm_weekly_mentor_job | 0 11 * * 1 | Crm::WeeklyMentorJob | scheduled_jobs |
| crm_monthly_mentor_job | 30 11 1 * * | Crm::MonthlyMentorJob | scheduled_jobs |
| crm_comments_agent_job | */5 | Crm::CommentsAgentJob | scheduled_jobs |
| crm_stalled_cards_job | */30 | CrmStalledCardsJob | scheduled_jobs |
| crm_harvest_job | 10 12-20 * * 1-6 | Crm::HarvestJob | low |
| crm_auto_manager_job | 10 11 * * 1-5 | Crm::AutoManagerJob | low |
| crm_conversation_auditor_job | 40 10 * * * | Crm::ConversationAuditorJob | low |
| crm_creative_job | 30 11 * * 1 | Crm::CreativeJob | low |
| crm_appointment_reminder_send_job | */15 | Crm::AppointmentReminderSendJob | low |
| crm_oftalmofacil_sync_job | 7,22,37,52 | Crm::OftalmofacilSyncJob | low |
| (novo, item 169) crm_voice_campaign_dialer_job | */5 | Crm::VoiceAgent::CampaignDialerJob | low |

## opportunity — Radar de Oportunidades (`app/jobs/crm/opportunity_radar_job.rb:12`, `app/services/crm/opportunity_radar_service.rb:79`)
Gatilho: cron */10 (ou "Radar pontual" pelo botão). Liga/desliga: `ai_config.agents.opportunity.enabled`.
1. account_id vindo do botão → varredura pontual c/ overrides e fim
2. Fora de 07:30–18:00 SP só roda nas janelas 20h/00h/04h; senão aborta
3. Conta com radar desligado → pula · 4. Sem vigias nem colunas → pula
5. Serviço: agente pausado / sem chave / nenhuma coluna → return
6. Carrega estado (alerts vivos, checked 6h, history) · 7. Teto 15 análises (auto) / 40 (manual)
8. Candidatos por vigia: conversas open dos contatos na coluna, esperando entre lookback e wait_minutes (limit 80)
9. Pula: alerta vivo / duplicada / já checada há < 6h
10. IA classifica (oportunidade/motivo/ação); erro → segue
11. `oportunidade == true` → cria alerta · 12. Grava alerts(30) + checked + history(500) + last_run
Saídas: avisos no Meu Painel; AiUsage 'opportunity'. Estado: `ai_config.opportunity_state {alerts, checked, history, last_run_at}`.

## followup_bots — Robôs de follow-up (`app/jobs/crm/followup_bot_job.rb:71`)
Gatilho: cron */2 (fila high). Liga/desliga: `crm_followup_bots.active` + janela começa/para (`within_window?`).
1. Lock Redis CRM_FOLLOWUP_BOT_JOB_LOCK 10 min · 2. Robô fora da janela → 'fora_da_janela'
3. Fora do horário de envio da conta (`agenda_config.followup_hours`, 08–20) → 'fora_do_expediente' · 4. Sem etapas → 'sem_etapas'
5. Uma conversa por contato (última atividade ≤ 3 dias, open; robô de coluna filtra stage/inbox)
6. Travas em cascata: paciente pausado → etiqueta de encerramento (nao_perturbe/perda_*) → filtro de etiquetas → paciente falou por último
7. Calcula prazo por etapa (âncora + espaçamento + próximo horário de envio)
8. Etapa bloqueada por skip/only_labels → tratada sem enviar · 9. Texto fora da janela 24h do WhatsApp → sem enviar (template passa)
10. Vencida há > 3h → "momento perdido" (anti-rajada)
11. Travas físicas: cadência completa → ressincroniza; última cutucada < 30 min → segura; ≥ 4/dia → amanhã
12. Envia NO MÁXIMO 1 cutucada (marca estado antes, merge atômico, mensagem outgoing)
Saídas: mensagem outgoing (`cevico_followup_bot_id/step`). Estado: `bot.last_run_at`, `activity_log.last_run/events`, `conversation.additional_attributes.cevico_followup`.

## scheduler — Secretário da Agenda (`app/services/crm/appointment_applier.rb:14`, `appointment_extraction_service.rb:108`, `appointment_recorder.rb:9`)
Gatilho: EVENTO — ação de coluna `schedule_appointment` (CrmAutomationFireJob:396) ou releitura (`Crm::SchedulerRecheckJob`, 20 s após mensagem c/ termo de horário, freio 10 min). Liga/desliga: `ai_config.agents.scheduler.enabled`.
1. Sem conversa/contato → fim · 2. Releitura do mesmo contato há < 2 min → fim silencioso · 3. Carimba last_read_at
4. IA extrai (nome, telefone, data, hora, unidade, médico, reagendamento, cancelamento…); sem chave/pausado → linha ':erro' no registro
5. cancelamento sem novo horário → cancel_future (sem consulta futura → tarefa "⚠️ Pediu cancelar/remarcar")
6. found + starts_at → Recorder: já existe → :already · consulta futura do mesmo contato → REAGENDA · senão cria Task consulta → nota privada "📅 agendada/REAGENDADA pela IA"
7. Sem dia/hora → tarefa "⚠️ Confirmar consulta" (1 aberta por paciente) + nota
Saídas: Task `task_type 'consulta'`, tarefas de revisão, notas privadas, AiUsage 'scheduler'. Estado: `agenda_config.scheduler_log` (100), `contact.cevico_scheduler_last_read_at`.

## reminders — Lembretes D-1/D-0 + confirmação (`app/jobs/crm/appointment_reminder_send_job.rb:31`, `crm_listener.rb:112`)
Gatilho: cron */15. Liga/desliga: `agenda_config.appointment_reminders.d1|d0.enabled`.
1. Por régua: desligada → pula · 2. Hora SP ≠ hora configurada (d1=10h, d0=7h) → pula · 3. Sem caixa/modelo → pula
4. Alvo: consultas do dia (d1 = amanhã, d0 = hoje), não canceladas, sem presença marcada, com contato
5. Contato sem telefone → pula · 6. Já enviado (marca `cevico_appt_reminders[task][regua]`) → pula
7. Personaliza {{hora}}/{{unidade}} → envia MENSAGEM MODELO (SendTemplateService) · 8. Falhou → não marca · 9. Marca (merge atômico)
10. Paciente responde "sim/confirmo" (listener) → grava `confirmed` + nota "✅ CONFIRMOU"
Estado: marcas no contato. Conferência do dia (`attendance_reminder_job.rb`): cron */30, dia útil, após o horário-limite (19h), pendentes > 0 → 1 tarefa "✅ Concluir a conferência do dia" por tipo.

## harvest — Colheitadeira (`app/jobs/crm/harvest_job.rb:13`, `harvest_service.rb`)
Gatilho: cron 10 12-20 seg–sáb (ou botões prévia/enviar). Liga/desliga: `ai_config.agents.harvest.enabled`.
1. Lock 30 min · 2. Desligado → pula · 3. Hoje < day_of_month → não gera · 4. Já gerou este mês → não regera
5. Pool de frios (colunas configuradas, telefone, sem atividade > cold_days, sem nao_perturbe/perda, não colhido há 4 meses; cap 5×, máx 1500)
6. Pontua em lotes de 25 c/ IA (máx 40 chamadas; falha → heurística) · 7. Seleciona N melhores → estado 'preview' + tarefa de aprovação (se require_approval)
8. Aprovado? não → espera · 9. Modo 'organize' (padrão) → etiqueta oportunidade_AAAA_MM, done, sem mensagem
10. Modo 'send': sem caixa/modelo → erro; orçamento = daily_cap − enviados hoje (≤ 12/h); envia modelo + etiqueta colheita_AAAA_MM
Estado: `ai_config.harvest_state {month_key, status, generated_at, approved_at, stats, last_error}`.

## manager — Gestor Autônomo (`app/jobs/crm/auto_manager_job.rb:8`, `auto_manager_service.rb`)
Gatilho: cron 10 11 seg–sex (08:10 SP) ou "Rodar agora". Liga/desliga: `ai_config.agents.manager.enabled`.
1. Desligado → skip · 2. Já rodou hoje (sem force) → skip · 3. < 4 semanas de histórico → skip
4. Por indicador: baseline (média) zero → pula · 5. Volume abaixo do mínimo → pula · 6. Compara pior de (semana projetada, semana fechada) vs baseline
7. Queda menor que drop_pct (25%) → não é achado · 8. 3 piores achados → tarefas "📊 Gestor: …" (sem duplicar) · 9. Briefing c/ IA (haiku; sem chave → nulo) · 10. Grava estado
Estado: `ai_config.manager_state {last_run_date, last_run_at, findings, brief, tasks_opened}`.

## auditor — Auditor de Conversas (`app/jobs/crm/conversation_auditor_job.rb:8`, `conversation_auditor_service.rb`)
Gatilho: cron 40 10 (07:40 SP) ou "Rodar agora". Liga/desliga: `ai_config.agents.auditor.enabled`.
1. Desligado → skip · 2. Sem chave → skip · 3. Dia já auditado → skip
4. Conversas de ONTEM c/ ≥ 2 mensagens, até daily_cap (150) · 5. Nenhuma → fecha o dia 'sem conversas'
6. Lotes de 5 (últimas 30 mensagens) · 7. Lote c/ erro → conta 0 e segue · 8. Nota 0–10, etapa, acerto, falhas, próxima ação → `conversation.audit` (merge atômico)
9. Agrega por atendente/dia (with_lock) · 10. Fecha o dia (days_done, poda 30 dias)
Estado: `ai_config.auditor_state {days_done, agents, last_run_at}`.

## instagram — Atendente Direct & Messenger (`app/jobs/crm/instagram_agent_job.rb:15`, `instagram_agent_service.rb`)
Gatilho: EVENTO — mensagem recebida numa caixa configurada (listener, espera 12 s). Liga/desliga: `ai_config.agents.instagram.enabled` + `inbox_ids`.
1. Conversa não-open → fim · 2. Agente pausado nesta conversa (humano assumiu) → fim · 3. Não é mais a última mensagem → desiste
4. Teto 60 respostas/dia na conversa → pausa · 5. Pausado/sem chave/vazia → erro
6. Contexto vivo: data/hora + telefone + HORÁRIOS LIVRES (AgendaSlots) · 7. IA → mensagens(≤3), etapa, agendar, pausar, chamar_humano
8. Revalida "ainda é a última?" → envia até 3 mensagens (1,5 s entre elas; para se chegar mensagem nova)
9. agendar → trava Redis do horário + slot_available? → inválido → tarefa "⚠️ Confirmar consulta (Instagram)" · válido → Recorder + telefone no contato + nota
10. chamar_humano → nota "🙋 pediu humano" + pausa · pausar/agendar → pausa
Estado: `conversation.cevico_atendente_ia {paused, reason}`, `ai_config.instagram_state.events`. Humano responde → pausa; 👍 → retoma.

## comments — Respondedor de Comentários (`app/jobs/crm/comments_agent_job.rb:6`, `comments_agent_service.rb`)
Gatilho: cron */5. Liga/desliga: `ai_config.agents.comments.enabled` + `page_access_token`.
1. Sem token/chave/pausado → erro · 2. Fora de 07–22h SP → fora do horário · 3. Poda memória (30 dias)
4. Coleta comentários (10 mídias IG + 10 posts FB) · 5. Teto 10 respostas/rodada · 6. Já tratado → pula
7. IA: chamar_humano → 'humano' (não responde) · responder → POST no Graph · senão 'ignorado' · 8. Marca ANTES de responder
Estado: `ai_config.comments_state {handled, events, last_run_at}`.

## creative — Criativo Perpétuo (`app/jobs/crm/creative_job.rb:8`, `creative_service.rb`)
Gatilho: cron 30 11 seg (08:30 SP) ou "Gerar agora". Liga/desliga: `ai_config.agents.creative.enabled`.
1. Desligado/sem chave → skip · 2. Semana já gerada → skip · 3. Vencedores 90 dias (utm_term + ad_name) cruzados c/ jornada (consulta → compareceu → cirurgia → receita)
4. Vencedor sem consulta marcada → descartado · 5. Sem vencedores → skip · 6. Gera variações c/ objeções reais (mapa de objeções) · 7. Estado 'pending' + tarefa "🎨 Criativos da semana"
8. Revisão na tela: aprovar → approved_log; recusar → status
Estado: `ai_config.creative_state {week_key, generated_at, winners, approved_log}`.

## mentor — Mentor do Time (`app/jobs/crm/weekly_mentor_job.rb:10`, `monthly_mentor_job.rb:7`, `weekly_mentor_service.rb`)
Gatilho: cron 0 11 seg (semanal) e 30 11 dia 1 (mensal), ou botão. Liga/desliga: `ai_config.agents.mentor.enabled`.
1. Desligado/sem chave → skip · 2. Período: semana/mês fechado (botão = últimos 7 dias) · 3. Métricas por pessoa (tempo de resposta, % na meta, resolvidas, mensagens, tarefas)
4. Pessoa sem uso → fora · 5. Time inativo → fim · 6. Mediana do time · 7. Anexa meta do mês · 8. 1 chamada de IA por pessoa (erro → não grava) · 9. Grava Crm::WeeklyFeedback
Estado: `crm_weekly_feedbacks` (cadence weekly|monthly).

## oftalmofacil — Sincronização (`app/jobs/crm/oftalmofacil_sync_job.rb:9`, `oftalmofacil_sync_service.rb`)
Gatilho: cron 7,22,37,52 ou "Sincronizar agora". Liga/desliga: `agenda_config.oftalmofacil.enabled` + conexão configurada.
1. MySQL só-leitura · 2. Cursor = last_sync_at (sem cursor = 1ª carga → automações silenciadas) · 3. Lotes de 500 · 4. Espelha em Crm::OftalmofacilSurgery (idempotente)
5. Classifica status · 6. Casa paciente: telefone → CPF → nome → cria · 7. Enriquece cadastro · 8. Coluna-alvo (Agendada/Realizada/Pós)
9. 🛡️ Card já adiante nunca volta · 10. Valor + StageLog retrodatado + automações só se evento recente · 11. Etiquetas cancelada/falta · 12. Grava cursor + resumo
Estado: `agenda_config.oftalmofacil {last_sync_at, last_run_at, last_result}`.

## calls — Chamadas nativas (item 167) (`app/services/crm/calls/webhook_service.rb:20`, `outbound_service.rb:5`)
Gatilho: WEBHOOK da Meta campo `calls` (desvio `Cevico::WhatsappCallsWebhook`). Liga/desliga: `agenda_config.calls.enabled` + caixa configurada.
Recebida: 1. connect novo → contato/conversa (ConversationFinder) + Crm::Call ringing · 2. Fora do horário (se business_hours_only) → recusa na Meta, rejected/outside_hours, card, conversa reaberta, aviso 'missed'
3. Senão toca p/ ring_user_ids (cable `cevico_call.ringing`) · 4. Atendente aceita (WebRTC no navegador; 409 se outra já pegou) · 5. terminate → duração, status (completed/missed/failed), card na conversa; perdida → reabre conversa + aviso
6. Gravação sobe do navegador → transcrição (ffmpeg → Gemini) → card atualizado
Ligar p/ paciente: 1. Sem caixa/telefone → erro · 2. Permissão na Meta? não → "Pedir permissão" (mensagem interativa; resposta grava no contato) · 3. Sim → connect c/ SDP → Crm::Call outbound ringing → answer via webhook → conversa
Estado: `cevico_calls`, `contact.cevico_call_permission`, `agenda_config.calls.meta`.

## voice — Agente de Ligação (item 169, ver docs/AGENTE_LIGACAO.md)
Gatilho: ligação recebida no número da IA (ElevenLabs↔WhatsApp) ou campanha (dialer cron */5). Liga/desliga: `ai_config.voice.enabled`.
Recebida: ElevenLabs atende → (initiation webhook devolve nome/próxima consulta) → IA conversa c/ ferramentas (buscar_paciente, horarios_livres, marcar_consulta, minha_consulta, enviar_whatsapp, registrar_resultado; transferir p/ humano) → pós-chamada assinado → Crm::Call (handled_by ai) + card + transcrição + resumo + resultado + custo.
Campanha: público (etiquetas/etapas/período) → contatos queued → dentro do horário e do teto → outbound-call (template de permissão → liga quando aceita) → calling → pós-chamada fecha c/ resultado → campanha completed.

## campaigns — Campanha WhatsApp + réguas (`app/jobs/crm/campaign_run_job.rb:9`, `message_automation_run_job.rb:9`, `scheduler_job.rb:7`)
Gatilho: cron */5 (SchedulerJob: campanhas `due` + réguas ativas) ou "Enviar agora".
Campanha: 1. Não-processing → fim · 2. Lock 2 h · 3. Já enviados (CampaignContact) → skipped · 4. resolve_audience · 5. SendTemplateService (nil → skipped) · 6. CampaignContact + etiqueta · 7. 0,2 s/contato · 8. Progresso a cada 10 · 9. completed/failed
Régua (MessageAutomation): 1. Inativa → fim · 2. Lock 1 h · 3. Elegíveis: etiqueta há ≥ delay_days e/ou coluna há ≥ delay_days; exige required_labels; exclui exclude/marker · 4. Marca ANTES de enviar · 5. Envia modelo · 6. Falha → desfaz marca · 7. stats + last_run_at
Estado: `campaign.status/stats`, `automation.stats.last_run_at`.

## column_automations — Automações de coluna (`app/jobs/crm_automation_fire_job.rb:4`, `app/models/crm/automation.rb`)
Gatilho: EVENTO — card_entered/card_left (board, conversa, OftalmoFácil, regras), label_added/removed, message_created (listener), value_added (contato), card_stalled (cron */30 `CrmStalledCardsJob`), teste manual. Liga/desliga: `crm_automations.active`.
1. Inativa → fim · 2. Contato resolvido na conta da automação · 3. card_entered c/ atraso e o card já saiu → não dispara
4. Caixa de chegada não bate → não dispara · 5. Etiqueta exigida ausente → não dispara · 6. Monta payload
7. Ação: webhook | n8n_flow | apply_label (redispara label_added) | move_card (dispara card_entered) | log_timeline | notify_team | meta_ads_event | google_ads_conversion | send_form (cooldown 7 d, não reenvia respondido) | send_template (cooldown 7 d) | ai_analyze | schedule_appointment | closing_extract | nps_score | set_value
8. Trilha no contato (60) · 9. AutomationLog fired/failed
card_stalled: delay ≤ 0 → pula · cards parados ≥ delay · já disparou desde que entrou → pula · lock 6 h · enfileira
Estado: `crm_automation_logs`, `contact.cevico_automation_trail`.

## conversation — Analista de Conversas (`app/services/crm/conversation_insight_service.rb`)
Gatilho: botão "Analisar com IA" ou ação de coluna ai_analyze. 1. Sem chave/pausado → erro · 2. Transcrição vazia → erro · 3. IA → interesse, resumo, próximo passo, etapa, frases · 4. Grava `conversation.ai_insight`.

## nps · closing · sales · form (curtos)
- nps (`nps_service.rb`): ação de coluna nps_score → sem chave/pausado → erro · IA lê nota 0–10 · respondeu? não → nada · sim → etiqueta nps-x-y (troca a anterior) + `contact.nps`.
- closing (`surgery_closing_service.rb`): ação de coluna closing_extract → IA extrai fechado/valor/pagamento/data · fechado? não → nada · sim → `contact.surgery_closing` + valor do card se vazio.
- sales (`sales_coach_service.rb`, `objection_map_service.rb`): botão "Ajuda com objeção" (ao vivo) · "Insights" (job; exige fechamentos) · "Mapa de objeções" (job admin) → `ai_config.agents.sales.insights/objection_map`.
- form (`form_insight_service.rb`): botão no hub de Formulários → sem respostas → erro · até 300 respostas → `form.ai_insight`.

## surgery_confirmation — Confirmação de cirurgia (EXTERNO hoje: N8N "CONFIRMACAO CIRURGICA - IOP", 10h)
Planilha (Procedimento, Paciente, Data, Telefone, Hora) → p/ cada linha c/ telefone → contato existe? não → cria (caixa 5) → conversa aberta na caixa 5? não → cria → envia modelo `confirmar_cirurgia` (nome, data, hora) → paciente responde "confirmo". Item 168 traz isso p/ dentro (fonte = espelho OftalmoFácil).

## Transversais
- Interruptor único: `ai_config.agents.<key>.enabled == true` (padrão DESLIGADO). Custos: `Crm::AiUsage` por chamada.
- Guardrails: internos = OPERATIONAL; instagram/comments (e voice) = RESPONDER.
- Escrita concorrente: `Cevico::AttributeMerge.merge!` ou `with_lock + reload`.
