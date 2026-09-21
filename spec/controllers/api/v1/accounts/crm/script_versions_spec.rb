require 'rails_helper'

# 🕘 rodada 191: histórico do Roteiro (foto antes de editar) + voltar para uma versão
RSpec.describe 'CRM script versions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/script_versions" }
  let(:settings_url) { "/api/v1/accounts/#{account.id}/crm/settings/update_ai" }
  let(:headers) { admin.create_new_auth_token }

  before { CrmSetting.create!(account: account, ai_config: {}) }

  it 'só admin entra' do
    get base, headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'salvar o Roteiro na tela tira uma foto ANTES (sem repetir foto idêntica)', :aggregate_failures do
    post settings_url, params: { script: { persona: 'Você é a Clara.' } }, headers: headers, as: :json
    post settings_url, params: { script: { persona: 'Você é a Clara.' } }, headers: headers, as: :json
    post settings_url, params: { script: { persona: 'Você é o Guilherme.' } }, headers: headers, as: :json

    get base, headers: headers, as: :json
    versions = response.parsed_body['versions']
    expect(versions.size).to eq(2)
    expect(versions.first).to include('kind' => 'script', 'note' => 'antes de editar na tela', 'size' => 'Você é a Clara.'.length)
    expect(versions.first.dig('author', 'id')).to eq(admin.id)
    expect(versions.last['size']).to eq(0) # a primeira foto = Roteiro todo padrão
  end

  it 'voltar para uma versão do Roteiro tira foto do atual e escreve a antiga', :aggregate_failures do
    version = Crm::ScriptVersion.create!(account: account, kind: 'script', content: { 'persona' => 'Texto antigo' }, note: 'x')
    Crm::ScriptVersion.write_script!(account, { 'persona' => 'Texto atual', 'handoff' => 'H' })

    post "#{base}/#{version.id}/restore", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['ok']).to be(true)
    sections = body['script'].index_by { |s| s['key'] }
    expect(sections['persona']).to include('text' => 'Texto antigo', 'custom' => true)
    expect(sections['handoff']['custom']).to be(false)
    expect(body['script_updated_at']).to be_present
    expect(Crm::CevicoScript.section_text(account, 'persona')).to eq('Texto antigo')

    backup = Crm::ScriptVersion.where(account: account).order(:id).last
    expect(backup.note).to eq("antes de voltar para a versão ##{version.id}")
    expect(backup.content).to eq('persona' => 'Texto atual', 'handoff' => 'H')
  end

  it 'voltar para uma versão dos passos do agente grava o prompt publicado', :aggregate_failures do
    CrmSetting.find_by(account: account).update!(ai_config: { 'agents' => { 'atendente_pos' => { 'prompt' => 'novo', 'draft' => 'r' } } })
    version = Crm::ScriptVersion.create!(account: account, kind: 'stage', agent_key: 'atendente_pos', content: { 'prompt' => 'antigo' })

    post "#{base}/#{version.id}/restore", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('kind' => 'stage', 'agent_key' => 'atendente_pos', 'prompt' => 'antigo')
    agent = CrmSetting.find_by(account: account).ai_config.dig('agents', 'atendente_pos')
    expect(agent).to include('prompt' => 'antigo', 'draft' => 'r')

    get base, params: { kind: 'stage', agent_key: 'atendente_pos' }, headers: headers, as: :json
    expect(response.parsed_body['versions'].map { |v| v['note'] }).to eq(["antes de voltar para a versão ##{version.id}", nil])
  end

  it 'não acha versão de outra conta' do
    other = Crm::ScriptVersion.create!(account: create(:account), kind: 'script', content: {})
    post "#{base}/#{other.id}/restore", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
