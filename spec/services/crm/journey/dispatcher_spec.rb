require 'rails_helper'

# 🛡️ auditoria 10/10 (#426): o planejador olha a consulta/cirurgia só na hora
# de PLANEJAR; o despachante precisa olhar de novo na hora de MANDAR — consulta
# cancelada/remarcada ou cirurgia que saiu de "agendada" não recebe a mensagem.
RSpec.describe Crm::Journey::Dispatcher do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tz) { Crm::Journey::Settings::TZ }
  let(:now) { tz.local(2026, 9, 18, 10, 5) } # sexta
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:template_params) do
    { 'name' => 'consulta_hoje', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'processed_params' => { 'body' => { '1' => '{{primeiro_nome}}', '2' => '{{data}}', '3' => '{{hora}}' } } }
  end
  let(:content) { { 'mode' => 'template', 'template_params' => template_params, 'message_preview' => 'Olá {{1}}, sua consulta é {{2}} às {{3}}.' } }
  let(:templates) { [] }

  def create_message(kind:, offset:, at: '10:00', extra: {})
    Crm::JourneyMessage.create!(account: account, name: "Mensagem #{kind} #{offset}", step: 'consulta', inbox: inbox,
                                trigger: { 'kind' => kind, 'offset_days' => offset, 'at' => at }.merge(extra), content: content)
  end

  def create_task(due_at:)
    account.tasks.create!(task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                          title: 'Consulta: Maria', due_at: due_at, contact: contact)
  end

  def plan!(at = now)
    Crm::Journey::Planner.new(account: account, now: at).perform
    Crm::JourneySend.order(:id).last
  end

  def dispatch!(at = now)
    described_class.new(account: account, now: at).perform
  end

  before do
    CrmSetting.create!(account: account, agenda_config: {})
    allow(Crm::SendTemplateService).to receive(:new) do |source:, contact: nil| # rubocop:disable Lint/UnusedBlockArgument
      templates << source.template_params['name']
      instance_double(Crm::SendTemplateService, perform: conversation, message: nil)
    end
  end

  describe 'consulta da Agenda (kind appointment, no dia)' do
    let!(:message) { create_message(kind: 'appointment', offset: 0) }
    let!(:task) { create_task(due_at: tz.local(2026, 9, 18, 15, 0)) }

    it 'manda quando a consulta continua de pé (controle)', :aggregate_failures do
      send = plan!
      dispatch!
      expect(send.reload.status).to eq('sent')
      expect(templates).to eq(['consulta_hoje'])
    end

    it 'NÃO manda se a consulta foi para a Lixeira depois do planejamento', :aggregate_failures do
      send = plan!
      task.to_trash!(by: admin)
      dispatch!
      expect(send.reload.status).to eq('skipped')
      expect(send.error).to eq('A consulta foi cancelada')
      expect(templates).to be_empty
    end

    it 'NÃO manda se o paciente já avisou que não vem', :aggregate_failures do
      send = plan!
      task.update!(declined_at: Time.current)
      dispatch!
      expect(send.reload.status).to eq('skipped')
      expect(send.error).to eq('O paciente já avisou que não vem')
      expect(templates).to be_empty
    end

    it 'NÃO manda se a consulta foi remarcada para outro dia (a do novo dia nasce sozinha)', :aggregate_failures do
      send = plan!
      task.update!(due_at: tz.local(2026, 9, 22, 15, 0))
      dispatch!
      expect(send.reload.status).to eq('skipped')
      expect(send.error).to eq('A consulta foi remarcada para outro dia')
      expect(templates).to be_empty
    end

    it 'NÃO manda se a consulta sumiu de vez', :aggregate_failures do
      send = plan!
      send.update!(source_id: nil, source_type: nil)
      dispatch!
      expect(send.reload.status).to eq('skipped')
      expect(send.error).to eq('A consulta ou cirurgia deste envio não existe mais')
      expect(templates).to be_empty
    end

    it 'NÃO manda "sua consulta é hoje" depois do horário da consulta (ex.: aprovação tardia)', :aggregate_failures do
      message.update!(approval: 'review')
      send = plan!
      expect(send.status).to eq('pending_review')
      outcome = described_class.new(account: account, now: tz.local(2026, 9, 18, 16, 0)).dispatch(send)
      expect(outcome).to eq(:skipped)
      expect(send.reload.error).to start_with('O horário da consulta já passou')
      expect(templates).to be_empty
    end

    it 'envio de teste ("Testar no meu número") sai mesmo sem consulta ligada ou com consulta de outro dia', :aggregate_failures do
      sem_consulta = Crm::JourneySend.create!(account: account, journey_message: message, contact: contact, source: nil,
                                              event_key: 'teste:abcd1234', scheduled_for: now, status: 'queued')
      expect(described_class.new(account: account, now: now).dispatch(sem_consulta)).to eq(:sent)

      outro_dia = Crm::JourneySend.create!(account: account, journey_message: message, contact: contact,
                                           source: create_task(due_at: tz.local(2026, 9, 21, 15, 0)),
                                           event_key: 'teste:ef567890', scheduled_for: now, status: 'queued')
      expect(described_class.new(account: account, now: now).dispatch(outro_dia)).to eq(:sent)
      expect(templates).to eq(%w[consulta_hoje consulta_hoje])
    end

    it 'consulta arquivada é pulada com o motivo certo', :aggregate_failures do
      send = plan!
      task.update!(archived_at: Time.current)
      dispatch!
      expect(send.reload.status).to eq('skipped')
      expect(send.error).to eq('A consulta foi arquivada')
    end

    it 'consulta confirmada continua recebendo a mensagem do dia' do
      send = plan!
      task.update!(confirmed_at: Time.current)
      dispatch!
      expect(send.reload.status).to eq('sent')
    end
  end

  describe 'mensagem DEPOIS da consulta (offset positivo)' do
    let!(:task) { create_task(due_at: tz.local(2026, 9, 15, 15, 0)) }

    before { create_message(kind: 'appointment', offset: 3) }

    it 'sai normalmente mesmo com a consulta já passada, mas não para consulta cancelada', :aggregate_failures do
      send = plan!
      dispatch!
      expect(send.reload.status).to eq('sent')

      task.to_trash!(by: admin)
      send.update!(status: 'queued')
      dispatch!
      expect(send.reload.status).to eq('skipped')
      expect(templates).to eq(['consulta_hoje'])
    end
  end

  describe 'cirurgia do hub (kind surgery, véspera)' do
    let!(:surgery) do
      Crm::OftalmofacilSurgery.create!(account: account, contact: contact, item_token: 'tok1', patient_name: 'Maria Teste',
                                       surgery_date: Date.new(2026, 9, 19), surgery_hour: '08:30', status_kind: 'agendada',
                                       procedure_name: 'Catarata', clinic_name: 'IOP', raw: {})
    end

    before { create_message(kind: 'surgery', offset: -1) }

    it 'NÃO manda se a cirurgia deixou de estar agendada', :aggregate_failures do
      send = plan!
      surgery.update!(status_kind: 'cancelada')
      dispatch!
      expect(send.reload.status).to eq('skipped')
      expect(send.error).to eq('A cirurgia não está mais agendada')
      expect(templates).to be_empty
    end

    it 'NÃO manda se a cirurgia mudou de dia', :aggregate_failures do
      send = plan!
      surgery.update!(surgery_date: Date.new(2026, 9, 26))
      dispatch!
      expect(send.reload.status).to eq('skipped')
      expect(send.error).to eq('A cirurgia foi remarcada para outro dia')
      expect(templates).to be_empty
    end

    it 'manda quando a cirurgia continua agendada no dia (controle)' do
      send = plan!
      dispatch!
      expect(send.reload.status).to eq('sent')
    end
  end

  describe '#retry_blocker (o "Reenviar" da tela)' do
    let!(:task) { create_task(due_at: tz.local(2026, 9, 18, 15, 0)) }

    before { create_message(kind: 'appointment', offset: 0) }

    it 'recusa envio planejado para um dia que já passou, aceita o de hoje e repete as checagens do evento', :aggregate_failures do
      send = plan!
      send.update!(status: 'expired')
      ontem = described_class.new(account: account, now: tz.local(2026, 9, 19, 9, 0))
      expect(ontem.retry_blocker(send)).to eq('Esta mensagem era para 18/09 e o dia já passou')

      hoje = described_class.new(account: account, now: tz.local(2026, 9, 18, 11, 0))
      expect(hoje.retry_blocker(send)).to be_nil

      task.to_trash!(by: admin)
      expect(hoje.retry_blocker(send.reload)).to eq('A consulta foi cancelada')
    end

    it 'mensagem da véspera (offset -1) reenviada no dia da consulta é recusada na porta, com o motivo certo' do
      vespera = create_message(kind: 'appointment', offset: -1, at: '09:00')
      send = Crm::JourneySend.create!(account: account, journey_message: vespera, contact: contact, source: task,
                                      event_key: "task:#{task.id}", scheduled_for: tz.local(2026, 9, 17, 9, 0), status: 'expired')
      no_dia = described_class.new(account: account, now: tz.local(2026, 9, 18, 10, 0))
      expect(no_dia.retry_blocker(send)).to eq('Esta mensagem era para 17/09 e o dia já passou')
    end

    it 'mensagem de DEPOIS da consulta (offset +3) pode ser reenviada no mesmo dia, mas não no dia seguinte', :aggregate_failures do
      depois = create_message(kind: 'appointment', offset: 3)
      antiga = create_task(due_at: tz.local(2026, 9, 15, 15, 0))
      send = Crm::JourneySend.create!(account: account, journey_message: depois, contact: contact, source: antiga,
                                      event_key: "task:#{antiga.id}", scheduled_for: tz.local(2026, 9, 18, 10, 0), status: 'failed')
      mesmo_dia = described_class.new(account: account, now: tz.local(2026, 9, 18, 11, 0))
      expect(mesmo_dia.retry_blocker(send)).to be_nil

      dia_seguinte = described_class.new(account: account, now: tz.local(2026, 9, 19, 11, 0))
      expect(dia_seguinte.retry_blocker(send)).to eq('Esta mensagem era para 18/09 e o dia já passou')
    end

    it 'não barra envio de teste ("Testar no meu número") sem consulta ligada' do
      msg = Crm::JourneyMessage.find_by!(name: 'Mensagem appointment 0')
      send = Crm::JourneySend.create!(account: account, journey_message: msg, contact: contact, source: nil,
                                      event_key: 'teste:11112222', scheduled_for: now - 1.day, status: 'failed')
      expect(described_class.new(account: account, now: now).retry_blocker(send)).to be_nil
    end

    it 'não barra mensagem de coluna/etiqueta (sem data de evento)' do
      label_msg = create_message(kind: 'label', offset: 0, extra: { 'label' => 'vip' })
      send = Crm::JourneySend.create!(account: account, journey_message: label_msg, contact: contact, event_key: 'label:1',
                                      scheduled_for: now - 2.days, status: 'failed')
      expect(described_class.new(account: account, now: now).retry_blocker(send)).to be_nil
    end
  end
end
