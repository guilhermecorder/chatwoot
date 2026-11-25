require 'rails_helper'

# 🔒 item 417: os três últimos pontos da CEVICO que gravavam additional_attributes
# direto (canal de origem do contato, carimbo do Plano de Reativação e da
# Segmentação na mensagem) passaram para o Cevico::AttributeMerge. O que se
# garante aqui: MESMAS chaves e valores de antes, e uma gravação feita em
# paralelo (cópia velha na memória) não é mais apagada.
RSpec.describe 'Item 417 — carimbos pelo merge atômico' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Elizângela') }
  let(:contact) { create(:contact, account: account, additional_attributes: { 'sexo' => 'feminino' }) }

  # outra gravação, por outro caminho, sem a cópia da memória ficar sabendo
  def grava_em_paralelo(record, extra)
    fresh = record.class.find(record.id)
    fresh.update_column(:additional_attributes, (fresh.additional_attributes || {}).merge(extra)) # rubocop:disable Rails/SkipsModelValidations
  end

  describe 'Crm::LeadChannel.stamp!' do
    let(:at) { Time.zone.parse('2026-11-24 10:00') }

    it 'grava canal_origem com quem informou e quando, sem mexer nas outras chaves', :aggregate_failures do
      expect(Crm::LeadChannel.stamp!(contact, 'ligacao', user: admin, at: at)).to be(true)
      esperado = { 'sexo' => 'feminino', 'canal_origem' => { 'key' => 'ligacao', 'por' => 'Elizângela', 'em' => at.iso8601 } }
      expect(contact.additional_attributes).to eq(esperado)
      expect(contact.reload.additional_attributes).to eq(esperado)
    end

    it 'primeiro toque vence e chave inválida não grava', :aggregate_failures do
      Crm::LeadChannel.stamp!(contact, 'ligacao', user: admin, at: at)
      expect(Crm::LeadChannel.stamp!(contact, 'indicacao', user: admin)).to be(false)
      expect(Crm::LeadChannel.stamp!(contact, 'nao_existe', user: admin)).to be(false)
      expect(Crm::LeadChannel.stamp!(nil, 'ligacao')).to be(false)
      expect(contact.reload.additional_attributes.dig('canal_origem', 'key')).to eq('ligacao')
    end

    it 'cópia velha na memória: não apaga o que foi gravado em paralelo', :aggregate_failures do
      grava_em_paralelo(contact, 'cevico_followup_pausa' => true)
      expect(Crm::LeadChannel.stamp!(contact, 'balcao', user: nil, at: at)).to be(true)
      expect(contact.reload.additional_attributes).to eq(
        'sexo' => 'feminino', 'cevico_followup_pausa' => true,
        'canal_origem' => { 'key' => 'balcao', 'por' => nil, 'em' => at.iso8601 }
      )
    end

    it 'cópia velha na memória: respeita o primeiro toque que já está no banco', :aggregate_failures do
      grava_em_paralelo(contact, 'canal_origem' => { 'key' => 'ligacao', 'por' => 'Outra', 'em' => at.iso8601 })
      expect(Crm::LeadChannel.stamp!(contact, 'balcao', user: admin)).to be(false)
      expect(contact.reload.additional_attributes.dig('canal_origem', 'key')).to eq('ligacao')
    end
  end

  describe 'carimbo na mensagem do envio em lote' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let(:message) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       additional_attributes: { 'cevico_auto' => 'Campaign' })
    end
    let(:tpl) { { 'template_params' => { 'name' => 'reativa', 'language' => 'pt_BR' }, 'message_preview' => 'Oi {{1}}' } }
    let(:child) { Struct.new(:account, :sender, :name, :parent_id).new(account, admin, 'Filha', 77) }

    def envio_de_mentira(msg)
      sender = instance_double(Crm::SendTemplateService, message: msg, perform: msg&.conversation)
      allow(Crm::SendTemplateService).to receive(:new).and_return(sender)
    end

    it 'Plano de Reativação: grava cevico_reactivation e preserva o resto', :aggregate_failures do
      envio_de_mentira(message)
      grava_em_paralelo(message, 'cevico_wa_billing' => { 'categoria' => 'MARKETING' })
      expect(Crm::ReactivationPlan.deliver(child, inbox, tpl, contact, slice: 'nao_fechou', frente: 'padrao')).to eq(conversation)
      expect(message.reload.additional_attributes).to eq(
        'cevico_auto' => 'Campaign', 'cevico_wa_billing' => { 'categoria' => 'MARKETING' },
        'cevico_reactivation' => { 'plan_id' => 77, 'slice' => 'nao_fechou', 'frente' => 'padrao', 'template' => 'reativa' }
      )
    end

    it 'Segmentação: grava cevico_segment e preserva o resto', :aggregate_failures do
      envio_de_mentira(message)
      grava_em_paralelo(message, 'cevico_wa_billing' => { 'categoria' => 'MARKETING' })
      segment = Struct.new(:id, :kind).new(5, 'reativacao')
      variant = tpl.merge('key' => 'a')
      expect(Crm::SegmentSender.deliver(segment, child, inbox, variant, contact)).to eq(conversation)
      expect(message.reload.additional_attributes).to eq(
        'cevico_auto' => 'Campaign', 'cevico_wa_billing' => { 'categoria' => 'MARKETING' },
        'cevico_segment' => { 'segment_id' => 5, 'variant' => 'a', 'kind' => 'reativacao', 'template' => 'reativa' }
      )
    end

    it 'envio que não gerou mensagem segue sem erro', :aggregate_failures do
      envio_de_mentira(nil)
      expect { Crm::ReactivationPlan.deliver(child, inbox, tpl, contact) }.not_to raise_error
      expect { Crm::SegmentSender.deliver(Struct.new(:id, :kind).new(5, 'x'), child, inbox, tpl.merge('key' => 'a'), contact) }.not_to raise_error
    end
  end
end
