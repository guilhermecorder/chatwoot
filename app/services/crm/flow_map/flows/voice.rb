# 🤖📞 Agente de Ligação (item 169 → rodada 195) — fluxo ponta a ponta de
# docs/AGENTE_LIGACAO.md §6 (recebida) e §7 (campanha) + a seleção de LEADS
# NÃO RESPONSIVOS de hora em hora (Crm::VoiceAgent::UnresponsiveLeadsJob:
# sombra = lista "ligaria hoje"; ao vivo = campanha do dia que o discador
# liga). A conversa roda na ElevenLabs com o Roteiro CEVICO + regras de voz +
# etapa; o sistema entra pelas ferramentas (webhooks) e pelo pós-chamada.
class Crm::FlowMap::Flows::Voice
  FLOW = Crm::FlowMap::Flow.define(:voice) do # rubocop:disable Metrics/BlockLength
    name 'Agente de Ligação'
    group 'Atendimento ao paciente'
    icon 'i-lucide-phone-call'
    color '#7C3AED'
    what 'liga para leads parados nas colunas escolhidas (sem resposta há N horas) e conduz ao agendamento ou ao WhatsApp; ' \
         'atende as ligações no número da clínica'
    config tab: 'agentes', anchor: 'voice'
    trigger :cron, 'Hora em hora (leads parados) · recebida · campanha 5 min'
    jobs 'Crm::VoiceAgent::UnresponsiveLeadsJob', 'Crm::VoiceAgent::CampaignDialerJob', 'Crm::VoiceAgent::PostCallJob'

    node :ligado, 'Card do agente ligado?', kind: :decision
    node :tipo, 'Leads parados, ligação recebida ou campanha?', kind: :decision
    # ── leads não responsivos (195) ──
    node :selecao, 'Seleciona leads parados nas colunas vigiadas (≥ N h)'
    node :modo, 'Ao vivo agora? (modo + trava + janela + ElevenLabs)', kind: :decision
    node :sombra, 'Sombra: grava "ligaria hoje para N" (nada é discado)', kind: :output
    node :campanha_dia, 'Enfileira na campanha do dia 🤖 Leads não responsivos'
    # ── recebida ──
    node :atende, 'ElevenLabs atende no número da IA', kind: :external
    node :inicio, 'Webhook de início: nome, próxima consulta, motivo'
    node :conversa, 'IA fala: Roteiro + regras de voz + etapa', kind: :ai
    node :ferramentas, 'Ferramentas: paciente, horários, marcar, WhatsApp', kind: :loop
    node :transferir, 'Pediu humano, urgência ou fora do escopo?', kind: :decision
    node :transfere, 'Transfere para o número humano', kind: :external
    node :poscall, 'Pós-chamada assinado (transcrição + áudio)', kind: :external
    node :fecha, 'Fecha a ligação: resumo, resultado, custo'
    node :saida, 'Card na conversa + Agenda + Dashboard de Ligações', kind: :output
    # ── campanha ──
    node :campanha, 'Campanha em andamento (público escolhido)'
    node :horario, 'Dentro do horário e do teto diário?', kind: :decision
    node :espera, 'Espera a próxima rodada'
    node :fila, 'Para cada contato na fila (simultâneas)', kind: :loop
    node :permissao, 'Template de permissão → liga se aceitar', kind: :external
    node :aceitou, 'Paciente aceitou a ligação?', kind: :decision
    node :sem_permissao, 'Sem permissão: não ligou', kind: :output
    node :ligando, 'Contato em ligação (calling)'
    node :concluida, 'Era campanha e a fila esvaziou?', kind: :decision
    node :completa, 'Campanha concluída', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :tipo, 'sim'
    edge :tipo, :selecao, 'leads parados'
    edge :selecao, :modo
    edge :modo, :sombra, 'não'
    edge :sombra, :fim
    edge :modo, :campanha_dia, 'sim'
    edge :campanha_dia, :campanha
    edge :tipo, :atende, 'recebida'
    edge :atende, :inicio
    edge :inicio, :conversa
    edge :conversa, :ferramentas
    edge :ferramentas, :transferir
    edge :transferir, :transfere, 'sim'
    edge :transfere, :poscall
    edge :transferir, :poscall, 'não'
    edge :poscall, :fecha
    edge :fecha, :saida
    edge :saida, :concluida
    edge :concluida, :completa, 'sim'
    edge :completa, :fim
    edge :concluida, :fim, 'não'
    edge :tipo, :campanha, 'campanha'
    edge :campanha, :horario
    edge :horario, :espera, 'não'
    edge :espera, :fim
    edge :horario, :fila, 'sim'
    edge :fila, :permissao
    edge :permissao, :aceitou
    edge :aceitou, :sem_permissao, 'não'
    edge :sem_permissao, :concluida
    edge :aceitou, :ligando, 'sim'
    edge :ligando, :conversa

    live do |account|
      v = ai(account)['voice'] || {}
      cfg = ai(account).dig('agents', 'voice') || {}
      shadow = ai(account).dig('voice_state', 'shadow') || {}
      events = Array(ai(account).dig('voice_state', 'events'))
      counters = { 'custo 7 dias (US$)' => Crm::AiUsage.where(account_id: account.id, agent_key: 'voice',
                                                              created_at: 7.days.ago..).sum(:cost_usd).to_f.round(2) }
      counters['modo'] = Crm::VoiceAgent::UnresponsiveLeadsJob.live_now?(account, cfg) ? 'ao vivo' : 'sombra'
      counters['colunas vigiadas'] = Array(cfg['stage_ids']).size
      counters[shadow['mode'] == 'live' ? 'ligações hoje' : 'ligaria hoje'] = Array(shadow['items']).size
      if Crm::Call.column_names.include?('handled_by')
        counters['ligações da IA hoje'] = Crm::Call.where(account_id: account.id, handled_by: 'ai', started_at: today_range).count
      end
      # a tabela de campanhas de ligação chega com o item 169 — só conta se já existir
      counters['campanhas em andamento'] = Crm::CallCampaign.where(account_id: account.id, status: :processing).count if defined?(Crm::CallCampaign)
      {
        enabled: cfg['enabled'] == true || v['enabled'] == true,
        last_run_at: last_at(events) || v.dig('state', 'last_call_at') || usage_last(account, 'voice'),
        counters: counters,
        note: v['agent_id'].present? ? 'roda na ElevenLabs' : 'ainda não sincronizado com a ElevenLabs'
      }
    end
  end

  def self.flow
    FLOW
  end
end
