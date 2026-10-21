require 'rails_helper'

# rubocop:disable RSpec/DescribeMethod, RSpec/SpecFilePathFormat, RSpec/MultipleMemoizedHelpers, Metrics/AbcSize

# 🔒 Rodada 6 (#210/#227/#270): apagar paciente (botão Excluir contato / pedido
# de exclusão da LGPD) dava erro de chave estrangeira para todo paciente com
# card, consulta ou anotação clínica. Agora: dado do paciente sai junto;
# consulta e cirurgia ficam na Agenda/hub, só que sem paciente.
RSpec.describe Contact, 'apagar paciente com dados da CEVICO' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511988887777') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Novo contato') }
  let(:form) { Crm::Form.create!(account: account, name: 'Pré-consulta', questions: [], funnel_stats: {}, ai_insight: {}) }
  let(:campaign) { Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: { 'name' => 'x' }) }

  let!(:card) { Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage) }
  let!(:consulta) do
    Task.create!(account: account, creator: user, title: 'Consulta: Maria Teste', task_type: 'consulta', unit: 'tatuape',
                 contact: contact, due_at: 1.day.from_now)
  end
  let!(:nota) { Crm::ClinicalNote.create!(account: account, contact: contact, author: user, performed_at: 1.day.ago) }
  let!(:resposta) do
    Crm::FormResponse.create!(account: account, form: form, contact: contact, completed_at: 1.hour.ago,
                              answers: [{ 'id' => 'q1', 'label' => 'Usa colírio?', 'type' => 'text', 'value' => 'Sim' }])
  end
  let!(:na_campanha) { Crm::CampaignContact.create!(campaign: campaign, contact: contact, sent_at: 1.day.ago) }
  let!(:link) { CevicoPageRef.create!(account: account, contact: contact, token: "tok-#{SecureRandom.hex(4)}") }
  let!(:cirurgia) do
    Crm::OftalmofacilSurgery.create!(account: account, contact: contact, item_token: "of-#{SecureRandom.hex(4)}",
                                     patient_name: 'Maria Teste', surgery_date: 3.days.from_now.to_date)
  end

  def expect_cevico_data_gone_and_agenda_kept
    expect(Crm::Contact.exists?(card.id)).to be(false)
    expect(Crm::ClinicalNote.exists?(nota.id)).to be(false)
    expect(Crm::FormResponse.exists?(resposta.id)).to be(false)
    expect(Crm::CampaignContact.exists?(na_campanha.id)).to be(false)
    expect(CevicoPageRef.exists?(link.id)).to be(false)
    # a consulta e a cirurgia continuam (o horário não some da agenda), sem paciente
    expect(consulta.reload.contact_id).to be_nil
    expect(cirurgia.reload.contact_id).to be_nil
  end

  it 'apaga paciente com card + consulta + nota clínica sem erro (antes: InvalidForeignKey)' do
    expect { contact.destroy! }.not_to raise_error
    expect(described_class.exists?(contact.id)).to be(false)
    expect_cevico_data_gone_and_agenda_kept
  end

  it 'o histórico de colunas do card fica guardado (sem dado pessoal)' do
    expect(Crm::StageLog.where(crm_contact_id: card.id).count).to eq(1)
    contact.destroy!
    expect(Crm::StageLog.where(crm_contact_id: card.id).count).to eq(1)
  end

  it 'o próprio banco segue a mesma regra (apagar direto, sem passar pelo Rails)' do
    expect { described_class.where(id: contact.id).delete_all }.not_to raise_error
    expect_cevico_data_gone_and_agenda_kept
  end
end
# rubocop:enable RSpec/DescribeMethod, RSpec/SpecFilePathFormat, RSpec/MultipleMemoizedHelpers, Metrics/AbcSize
