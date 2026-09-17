# 🎨 Criativo Perpétuo — passos reais de app/jobs/crm/creative_job.rb e creative_service.rb (item 170).
class Crm::FlowMap::Flows::Creative
  FLOW = Crm::FlowMap::Flow.define(:creative) do # rubocop:disable Metrics/BlockLength
    name 'Criativo Perpétuo'
    group 'Marketing e aquisição'
    icon 'i-lucide-wand-sparkles'
    color '#DB2777'
    what 'toda semana escreve variações dos anúncios e termos que mais viram cirurgia'
    config tab: 'agentes', anchor: 'creative'
    trigger :cron, 'Segunda 08:30 (Crm::CreativeJob) ou "Gerar agora"'
    jobs 'Crm::CreativeJob'

    node :ligado, 'Agente ligado e com chave?', kind: :decision
    node :semana, 'Semana já gerada?', kind: :decision
    node :vencedores, 'Vencedores 90 dias × jornada real (consulta → cirurgia)'
    node :consulta, 'Vencedor tem consulta marcada?', kind: :decision
    node :descarta, 'Descarta o vencedor'
    node :algum, 'Sobrou algum vencedor?', kind: :decision
    node :ia, 'IA escreve variações com as objeções reais', kind: :ai
    node :pendente, 'Estado pendente + tarefa 🎨 Criativos da semana', kind: :output
    node :revisao, 'Você aprova ou recusa?', kind: :decision
    node :aprovada, 'Guarda no registro de aprovadas', kind: :output
    node :recusada, 'Marca como recusada'
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :semana, 'sim'
    edge :semana, :fim, 'sim'
    edge :semana, :vencedores, 'não'
    edge :vencedores, :consulta
    edge :consulta, :descarta, 'não'
    edge :descarta, :algum
    edge :consulta, :algum, 'sim'
    edge :algum, :fim, 'não'
    edge :algum, :ia, 'sim'
    edge :ia, :pendente
    edge :pendente, :revisao
    edge :revisao, :aprovada, 'aprova'
    edge :aprovada, :fim
    edge :revisao, :recusada, 'recusa'
    edge :recusada, :fim

    live do |account|
      st = ai(account)['creative_state'] || {}
      {
        enabled: agent_enabled?(account, 'creative'),
        last_run_at: st['generated_at'],
        counters: {
          'semana' => st['week_key'].presence || '—',
          'vencedores' => Array(st['winners']).size,
          'aprovadas' => Array(st['approved_log']).size
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
