require 'rails_helper'

# 💸 #444 (13/10): o "Gasto da IA" usava US$ 3 / US$ 15 para o Sonnet 5, mas o
# preço de lista é US$ 2 / US$ 10 (tabela oficial de 06/10/2026). Como o Sonnet
# é o modelo dos agentes de mais volume, o gasto aparecia ~50% maior.
RSpec.describe Crm::AiAgentConfig do
  let(:account) { create(:account) }
  let(:usage_struct) { Struct.new(:input_tokens, :cache_creation_input_tokens, :cache_read_input_tokens, :output_tokens) }
  let(:reply_struct) { Struct.new(:usage) }

  # serviço de mentira com o agente e o modelo escolhidos no ai_config
  def service_for(model)
    klass = Class.new do
      include Crm::AiAgentConfig
      def initialize(account)
        @account = account
      end
      public :record_usage, :model
    end
    klass.const_set(:AGENT_KEY, 'scheduler')
    klass.const_set(:SYSTEM_PROMPT, 'Você é o Secretário.')
    CrmSetting.create!(account: account, ai_config: {
                         'api_key' => 'x',
                         'agents' => { 'scheduler' => { 'enabled' => true, 'model' => model } }
                       })
    klass.new(account)
  end

  # 1 milhão de cada: entrada nova, gravação no cache, leitura do cache, saída
  def um_milhao_de_cada(service)
    service.record_usage(reply_struct.new(usage_struct.new(1_000_000, 1_000_000, 1_000_000, 1_000_000)))
    Crm::AiUsage.last
  end

  describe 'tabela de preços' do
    it 'tem preço para todo modelo que o admin pode escolher' do
      expect(described_class::MODELS - described_class::PRICING.keys).to be_empty
    end

    it 'bate com a tabela oficial (US$ por milhão: entrada / saída)' do
      expect(described_class::PRICING).to eq(
        'claude-opus-4-8' => [5.0, 25.0],
        'claude-sonnet-5' => [2.0, 10.0],
        'claude-haiku-4-5' => [1.0, 5.0]
      )
    end

    it 'guarda a data da tabela conferida' do
      expect(Date.iso8601(described_class::PRICING_TABLE_DATE)).to eq(Date.new(2026, 10, 6))
    end

    it 'usa gravação no cache a 2x (ttl 1 h) e leitura a 10%' do
      expect(described_class::CACHE_TTL).to eq('1h')
      expect(described_class::CACHE_WRITE_FACTOR).to eq(2.0)
      expect(described_class::CACHE_READ_FACTOR).to eq(0.1)
    end
  end

  describe '#record_usage' do
    # custo = entrada + gravação 2x + leitura 10% + saída
    {
      'claude-sonnet-5' => 2.0 + 4.0 + 0.2 + 10.0,   # 16,20 (antes dava 24,30)
      'claude-opus-4-8' => 5.0 + 10.0 + 0.5 + 25.0,  # 40,50
      'claude-haiku-4-5' => 1.0 + 2.0 + 0.1 + 5.0    # 8,10
    }.each do |model_id, esperado|
      it "grava o custo certo para o #{model_id} (US$ #{esperado})" do
        service = service_for(model_id)
        expect(service.model).to eq(model_id)

        row = um_milhao_de_cada(service)
        expect(row.model).to eq(model_id)
        expect(row.input_tokens).to eq(3_000_000)
        expect(row.cache_write_tokens).to eq(1_000_000)
        expect(row.cache_read_tokens).to eq(1_000_000)
        expect(row.output_tokens).to eq(1_000_000)
        expect(row.cost_usd.to_f).to be_within(0.000001).of(esperado)
      end
    end

    it 'Sonnet sem cache: 10 mil de entrada + 1 mil de saída = US$ 0,03 (não US$ 0,045)' do
      service = service_for('claude-sonnet-5')
      service.record_usage(reply_struct.new(usage_struct.new(10_000, 0, 0, 1_000)))
      expect(Crm::AiUsage.last.cost_usd.to_f).to be_within(0.000001).of(0.03)
    end
  end
end
