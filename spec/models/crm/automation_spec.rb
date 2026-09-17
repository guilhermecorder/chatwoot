require 'rails_helper'

RSpec.describe Crm::Automation do
  let(:account) { create(:account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Coluna') }

  def build_automation(attrs = {})
    described_class.new({ stage: stage, name: 'Automação', trigger_type: 'card_entered',
                          action_type: 'webhook', delay_minutes: 0, action_config: {} }.merge(attrs))
  end

  describe 'validations' do
    it 'is valid with the default attributes' do
      expect(build_automation).to be_valid
    end

    it 'requires a name' do
      expect(build_automation(name: '')).not_to be_valid
    end

    it 'rejects an unknown trigger type' do
      expect(build_automation(trigger_type: 'unknown')).not_to be_valid
    end

    it 'rejects a negative delay' do
      expect(build_automation(delay_minutes: -1)).not_to be_valid
    end

    describe 'action_type' do
      Crm::Automation::ACTION_TYPES.each do |action_type|
        it "accepts #{action_type}" do
          expect(build_automation(action_type: action_type)).to be_valid
        end
      end

      it 'rejects an unknown action type' do
        automation = build_automation(action_type: 'unknown')

        expect(automation).not_to be_valid
        expect(automation.errors[:action_type]).to include('is not included in the list')
      end

      # Agentes de coluna oferecidos na tela (ColumnAutomationsModal): antes
      # faltavam no allow-list e o create! do AutomationsController devolvia 422.
      it 'accepts the Monitor de Fechamento and Agente de NPS column agents' do
        expect(build_automation(action_type: 'closing_extract')).to be_valid
        expect(build_automation(action_type: 'nps_score')).to be_valid
      end

      it 'allows every action the settings controller creates for column agents' do
        agent_actions = Api::V1::Accounts::Crm::SettingsController::AGENT_STAGE_ACTIONS.values

        expect(Crm::Automation::ACTION_TYPES).to include(*agent_actions)
      end
    end
  end

  describe 'persistence through the stage association' do
    it 'creates a closing_extract automation without raising' do
      expect do
        stage.automations.create!(name: 'Monitor de Fechamento', trigger_type: 'message_created',
                                  action_type: 'closing_extract', delay_minutes: 0, action_config: {})
      end.to change(described_class, :count).by(1)
    end

    it 'creates an nps_score automation without raising' do
      expect do
        stage.automations.create!(name: 'Agente de NPS', trigger_type: 'message_created',
                                  action_type: 'nps_score', delay_minutes: 0, action_config: {})
      end.to change(described_class, :count).by(1)
    end
  end
end
