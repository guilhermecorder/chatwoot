require 'rails_helper'

# 💸 item 213 (23/09): cache do prompt — o roteiro vai como bloco marcado para
# cache (1 h) e o custo registrado considera leitura (10%) e gravação (2x)
RSpec.describe Crm::AiAgentConfig do
  let(:account) { create(:account) }
  let(:klass) do
    Class.new do
      include Crm::AiAgentConfig
      def initialize(account)
        @account = account
      end
      public :cached_system, :record_usage, :model
    end.tap do |k|
      # constantes dentro de Class.new caem no escopo do arquivo — por isso const_set
      k.const_set(:AGENT_KEY, 'scheduler')
      k.const_set(:SYSTEM_PROMPT, 'Você é o Secretário.')
    end
  end
  let(:usage_struct) { Struct.new(:input_tokens, :cache_creation_input_tokens, :cache_read_input_tokens, :output_tokens) }
  let(:reply_struct) { Struct.new(:usage) }
  let(:service) { klass.new(account) }

  before { CrmSetting.create!(account: account, ai_config: { 'api_key' => 'x', 'agents' => { 'scheduler' => { 'enabled' => true } } }) }

  it 'embrulha o prompt num bloco com cache_control de 1 h (guardrail incluso)' do
    blocks = service.cached_system
    expect(blocks.size).to eq(1)
    expect(blocks.first[:cache_control]).to eq({ type: 'ephemeral', ttl: '1h' })
    expect(blocks.first[:text]).to start_with('Você é o Secretário.')
  end

  it 'aceita um texto próprio' do
    expect(service.cached_system('outro')[0][:text]).to eq('outro')
  end

  it 'registra o custo com cache: leitura a 10%, gravação a 2x (sonnet US$3/M entrada)' do
    usage = usage_struct.new(1_000, 10_000, 0, 100)
    service.record_usage(reply_struct.new(usage))
    row = Crm::AiUsage.last
    expect(row.input_tokens).to eq(11_000)
    # 1000*3 + 10000*3*2 + 100*15 = 3000 + 60000 + 1500 = 64500 / 1e6
    expect(row.cost_usd.to_f).to be_within(0.000001).of(0.0645)

    usage2 = usage_struct.new(1_000, 0, 10_000, 100)
    service.record_usage(reply_struct.new(usage2))
    # 1000*3 + 10000*0.3 + 100*15 = 3000 + 3000 + 1500 = 7500 / 1e6
    expect(Crm::AiUsage.last.cost_usd.to_f).to be_within(0.000001).of(0.0075)
  end
end
