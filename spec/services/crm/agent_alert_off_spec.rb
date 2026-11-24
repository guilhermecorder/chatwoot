require 'rails_helper'

# 🔕 24/11/2026 (LIFE): tipos de aviso desligados na conta não entram no Radar nem no popup
RSpec.describe Crm::AgentAlert do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Welliton') }
  let(:task) do
    Task.create!(account: account, title: 'Retorno: chamar o cliente', creator: user, assignee: user, contact: contact, due_at: 1.minute.ago)
  end

  def alerts
    Array(CrmSetting.find_by(account_id: account.id)&.ai_config&.dig('opportunity_state', 'alerts'))
  end

  it 'sem o interruptor, o aviso de "chegou o dia" entra no Radar' do
    described_class.push(account: account, kind: described_class::DUE_KIND, task: task, conversation: nil, agent_key: 'atendente_agendamento')
    expect(alerts.map { |a| a['kind'] }).to eq(['tarefa_no_prazo'])
  end

  it 'com o tipo desligado, o aviso não entra e o que já estava deixa de valer', :aggregate_failures do
    old = { 'kind' => 'tarefa_no_prazo', 'task_id' => task.id, 'created_at' => Time.current.iso8601 }
    CrmSetting.create!(account: account, ai_config: { described_class::OFF_KEY => %w[tarefa_no_prazo] })

    expect(described_class.push(account: account, kind: described_class::DUE_KIND, task: task, conversation: nil,
                                agent_key: 'atendente_agendamento')).to be_nil
    expect(alerts).to be_empty
    expect(described_class.still_open?(account, old)).to be(false)
  end
end
