require 'rails_helper'

# 🚫 Rodada 3 da auditoria (#45): pesquisa de satisfação que a Meta recusou
# deixa de contar como enviada — a marca é devolvida (a pessoa não fica "com
# pesquisa recente", nenhum lembrete sai de uma pesquisa que não chegou), a
# cirurgia aparece nas puladas com o erro e NÃO é reenviada sozinha.
RSpec.describe Crm::NpsSurvey do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:tz) { described_class::TZ }
  let(:now) { tz.parse('2026-09-26 10:05') }
  let(:tpl) do
    { 'name' => 'pesquisa_nps', 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => { 'body' => { '1' => '{{nome}}' } } }
  end
  let(:reminder_tpl) { tpl.merge('name' => 'pesquisa_nps_lembrete') }
  let(:cfg) do
    { 'enabled' => true, 'mode' => 'live', 'hour' => 10, 'inbox_id' => inbox.id, 'template_params' => tpl, 'message_preview' => 'Oi {{1}}',
      'catch_up_days' => 3,
      'reminder' => { 'enabled' => true, 'hours' => 1, 'template_params' => reminder_tpl, 'message_preview' => 'Lembrete {{1}}' } }
  end
  let!(:settings) { CrmSetting.create!(account: account, agenda_config: { 'nps_survey' => cfg }) }
  let(:ana) { create(:contact, account: account, name: 'Ana Catarata', phone_number: '+5511911110001') }
  let!(:cirurgia) do
    account.tasks.create!(title: 'Cirurgia: Ana', task_type: 'cirurgia', procedure: 'Facoemulsificação', contact: ana, creator: admin,
                          due_at: tz.parse("#{now.to_date - 15} 09:00"), attendance: 'attended', status: :done)
  end

  def mark
    ana.reload.additional_attributes[described_class::MARK_KEY] || {}
  end

  def state
    settings.reload.agenda_config['nps_survey_state']
  end

  def surveys
    Message.where("additional_attributes -> 'template_params' ->> 'name' = ?", 'pesquisa_nps')
  end

  it 'enviada de verdade: a marca guarda o id da mensagem', :aggregate_failures do
    described_class.run_all(now)
    expect(surveys.count).to eq(1)
    expect(mark['message_id']).to eq(surveys.last.id)
    expect(mark['pending_at']).to be_present
    expect(state['sent'].first['message_id']).to eq(surveys.last.id)
  end

  # o lembrete compara pending_at com o relógio de verdade: o teste viaja no tempo
  it 'a Meta recusou: devolve a marca, lista nas puladas com o erro, não manda lembrete e não reenvia sozinha', :aggregate_failures do
    travel_to(now) { described_class.run_all(now) }
    surveys.last.update!(status: :failed, external_error: '131047: Re-engagement message')

    # rodada seguinte (mesma hora): confere a recusa ANTES de rodar
    expect { travel_to(now + 15.minutes) { described_class.run_all(now + 15.minutes) } }
      .not_to change(Message.where(message_type: :outgoing), :count)

    expect(mark['pending_at']).to be_nil
    expect(mark['message_id']).to be_nil
    expect(mark['task_ids']).not_to include(cirurgia.id)
    expect(mark['refused']).to include('task_id' => cirurgia.id, 'error' => '131047: Re-engagement message')
    expect(described_class.recent?(ana)).to be(false)

    expect(state['sent']).to be_empty
    expect(state['skipped'].map { |e| e['why'] }).to eq(['a Meta recusou (131047: Re-engagement message)'])

    # horas depois: nem o lembrete da pesquisa (não há pesquisa pendente) nem uma nova pesquisa
    expect { travel_to(now + 2.hours) { described_class.run_all(now + 2.hours) } }
      .not_to change(Message.where(message_type: :outgoing), :count)
    expect(mark['reminded_at']).to be_nil
  end

  it 'lembrete da pesquisa recusado pela Meta: fica a nota e ele não se repete', :aggregate_failures do
    travel_to(now) { described_class.run_all(now) }
    travel_to(now + 2.hours) { described_class.run_all(now + 2.hours) } # lembrete de quem não respondeu
    lembrete = Message.where("additional_attributes -> 'template_params' ->> 'name' = ?", 'pesquisa_nps_lembrete').last
    expect(lembrete).to be_present
    expect(mark['reminder_message_id']).to eq(lembrete.id)

    lembrete.update!(status: :failed, external_error: '131026: Message undeliverable')
    expect { travel_to(now + 3.hours) { described_class.run_all(now + 3.hours) } }
      .not_to change(Message.where(message_type: :outgoing), :count)

    expect(mark['reminder_refused']).to eq('131026: Message undeliverable')
    expect(mark['reminder_message_id']).to be_nil
    expect(mark['pending_at']).to be_present # a pesquisa em si chegou: continua aguardando a nota
    expect(state['reminders']).to be_empty
    expect(state['skipped'].map { |e| e['why'] }).to include('a Meta recusou: 131026: Message undeliverable')
  end
end
