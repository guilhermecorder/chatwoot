# 📡 Radar de Oportunidades — passos reais de app/jobs/crm/opportunity_radar_job.rb
# e opportunity_radar_service.rb (item 170).
class Crm::FlowMap::Flows::Opportunity
  FLOW = Crm::FlowMap::Flow.define(:opportunity) do # rubocop:disable Metrics/BlockLength
    name 'Radar de Oportunidades'
    group 'Vendas e fechamento'
    icon 'i-lucide-radar'
    color '#DC2626'
    what 'vigia colunas do CRM e avisa o painel quando um lead esfria'
    config tab: 'agentes', anchor: 'opportunity'
    trigger :cron, 'A cada 10 min (07:30–18:00) ou Radar pontual'
    jobs 'Crm::OpportunityRadarJob'

    node :pontual, 'Radar pontual (botão)?', kind: :decision
    node :varredura, 'Varredura única com os filtros escolhidos'
    node :horario, 'Dentro de 07:30–18:00 (ou 20h/00h/04h)?', kind: :decision
    node :ligado, 'Agente ligado?', kind: :decision
    node :vigias, 'Tem vigias ou colunas?', kind: :decision
    node :chave, 'Pausado ou sem chave?', kind: :decision
    node :estado, 'Carrega alertas vivos, checados e histórico'
    node :teto, 'Teto: 15 análises (auto) / 40 (manual)'
    node :vigia, 'Para cada vigia (coluna + atendente + janela)', kind: :loop
    node :candidatos, 'Conversas abertas esperando resposta (≤ 80)'
    node :pula, 'Alerta vivo, duplicada ou checada há < 6 h?', kind: :decision
    node :ia, 'IA classifica a oportunidade', kind: :ai
    node :oportunidade, 'É oportunidade?', kind: :decision
    node :alerta, 'Aviso no Radar do Meu Painel', kind: :output
    node :grava, 'Grava alertas (30), checados e histórico (500)'
    node :fim, 'Fim', kind: :end

    edge :trigger, :pontual
    edge :pontual, :varredura, 'sim'
    edge :varredura, :vigia
    edge :pontual, :horario, 'não'
    edge :horario, :fim, 'não'
    edge :horario, :ligado, 'sim'
    edge :ligado, :fim, 'não'
    edge :ligado, :vigias, 'sim'
    edge :vigias, :fim, 'não'
    edge :vigias, :chave, 'sim'
    edge :chave, :fim, 'sim'
    edge :chave, :estado, 'não'
    edge :estado, :teto
    edge :teto, :vigia
    edge :vigia, :candidatos
    edge :candidatos, :pula
    edge :pula, :grava, 'sim'
    edge :pula, :ia, 'não'
    edge :ia, :oportunidade
    edge :oportunidade, :alerta, 'sim'
    edge :alerta, :grava
    edge :oportunidade, :grava, 'não'
    edge :grava, :fim

    live do |account|
      st = ai(account)['opportunity_state'] || {}
      watchers = Array(ai(account).dig('agents', 'opportunity', 'watchers'))
      {
        enabled: agent_enabled?(account, 'opportunity'),
        last_run_at: st['last_run_at'] || ai(account)['opportunity_last_run'],
        counters: {
          'alertas vivos' => Array(st['alerts']).size,
          'vigias' => watchers.size,
          'análises (7 dias)' => usage_count(account, 'opportunity', 7.days.ago)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
