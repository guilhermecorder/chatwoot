require 'rails_helper'
require 'sidekiq/cli'

# 🚦 Rodada 6 (RESIL-1): a IA lenta não pode mais travar mensagens, lembretes e NPS
RSpec.describe 'Filas do Sidekiq (config/sidekiq.yml)' do # rubocop:disable RSpec/DescribeClass
  # lê o arquivo do mesmo jeito que o Sidekiq de produção lê (com o ERB e o bloco production)
  let(:config) do
    cli = Sidekiq::CLI.instance
    old_config = cli.config
    old_env = cli.environment
    cli.config = Sidekiq::Config.new
    cli.send(:setup_options, ['-C', Rails.root.join('config/sidekiq.yml').to_s, '-e', 'production'])
    cli.config
  ensure
    cli.config = old_config
    cli.environment = old_env
  end

  it 'as filas da IA rodam em cápsulas próprias (5 + 2 linhas), no MESMO processo (deploy com um Sidekiq só)', :aggregate_failures do
    ia = config.capsules['ia']
    expect(ia).to be_present
    expect(ia.queues).to eq(['ai'])
    expect(ia.concurrency).to eq(5)

    fundo = config.capsules['ia_fundo']
    expect(fundo).to be_present
    expect(fundo.queues).to eq(['ai_fundo'])
    expect(fundo.concurrency).to eq(2)
  end

  it 'as 10 linhas normais NÃO pegam IA e a mensagem do WhatsApp entra antes da fila default', :aggregate_failures do
    default = config.default_capsule
    expect(default.concurrency).to eq(10)
    expect(default.queues).not_to include('ai', 'ai_fundo')
    expect(default.queues.index('medium')).to be < default.queues.index('default')
    expect(default.queues).to include('low', 'scheduled_jobs')
  end

  it 'os jobs de IA vão para a fila ai e o webhook do WhatsApp para medium', :aggregate_failures do
    expect(Crm::ResponderAgentJob.new.queue_name).to eq('ai')
    expect(Crm::InstagramAgentJob.new.queue_name).to eq('ai')
    expect(Crm::MediaReadingJob.new.queue_name).to eq('ai')
    expect(Webhooks::WhatsappEventsJob.new.queue_name).to eq('medium')
  end

  it 'automação com IA vai para ai_fundo; o resto da automação continua na default', :aggregate_failures do
    account = create(:account)
    pipeline = Crm::Pipeline.create!(account: account, name: 'Funil fila')
    stage = Crm::Stage.create!(pipeline: pipeline, name: 'Coluna')
    base = { trigger_type: 'card_entered', delay_minutes: 0, action_config: {} }
    ia = stage.automations.create!(base.merge(name: 'Analisa', action_type: 'ai_analyze'))
    etiqueta = stage.automations.create!(base.merge(name: 'Etiqueta', action_type: 'apply_label'))

    expect(CrmAutomationFireJob.new(ia.id, 1, {}).queue_name).to eq('ai_fundo')
    expect(CrmAutomationFireJob.new(etiqueta.id, 1, {}).queue_name).to eq('default')
    expect(CrmAutomationFireJob.new(0, 1, {}).queue_name).to eq('default')
  end

  it 'o banco tem conexões para as três cápsulas juntas (10 + 5 + 2)' do
    allow(Sidekiq).to receive(:server?).and_return(true)
    pool = YAML.safe_load(ERB.new(Rails.root.join('config/database.yml').read).result, aliases: true)['production']['pool']
    expect(pool.to_i).to eq(17)
  end
end
