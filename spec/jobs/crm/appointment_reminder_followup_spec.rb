require 'rails_helper'

# 🔁 item 288 (29/09): reforço do lembrete de consulta para quem não respondeu
RSpec.describe Crm::AppointmentReminderFollowup do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:sent_at) { tz.parse('2026-09-28 10:05') } # segunda, hora do lembrete D-2
  let(:vars) { { '1' => '{{nome}}', '2' => '{{data}}', '3' => '{{hora}}' } }
  let(:tpl) { ->(name) { { 'name' => name, 'language' => 'pt_BR', 'category' => 'UTILITY', 'processed_params' => { 'body' => vars } } } }
  let(:followup) do
    { 'enabled' => true, 'hours' => 6, 'max' => 2, 'template_params' => tpl.call('reforco_confirmacao'),
      'message_preview' => 'Oi {{1}}, ainda não tivemos sua resposta' }
  end
  let(:d2_cfg) do
    { 'enabled' => true, 'hour' => 10, 'inbox_id' => inbox.id, 'mode' => 'live',
      'template_params' => tpl.call('confirmacao_consulta'), 'message_preview' => 'Confirma? {{1}}', 'followup' => followup }
  end
  let!(:settings) { CrmSetting.create!(account: account, agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg } }) }
  let(:maria) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990001') }
  let!(:task) { consulta(maria, '2026-09-30 15:00') }
  let(:sources) { [] }

  def consulta(contact, at, **extra)
    account.tasks.create!({ title: "Consulta: #{contact.name}", task_type: 'consulta', modality: 'avaliacao', unit: 'paulista',
                            due_at: tz.parse(at), contact: contact, phone: contact.phone_number, creator: admin }.merge(extra))
  end

  def run_at(time)
    time = tz.parse(time) if time.is_a?(String)
    travel_to(time) { Crm::AppointmentReminderSendJob.perform_now(time) }
  end

  def marks(contact = maria, appointment = task)
    contact.reload.additional_attributes.dig('cevico_appt_reminders', appointment.id.to_s) || {}
  end

  def sent_names
    sources.map { |s| s[3]['name'] }
  end

  def incoming_from(contact, at)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'oi, tudo bem?', created_at: at)
  end

  before do
    admin
    allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
      svc = m.call(**kw)
      allow(svc).to receive(:perform).and_return(instance_double(Conversation))
      svc
    end
    allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
      sources << args
      m.call(*args)
    end
    run_at(sent_at) # o lembrete D-2 sai às 10h05
  end

  it 'o lembrete guarda a hora da consulta; antes das 6 horas nada de reforço', :aggregate_failures do
    expect(sent_names).to eq(['confirmacao_consulta'])
    expect(Time.zone.parse(marks['d2_due']).to_i).to eq(task.due_at.to_i)
    run_at('2026-09-28 15:50')
    expect(sent_names).to eq(['confirmacao_consulta'])
    expect(marks.keys).not_to include('d2_f1')
  end

  it 'envia o reforço depois de 6 horas sem resposta, com o modelo do reforço e os dados da consulta', :aggregate_failures do
    run_at('2026-09-28 16:20')
    expect(sent_names).to eq(%w[confirmacao_consulta reforco_confirmacao])
    reforco = sources.last
    expect(reforco[1]).to eq(inbox)
    expect(reforco[3].dig('processed_params', 'body')).to eq('1' => 'Maria', '2' => '30/09/2026', '3' => '15:00') # item 323: primeiro nome
    expect(reforco[5]).to eq('Reforço 1 do lembrete de consulta (D2)')
    expect(marks['d2_f1']).to be_present

    history = settings.reload.agenda_config.dig('appointment_reminders_state', 'followups', 'd2')
    expect(history.first).to include('name' => 'Maria Silva', 'number' => 1, 'template' => 'reforco_confirmacao', 'task_id' => task.id)
    expect(settings.agenda_config.dig('appointment_reminders_state', 'd2', 'sent')).to be_present # a última rodada continua lá
  end

  it 'nunca manda o mesmo reforço duas vezes; o 2º só sai 6 horas depois do 1º, e para no máximo configurado', :aggregate_failures do
    run_at('2026-09-28 16:20')
    run_at('2026-09-28 16:35')
    run_at('2026-09-28 19:50')
    expect(sent_names.count('reforco_confirmacao')).to eq(1)

    run_at('2026-09-29 08:05') # 6 h depois do 1º cairia 22h20 → sai na manhã seguinte
    expect(sent_names.count('reforco_confirmacao')).to eq(2)
    expect(marks.keys).to include('d2_f1', 'd2_f2')

    run_at('2026-09-29 14:30')
    run_at('2026-09-29 19:30')
    expect(sent_names.count('reforco_confirmacao')).to eq(2)
  end

  it 'com máximo 1, não existe 2º reforço' do
    settings.update!(agenda_config: settings.agenda_config.deep_merge('appointment_reminders' => { 'd2' => { 'followup' => { 'max' => 1 } } }))
    run_at('2026-09-28 16:20')
    run_at('2026-09-29 08:05')
    expect(sent_names.count('reforco_confirmacao')).to eq(1)
  end

  it 'duas rodadas ao mesmo tempo: quem chega depois encontra a marca e não envia' do
    job = Crm::AppointmentReminderSendJob.new
    travel_to(tz.parse('2026-09-28 16:20')) do
      now = tz.parse('2026-09-28 16:20')
      expect(job.send(:claim_followup!, maria, task, 'd2', 1, now)).to be(true)
      expect(job.send(:claim_followup!, Contact.find(maria.id), task, 'd2', 1, now)).to be(false)
      Crm::AppointmentReminderSendJob.perform_now(now)
    end
    expect(sent_names).to eq(['confirmacao_consulta'])
  end

  it 'a marca do reforço não apaga outras chaves do contato (gravação atômica)', :aggregate_failures do
    stale = Contact.find(maria.id) # cópia antiga em memória
    Cevico::AttributeMerge.merge!(Contact.find(maria.id)) { |attrs| attrs.merge('outra_chave' => 'fica') }
    job = Crm::AppointmentReminderSendJob.new
    expect(job.send(:claim_followup!, stale, task, 'd2', 1, tz.parse('2026-09-28 16:20'))).to be(true)
    attrs = maria.reload.additional_attributes
    expect(attrs['outra_chave']).to eq('fica')
    expect(attrs.dig('cevico_appt_reminders', task.id.to_s).keys).to include('d2', 'd2_due', 'd2_f1')
  end

  it 'não envia se o paciente respondeu qualquer coisa depois do lembrete' do
    incoming_from(maria, tz.parse('2026-09-28 11:00'))
    run_at('2026-09-28 16:20')
    expect(sent_names).to eq(['confirmacao_consulta'])
  end

  it 'mensagem ANTIGA do paciente (antes do lembrete) não conta como resposta' do
    incoming_from(maria, tz.parse('2026-09-27 09:00'))
    run_at('2026-09-28 16:20')
    expect(sent_names).to eq(%w[confirmacao_consulta reforco_confirmacao])
  end

  it 'não envia se a consulta foi confirmada, recusada, cancelada ou remarcada', :aggregate_failures do
    joao = create(:contact, account: account, name: 'João', phone_number: '+5511999990002')
    ana = create(:contact, account: account, name: 'Ana', phone_number: '+5511999990003')
    bia = create(:contact, account: account, name: 'Bia', phone_number: '+5511999990004')
    outras = [consulta(joao, '2026-09-30 09:00'), consulta(ana, '2026-09-30 10:00'), consulta(bia, '2026-09-30 11:00')]
    sources.clear
    run_at(sent_at + 10.minutes) # os 3 recebem o lembrete
    expect(sent_names.size).to eq(3)

    task.update!(confirmed_at: Time.current)
    outras[0].update!(declined_at: Time.current)
    outras[1].update!(canceled_at: Time.current)
    outras[2].update!(due_at: tz.parse('2026-10-01 11:00'), rescheduled_count: 1)
    sources.clear
    run_at('2026-09-28 16:30')
    expect(sent_names).to be_empty
  end

  it 'respeita 07h–20h: vencido à noite, só sai às 07h do dia seguinte', :aggregate_failures do
    settings.update!(agenda_config: settings.agenda_config.deep_merge('appointment_reminders' => { 'd2' => { 'followup' => { 'hours' => 11 } } }))
    run_at('2026-09-28 21:10') # venceu 21h05
    run_at('2026-09-29 02:00')
    run_at('2026-09-29 06:50')
    expect(sent_names).to eq(['confirmacao_consulta'])
    run_at('2026-09-29 07:05')
    expect(sent_names).to eq(%w[confirmacao_consulta reforco_confirmacao])
  end

  it 'nunca depois do horário da consulta' do
    task.update_columns(due_at: tz.parse('2026-09-28 16:00')) # rubocop:disable Rails/SkipsModelValidations
    Cevico::AttributeMerge.merge!(maria) do |attrs|
      attrs.deep_merge('cevico_appt_reminders' => { task.id.to_s => { 'd2_due' => task.due_at.iso8601 } })
    end
    run_at('2026-09-28 16:20')
    expect(sent_names).to eq(['confirmacao_consulta'])
  end

  it 'reforço vencido há mais de um dia não sai (ligar hoje não dispara os antigos)' do
    run_at('2026-09-29 16:30') # venceu 28/09 16h05
    expect(sent_names).to eq(['confirmacao_consulta'])
  end

  it 'DESLIGADO por padrão: sem o bloco do reforço, ou com ele desligado, nada sai', :aggregate_failures do
    settings.update!(agenda_config: settings.agenda_config.merge('appointment_reminders' => { 'd2' => d2_cfg.except('followup') }))
    run_at('2026-09-28 16:20')
    settings.update!(agenda_config: settings.agenda_config.merge(
      'appointment_reminders' => { 'd2' => d2_cfg.merge('followup' => followup.merge('enabled' => false)) }
    ))
    run_at('2026-09-28 16:35')
    expect(sent_names).to eq(['confirmacao_consulta'])
  end

  it 'lembrete em sombra, lembrete desligado ou interruptor geral desligado: sem reforço', :aggregate_failures do
    settings.update!(agenda_config: settings.agenda_config.merge('appointment_reminders' => { 'd2' => d2_cfg.merge('mode' => 'shadow') }))
    run_at('2026-09-28 16:20')
    settings.update!(agenda_config: settings.agenda_config.merge('appointment_reminders' => { 'd2' => d2_cfg.merge('enabled' => false) }))
    run_at('2026-09-28 16:35')
    settings.update!(agenda_config: settings.agenda_config.merge('appointment_reminders' => { 'd2' => d2_cfg },
                                                                 'appointment_confirmation' => { 'enabled' => false }))
    run_at('2026-09-28 16:50')
    expect(sent_names).to eq(['confirmacao_consulta'])
  end

  it 'se o envio nem saiu (sem conversa), a marca é devolvida para tentar na próxima rodada', :aggregate_failures do
    allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
      svc = m.call(**kw)
      allow(svc).to receive(:perform).and_return(nil)
      svc
    end
    run_at('2026-09-28 16:20')
    expect(marks.keys).not_to include('d2_f1')
    expect(settings.reload.agenda_config.dig('appointment_reminders_state', 'followups')).to be_nil
  end

  describe 'pacientes do Oftalmofácil (mesma regra do lembrete)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:of_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
    let(:parceiro) { create(:contact, account: account, name: 'Paciente Parceiro', phone_number: '+5511999990051') }
    let(:partner_cfg) do
      { 'enabled' => true, 'inbox_id' => of_inbox.id, 'template_params' => tpl.call('confirmacao_oftalmofacil'), 'message_preview' => 'Olá {{1}}' }
    end
    let(:partner_followup) { { 'template_params' => tpl.call('reforco_oftalmofacil'), 'message_preview' => 'Oi {{1}}' } }

    def prepare(cfg)
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => cfg } })
      task.update!(confirmed_at: Time.current) # tira a Maria da conta
      consulta(parceiro, '2026-09-30 10:00', source: 'oftalmofacil', source_detail: 'CLINICA X', external_ref: 'p51')
      sources.clear
      run_at(sent_at + 10.minutes)
    end

    it 'ligado: o reforço sai pela caixa deles, com o modelo de reforço deles', :aggregate_failures do
      prepare(d2_cfg.merge('partner' => partner_cfg, 'followup' => followup.merge('partner' => partner_followup)))
      expect(sent_names).to eq(['confirmacao_oftalmofacil'])
      run_at('2026-09-28 16:30')
      expect(sent_names).to eq(%w[confirmacao_oftalmofacil reforco_oftalmofacil])
      expect(sources.last[1]).to eq(of_inbox)
    end

    it 'sem modelo de reforço próprio, o parceiro não recebe (nunca o modelo da CEVICO)' do
      prepare(d2_cfg.merge('partner' => partner_cfg))
      run_at('2026-09-28 16:30')
      expect(sent_names).to eq(['confirmacao_oftalmofacil'])
    end

    it 'bloco do Oftalmofácil desligado depois do lembrete: a cerca segura o reforço' do
      prepare(d2_cfg.merge('partner' => partner_cfg, 'followup' => followup.merge('partner' => partner_followup)))
      settings.update!(agenda_config: settings.agenda_config.deep_merge(
        'appointment_reminders' => { 'd2' => { 'partner' => { 'enabled' => false } } }
      ))
      run_at('2026-09-28 16:30')
      expect(sent_names).to eq(['confirmacao_oftalmofacil'])
    end
  end
end
