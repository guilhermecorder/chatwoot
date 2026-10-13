require 'rails_helper'

# 🌾 achado #44 (auditoria 07/10): os botões da Colheitadeira e a gravação da
# tela da IA não podem provocar um segundo envio para o mesmo lead.
RSpec.describe 'CRM settings — Colheitadeira (achado #44)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }
  let(:lock_key) { Crm::HarvestJob::LOCK_KEY }

  after { Redis::Alfred.delete(lock_key) }

  it '"Enviar agora" e "Gerar prévia" são recusados com aviso quando já tem uma rodada em andamento', :aggregate_failures do
    allow(Crm::HarvestJob).to receive(:perform_later)
    Redis::LockManager.new.lock(lock_key, 1.minute)

    post "#{base}/harvest_send_now", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to include('rodada da Colheitadeira em andamento')

    post "#{base}/harvest_preview", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:conflict)

    expect(Crm::HarvestJob).not_to have_received(:perform_later)
  end

  it 'com a trava livre o pedido entra na fila como antes', :aggregate_failures do
    allow(Crm::HarvestJob).to receive(:perform_later)

    post "#{base}/harvest_send_now", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['enqueued']).to be(true)
    expect(Crm::HarvestJob).to have_received(:perform_later).with(account.id, 'batch')
  end

  it 'salvar a tela da IA não apaga a marca de "enviado" que um lote gravou enquanto a tela estava aberta', :aggregate_failures do
    settings = CrmSetting.create!(account: account, ai_config: {
                                    'agents' => { 'harvest' => { 'enabled' => true } },
                                    'harvest_state' => { 'status' => 'approved',
                                                         'selected' => [{ 'contact_id' => 1, 'sent_at' => nil, 'skipped' => false }] }
                                  })
    # a tela leu a foto velha; antes de gravar, um lote reservou o lead 1
    allow(CrmSetting).to receive(:find_or_create_by!).and_wrap_original do |m, **kw|
      record = m.call(**kw)
      fresh = settings.reload.ai_config.deep_dup
      fresh['harvest_state']['selected'][0]['sent_at'] = '2026-10-12T10:00:00-03:00'
      settings.update_column(:ai_config, fresh) # rubocop:disable Rails/SkipsModelValidations
      record
    end

    post "#{base}/update_ai", params: { agents: { harvest: { enabled: true, daily_cap: 20 } } },
                              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    saved = CrmSetting.find_by(account: account).ai_config
    expect(saved.dig('agents', 'harvest', 'daily_cap').to_i).to eq(20)
    expect(saved.dig('harvest_state', 'selected', 0, 'sent_at')).to eq('2026-10-12T10:00:00-03:00')
  end
end
