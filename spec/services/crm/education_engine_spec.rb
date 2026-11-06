require 'rails_helper'

# 🎓 item 389: Motor de Educação — lê ontem, separa quem agendou × quem não,
# guarda o placar por caixa, cria sugestões pendentes; aprovar acrescenta o
# aprendizado com foto antes; o bloco só entra na caixa piloto.
RSpec.describe Crm::EducationEngine do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:pilot) { create(:inbox, account: account) }
  let(:control) { create(:inbox, account: account) }
  let(:day) { described_class::TZ.yesterday }
  let(:at) { described_class::TZ.parse("#{day.iso8601} 10:00") }
  let(:messages_api) { double('messages') } # rubocop:disable RSpec/VerifiedDoubles
  let(:answer) do
    { resumo: 'Quem agendou recebeu dois horários logo depois do valor.',
      padroes_que_agendaram: ['Ofereceu dois horários'], padroes_que_perderam: ['Valor sem convite'],
      aprendizados: [{ regra: 'Depois do valor, ofereça dois horários na mesma mensagem.', por_que: 'Visto em 3 conversas.',
                       conversa_id: 77, paciente_disse: 'Quanto custa?', atendente_disse: 'R$ 150.',
                       deveria_dizer: 'R$ 150 à vista. Tenho quarta 10h ou quinta 15h, qual fica melhor?', confianca: 'alta' }] }.to_json
  end

  def configure(motor = {})
    CrmSetting.create!(account: account, ai_config: {
                         'api_key' => 'sk-teste',
                         'motor' => { 'enabled' => true, 'pilot_inbox_ids' => [pilot.id], 'control_inbox_ids' => [control.id] }.merge(motor)
                       })
  end

  def stub_ai
    usage = double('usage', input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 0, cache_read_input_tokens: 0) # rubocop:disable RSpec/VerifiedDoubles
    message = double('message', content: [double('block', type: :text, text: answer)], usage: usage) # rubocop:disable RSpec/VerifiedDoubles
    allow(messages_api).to receive(:create).and_return(message)
    allow(Anthropic::Client).to receive(:new).and_return(double('client', messages: messages_api)) # rubocop:disable RSpec/VerifiedDoubles
  end

  def talk(inbox)
    contact = create(:contact, account: account)
    conv = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, conversation: conv, account: account, inbox: inbox, message_type: :incoming, content: 'Quanto custa?', created_at: at)
    create(:message, conversation: conv, account: account, inbox: inbox, message_type: :outgoing, content: 'R$ 150.',
                     created_at: at + 1.minute)
    conv
  end

  def book(conv)
    Task.create!(account: account, creator: user, title: 'Consulta', task_type: 'consulta', unit: 'tatuape',
                 contact: conv.contact, due_at: 3.days.from_now, created_at: at + 5.minutes)
  end

  describe '.prompt_block' do
    it 'entra só na caixa piloto, no Atendente de Agendamento, com o motor ligado e com aprendizados', :aggregate_failures do
      configure('rules' => '- Ofereça dois horários.')
      in_pilot = create(:conversation, account: account, inbox: pilot)
      in_control = create(:conversation, account: account, inbox: control)

      expect(described_class.prompt_block(in_pilot, 'atendente_agendamento')).to include('APRENDIZADOS DO MOTOR', 'Ofereça dois horários')
      expect(described_class.prompt_block(in_control, 'atendente_agendamento')).to be_nil
      expect(described_class.prompt_block(in_pilot, 'atendente_pos')).to be_nil

      described_class.update_settings!(account, enabled: false)
      expect(described_class.prompt_block(in_pilot, 'atendente_agendamento')).to be_nil
    end
  end

  describe '#call' do
    it 'separa quem agendou, guarda o placar por caixa e cria a sugestão pendente', :aggregate_failures do
      configure
      stub_ai
      booked = talk(pilot)
      book(booked)
      talk(pilot)
      talk(control)

      result = described_class.new(account: account).call(day: day)

      expect(result).to include(ok: true, suggestions: 1)
      row = described_class.settings(account).dig('state', 'days', day.iso8601)
      expect(row['score']).to eq(pilot.id.to_s => { 'n' => 2, 'booked' => 1 }, control.id.to_s => { 'n' => 1, 'booked' => 0 })
      expect(row['summary']).to include('dois horários')
      guidance = Crm::AgentGuidance.find_by(account: account, source: 'motor')
      expect(guidance).to have_attributes(status: 'pending', target_section: 'motor', agent_key: 'atendente_agendamento')
      expect(messages_api).to have_received(:create) do |args|
        text = args[:messages].first[:content]
        expect(text).to include('QUE VIRARAM CONSULTA AGENDADA (1)', 'QUE NÃO VIRARAM CONSULTA (2)')
      end

      # o mesmo dia não é lido duas vezes; a mesma regra não volta
      expect(described_class.new(account: account).call(day: day)).to eq(skipped: 'já leu este dia')
      described_class.new(account: account).call(day: day, force: true)
      expect(Crm::AgentGuidance.where(account: account, source: 'motor').count).to eq(1)
    end

    it 'desligado não chama a IA' do
      configure('enabled' => false)
      expect(described_class.new(account: account).call(day: day)).to eq(skipped: 'desligado')
    end
  end

  describe 'aprovar e voltar' do
    it 'aprovar acrescenta o aprendizado com foto antes; voltar restaura', :aggregate_failures do
      configure('rules' => '- Regra antiga.')
      guidance = Crm::AgentGuidance.create!(account: account, agent_key: 'atendente_agendamento', source: 'motor',
                                            target_section: 'motor', rule: 'Ofereça dois horários.')

      guidance.apply!(by: user)

      expect(described_class.rules(account)).to eq("- Regra antiga.\n- Ofereça dois horários.")
      version = Crm::ScriptVersion.find_by(account: account, kind: 'motor')
      expect(version.content).to eq('rules' => '- Regra antiga.')
      # o Roteiro de todos não muda
      expect(CrmSetting.find_by(account: account).ai_config['script']).to be_nil

      version.restore!(by: user)
      expect(described_class.rules(account)).to eq('- Regra antiga.')
    end
  end
end
