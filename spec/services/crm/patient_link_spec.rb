require 'rails_helper'

# 👪 item 346: quem agenda para outra pessoa — cadastro próprio + vínculo nos dois lados
RSpec.describe Crm::PatientLink do
  let(:account) { create(:account) }
  let(:henrique) { create(:contact, account: account, name: 'Henrique Souza', phone_number: '+5511988887777') }

  describe '.patient_for!' do
    it 'telefone próprio do paciente: cria o cadastro com nome + telefone', :aggregate_failures do
      patient = described_class.patient_for!(account: account, requester: henrique, name: 'Ricardo Lima', phone: '(11) 97777-6666')
      expect(patient).not_to eq(henrique)
      expect(patient.name).to eq('Ricardo Lima')
      expect(patient.phone_number).to eq('+5511977776666')
      expect(patient.additional_attributes['origem']).to eq('agendado_por_outro')
    end

    it 'telefone que já é de um cadastro: reaproveita (sem duplicar)' do
      ricardo = create(:contact, account: account, name: 'Ricardo Lima', phone_number: '+5511977776666')
      expect(described_class.patient_for!(account: account, requester: henrique, name: 'Ricardo Lima', phone: '11977776666')).to eq(ricardo)
    end

    it 'sem telefone próprio (o mesmo de quem agenda): cadastro só com o nome', :aggregate_failures do
      patient = described_class.patient_for!(account: account, requester: henrique, name: 'Joãozinho Souza', phone: '11988887777')
      expect(patient).not_to eq(henrique)
      expect(patient.phone_number).to be_blank
    end

    it 'o mesmo dependente agendado de novo (sem telefone) não duplica' do
      first = described_class.patient_for!(account: account, requester: henrique, name: 'Joãozinho Souza', phone: '')
      described_class.link!(requester: henrique, patient: first)
      again = described_class.patient_for!(account: account, requester: henrique.reload, name: 'Joãozinho Souza', phone: '')
      expect(again).to eq(first)
    end
  end

  describe '.link!' do
    let(:ricardo) { create(:contact, account: account, name: 'Ricardo Lima', phone_number: '+5511977776666') }
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
    let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta') }

    it 'amarra os dois lados e escreve uma linha na observação de cada card, sem repetir', :aggregate_failures do
      card_r = Crm::Contact.create!(contact_id: ricardo.id, pipeline_id: pipeline.id, stage_id: stage.id)
      card_h = Crm::Contact.create!(contact_id: henrique.id, pipeline_id: pipeline.id, stage_id: stage.id, notes: 'lead quente')

      2.times { described_class.link!(requester: henrique, patient: ricardo) }

      expect(ricardo.reload.additional_attributes['agendado_por']).to include('contact_id' => henrique.id, 'phone' => '+5511988887777')
      expect(henrique.reload.additional_attributes['agendou_para'].map { |e| e['contact_id'] }).to eq([ricardo.id])
      expect(card_r.reload.notes).to eq('👪 Agendado por Henrique Souza (+5511988887777)')
      expect(card_h.reload.notes).to eq("lead quente\n👪 Agendou para Ricardo Lima (+5511977776666)")
    end
  end
end
