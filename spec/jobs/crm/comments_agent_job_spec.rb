require 'rails_helper'

# 🔒 Rodada 4 da auditoria: o Respondedor de Comentários roda a cada 5 min e
# uma rodada pode demorar mais que isso. Com a trava por conta, duas rodadas
# nunca correm juntas (senão as duas poderiam responder o mesmo comentário).
RSpec.describe Crm::CommentsAgentJob do
  let(:account) { create(:account) }
  let(:key) { described_class.lock_key(account.id) }
  let(:service) { instance_double(Crm::CommentsAgentService, call: { success: true }) }

  before do
    CrmSetting.create!(account: account, ai_config: {
                         'agents' => { 'comments' => { 'enabled' => true, 'page_access_token' => 'tok' } }
                       })
    allow(Crm::CommentsAgentService).to receive(:new).and_return(service)
    Redis::LockManager.new.unlock(key)
  end

  after { Redis::LockManager.new.unlock(key) }

  it 'com uma rodada em andamento na conta, a nova não roda' do
    Redis::LockManager.new.lock(key, 1.minute)
    described_class.perform_now
    expect(service).not_to have_received(:call)
  end

  it 'sem rodada em andamento, roda e solta a trava no fim', :aggregate_failures do
    described_class.perform_now
    expect(service).to have_received(:call).once
    expect(Redis::LockManager.new.locked?(key)).to be(false)
  end

  it 'solta a trava mesmo se a rodada der erro' do
    allow(service).to receive(:call).and_raise(StandardError, 'Meta fora do ar')
    described_class.perform_now
    expect(Redis::LockManager.new.locked?(key)).to be(false)
  end
end
