require 'rails_helper'

# 🔒 Rodada 4 da auditoria (#229): o simulador troca o "motivo da ligação" pelo
# Cevico::AttributeMerge — não pode apagar o que outro escritor gravou na conversa.
RSpec.describe Crm::AgentSimulator do
  let(:account) { create(:account) }
  let(:conversation) do
    create(:conversation, account: account, additional_attributes: { 'cevico_simulado' => true, 'cevico_simulado_objective' => 'antigo' })
  end

  it 'troca o motivo sem apagar a chave gravada no meio por outro processo' do
    foto_velha = Conversation.find(conversation.id)
    Cevico::AttributeMerge.merge!(Conversation.find(conversation.id)) { |a| a.merge('cevico_ia_shadow_count' => 3) }

    described_class.new(account: account, agent_key: 'ligacao', objective: 'Confirmar consulta').objective!(foto_velha)

    expect(conversation.reload.additional_attributes).to include(
      'cevico_simulado' => true, 'cevico_simulado_objective' => 'Confirmar consulta', 'cevico_ia_shadow_count' => 3
    )
  end

  it 'não grava quando o motivo está em branco ou é o mesmo' do
    described_class.new(account: account, agent_key: 'ligacao', objective: '').objective!(conversation)
    described_class.new(account: account, agent_key: 'ligacao', objective: 'antigo').objective!(conversation)

    expect(conversation.reload.additional_attributes['cevico_simulado_objective']).to eq('antigo')
  end
end
