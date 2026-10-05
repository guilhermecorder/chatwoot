# 🏷️ Higiene dos dados — passos reais de app/jobs/crm/stage_log_bulk_sweep_job.rb
# (item 309: carga em massa fora dos indicadores) e
# app/jobs/crm/source_stamp_sweep_job.rb (item 322: carimbo de fonte).
class Crm::FlowMap::Flows::DataHygiene
  FLOW = Crm::FlowMap::Flow.define(:data_hygiene) do # rubocop:disable Metrics/BlockLength
    name 'Higiene dos dados'
    group 'Infraestrutura'
    icon 'i-lucide-stamp'
    color '#152C61'
    what 'tira as cargas em massa dos indicadores e carimba a fonte do que ficou sem carimbo'
    config route: 'crm_sources'
    trigger :cron, 'Toda madrugada, 04:10 e 04:25'
    jobs 'Crm::StageLogBulkSweepJob', 'Crm::SourceStampSweepJob'

    node :rajada, '30+ cards na mesma coluna no mesmo minuto?', kind: :decision
    node :bulk, 'Entrada marcada como carga em massa', kind: :output
    node :pendente, 'Tem registro sem carimbo de fonte?', kind: :decision
    node :parceiras, 'Fontes parceiras: funil, origem e cerca'
    node :casa, 'O resto fica com a fonte da casa'
    node :grava, 'Carimbo gravado (só no que não tinha)', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :rajada
    edge :rajada, :bulk, 'sim'
    edge :rajada, :pendente, 'não'
    edge :bulk, :pendente
    edge :pendente, :fim, 'não'
    edge :pendente, :parceiras, 'sim'
    edge :parceiras, :casa
    edge :casa, :grava
    edge :grava, :fim

    live do |account|
      {
        enabled: true,
        counters: {
          'sem carimbo' => Crm::SourceBackfill.pending(account).values.sum,
          'cargas em massa marcadas' => Crm::StageLogBulk.marked_count(account)
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
