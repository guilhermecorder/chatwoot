require 'rails_helper'

# 🚧 item 231 (24/09): cerca dos parceiros — paciente de parceiro do hub
# Oftalmofácil nunca recebe mensagem automática; só a caixa dos parceiros
# (operada por gente) fala com ele.
RSpec.describe Crm::PartnerGuard do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:cevico_inbox) { create(:inbox, account: account, name: 'GOOGLE') }
  let(:partner_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
  let!(:cevico) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 1)
    end
  end
  let!(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 0)
    end
  end
  let!(:settings) do # rubocop:disable RSpec/LetSetup
    CrmSetting.create!(account: account, agenda_config: {
                         'oftalmofacil' => { 'provider_name' => 'CATARATA_SP', 'partner_pipeline_id' => partners.id,
                                             'partner_inbox_ids' => [partner_inbox.id] }
                       })
  end
  let(:ours) { create(:contact, account: account, name: 'Nosso', phone_number: '+5511911110000') }
  let(:by_card) { create(:contact, account: account, name: 'Parceiro por card', phone_number: '+5511922220000') }
  let(:by_label) { create(:contact, account: account, name: 'Parceiro por etiqueta', phone_number: '+5511933330000') }
  let(:by_attr) do
    create(:contact, account: account, name: 'Parceiro por atributo', phone_number: '+5511944440000',
                     additional_attributes: { 'origem' => 'oftalmofacil', 'parceiro' => 'CLINICA VISAO NORTE' })
  end

  before do
    Rails.cache.clear
    Crm::Contact.create!(contact: ours, pipeline: cevico, stage: cevico.stages.first)
    Crm::Contact.create!(contact: by_card, pipeline: partners, stage: partners.stages.first)
    by_label.add_labels(%w[oftalmofacil of_clinica_visao_norte])
    ours.add_labels(%w[oftalmofacil]) # a CATARATA_SP também ganha essa etiqueta — NÃO é parceiro
    by_attr
  end

  it 'reconhece o paciente de parceiro por card, etiqueta of_ ou atributo — e não confunde a CEVICO', :aggregate_failures do
    expect(described_class.partner_contact?(by_card)).to be true
    expect(described_class.partner_contact?(by_label)).to be true
    expect(described_class.partner_contact?(by_attr)).to be true
    expect(described_class.partner_contact?(ours)).to be false
    expect(described_class.excluded_contact_ids(account)).to contain_exactly(by_card.id, by_label.id, by_attr.id)
  end

  it 'conversa na caixa dos parceiros é de parceiro mesmo sem card/etiqueta; na caixa da CEVICO só se o paciente for', :aggregate_failures do
    stranger = create(:contact, account: account, phone_number: '+5511955550000')
    expect(described_class.partner_conversation?(create(:conversation, account: account, inbox: partner_inbox, contact: stranger))).to be true
    expect(described_class.partner_conversation?(create(:conversation, account: account, inbox: cevico_inbox, contact: stranger))).to be false
    expect(described_class.partner_conversation?(create(:conversation, account: account, inbox: cevico_inbox, contact: by_label))).to be true
  end

  it 'conversa nova na caixa dos parceiros NÃO cria card no funil da CEVICO (a da CEVICO cria)', :aggregate_failures do
    stranger = create(:contact, account: account, phone_number: '+5511966660000')
    listener = CrmListener.instance
    conv = create(:conversation, account: account, inbox: partner_inbox, contact: stranger)
    listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conv))
    expect(Crm::Contact.where(contact_id: stranger.id, pipeline_id: cevico.id)).not_to exist

    other = create(:contact, account: account, phone_number: '+5511977770000')
    conv2 = create(:conversation, account: account, inbox: cevico_inbox, contact: other)
    listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conv2))
    expect(Crm::Contact.where(contact_id: other.id, pipeline_id: cevico.id)).to exist
  end

  it 'automação que fala com o paciente é bloqueada para parceiro; ação interna (etiqueta) passa', :aggregate_failures do
    stage = partners.stages.first
    talk = Crm::Automation.create!(stage: stage, name: 'msg', trigger_type: 'card_entered', action_type: 'send_form',
                                   action_config: { 'template' => 'oi {{nome}}' }, active: true)
    tag = Crm::Automation.create!(stage: stage, name: 'tag', trigger_type: 'card_entered', action_type: 'apply_label',
                                  action_config: { 'label' => 'marcado' }, active: true)
    expect(Crm::SendTemplateService).not_to receive(:new) if defined?(Crm::SendTemplateService)
    expect { CrmAutomationFireJob.perform_now(talk.id, by_card.id, {}) }.not_to change(Crm::AutomationLog, :count)
    CrmAutomationFireJob.perform_now(tag.id, by_card.id, {})
    expect(by_card.reload.label_list).to include('marcado')
  end

  it 'campanha e régua deixam o parceiro de fora do público' do
    label = account.labels.create!(title: 'oftalmofacil')
    campaign = Crm::Campaign.new(account: account, audience: { 'include_label_ids' => [label.id] })
    expect(campaign.resolve_audience.pluck(:id)).to contain_exactly(ours.id)
  end

  it 'lembrete D-1 pula consulta de parceiro e o robô de follow-up ignora a caixa dos parceiros', :aggregate_failures do
    task = account.tasks.new(title: 'Exame: Maria', task_type: 'consulta', modality: 'exames', due_at: 1.day.from_now,
                             contact: by_label, source: 'oftalmofacil', source_detail: 'CLINICA VISAO NORTE')
    expect(described_class.partner_task?(task)).to be true

    bot = Crm::FollowupBot.new(account: account) if defined?(Crm::FollowupBot)
    if bot
      create(:conversation, account: account, inbox: partner_inbox, contact: create(:contact, account: account))
      keep = create(:conversation, account: account, inbox: cevico_inbox, contact: ours)
      job = Crm::FollowupBotJob.new
      expect(job.send(:conversations, bot).pluck(:id)).to contain_exactly(keep.id)
    end
  end
end
