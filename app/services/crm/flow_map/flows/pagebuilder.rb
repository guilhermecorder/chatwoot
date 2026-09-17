# 🧱 Construtor de Páginas — app/jobs/crm/page_generate_job.rb e page_edit_job.rb (item 170).
class Crm::FlowMap::Flows::Pagebuilder
  FLOW = Crm::FlowMap::Flow.define(:pagebuilder) do # rubocop:disable Metrics/BlockLength
    name 'Construtor de Páginas'
    group 'Marketing e aquisição'
    icon 'i-lucide-layout-template'
    color '#1D4ED8'
    what 'monta páginas públicas inteiras a partir de uma copy pronta'
    config tab: 'agentes', anchor: 'pagebuilder'
    trigger :manual, 'Botão Gerar / Editar página (roda em segundo plano)'
    jobs 'Crm::PageGenerateJob', 'Crm::PageEditJob'

    node :ligado, 'Agente ligado?', kind: :decision
    node :chave, 'Sem chave ou pausado?', kind: :decision
    node :erro, 'Aviso de erro na página', kind: :output
    node :copy, 'Copy pronta + referências da marca'
    node :ia, 'IA monta (ou edita) a página inteira', kind: :ai
    node :salva, 'Página pública salva para publicar', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :chave, 'sim'
    edge :chave, :erro, 'sim'
    edge :erro, :fim
    edge :chave, :copy, 'não'
    edge :copy, :ia
    edge :ia, :salva
    edge :salva, :fim

    live do |account|
      {
        enabled: agent_enabled?(account, 'pagebuilder'),
        last_run_at: usage_last(account, 'pagebuilder'),
        counters: { 'páginas (30 dias)' => usage_count(account, 'pagebuilder', 30.days.ago) }
      }
    end
  end

  def self.flow
    FLOW
  end
end
