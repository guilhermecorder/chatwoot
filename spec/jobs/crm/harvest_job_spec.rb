require 'rails_helper'

# 🌾 achado #44 (auditoria 07/10): o botão "Enviar agora" da tela rodava sem a
# trava do cron — dois cliques (ou clique durante a rodada horária) eram duas
# rodadas ao mesmo tempo. Agora todo caminho pega a MESMA trava.
RSpec.describe Crm::HarvestJob do
  let(:account) { create(:account) }
  let(:lock_key) { described_class::LOCK_KEY }
  let(:service) { instance_double(Crm::HarvestService, send_batch!: { ok: true }, generate_preview!: { ok: true }) }

  before do
    allow(Crm::HarvestService).to receive(:new).and_return(service)
  end

  after { Redis::Alfred.delete(lock_key) }

  it 'o botão da tela recusa o pedido enquanto outra rodada está com a trava e deixa o aviso para a tela', :aggregate_failures do
    CrmSetting.create!(account: account, ai_config: { 'harvest_state' => { 'status' => 'approved', 'last_error' => nil } })
    allow(Crm::HarvestService).to receive(:new).and_call_original # o aviso é gravado pelo service de verdade
    Redis::LockManager.new.lock(lock_key, 1.minute)

    described_class.perform_now(account.id, 'batch')

    expect(service).not_to have_received(:send_batch!)
    expect(Redis::LockManager.new.locked?(lock_key)).to be(true) # não solta a trava dos outros
    expect(CrmSetting.find_by(account: account).ai_config.dig('harvest_state', 'last_error')).to eq(described_class::BUSY_MESSAGE)
    expect(CrmSetting.find_by(account: account).ai_config.dig('harvest_state', 'status')).to eq('approved')
  end

  it 'o cron (sem conta) com a trava ocupada só registra no log, sem mexer em estado nenhum' do
    Redis::LockManager.new.lock(lock_key, 1.minute)

    expect { described_class.perform_now }.not_to raise_error
    expect(service).not_to have_received(:send_batch!)
  end

  it 'com a trava livre o botão roda e solta a trava no fim', :aggregate_failures do
    described_class.perform_now(account.id, 'batch')

    expect(service).to have_received(:send_batch!).once
    expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
  end

  it 'solta a trava mesmo quando o lote falha' do
    allow(service).to receive(:generate_preview!).and_raise(StandardError, 'IA fora do ar')

    expect { described_class.perform_now(account.id, 'preview') }.to raise_error(StandardError, 'IA fora do ar')
    expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
  end
end
