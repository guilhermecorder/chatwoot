require 'rails_helper'

# 💸 #444 (13/10): corrige o histórico do Sonnet 5 gravado com o preço velho (3/15)
RSpec.describe Crm::AiUsageReprice do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  # 1 milhão de entrada nova + 1 mi gravado no cache + 1 mi lido + 1 mi de saída
  def usage(cost, model: 'claude-sonnet-5', acc: account, cache: true)
    Crm::AiUsage.create!(account: acc, agent_key: 'scheduler', model: model,
                         input_tokens: cache ? 3_000_000 : 1_000_000, output_tokens: 1_000_000,
                         cache_write_tokens: cache ? 1_000_000 : 0, cache_read_tokens: cache ? 1_000_000 : 0,
                         cost_usd: cost)
  end

  it 'corrige só as linhas do Sonnet gravadas com o preço velho (2/3 do valor)' do
    velha = usage(24.30)                    # 3 + 6 + 0,3 + 15 (preço velho)
    velha_sem_cache = usage(18.0, cache: false) # 3 + 15
    nova = usage(16.20)                     # já com o preço certo
    estranha = usage(20.0)                  # não bate com nenhuma conta
    haiku = usage(8.10, model: 'claude-haiku-4-5')

    expect(described_class.new.summary).to include(total: 4, stale: 2, current: 1, unmatched: 1)
    expect(described_class.new.apply!).to eq(2)

    expect(velha.reload.cost_usd.to_f).to be_within(0.000001).of(16.20)
    expect(velha_sem_cache.reload.cost_usd.to_f).to be_within(0.000001).of(12.0)
    expect(nova.reload.cost_usd.to_f).to be_within(0.000001).of(16.20)
    expect(estranha.reload.cost_usd.to_f).to be_within(0.000001).of(20.0)
    expect(haiku.reload.cost_usd.to_f).to be_within(0.000001).of(8.10)
  end

  it 'rodar de novo não mexe em nada (não corta 2/3 duas vezes)' do
    velha = usage(24.30)
    described_class.new.apply!

    expect(described_class.new.apply!).to eq(0)
    expect(velha.reload.cost_usd.to_f).to be_within(0.000001).of(16.20)
  end

  it 'com ACCOUNT_ID mexe só naquela conta' do
    minha = usage(24.30)
    outra = usage(24.30, acc: other_account)

    described_class.new(account_id: account.id).apply!

    expect(minha.reload.cost_usd.to_f).to be_within(0.000001).of(16.20)
    expect(outra.reload.cost_usd.to_f).to be_within(0.000001).of(24.30)
  end

  it 'o resumo mostra quanto o histórico cai' do
    usage(24.30)
    usage(18.0, cache: false)

    expect(described_class.new.summary).to include(stale_cost_usd: 42.3, new_cost_usd: 28.2)
  end
end
