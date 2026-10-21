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

  # ── item 333 ────────────────────────────────────────────────────────────
  def future_task(when_at = 3.days.from_now.change(hour: 10), attrs = {})
    account.tasks.create!({ title: 'Consulta: Maria Silva', task_type: 'consulta', due_at: when_at, status: :todo, unit: 'tatuape',
                            contact: contact, phone: "+#{phone}", creator: account.administrators.first }.merge(attrs))
  end

  it 'enviar_whatsapp sai pela caixa em que o paciente JÁ conversa (regra 2), não pela da assistente', :aggregate_failures do
    other_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                              validate_provider_config: false)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: other_channel.inbox, source_id: phone)
    talk = create(:conversation, account: account, inbox: other_channel.inbox, contact: contact, contact_inbox: contact_inbox,
                                 last_activity_at: 1.minute.from_now)
    create(:message, account: account, inbox: other_channel.inbox, conversation: talk, message_type: :incoming, content: 'oi')
    talk.update_column(:last_activity_at, 1.hour.from_now) # rubocop:disable Rails/SkipsModelValidations

    result = run('enviar_whatsapp', 'tipo' => 'continuar')

    expect(result).to eq({ ok: true, motivo: 'enviado' })
    sent = talk.messages.where(message_type: :outgoing).last
    expect(sent.content).to include('vamos continuar por aqui')
  end

  it 'confirmar_presenca "confirmou" grava na consulta e marca o lembrete — o mesmo caminho do SIM do WhatsApp', :aggregate_failures do
    task = future_task

    result = run('confirmar_presenca', 'resposta' => 'confirmou')

    expect(result[:ok]).to be(true)
    expect(result[:resultado]).to eq('confirmada')
    expect(task.reload.confirmed_at).to be_present
    expect(contact.reload.additional_attributes.dig('cevico_appt_reminders', task.id.to_s, 'confirmed')).to be_present
  end

  it 'confirmar_presenca "nao_vai" não cancela: marca, etiqueta e avisa a equipe no Meu Painel', :aggregate_failures do
    task = future_task

    result = run('confirmar_presenca', 'resposta' => 'nao_vai')

    expect(result[:resultado]).to eq('equipe_avisada')
    task.reload
    expect(task.declined_at).to be_present
    expect(task.canceled_at).to be_nil
    expect(contact.reload.label_list).to include('confirmar_urgente')
    alert = CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts').last
    expect(alert['kind']).to eq('nao_confirmou')
    expect(alert['motivo']).to include('disse na ligação')
  end

  it 'marcar_consulta para OUTRA pessoa cria consulta nova e não mexe na de quem ligou', :aggregate_failures do
    stub_slot_lock
    mine = future_task
    slot = Crm::AgendaSlots.free_slots(account, days: 10).find { |s| s[:date] != mine.due_at.to_date }

    result = run('marcar_consulta', 'nome' => 'Ana Souza', 'data' => slot[:date].to_s, 'hora' => slot[:time], 'unidade' => slot[:unit],
                                    'para_outra_pessoa' => 'sim')

    expect(result[:resultado]).to eq('marcada')
    expect(mine.reload.due_at).to eq(mine.due_at) # a dela continua onde estava
    other = account.tasks.find_by(title: 'Consulta: Ana Souza')
    expect(other).to be_present
    expect(other.id).not_to eq(mine.id)
    expect(other.phone).to eq("+#{phone}") # o lembrete dela chega no WhatsApp de quem marcou
  end

  it 'marcar_consulta para o próprio paciente move o card para a coluna de agendamento', :aggregate_failures do
    stub_slot_lock
    pipeline = Crm::Pipeline.create!(account: account, name: 'CEVICO')
    entry = Crm::Stage.create!(pipeline: pipeline, name: 'Novos Contatos', position: 0)
    booked = Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 1)
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: entry.id)
    CrmSetting.find_by(account: account).update!(agenda_config: { 'booking' => { 'stage_id' => booked.id } })
    slot = Crm::AgendaSlots.free_slots(account, days: 10).first

    run('marcar_consulta', 'nome' => 'Maria Silva', 'data' => slot[:date].to_s, 'hora' => slot[:time], 'unidade' => slot[:unit])

    expect(Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id).stage_id).to eq(booked.id)
    expect(contact.reload.label_list).to include('consulta_agendada')
  end

  it 'chamar_equipe abre tarefa urgente de verdade (com aviso no Meu Painel) — nada de "a equipe foi avisada" vazio', :aggregate_failures do
    result = run('chamar_equipe', 'motivo' => 'dor forte no olho operado', 'urgencia' => 'alta', 'detalhes' => 'Operou há 3 dias.')

    expect(result[:ok]).to be(true)
    task = account.tasks.find(result[:tarefa])
    expect(task.title).to start_with('🔴 Ligação · Maria Silva')
    expect(task.priority).to eq('urgent')
    expect(task.description).to include('Operou há 3 dias.')
    alert = CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts').last
    expect(alert['kind']).to eq('pos_op_atencao')
  end

  it 'cerca dos parceiros: paciente de clínica parceira não recebe nenhuma ferramenta (só o registro do resultado)', :aggregate_failures do
    contact.add_labels(['of_clinica_x'])
    future_task

    %w[buscar_paciente horarios_livres minha_consulta enviar_whatsapp confirmar_presenca chamar_equipe].each do |tool|
      result = run(tool, 'tipo' => 'continuar', 'resposta' => 'confirmou', 'motivo' => 'x', 'urgencia' => 'normal')
      expect(result).to eq({ ok: false, erro: described_class::PARTNER_REFUSAL }), tool
    end
    expect(run('registrar_resultado', 'resultado' => 'outro', 'resumo' => 'parceiro')[:ok]).to be(true)
    expect(account.tasks.where(task_type: 'consulta').last.confirmed_at).to be_nil
  end
end
