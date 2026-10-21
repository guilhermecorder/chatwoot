require 'rails_helper'

# 🚫 Rodada 3 da auditoria (#45 / RESIL-7): o lembrete era dado como "enviado"
# quando a mensagem era gravada, mas a Meta responde DEPOIS — quando ela
# recusa (modelo pausado, variável vazia, número inválido), a mensagem fica
# status failed e ninguém via. Agora a rodada seguinte do cron confere:
# sai das enviadas, entra nas puladas com o erro, a marca é devolvida (o
# reforço não conta horas de uma mensagem que não chegou), a responsável
# ganha uma tarefa e NÃO reenvia sozinho — o reenvio é pelo card.
RSpec.describe Crm::AppointmentReminderSendJob do # rubocop:disable RSpec/SpecFilePathFormat
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:now) { tz.parse('2026-09-26 10:05') } # sábado; D-1 = consulta de domingo 27/09
  let(:vars) { { '1' => '{{nome_completo}}', '2' => '{{data}}', '3' => '{{hora}}' } }
  let(:tpl) { ->(name) { { 'name' => name, 'language' => 'pt_BR', 'category' => 'UTILITY', 'processed_params' => { 'body' => vars } } } }
  let(:d1_cfg) do
    { 'enabled' => true, 'hour' => 10, 'inbox_id' => inbox.id, 'mode' => 'live',
      'template_params' => tpl.call('lembrete_d1'), 'message_preview' => 'Oi {{1}}, amanhã {{2}} às {{3}}',
      'followup' => { 'enabled' => true, 'hours' => 1, 'max' => 2, 'template_params' => tpl.call('reforco_d1'),
                      'message_preview' => 'Reforço {{1}}' } }
  end
  let!(:settings) { CrmSetting.create!(account: account, agenda_config: { 'appointment_reminders' => { 'd1' => d1_cfg } }) }
  let(:maria) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990001') }
  let!(:consulta) do
    account.tasks.create!(title: 'Consulta: Maria Silva', task_type: 'consulta', modality: 'avaliacao', unit: 'paulista',
                          due_at: tz.parse('2026-09-27 09:00'), contact: maria, phone: maria.phone_number, creator: admin)
  end

  def state
    settings.reload.agenda_config.dig('appointment_reminders_state', 'd1')
  end

  def marks
    maria.reload.additional_attributes.dig('cevico_appt_reminders', consulta.id.to_s) || {}
  end

  def reminder_messages
    Message.where("additional_attributes -> 'template_params' ->> 'name' = ?", 'lembrete_d1')
  end

  def meta_refuses!(message, error = '131026: Message undeliverable')
    message.update!(status: :failed, external_error: error)
  end

  before { admin }

  it 'enviada de verdade: a lista guarda o id da mensagem e a marca fica na consulta', :aggregate_failures do
    described_class.perform_now(now)

    entry = state['sent'].first
    expect(entry).to include('task_id' => consulta.id, 'name' => 'Maria Silva')
    expect(entry['message_id']).to eq(reminder_messages.last.id)
    expect(marks['d1']).to be_present
  end

  it 'a Meta recusou: sai das enviadas, entra nas puladas com o erro, devolve a marca, avisa a responsável e não reenvia', :aggregate_failures do
    described_class.perform_now(now)
    message = reminder_messages.last
    meta_refuses!(message)

    expect { described_class.perform_now(now + 15.minutes) }.not_to change(Message.where(message_type: :outgoing), :count)

    expect(state['sent']).to be_empty
    expect(state['skipped'].map { |e| e['why'] }).to eq(['a Meta recusou: 131026: Message undeliverable — corrija e reenvie pelo card'])
    expect(state['skipped'].first).to include('task_id' => consulta.id, 'name' => 'Maria Silva')

    expect(marks['d1']).to be_nil
    expect(marks['d1_due']).to be_nil
    expect(marks.dig('d1_refused', 'error')).to eq('131026: Message undeliverable')

    tarefa = account.tasks.where(task_type: 'pos_op', contact_id: maria.id).first
    expect(tarefa).to be_present
    expect(tarefa.title).to include('Lembrete D1 não chegou')
    expect(tarefa.description).to include('131026')
    expect(tarefa.assignee).to eq(admin)
    expect(message.conversation.messages.where(message_type: :activity).last.content).to include('abriu a tarefa')

    # rodadas seguintes da mesma hora: continua pulada com o motivo, sem novo envio
    expect { described_class.perform_now(now + 30.minutes) }.not_to change(Message.where(message_type: :outgoing), :count)
    expect(state['sent']).to be_empty
    expect(state['skipped'].map { |e| e['why'] }).to eq(['a Meta recusou: 131026: Message undeliverable — corrija e reenvie pelo card'])
  end

  it 'o reforço NÃO sai de um lembrete que a Meta recusou', :aggregate_failures do
    described_class.perform_now(now)
    meta_refuses!(reminder_messages.last)
    described_class.perform_now(now + 15.minutes)

    described_class.perform_now(now + 2.hours)
    expect(Message.where("additional_attributes -> 'template_params' ->> 'name' = ?", 'reforco_d1')).to be_empty
    expect(marks['d1_f1']).to be_nil
  end

  it 'reenvio pelo card (item 320) manda de novo, limpa a nota da recusa e volta para as enviadas', :aggregate_failures do
    described_class.perform_now(now)
    meta_refuses!(reminder_messages.last)
    described_class.perform_now(now + 15.minutes)

    result = described_class.new.run_manual(account, 'd1', task_id: consulta.id, now: now + 1.hour)

    expect(result).to include(ok: true, sent: 1)
    expect(reminder_messages.count).to eq(2)
    expect(marks['d1']).to be_present
    expect(marks['d1_refused']).to be_nil
    expect(state['sent'].map { |e| e['task_id'] }).to eq([consulta.id])
    expect(state['sent'].first).to include('manual' => true)
    expect(state['sent'].first['message_id']).to eq(reminder_messages.last.id)
    expect(state['skipped']).to be_empty
  end

  it 'consulta remarcada depois da recusa é ciclo novo: recebe o lembrete de novo', :aggregate_failures do
    described_class.perform_now(now)
    meta_refuses!(reminder_messages.last)
    described_class.perform_now(now + 15.minutes)

    consulta.update!(due_at: tz.parse('2026-09-27 15:00'))
    expect { described_class.perform_now(now + 30.minutes) }.to change(reminder_messages, :count).by(1)
    expect(marks['d1']).to be_present
    expect(marks['d1_refused']).to be_nil
  end

  # revisão da Rodada 3: a conferência lê a MARCA da consulta, não a lista da
  # tela (que é cortada em 80 e trocada quando o dia vira)
  it 'recusa que chega depois de a lista da tela ter sido trocada ainda é reconciliada pela marca', :aggregate_failures do
    described_class.perform_now(now)
    expect(marks['d1_message_id']).to eq(reminder_messages.last.id)
    meta_refuses!(reminder_messages.last)

    # a lista "enviadas" sumiu (virada do dia / além do 80º): a marca continua
    settings.with_lock do
      agenda = settings.agenda_config
      agenda['appointment_reminders_state']['d1']['sent'] = []
      settings.update!(agenda_config: agenda)
    end

    described_class.perform_now(now + 15.minutes)

    expect(marks['d1']).to be_nil
    expect(marks['d1_message_id']).to be_nil
    expect(marks.dig('d1_refused', 'error')).to eq('131026: Message undeliverable')
    expect(state['skipped'].map { |e| e['task_id'] }).to eq([consulta.id])
    expect(account.tasks.where(task_type: 'pos_op', contact_id: maria.id)).to exist
  end

  # o reforço conta as horas pela marca (relógio de verdade): o teste viaja no tempo
  it 'o REFORÇO que a Meta recusou devolve a marca, aparece como recusado na lista e barra o 2º reforço', :aggregate_failures do
    travel_to(now) { described_class.perform_now(now) }
    travel_to(now + 2.hours) { described_class.perform_now(now + 2.hours) } # reforço 1 (1h depois do lembrete, dentro da janela)
    reforco = Message.where("additional_attributes -> 'template_params' ->> 'name' = ?", 'reforco_d1').last
    expect(reforco).to be_present
    expect(marks['d1_f1_message_id']).to eq(reforco.id)
    meta_refuses!(reforco, '132012: Parameter format does not match')

    expect { travel_to(now + 2.hours + 15.minutes) { described_class.perform_now(now + 2.hours + 15.minutes) } }
      .not_to change(Message.where(message_type: :outgoing), :count)

    expect(marks['d1_f1']).to be_nil
    expect(marks['d1_f1_message_id']).to be_nil
    expect(marks.dig('d1_f_refused', 'number')).to eq(1)
    expect(marks['d1']).to be_present # o lembrete em si chegou: a marca dele fica
    lista = settings.reload.agenda_config.dig('appointment_reminders_state', 'followups', 'd1')
    expect(lista.first).to include('task_id' => consulta.id, 'number' => 1)
    expect(lista.first['refused']).to eq('a Meta recusou: 132012: Parameter format does not match')
    tarefa = account.tasks.where(task_type: 'pos_op', contact_id: maria.id).first
    expect(tarefa.title).to include('Reforço 1 do lembrete D1 não chegou')

    # o 2º reforço (max 2) NÃO sai: a causa costuma ser a mesma; a equipe decide
    expect { travel_to(now + 4.hours) { described_class.perform_now(now + 4.hours) } }
      .not_to change(Message.where(message_type: :outgoing), :count)
    expect(marks['d1_f2']).to be_nil
  end

  it 'muitas recusas na mesma rodada abrem UMA tarefa resumo em vez de uma por paciente', :aggregate_failures do
    4.times do |i|
      paciente = create(:contact, account: account, name: "Paciente #{i}", phone_number: "+551199999100#{i}")
      account.tasks.create!(title: "Consulta: Paciente #{i}", task_type: 'consulta', modality: 'avaliacao', unit: 'paulista',
                            due_at: tz.parse('2026-09-27 10:00') + i.minutes, contact: paciente, phone: paciente.phone_number, creator: admin)
    end
    described_class.perform_now(now)
    expect(reminder_messages.count).to eq(5)
    reminder_messages.find_each { |m| meta_refuses!(m, '131047: Re-engagement message') }

    described_class.perform_now(now + 15.minutes)

    resumo = account.tasks.where(task_type: 'pos_op')
    expect(resumo.count).to eq(1)
    expect(resumo.first.title).to include('Lembretes recusados pela Meta')
    expect(resumo.first.description).to include('5 não chegaram', '131047', 'Maria Silva')
    expect(resumo.first.assignee).to eq(admin)
    expect(state['sent']).to be_empty
    expect(state['skipped'].size).to eq(5)
    expect(marks['d1']).to be_nil

    # recusa ISOLADA depois do resumo volta a ser tarefa por paciente (com a conversa)
    described_class.new.run_manual(account, 'd1', task_id: consulta.id, now: now + 1.hour)
    meta_refuses!(reminder_messages.last, '131047: Re-engagement message')
    described_class.perform_now(now + 75.minutes)
    expect(account.tasks.where(task_type: 'pos_op').count).to eq(2)
    expect(account.tasks.where(task_type: 'pos_op', contact_id: maria.id).first.title).to include('Lembrete D1 não chegou')
  end
end
