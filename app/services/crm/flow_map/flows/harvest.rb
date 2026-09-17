# 🌾 Colheitadeira da Base — passos reais de app/jobs/crm/harvest_job.rb e harvest_service.rb (item 170).
class Crm::FlowMap::Flows::Harvest
  FLOW = Crm::FlowMap::Flow.define(:harvest) do # rubocop:disable Metrics/BlockLength
    name 'Colheitadeira da Base'
    group 'Marketing e aquisição'
    icon 'i-lucide-wheat'
    color '#CA8A04'
    what 'pontua a base fria todo mês e reativa os leads mais propensos'
    config tab: 'agentes', anchor: 'harvest'
    trigger :cron, 'De hora em hora no expediente (HarvestJob) ou botões'
    jobs 'Crm::HarvestJob'

    node :lock, 'Trava de 30 min'
    node :ligado, 'Agente ligado?', kind: :decision
    node :dia, 'Já chegou o dia do mês configurado?', kind: :decision
    node :gerou, 'Já gerou a prévia deste mês?', kind: :decision
    node :pool, 'Base fria: colunas, telefone, sem contato há N dias'
    node :pontua, 'IA pontua em lotes de 25 (máx. 40 chamadas)', kind: :ai
    node :seleciona, 'Escolhe os N melhores → prévia'
    node :aprovacao, 'Precisa de aprovação?', kind: :decision
    node :tarefa, 'Tarefa de aprovação para o admin', kind: :output
    node :aprovado, 'Aprovado?', kind: :decision
    node :espera, 'Espera a aprovação'
    node :modo, 'Modo organizar ou enviar?', kind: :decision
    node :organiza, 'Etiqueta oportunidade_AAAA_MM (sem mensagem)', kind: :output
    node :caixa, 'Tem caixa e modelo?', kind: :decision
    node :erro, 'Erro registrado no estado', kind: :output
    node :orcamento, 'Orçamento do dia (teto − enviados, ≤ 12/h)'
    node :envia, 'Envia o modelo + etiqueta colheita_AAAA_MM', kind: :external
    node :fim, 'Fim', kind: :end

    edge :trigger, :lock
    edge :lock, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :dia, 'sim'
    edge :dia, :fim, 'não'
    edge :dia, :gerou, 'sim'
    edge :gerou, :aprovado, 'sim'
    edge :gerou, :pool, 'não'
    edge :pool, :pontua
    edge :pontua, :seleciona
    edge :seleciona, :aprovacao
    edge :aprovacao, :tarefa, 'sim'
    edge :tarefa, :aprovado
    edge :aprovacao, :modo, 'não'
    edge :aprovado, :espera, 'não'
    edge :espera, :fim
    edge :aprovado, :modo, 'sim'
    edge :modo, :organiza, 'organizar'
    edge :organiza, :fim
    edge :modo, :caixa, 'enviar'
    edge :caixa, :erro, 'não'
    edge :erro, :fim
    edge :caixa, :orcamento, 'sim'
    edge :orcamento, :envia
    edge :envia, :fim

    live do |account|
      st = ai(account)['harvest_state'] || {}
      stats = st['stats'].is_a?(Hash) ? st['stats'] : {}
      {
        enabled: agent_enabled?(account, 'harvest'),
        last_run_at: st['generated_at'],
        counters: {
          'mês' => st['month_key'].presence || '—',
          'situação' => st['status'].presence || 'sem prévia',
          'enviados' => stats['sent'] || 0
        },
        note: st['last_error'].presence
      }
    end
  end

  def self.flow
    FLOW
  end
end
