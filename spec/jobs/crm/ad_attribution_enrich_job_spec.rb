require 'rails_helper'

# 🔒 Rodada 4 da auditoria (#66/#174): enquanto a Meta responde com o nome do
# anúncio, outro escritor pode gravar pausa da IA / lembrete no mesmo contato e
# na mesma conversa. O job tem de completar o carimbo SEM apagar essas marcas.
RSpec.describe Crm::AdAttributionEnrichJob do
  let(:account) { create(:account) }
  let(:meta_ads) { { 'source_id' => '120200', 'ad_title' => 'Lente' } }
  let(:contact) { create(:contact, account: account, additional_attributes: { 'meta_ads' => meta_ads }) }
  let(:conversation) { create(:conversation, account: account, contact: contact, additional_attributes: { 'meta_ads' => meta_ads }) }
  let(:lookup) { instance_double(Crm::AdNameLookupService) }

  before { allow(Crm::AdNameLookupService).to receive(:new).and_return(lookup) }

  it 'completa o nome do anúncio sem apagar a pausa da IA nem o lembrete gravados durante a busca na Meta' do
    allow(lookup).to receive(:name_for).with('120200') do
      # "outro processo" grava no meio da chamada HTTP (foto do job já está velha)
      Cevico::AttributeMerge.merge!(Conversation.find(conversation.id)) { |a| a.merge('cevico_atendente_wa' => { 'paused' => true }) }
      Cevico::AttributeMerge.merge!(Contact.find(contact.id)) { |a| a.merge('cevico_appt_reminders' => { 'd2' => 'enviado' }) }
      'CEVICO | Refrativa | Vídeo 03'
    end

    described_class.perform_now(contact.id, conversation.id)

    conversation.reload
    expect(conversation.additional_attributes['meta_ads']).to eq(meta_ads.merge('ad_name' => 'CEVICO | Refrativa | Vídeo 03'))
    expect(conversation.additional_attributes['cevico_atendente_wa']).to eq('paused' => true)

    contact.reload
    expect(contact.additional_attributes['meta_ads']).to eq(meta_ads.merge('ad_name' => 'CEVICO | Refrativa | Vídeo 03'))
    expect(contact.additional_attributes['cevico_appt_reminders']).to eq('d2' => 'enviado')
  end

  it 'não chama a Meta quando o carimbo já tem nome, e não grava nada quando a Meta não responde' do
    contact.update_column(:additional_attributes, { 'meta_ads' => meta_ads.merge('ad_name' => 'Já tinha') }) # rubocop:disable Rails/SkipsModelValidations
    allow(lookup).to receive(:name_for).with('120200').and_return(nil)

    described_class.perform_now(contact.id, conversation.id)

    expect(lookup).to have_received(:name_for).once # só a conversa foi perguntar
    expect(contact.reload.additional_attributes['meta_ads']['ad_name']).to eq('Já tinha')
    expect(conversation.reload.additional_attributes['meta_ads']).to eq(meta_ads)
  end

  it 'se alguém completou o carimbo enquanto a Meta respondia, mantém o que já estava' do
    allow(lookup).to receive(:name_for).with('120200') do
      Cevico::AttributeMerge.merge!(Conversation.find(conversation.id)) { |a| a.merge('meta_ads' => meta_ads.merge('ad_name' => 'Primeiro')) }
      'Segundo'
    end

    described_class.perform_now(contact.id, conversation.id)

    expect(conversation.reload.additional_attributes['meta_ads']['ad_name']).to eq('Primeiro')
  end
end
