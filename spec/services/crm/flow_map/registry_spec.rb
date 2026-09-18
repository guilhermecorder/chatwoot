require 'rails_helper'

# 🗺️ Contrato do Mapa de Fluxos (item 170): todo agente do AGENT_META e todo
# job CEVICO do config/schedule.yml precisam de um fluxograma. Quem cria ou
# muda um agente e esquece o fluxo quebra aqui — de propósito.
RSpec.describe Crm::FlowMap::Registry do
  let(:account) { create(:account) }

  # job agendado → chave do fluxo que o desenha (mapa explícito, sem mágica)
  let(:job_to_flow) do
    {
      'Crm::SchedulerJob' => 'campaigns',
      'Crm::FollowupBotJob' => 'followup_bots',
      'Crm::AttendanceReminderJob' => 'reminders',
      'Crm::OpportunityRadarJob' => 'opportunity',
      'Crm::WeeklyMentorJob' => 'mentor',
      'Crm::MonthlyMentorJob' => 'mentor',
      'Crm::CommentsAgentJob' => 'comments',
      'CrmStalledCardsJob' => 'stalled_cards',
      'Crm::HarvestJob' => 'harvest',
      'Crm::AutoManagerJob' => 'manager',
      'Crm::ConversationAuditorJob' => 'auditor',
      'Crm::CreativeJob' => 'creative',
      'Crm::AppointmentReminderSendJob' => 'reminders',
      'Crm::JourneyRunJob' => 'journey',
      'Crm::OftalmofacilSyncJob' => 'oftalmofacil',
      'Crm::VoiceAgent::CampaignDialerJob' => 'voice'
    }
  end

  def scheduled_cevico_jobs
    YAML.load_file(Rails.root.join('config/schedule.yml')).values.map { |cfg| cfg['class'] }.grep(/\ACrm/)
  end

  it 'tem um fluxo para cada agente do Painel dos agentes (AGENT_META)' do
    missing = Api::V1::Accounts::Crm::AiDashboardsController::AGENT_META.keys - described_class.keys
    expect(missing).to be_empty, "agentes sem fluxograma: #{missing.join(', ')}"
  end

  it 'desenha todo job CEVICO agendado no config/schedule.yml' do
    scheduled_cevico_jobs.each do |job_class|
      key = job_to_flow[job_class]
      expect(key).to be_present, "job #{job_class} não está no mapa job_to_flow da spec"
      flow = described_class.find_flow(key)
      expect(flow).to be_present, "fluxo #{key} (do job #{job_class}) não existe"
      expect(flow.jobs).to include(job_class), "fluxo #{key} não cita o job #{job_class} em `jobs`"
    end
  end

  it 'mantém o mapa da spec coerente com os fluxos (mesmo antes do job entrar no cron)' do
    job_to_flow.each do |job_class, key|
      expect(described_class.find_flow(key)&.jobs).to include(job_class), "#{key} não cita #{job_class}"
    end
  end

  it 'cobre todas as chaves obrigatórias do contrato, na ordem dos grupos' do
    expect(described_class.keys).to include(
      'scheduler', 'instagram', 'comments', 'nps', 'conversation', 'calls', 'voice', 'reminders', 'journey', 'followup_bots',
      'sales', 'closing', 'opportunity', 'form', 'column_automations', 'campaigns',
      'copywriter', 'pagebuilder', 'creative', 'harvest',
      'manager', 'auditor', 'mentor', 'stalled_cards',
      'oftalmofacil'
    )
    groups = described_class.flows.map(&:group).uniq
    expect(groups).to eq(Crm::FlowMap::Flow::GROUPS)
  end

  it 'gera um Mermaid válido para cada fluxo' do
    described_class.flows.each do |flow|
      mermaid = flow.to_mermaid
      expect(mermaid).to start_with('flowchart TD'), "#{flow.key}: não começa com flowchart TD"
      expect(mermaid).not_to include('undefined'), "#{flow.key}: Mermaid com undefined"
      expect(mermaid).not_to include('""'), "#{flow.key}: nó com rótulo vazio"
      expect(mermaid).to include("#{flow.key}_trigger(["), "#{flow.key}: sem nó de gatilho"
      expect(mermaid).to include('classDef cv_off'), "#{flow.key}: sem classDef cv_off"
    end
  end

  it 'desenha todos os nós, com rótulos curtos e um nó de fim' do
    described_class.flows.each do |flow|
      mermaid = flow.to_mermaid
      flow.nodes.each do |node|
        expect(mermaid).to include("#{flow.key}_#{node.id}"), "#{flow.key}: nó #{node.id} não aparece"
        expect(node.label.length).to be <= 60, "#{flow.key}: rótulo longo demais em #{node.id} (#{node.label.length})"
      end
      expect(flow.nodes.map(&:kind)).to include(:end), "#{flow.key}: sem nó de fim"
    end
  end

  it 'apaga o fluxo (class off) quando o agente está desligado' do
    flow = described_class.find_flow('scheduler')
    expect(flow.to_mermaid(enabled: false)).to match(/class .* cv_off$/)
    expect(flow.to_mermaid(enabled: true)).not_to match(/class .* cv_off$/)
  end

  it 'lê o estado ao vivo de uma conta sem erro (nenhum "estado indisponível")' do
    CrmSetting.create!(account: account, ai_config: { 'agents' => { 'scheduler' => { 'enabled' => true } } })
    described_class.all(account).each do |row|
      expect(row[:live]).to include(:enabled, :last_run_at, :counters, :note)
      expect(row[:live][:note].to_s).not_to include('estado indisponível'), "#{row[:key]}: #{row[:live][:note]}"
      expect(row[:mermaid]).to be_present
      expect(row[:trigger]).to include(:kind, :label, :jobs)
    end
    expect(described_class.find(account, 'scheduler')[:live][:enabled]).to be(true)
  end

  it 'funciona numa conta sem CrmSetting (conta nova)' do
    rows = described_class.all(account)
    expect(rows.size).to eq(described_class.keys.size)
    expect(rows.map { |r| r[:live][:note].to_s }).not_to include(a_string_including('estado indisponível'))
  end

  it 'transforma erro do live em nota, sem derrubar a lista' do
    flow = Crm::FlowMap::Flow.define(:teste) do
      name 'Teste'
      group 'Infraestrutura'
      trigger :manual, 'x'
      node :fim, 'Fim', kind: :end
      edge :trigger, :fim
      live { |_a| raise 'boom' }
    end
    expect(flow.live_state(account)[:note]).to include('estado indisponível: boom')
  end

  it 'recusa aresta para nó inexistente' do
    flow = Crm::FlowMap::Flow.define(:quebrado) do
      name 'Quebrado'
      group 'Infraestrutura'
      trigger :manual, 'x'
      edge :trigger, :nada
    end
    expect { flow.validate! }.to raise_error(ArgumentError, /nó inexistente/)
  end
end
