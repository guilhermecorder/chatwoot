require 'rails_helper'

# 🔑 Robô que mantém a cotação da Bluesun ligada e avisa quando alguém precisa entrar no portal.
RSpec.describe Crm::KitQuoteKeepaliveJob do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:api) { 'https://api.bluesundobrasil.com.br' }
  let(:tarefas) { account.tasks.where(title: described_class::TITLE) }

  def sessao(expires_at:, refresh_expires_at:)
    Cevico::SettingMerge.merge_key!(account, :ai_config, 'kit_quote') do |current|
      (current || {}).merge('bluesun_sessao' => { 'token' => 'velha', 'expires_at' => expires_at.to_i,
                                                  'refresh_token' => 'chave', 'refresh_expires_at' => refresh_expires_at.to_i })
    end
  end

  def bluesun_salva
    CrmSetting.find_by(account: account).ai_config.dig('kit_quote', 'bluesun_sessao')
  end

  it 'renova antes de vencer e guarda a chave nova de 7 dias, sem abrir tarefa', :aggregate_failures do
    sessao(expires_at: 40.minutes.from_now, refresh_expires_at: 3.days.from_now)
    nova = { token: 'nova', expires_at: 3.hours.from_now.to_i, refresh_token: 'chave-2', refresh_expires_at: 7.days.from_now.to_i }
    renew = stub_request(:post, "#{api}/v1/validar_token").to_return(status: 200, body: nova.to_json)

    described_class.perform_now

    expect(renew).to have_been_requested.once
    expect(bluesun_salva).to include('token' => 'nova', 'refresh_token' => 'chave-2')
    expect(tarefas).to be_empty
  end

  it 'não chama o portal quando a sessão ainda tem folga' do
    sessao(expires_at: 2.hours.from_now, refresh_expires_at: 5.days.from_now)

    described_class.perform_now

    expect(WebMock).not_to have_requested(:post, "#{api}/v1/validar_token")
  end

  it 'abre UMA tarefa urgente para o administrador quando a sessão caiu', :aggregate_failures do
    sessao(expires_at: 10.minutes.ago, refresh_expires_at: 3.days.from_now)
    stub_request(:post, "#{api}/v1/validar_token").to_return(status: 401, body: '{}')

    2.times { described_class.perform_now }

    expect(tarefas.count).to eq(1)
    expect(tarefas.first).to have_attributes(assignee_id: admin.id, priority: 'urgent', status: 'todo')
    expect(tarefas.first.description).to include('caiu', 'Salvar sessão')
  end

  it 'avisa com 1 dia de folga quando a chave de 7 dias está no fim' do
    sessao(expires_at: 2.hours.from_now, refresh_expires_at: 20.hours.from_now)

    described_class.perform_now

    expect(tarefas.first).to have_attributes(priority: 'high')
  end

  it 'fecha a tarefa sozinho quando a sessão nova entra' do
    sessao(expires_at: 10.minutes.ago, refresh_expires_at: 1.hour.ago)
    described_class.perform_now
    expect(tarefas.first.status).to eq('todo')

    sessao(expires_at: 3.hours.from_now, refresh_expires_at: 7.days.from_now)
    described_class.perform_now

    expect(tarefas.first.reload.status).to eq('done')
  end
end
