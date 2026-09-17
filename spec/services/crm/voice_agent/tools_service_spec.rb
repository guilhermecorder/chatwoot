require 'rails_helper'

RSpec.describe Crm::VoiceAgent::ToolsService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:phone) { '5511999990000' }
  let!(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: "+#{phone}") }
  let(:conversation_id) { 'conv_abc' }

  before do
    # o Crm::AppointmentRecorder cria a consulta em nome do 1º admin da conta
    create(:user, account: account, role: :administrator)
    CrmSetting.create!(account: account, ai_config: { 'voice' => { 'enabled' => true, 'handoff_inbox_id' => inbox.id, 'tools_token' => 'x' } })
  end

  # sem Redis nos testes: a trava do horário sempre "abre"
  def stub_slot_lock
    allow(Redis::LockManager).to receive(:new).and_return(instance_double(Redis::LockManager, lock: true, unlock: true))
  end

  def run(tool, params = {})
    described_class.new(account: account, tool: tool, params: params.merge('telefone' => phone), conversation_id: conversation_id).perform
  end

  it 'buscar_paciente acha o paciente pelo telefone e grava a ligação da IA', :aggregate_failures do
    result = run('buscar_paciente')

    expect(result[:encontrado]).to be(true)
    expect(result[:primeiro_nome]).to eq('Maria')
    call = Crm::Call.find_by(account: account, provider_call_id: conversation_id)
    expect(call).to be_present
    expect(call.handled_by).to eq('ai')
    expect(call.meta_call_id).to eq("el:#{conversation_id}")
    expect(call).to be_accepted
    expect(call.contact).to eq(contact)
    expect(call.conversation.inbox_id).to eq(inbox.id)
  end

  it 'horarios_livres devolve no máximo 6 horários com o texto falado' do
    result = run('horarios_livres', 'dias' => 10)

    expect(result[:horarios].size).to be_between(1, 6)
    slot = result[:horarios].first
    expect(slot).to include(:data, :dia, :hora, :unidade, :medico, :falado)
    expect(slot[:falado]).to include('feira')
    expect(slot[:falado]).not_to match(/\d{2}:\d{2}/)
  end

  it 'marcar_consulta cria a consulta na Agenda e devolve "marcada"' do
    stub_slot_lock
    slot = Crm::AgendaSlots.free_slots(account, days: 10).first

    result = run('marcar_consulta', 'nome' => 'Maria Silva', 'data' => slot[:date].to_s, 'hora' => slot[:time],
                                    'unidade' => slot[:unit], 'procedimento' => 'consulta de avaliação')

    expect(result[:ok]).to be(true)
    expect(result[:resultado]).to eq('marcada')
    task = account.tasks.find_by(task_type: 'consulta', title: 'Consulta: Maria Silva')
    expect(task).to be_present
    expect(task.unit).to eq(slot[:unit])
    expect(task.contact).to eq(contact)
    expect(run('minha_consulta')[:encontrada]).to be(true)
  end

  it 'marcar_consulta recusa horário fora da agenda' do
    stub_slot_lock

    result = run('marcar_consulta', 'nome' => 'Maria', 'data' => (Date.current + 3).to_s, 'hora' => '03:00', 'unidade' => 'tatuape')

    expect(result[:ok]).to be(false)
    expect(result[:resultado]).to eq('horario_indisponivel')
  end

  it 'registrar_resultado grava resultado e resumo na ligação' do
    result = run('registrar_resultado', 'resultado' => 'quer_whatsapp', 'resumo' => 'Prefere seguir por escrito.')

    expect(result[:ok]).to be(true)
    call = Crm::Call.find_by(account: account, provider_call_id: conversation_id)
    expect(call.outcome).to eq('quer_whatsapp')
    expect(call.summary).to eq('Prefere seguir por escrito.')
  end

  it 'enviar_whatsapp avisa quando a caixa não está configurada' do
    CrmSetting.find_by(account: account).update!(ai_config: { 'voice' => { 'enabled' => true } })

    expect(run('enviar_whatsapp', 'tipo' => 'continuar')).to eq({ ok: false, motivo: 'caixa não configurada' })
  end
end
