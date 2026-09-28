require 'rails_helper'

# 🧭 27/09: o Mentor do Time conhece o PAPEL de cada pessoa e o que o sistema
# já faz sozinho; o login da IA fica fora do feedback e da mediana
RSpec.describe Crm::WeeklyMentorService do
  let(:account) { create(:account) }
  let(:vaneide) { create(:user, account: account, role: :agent, name: 'Vaneide') }
  let(:elizangela) { create(:user, account: account, role: :agent, name: 'Elizangela') }
  let(:robot) { create(:user, account: account, role: :agent, name: 'Atendimento IA') }
  let(:service) { described_class.new(account, rolling: true) }

  before do
    CrmSetting.create!(
      account: account,
      ai_config: { 'agents' => { 'mentor' => { 'enabled' => true }, 'opportunity' => { 'enabled' => true },
                                 'atendente_agendamento' => { 'enabled' => true, 'mode' => 'shadow' } } },
      agenda_config: { 'ai_user_id' => robot.id,
                       'team_roles' => { elizangela.id.to_s => { 'papel' => 'Fechamento de cirurgias',
                                                                 'responsabilidades' => 'fecha e agenda cirurgias' } },
                       'panel_assignments' => { vaneide.id.to_s => 'agendamento' },
                       'attendance_owners' => { 'cirurgia_user_id' => elizangela.id },
                       'nps_survey' => { 'enabled' => true } }
    )
    Crm::FollowupBot.create!(account: account, sender: vaneide, name: 'Régua', steps: [{ 'delay_hours' => 3, 'message' => 'oi' }])
  end

  it 'monta o papel escrito, ou o que o sistema sabe, e a lista do que roda sozinho', :aggregate_failures do
    written = service.send(:role_payload, elizangela)
    expect(written[:papel]).to eq('Fechamento de cirurgias')
    expect(written[:responsabilidades]).to eq('fecha e agenda cirurgias')
    expect(written[:o_sistema_sabe]).to include('responsável pela conferência do dia (cirurgias)')

    inferred = service.send(:role_payload, vaneide)
    expect(inferred[:papel]).to include('Agendamento')

    auto = service.send(:automations_payload)
    expect(auto.join("\n")).to include('Atendente de Agendamento', 'em sombra', '1 robô(s) de follow-up', 'NPS', 'Radar')
    expect(auto.join("\n")).not_to include('Pós-operatório')
  end

  it 'o login da IA fica fora do time e as notas privadas não contam como mensagem', :aggregate_failures do
    inbox = create(:inbox, account: account)
    conv = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, sender: robot, content: 'ia')
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, sender: vaneide, content: 'oi')
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, sender: vaneide, content: 'nota', private: true)

    active = service.send(:active_team_stats)
    expect(active.keys).to eq([vaneide])
    expect(active[vaneide][:mensagens_enviadas]).to eq(1)
  end

  it 'o prompt manda julgar pelo papel e não cobrar o que o sistema faz' do
    expect(described_class::SYSTEM_PROMPT).to include('papel_e_responsabilidades', 'o_sistema_faz_sozinho', 'NUNCA peça')
  end
end
