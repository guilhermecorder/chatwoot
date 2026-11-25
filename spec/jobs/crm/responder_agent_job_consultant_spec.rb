require 'rails_helper'

# 🧑‍🏫 item 414 (24/11): o que o JOB faz com o registro do consultor superior —
# nota de sombra, nota interna ao vivo e linha no registro do card. A IA é
# simulada: o serviço devolve a resposta já com (ou sem) o registro.
RSpec.describe Crm::ResponderAgentJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:agent_cfg) { { 'enabled' => true, 'mode' => 'shadow', 'inbox_ids' => [inbox.id], 'no_card' => true } }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'api_key' => 'sk-teste', 'agents' => { 'atendente_agendamento' => agent_cfg } })
  end
  let(:incoming) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'tenho suspeita de glaucoma')
  end
  let(:ai_reply) do
    { mensagens: ['A avaliação com a Dra. Roberta é R$ 300. Quer que eu veja um horário?'], etapa: 'sondagem', agendar: false,
      agendamento: {}, pausar: false, chamar_humano: true, leitura: 'glaucoma: passei para a equipe', acoes: [], modelo: 'gpt-6-luna' }
  end
  let(:record) do
    { 'gatilho' => 'chamar_humano', 'modo' => 'sombra', 'modelo' => 'claude-sonnet-5', 'principal' => 'gpt-6-luna', 'status' => 'ok',
      'efeito' => 'evitou_equipe', 'mudou' => true, 'aplicado' => false, 'custo_usd' => 0.021, 'ms' => 4200,
      'antes' => { 'mensagens' => ai_reply[:mensagens], 'chamar_humano' => true },
      'depois' => { 'mensagens' => ['É R$ 300 com a Dra. Roberta. Prefere terça à tarde na Paulista?'], 'chamar_humano' => false } }
  end

  before do
    stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
    create(:user, account: account, role: :administrator)
  end

  def stub_ai(result)
    service = instance_double(Crm::ResponderAgentService, call: result, spent_usd: 0.0, script_version: 'v1', experiment_arm: nil)
    allow(Crm::ResponderAgentService).to receive(:new).and_return(service)
  end

  def run(message = incoming)
    described_class.perform_now(conversation.id, message.id, 'atendente_agendamento')
  end

  def events
    settings.reload.ai_config.dig('atendente_agendamento_state', 'events') || []
  end

  def notes
    conversation.messages.where(message_type: :activity, private: true)
  end

  describe 'SOMBRA' do
    it 'a nota de sombra mostra o que o principal ia fazer × o que o consultor devolveu', :aggregate_failures do
      stub_ai(ai_reply.merge(consultor: record))
      run

      note = notes.last
      expect(note.content).to include('🧑‍🏫 Consultor superior (Claude Sonnet 5 · modo sombra)', 'chamou a equipe sem urgência clínica',
                                      'não precisava chamar a equipe; em sombra, valeu a resposta do principal',
                                      'O principal (GPT-6 Luna) ia responder:', '[chamaria a equipe]',
                                      'O consultor respondeu: É R$ 300 com a Dra. Roberta')
      expect(note.additional_attributes[Crm::ConsultantConfig::NOTE_KEY]).to eq(record)
      expect(note.additional_attributes.dig('cevico_ia_shadow', 'consultor')).to eq(record)
      # a resposta registrada continua sendo a do principal
      expect(note.additional_attributes.dig('cevico_ia_shadow', 'chamar_humano')).to be(true)
      expect(events.pluck('type')).to include('sombra', 'consultor')
      expect(events.find { |event| event['type'] == 'consultor' }['note']).to include('Consultor superior')
    end

    it 'sem consulta, a nota de sombra fica exatamente como sempre foi', :aggregate_failures do
      stub_ai(ai_reply)
      run

      note = notes.last
      expect(note.content).not_to include('Consultor')
      expect(note.additional_attributes.keys).to eq(['cevico_ia_shadow'])
      expect(note.additional_attributes['cevico_ia_shadow'].keys).to match_array(
        %w[agent etapa mensagens agendar agendamento slot_valid chamar_humano cancelar pausar leitura acoes modelo reserva trigger_message_id]
      )
      expect(events.pluck('type')).not_to include('consultor')
    end

    it 'teto do dia: uma linha só no registro do card, sem nota própria', :aggregate_failures do
      stub_ai(ai_reply.merge(consultor: record.slice('gatilho', 'modo', 'modelo').merge('status' => 'teto')))
      run
      run(create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'e aí?'))

      expect(events.count { |event| event['type'] == 'consultor_teto' }).to eq(1)
      expect(notes.last.content).to include('teto de consultas do dia atingido')
    end
  end

  describe 'AO VIVO' do
    let(:agent_cfg) { { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id], 'no_card' => true } }

    it 'consultor em sombra: o paciente recebe a resposta do principal e a consulta vira nota interna', :aggregate_failures do
      stub_ai(ai_reply.merge(chamar_humano: false, consultor: record))
      run

      expect(conversation.messages.where(message_type: :outgoing).pluck(:content)).to eq(ai_reply[:mensagens])
      note = notes.find { |message| message.additional_attributes.key?(Crm::ConsultantConfig::NOTE_KEY) }
      expect(note.content).to include('🧑‍🏫 Consultor superior', 'O consultor respondeu:', 'o paciente não vê isto')
      expect(note.additional_attributes[Crm::ConsultantConfig::NOTE_KEY]).to eq(record)
      expect(events.pluck('type')).to include('respondeu', 'consultor')
    end

    it 'sem consulta não nasce nota nem linha de consultor', :aggregate_failures do
      stub_ai(ai_reply.merge(chamar_humano: false))
      run

      expect(notes.any? { |message| message.additional_attributes.key?(Crm::ConsultantConfig::NOTE_KEY) }).to be(false)
      expect(events.pluck('type')).not_to include('consultor')
    end
  end

  it 'a regra de urgência clínica é a mesma para o job e para o consultor', :aggregate_failures do
    expect(described_class.clinical_urgency?(mensagens: ['Procure um pronto atendimento agora.'], leitura: '')).to be(true)
    expect(described_class.clinical_urgency?(mensagens: ['Vou passar para a equipe.'], leitura: 'sem urgência')).to be(false)
    alta = [{ 'ferramenta' => 'abrir_tarefa', 'ok' => true, 'resumo' => 'abriria tarefa (alta): dor forte (simulado)' }]
    expect(described_class.clinical_urgency?(mensagens: [], leitura: '', acoes: alta)).to be(true)
  end
end
