require 'rails_helper'
require 'prism'

RSpec.describe CrmAutomationFireJob do
  # action_type permitido no modelo => método privado do job que executa a ação
  let(:handlers) do
    {
      'webhook' => :fire_webhook,
      'n8n_flow' => :fire_n8n,
      'apply_label' => :apply_label,
      'move_card' => :move_card,
      'log_timeline' => :log_timeline,
      'notify_team' => :notify_team,
      'meta_ads_event' => :fire_meta_ads,
      'google_ads_conversion' => :fire_google_ads,
      'send_form' => :send_form,
      'ai_analyze' => :ai_analyze,
      'schedule_appointment' => :schedule_appointment,
      'set_value' => :set_value,
      'send_template' => :send_template,
      'closing_extract' => :closing_extract,
      'nps_score' => :nps_score
    }
  end

  # Lê o `case automation.action_type` do #perform direto do fonte, para que
  # um tipo despachado pelo job sem constar em Crm::Automation::ACTION_TYPES
  # (ou vice-versa) quebre aqui — e não como 422 na tela de automações.
  def dispatched_action_types
    source = Rails.root.join('app/jobs/crm_automation_fire_job.rb').read
    case_node = find_action_type_case(Prism.parse(source).value)
    raise 'case automation.action_type não encontrado em CrmAutomationFireJob#perform' unless case_node

    case_node.conditions.flat_map { |when_node| when_node.conditions.map(&:unescaped) }
  end

  def find_action_type_case(node)
    return node if action_type_case?(node)

    node.compact_child_nodes.each do |child|
      found = find_action_type_case(child)
      return found if found
    end
    nil
  end

  def action_type_case?(node)
    node.is_a?(Prism::CaseNode) &&
      node.predicate.is_a?(Prism::CallNode) &&
      node.predicate.name == :action_type &&
      node.predicate.receiver&.slice == 'automation'
  end

  describe 'dispatch table' do
    it 'dispatches exactly the action types the model allows' do
      expect(dispatched_action_types).to match_array(Crm::Automation::ACTION_TYPES)
    end

    it 'maps a handler in this spec for every allowed action type' do
      expect(handlers.keys).to match_array(Crm::Automation::ACTION_TYPES)
    end
  end

  describe '#perform' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account) }
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil') }
    let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Coluna') }
    let(:job) { described_class.new }

    def create_automation(action_type, attrs = {})
      stage.automations.create!({ name: "Automação #{action_type}", trigger_type: 'card_entered',
                                  action_type: action_type, delay_minutes: 0, action_config: {} }.merge(attrs))
    end

    Crm::Automation::ACTION_TYPES.each do |action_type|
      it "runs the #{action_type} handler and logs the firing" do
        automation = create_automation(action_type)
        handler = handlers.fetch(action_type)
        allow(job).to receive(handler)

        job.perform(automation.id, contact.id)

        expect(job).to have_received(handler)
        log = Crm::AutomationLog.find_by(automation: automation, contact_id: contact.id)
        expect(log&.status).to eq('fired')
      end
    end

    it 'passes the contact and the pipeline to closing_extract' do
      automation = create_automation('closing_extract')
      allow(job).to receive(:closing_extract)

      job.perform(automation.id, contact.id)

      expect(job).to have_received(:closing_extract).with(contact, pipeline)
    end

    it 'passes the contact to nps_score' do
      automation = create_automation('nps_score')
      allow(job).to receive(:nps_score)

      job.perform(automation.id, contact.id)

      expect(job).to have_received(:nps_score).with(contact)
    end

    it 'does nothing when the automation is inactive' do
      automation = create_automation('nps_score', active: false)
      allow(job).to receive(:nps_score)

      job.perform(automation.id, contact.id)

      expect(job).not_to have_received(:nps_score)
      expect(Crm::AutomationLog.where(automation: automation)).to be_empty
    end

    it 'does nothing for a contact from another account' do
      automation = create_automation('closing_extract')
      other_contact = create(:contact, account: create(:account))
      allow(job).to receive(:closing_extract)

      job.perform(automation.id, other_contact.id)

      expect(job).not_to have_received(:closing_extract)
      expect(Crm::AutomationLog.where(automation: automation)).to be_empty
    end
  end
end
