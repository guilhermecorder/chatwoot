require 'rails_helper'

# 🧾 item 413: o registro permanente de quem atendeu cada conversa (motor,
# Roteiro, custo), com ou sem teste A/B ligado. Alimenta o Comparativo de caixas.
RSpec.describe Crm::AttendanceUsage do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  def stamp
    conversation.reload.additional_attributes[described_class::STAMP]
  end

  it 'soma cada chamada por motor, Roteiro e agente, e cada resposta', :aggregate_failures do
    described_class.track!(conversation, 'atendente_agendamento', 'model' => 'gpt-6-luna', 'cost_usd' => 0.001, 'script' => 'v1')
    described_class.track!(conversation, 'atendente_agendamento', 'reply' => true)
    described_class.track!(conversation, 'atendente_agendamento', 'model' => 'claude-sonnet-5', 'cost_usd' => 0.02, 'script' => 'v1')
    described_class.track!(conversation, 'atendente_agendamento', 'reply' => true, 'booked' => true, 'handoff' => true)

    expect(stamp).to include('chamadas' => 2, 'respostas' => 2, 'custo_usd' => 0.021,
                             'roteiros' => { 'v1' => 2 }, 'agentes' => { 'atendente_agendamento' => 2 })
    expect(stamp['modelos']).to eq('gpt-6-luna' => { 'n' => 1, 'usd' => 0.001 }, 'claude-sonnet-5' => { 'n' => 1, 'usd' => 0.02 })
    expect(stamp.values_at('agendou_at', 'humano_at', 'desde', 'ultima_at')).to all(be_present)
  end

  it 'conta a falha sem inventar motor quando a chamada nem saiu', :aggregate_failures do
    described_class.track!(conversation, 'atendente_pos', 'model' => nil, 'cost_usd' => 0.0, 'error' => true, 'fallback' => false)

    expect(stamp).to include('erros' => 1)
    expect(stamp).not_to include('modelos', 'chamadas')
  end

  it 'não mexe nas outras chaves da conversa' do
    conversation.update!(additional_attributes: { 'meta_ads' => { 'source_id' => '123' } })

    described_class.track!(conversation, 'atendente_agendamento', 'reply' => true)

    expect(conversation.reload.additional_attributes['meta_ads']).to eq('source_id' => '123')
  end

  describe '.read' do
    it 'lê o carimbo permanente', :aggregate_failures do
      described_class.track!(conversation, 'atendente_agendamento', 'model' => 'gpt-6-luna', 'cost_usd' => 0.004, 'script' => 'v2')
      described_class.track!(conversation, 'atendente_agendamento', 'reply' => true, 'handoff' => true)

      read = described_class.read(conversation.reload.additional_attributes)

      expect(read).to include(custo_usd: 0.004, respostas: 1, chamadas: 1, humano: true, agendou: false)
      expect(read[:modelos]).to eq('gpt-6-luna' => 1)
      expect(read[:roteiros]).to eq('v2' => 1)
    end

    it 'cai no carimbo do teste A/B nas conversas antigas', :aggregate_failures do
      legacy = { Crm::EngineExperiment::STAMP => { 'atendente_agendamento' => {
        'test' => 't', 'arm' => 'b', 'script' => 'v2', 'model' => 'gpt-6-luna', 'respostas' => 3, 'custo_usd' => 0.01, 'agendou_at' => 'x'
      } } }

      read = described_class.read(legacy)

      expect(read).to include(custo_usd: 0.01, respostas: 3, agendou: true, humano: false)
      expect(read[:modelos]).to eq('gpt-6-luna' => 1)
      expect(read[:roteiros]).to eq('v2' => 1)
    end

    it 'devolve nil quando a conversa não tem registro nenhum' do
      expect(described_class.read('meta_ads' => {})).to be_nil
    end
  end
end
