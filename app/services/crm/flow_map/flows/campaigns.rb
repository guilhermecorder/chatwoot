# 📣 Campanha WhatsApp + réguas de mensagens — passos reais de
# app/jobs/crm/scheduler_job.rb, campaign_run_job.rb e message_automation_run_job.rb (item 170).
class Crm::FlowMap::Flows::Campaigns
  FLOW = Crm::FlowMap::Flow.define(:campaigns) do # rubocop:disable Metrics/BlockLength
    name 'Campanhas e réguas'
    group 'Vendas e fechamento'
    icon 'i-lucide-megaphone'
    color '#0F5FA6'
    what 'dispara as campanhas agendadas e as réguas de mensagens por etiqueta ou coluna'
    config route: 'crm_campaigns'
    trigger :cron, 'A cada 5 min (Crm::SchedulerJob) ou "Enviar agora"'
    jobs 'Crm::SchedulerJob', 'Crm::CampaignRunJob', 'Crm::MessageAutomationRunJob'

    node :tipo, 'Campanha na hora ou régua ativa?', kind: :decision
    # ── campanha ──
    node :processando, 'Campanha em envio?', kind: :decision
    node :lock_c, 'Trava de 2 h'
    node :publico, 'Resolve o público (etiquetas, etapas, período)'
    node :contato, 'Para cada contato (0,2 s entre eles)', kind: :loop
    node :enviado, 'Já enviado nesta campanha?', kind: :decision
    node :envia_c, 'Envia o modelo pelo WhatsApp', kind: :external
    node :ok, 'Enviou?', kind: :decision
    node :registra, 'Registra o contato + etiqueta'
    node :pulado, 'Marca como pulado'
    node :progresso, 'Progresso a cada 10 → concluída / falhou', kind: :output
    # ── régua ──
    node :ativa, 'Régua ativa?', kind: :decision
    node :lock_r, 'Trava de 1 h'
    node :elegiveis, 'Elegíveis: etiqueta/coluna há ≥ N dias'
    node :marca_r, 'Marca ANTES de enviar'
    node :envia_r, 'Envia o modelo pelo WhatsApp', kind: :external
    node :falhou, 'Falhou?', kind: :decision
    node :desfaz, 'Desfaz a marca'
    node :stats, 'Atualiza stats e última execução', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :tipo
    edge :tipo, :processando, 'campanha'
    edge :processando, :fim, 'não'
    edge :processando, :lock_c, 'sim'
    edge :lock_c, :publico
    edge :publico, :contato
    edge :contato, :enviado
    edge :enviado, :pulado, 'sim'
    edge :enviado, :envia_c, 'não'
    edge :envia_c, :ok
    edge :ok, :registra, 'sim'
    edge :ok, :pulado, 'não'
    edge :registra, :progresso
    edge :pulado, :progresso
    edge :progresso, :fim
    edge :tipo, :ativa, 'régua'
    edge :ativa, :fim, 'não'
    edge :ativa, :lock_r, 'sim'
    edge :lock_r, :elegiveis
    edge :elegiveis, :marca_r
    edge :marca_r, :envia_r
    edge :envia_r, :falhou
    edge :falhou, :desfaz, 'sim'
    edge :desfaz, :stats
    edge :falhou, :stats, 'não'
    edge :stats, :fim

    live do |account|
      camps = Crm::Campaign.where(account_id: account.id)
      rules = Crm::MessageAutomation.where(account_id: account.id)
      active_rules = rules.active
      last_rule = active_rules.pluck(:stats).filter_map { |s| s.is_a?(Hash) ? s['last_run_at'] : nil }.max
      {
        enabled: camps.exists?(status: %i[scheduled processing]) || active_rules.exists?,
        last_run_at: [camps.maximum(:started_at)&.iso8601, last_rule].compact.max,
        counters: {
          'campanhas agendadas' => camps.where(status: :scheduled).count,
          'em envio' => camps.where(status: :processing).count,
          'réguas ativas' => active_rules.count
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
