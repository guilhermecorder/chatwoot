# 🤖 Robôs de follow-up — passos reais de app/jobs/crm/followup_bot_job.rb (item 170):
# travas em cascata, janela 24h do WhatsApp, anti-rajada e no máximo 1 cutucada.
class Crm::FlowMap::Flows::FollowupBots
  FLOW = Crm::FlowMap::Flow.define(:followup_bots) do # rubocop:disable Metrics/BlockLength
    name 'Robôs de follow-up'
    group 'Atendimento ao paciente'
    icon 'i-lucide-bot'
    color '#0F5FA6'
    what 'cutuca o paciente que parou de responder, uma etapa por vez, dentro da janela do robô'
    config tab: 'robos'
    trigger :cron, 'A cada 2 min (Crm::FollowupBotJob)'
    jobs 'Crm::FollowupBotJob'

    node :lock, 'Trava de 10 min (uma rodada por vez)'
    node :robo, 'Para cada robô ativo', kind: :loop
    node :janela, 'Robô dentro da janela começa/para?', kind: :decision
    node :expediente, 'Horário de envio da conta (08–20h)?', kind: :decision
    node :etapas, 'Robô tem etapas?', kind: :decision
    node :conversa, 'Uma conversa por contato (aberta, ≤ 3 dias)', kind: :loop
    node :travas, 'Pausado, etiqueta de parada ou paciente falou por último?', kind: :decision
    node :prazo, 'Calcula o prazo da etapa (âncora + espaçamento)'
    node :bloqueada, 'Etapa bloqueada por etiquetas?', kind: :decision
    node :janela24, 'Texto fora da janela 24h do WhatsApp?', kind: :decision
    node :vencida, 'Vencida há mais de 3 h?', kind: :decision
    node :perdido, 'Momento perdido (anti-rajada)'
    node :fisicas, 'Cadência completa, < 30 min ou ≥ 4 hoje?', kind: :decision
    node :segura, 'Segura para a próxima rodada'
    node :envia, 'Envia 1 cutucada (marca o estado antes)', kind: :output
    node :registro, 'Registro de atividade do robô', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :lock
    edge :lock, :robo
    edge :robo, :janela
    edge :janela, :fim, 'não'
    edge :janela, :expediente, 'sim'
    edge :expediente, :fim, 'não'
    edge :expediente, :etapas, 'sim'
    edge :etapas, :fim, 'não'
    edge :etapas, :conversa, 'sim'
    edge :conversa, :travas
    edge :travas, :fim, 'sim'
    edge :travas, :prazo, 'não'
    edge :prazo, :bloqueada
    edge :bloqueada, :fim, 'sim'
    edge :bloqueada, :janela24, 'não'
    edge :janela24, :fim, 'sim (template passa)'
    edge :janela24, :vencida, 'não'
    edge :vencida, :perdido, 'sim'
    edge :perdido, :fim
    edge :vencida, :fisicas, 'não'
    edge :fisicas, :segura, 'sim'
    edge :segura, :fim
    edge :fisicas, :envia, 'não'
    edge :envia, :registro
    edge :registro, :fim

    live do |account|
      bots = Crm::FollowupBot.where(account_id: account.id)
      active = bots.active.to_a
      sent = active.flat_map { |b| Array(b.activity_log['events']).select { |e| e['type'] == 'sent' } }
      {
        enabled: active.any?,
        last_run_at: bots.maximum(:last_run_at),
        counters: {
          'robôs ativos' => active.size,
          'robôs no total' => bots.count,
          'cutucadas hoje' => count_today(sent)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
