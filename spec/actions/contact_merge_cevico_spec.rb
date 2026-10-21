require 'rails_helper'

# rubocop:disable RSpec/DescribeMethod, RSpec/SpecFilePathFormat, RSpec/MultipleExpectations, Rails/SkipsModelValidations

# 🔒 Rodada 6 (#227/#270/#200): mesclar duplicados leva TUDO da CEVICO para o
# contato que fica. Antes: erro de chave estrangeira (consulta/nota clínica no
# duplicado) ou o card + histórico de colunas do duplicado sumiam.
RSpec.describe ContactMergeAction, 'dados da CEVICO na mesclagem' do
  subject(:merge!) { described_class.new(account: account, base_contact: base, mergee_contact: mergee).perform }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:base) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511988887777') }
  let(:mergee) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+551188887777') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
  let(:novo) { Crm::Stage.create!(pipeline: pipeline, name: 'Novo contato', position: 0) }
  let(:agendado) { Crm::Stage.create!(pipeline: pipeline, name: 'Consulta Agendada', position: 3) }
  let(:form) { Crm::Form.create!(account: account, name: 'Pré-consulta', questions: [], funnel_stats: {}, ai_insight: {}) }

  def consulta_de(contact)
    Task.create!(account: account, creator: user, title: 'Consulta: Maria Teste', task_type: 'consulta', unit: 'tatuape',
                 contact: contact, due_at: 1.day.from_now)
  end

  context 'when o duplicado tem consulta + card e o contato que fica não tem card' do
    let!(:consulta) { consulta_de(mergee) }
    let!(:card) { Crm::Contact.create!(contact: mergee, pipeline: pipeline, stage: agendado) }
    let!(:nota) { Crm::ClinicalNote.create!(account: account, contact: mergee, author: user, performed_at: 1.day.ago) }
    let!(:resposta) do
      Crm::FormResponse.create!(account: account, form: form, contact: mergee, completed_at: 1.hour.ago,
                                answers: [{ 'id' => 'q1', 'label' => 'Usa colírio?', 'type' => 'text', 'value' => 'Sim' }])
    end
    let!(:cirurgia) do
      Crm::OftalmofacilSurgery.create!(account: account, contact: mergee, item_token: "of-#{SecureRandom.hex(4)}",
                                       patient_name: 'Maria Teste', surgery_date: 3.days.from_now.to_date)
    end

    it 'mescla sem erro e leva consulta, nota, formulário, cirurgia e o card para o contato que fica' do
      expect { merge! }.not_to raise_error
      expect(Contact.exists?(mergee.id)).to be(false)
      expect(consulta.reload.contact_id).to eq(base.id)
      expect(nota.reload.contact_id).to eq(base.id)
      expect(resposta.reload.contact_id).to eq(base.id)
      expect(cirurgia.reload.contact_id).to eq(base.id)
      expect(card.reload.contact_id).to eq(base.id)
      expect(card.stage_id).to eq(agendado.id)
      expect(Crm::StageLog.where(crm_contact_id: card.id).count).to eq(1)
    end
  end

  context 'when os dois têm card no mesmo funil' do
    let!(:card_base) { Crm::Contact.create!(contact: base, pipeline: pipeline, stage: novo) }
    let!(:card_mergee) { Crm::Contact.create!(contact: mergee, pipeline: pipeline, stage: agendado, value: 4500) }
    let!(:consulta) { consulta_de(mergee) }

    it 'fica o card que mexeu por último, no contato que fica, com o histórico de colunas dos dois' do
      card_base.update_columns(stage_moved_at: 2.days.ago)
      merge!
      cards = Crm::Contact.where(contact_id: base.id)
      expect(cards.count).to eq(1)
      expect(cards.first.id).to eq(card_mergee.id)
      expect(cards.first.stage_id).to eq(agendado.id)
      expect(cards.first.value.to_f).to eq(4500.0)
      expect(Crm::Contact.exists?(card_base.id)).to be(false)
      logs = Crm::StageLog.where(crm_contact_id: card_mergee.id)
      expect(logs.count).to eq(2)
      # só UMA coluna aberta (a do card que ficou)
      expect(logs.where(left_at: nil).pluck(:stage_id)).to eq([agendado.id])
      expect(consulta.reload.contact_id).to eq(base.id)
    end

    it 'card do duplicado parado há mais tempo: fica o do contato que fica e completa o valor vazio' do
      card_mergee.update_columns(stage_id: novo.id, stage_moved_at: 3.days.ago)
      card_base.update!(stage: agendado)
      merge!
      expect(Crm::Contact.where(contact_id: base.id).pluck(:id)).to eq([card_base.id])
      expect(card_base.reload.value.to_f).to eq(4500.0)
      expect(Crm::StageLog.where(crm_contact_id: card_base.id).count).to eq(3)
    end

    # coluna de desfecho ruim fica À DIREITA das boas no funil CEVICO
    it 'duplicado antigo em "Não Foi a Consulta" não tira o paciente de "Consulta Confirmada"' do
      confirmada = Crm::Stage.create!(pipeline: pipeline, name: 'Consulta Confirmada', position: 5)
      nao_foi = Crm::Stage.create!(pipeline: pipeline, name: 'Não Foi a Consulta', position: 6)
      card_mergee.update_columns(stage_id: nao_foi.id, stage_moved_at: 20.days.ago, updated_at: 20.days.ago)
      card_base.update!(stage: confirmada)

      merge!
      cards = Crm::Contact.where(contact_id: base.id)
      expect(cards.pluck(:id)).to eq([card_base.id])
      expect(cards.first.stage_id).to eq(confirmada.id)
      expect(Crm::StageLog.where(crm_contact_id: card_base.id, left_at: nil).pluck(:stage_id)).to eq([confirmada.id])
    end
  end

  it 'campanha em que os dois estavam: fica uma linha só, do contato que fica' do
    inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                      validate_provider_config: false).inbox
    campaign = Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: { 'name' => 'x' })
    Crm::CampaignContact.create!(campaign: campaign, contact: base, sent_at: 1.day.ago)
    Crm::CampaignContact.create!(campaign: campaign, contact: mergee, sent_at: 1.day.ago)
    expect { merge! }.not_to raise_error
    expect(Crm::CampaignContact.where(campaign: campaign).pluck(:contact_id)).to eq([base.id])
  end
end
# rubocop:enable RSpec/DescribeMethod, RSpec/SpecFilePathFormat, RSpec/MultipleExpectations, Rails/SkipsModelValidations
