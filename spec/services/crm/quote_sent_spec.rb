require 'rails_helper'

# 🏷️ 11/11/2026 (LIFE): proposta enviada → etiqueta automática → cartão anda, compromisso nasce.
RSpec.describe Crm::QuoteSent do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:contact) { create(:contact, account: account, name: 'Ivan Coral') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life') }
  let(:pronto) { Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento pronto', position: 0) }
  let(:enviado) do
    Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento Enviado', position: 1,
                       settings: { 'task_owner_id' => admin.id,
                                   'prazo' => { 'modo' => 'dia_util', 'hora' => '09:00', 'tarefa' => 'Confirmar se o cliente recebeu o orçamento' } })
  end

  # as duas automações que o followup_life_v3.rb cria na conta
  def automations!
    Crm::Automation.create!(stage: pronto, name: 'Orçamento enviado: levar o cartão', trigger_type: 'label_added', action_type: 'move_card',
                            delay_minutes: 0, action_config: { 'label_filter' => described_class::LABEL, 'target_stage_id' => enviado.id })
    Crm::Automation.create!(stage: enviado, name: 'Etiqueta: orçamento enviado', trigger_type: 'card_entered', action_type: 'apply_label',
                            delay_minutes: 0, action_config: { 'label' => described_class::LABEL })
  end

  it 'põe a etiqueta, guarda o valor no cartão, leva o cartão para a coluna e abre o compromisso', :aggregate_failures do
    automations!
    card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: pronto)

    perform_enqueued_jobs { expect(described_class.call(contact, value: 24_800)).to be(true) }

    expect(contact.reload.label_list).to eq(['orcamento-enviado'])
    expect(account.labels.find_by(title: 'orcamento-enviado')).to have_attributes(color: '#EA580C', show_on_sidebar: true)
    expect(card.reload).to have_attributes(stage_id: enviado.id, value: 24_800)
    task = Crm::StageDeadline.open_tasks(account, enviado.id, card.id).sole
    expect(task.title).to eq('⏰ Ivan Coral — Confirmar se o cliente recebeu o orçamento')
  end

  it 'chamar de novo não duplica nada; sem valor não mexe no valor; sem contato devolve false', :aggregate_failures do
    automations!
    card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: pronto, value: 10_000)

    perform_enqueued_jobs do
      described_class.call(contact)
      described_class.call(contact, value: 0)
    end

    expect(contact.reload.label_list).to eq(['orcamento-enviado'])
    expect(card.reload.value).to eq(10_000)
    expect(account.tasks.count).to eq(1)
    expect(described_class.call(nil)).to be(false)
  end
end
