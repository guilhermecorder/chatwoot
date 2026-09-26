require 'rails_helper'

# 📋 item 250 (26/09): régua D-2 — confirmação completa da consulta pela NOSSA Agenda
RSpec.describe Crm::AppointmentReminderSendJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:now) { tz.parse('2026-09-26 10:05') } # sábado
  let(:vars) { { '1' => '{{nome}}', '2' => '{{data}}', '3' => '{{hora}}', '4' => '{{valor}}' } }
  let(:tpl) { ->(name) { { 'name' => name, 'language' => 'en', 'category' => 'UTILITY', 'processed_params' => { 'body' => vars } } } }
  let(:d2_cfg) do
    { 'enabled' => true, 'hour' => 10, 'inbox_id' => inbox.id, 'mode' => 'live', 'default_value' => '150,00',
      'units' => { 'paulista' => { 'template_params' => tpl.call('confirmacao_consulta_paulista'), 'message_preview' => 'Paulista {{1}}' },
                   'tatuape' => { 'template_params' => tpl.call('confirmao_consulta_tatuape'), 'message_preview' => 'Tatuapé {{1}}' } } }
  end
  let!(:settings) { CrmSetting.create!(account: account, agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg } }) }

  def contact_named(name, phone)
    create(:contact, account: account, name: name, phone_number: phone)
  end

  def consulta(contact, at, unit: 'paulista', **extra)
    account.tasks.create!({ title: "Consulta: #{contact.name}", task_type: 'consulta', modality: 'avaliacao', unit: unit,
                            due_at: tz.parse(at), contact: contact, phone: contact.phone_number, creator: admin }.merge(extra))
  end

  before do
    admin
    allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
      svc = m.call(**kw)
      allow(svc).to receive(:perform).and_return(instance_double(Conversation))
      svc
    end
  end

  it 'dN = hoje + N; com a ponte ligada, na sexta o de 1–2 dias antes adianta a segunda', :aggregate_failures do
    friday = tz.parse('2026-09-25 10:00')
    bridge = { 'weekend_bridge' => true }
    expect(described_class.target_dates('d2', bridge, friday)).to eq([Date.new(2026, 9, 27), Date.new(2026, 9, 28)])
    expect(described_class.target_dates('d1', bridge, friday)).to eq([Date.new(2026, 9, 26), Date.new(2026, 9, 28)])
    expect(described_class.target_dates('d2', {}, friday)).to eq([Date.new(2026, 9, 27)])
    expect(described_class.target_dates('d0', bridge, friday)).to eq([Date.new(2026, 9, 25)])
    expect(described_class.target_dates('d5', {}, now)).to eq([Date.new(2026, 10, 1)])
    expect(described_class.target_dates('d2', {}, now)).to eq([Date.new(2026, 9, 28)])
  end

  it 'vários lembretes ao mesmo tempo: 2 dias antes e no dia, cada um com sua hora; interruptor geral desliga tudo', :aggregate_failures do
    no_dia = { 'enabled' => true, 'hour' => 7, 'inbox_id' => inbox.id, 'mode' => 'live',
               'template_params' => tpl.call('lembrete_d0_hoje'), 'message_preview' => 'Hoje {{1}}' }
    settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg, 'd0' => no_dia } })
    hoje = contact_named('Paciente De Hoje', '+5511999990041')
    depois = contact_named('Paciente De Segunda', '+5511999990042')
    consulta(hoje, '2026-09-26 15:00', confirmed_at: Time.current) # confirmada também recebe o do dia
    consulta(depois, '2026-09-28 09:00')

    sources = []
    allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
      sources << args[3]['name']
      m.call(*args)
    end
    described_class.perform_now(tz.parse('2026-09-26 07:10'))
    expect(sources).to eq(['lembrete_d0_hoje'])
    described_class.perform_now(now)
    expect(sources).to eq(%w[lembrete_d0_hoje confirmacao_consulta_paulista])
    state = settings.reload.agenda_config['appointment_reminders_state']
    expect(state.keys).to contain_exactly('d0', 'd2')

    settings.update!(agenda_config: settings.agenda_config.merge('appointment_confirmation' => { 'enabled' => false }))
    consulta(contact_named('Outra De Segunda', '+5511999990043'), '2026-09-28 11:00')
    described_class.perform_now(now + 5.minutes)
    expect(sources.size).to eq(2)
  end

  it 'lembrete antigo sem modo continua AO VIVO (nada muda para quem já usava a véspera)' do
    legacy = { 'enabled' => true, 'hour' => 10, 'inbox_id' => inbox.id, 'template_params' => tpl.call('lembrete_d1_confirma') }
    settings.update!(agenda_config: { 'appointment_reminders' => { 'd1' => legacy } })
    consulta(contact_named('Paciente Véspera', '+5511999990051'), '2026-09-27 09:00', modality: 'exames')
    expect(Crm::SendTemplateService).to receive(:new).once.and_call_original
    described_class.perform_now(now)
  end

  it 'AO VIVO: manda o modelo da unidade certa com nome, data, hora e valor preenchidos; pula parceiro e quem já confirmou', :aggregate_failures do
    maria = contact_named('Maria Paulista', '+5511999990001')
    joao = contact_named('João Tatuapé', '+5511999990002')
    ana = contact_named('Ana Confirmada', '+5511999990003')
    consulta(maria, '2026-09-28 09:00', description: 'Valor: 250,00')
    consulta(joao, '2026-09-28 14:30', unit: 'tatuape')
    consulta(ana, '2026-09-28 11:00', confirmed_at: Time.current)
    consulta(contact_named('Hoje Não', '+5511999990004'), '2026-09-27 09:00') # D-1, não é desta régua
    partner = contact_named('Parceiro', '+5511999990005')
    consulta(partner, '2026-09-28 10:00', source: 'oftalmofacil', source_detail: 'CLINICA X', external_ref: 'p1')

    sources = []
    allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
      sources << args
      m.call(*args)
    end
    described_class.perform_now(now)

    names = sources.map { |s| s[3]['name'] }
    expect(names).to contain_exactly('confirmacao_consulta_paulista', 'confirmao_consulta_tatuape')
    paulista = sources.find { |s| s[3]['name'] == 'confirmacao_consulta_paulista' }
    expect(paulista[3].dig('processed_params', 'body')).to eq('1' => 'Maria Paulista', '2' => '28/09/2026', '3' => '09:00', '4' => '250,00')
    tatuape = sources.find { |s| s[3]['name'] == 'confirmao_consulta_tatuape' }
    expect(tatuape[3].dig('processed_params', 'body')['4']).to eq('150,00')
    expect(maria.reload.additional_attributes.dig('cevico_appt_reminders', account.tasks.find_by(contact: maria).id.to_s, 'd2')).to be_present

    state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
    expect(state['mode']).to eq('live')
    expect(state['sent'].map { |e| e['name'] }).to contain_exactly('Maria Paulista', 'João Tatuapé')
    expect(state['skipped'].map { |e| e['why'] }).to include('paciente de parceiro (cerca)')
  end

  it 'SOMBRA: não manda nada, só registra quem receberia', :aggregate_failures do
    settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('mode' => 'shadow') } })
    maria = contact_named('Maria Sombra', '+5511999990011')
    consulta(maria, '2026-09-28 09:00')

    expect(Crm::SendTemplateService).not_to receive(:new)
    described_class.perform_now(now)

    state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
    expect(state['mode']).to eq('shadow')
    expect(state['sent'].first).to include('name' => 'Maria Sombra', 'unit' => 'Av. Paulista', 'template' => 'confirmacao_consulta_paulista')
    expect(maria.reload.additional_attributes).not_to include('cevico_appt_reminders')
  end

  it 'na mesma hora não repete; fora da hora não roda', :aggregate_failures do
    maria = contact_named('Maria Uma Vez', '+5511999990021')
    consulta(maria, '2026-09-28 09:00')
    expect(Crm::SendTemplateService).to receive(:new).once.and_call_original
    described_class.perform_now(now)
    described_class.perform_now(now + 20.minutes)
    described_class.perform_now(tz.parse('2026-09-26 13:00'))
  end

  it 'consulta sem unidade com modelo não é enviada e aparece como pulada' do
    maria = contact_named('Maria Online', '+5511999990031')
    consulta(maria, '2026-09-28 09:00', unit: 'online')
    described_class.perform_now(now)
    state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
    expect(state['skipped'].first).to include('why' => 'sem modelo para Online')
  end

  describe 'pacientes do Oftalmofácil (cerca liberada por UMA caixa)' do
    let(:of_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
    let(:partner_cfg) do
      { 'enabled' => true, 'inbox_id' => of_inbox.id,
        'template_params' => tpl.call('confirmacao_oftalmofacil').merge('processed_params' => { 'body' => { '1' => '{{nome}}', '2' => '{{parceiro}}' } }),
        'message_preview' => 'Olá {{1}}, {{2}}' }
    end
    let!(:parceiro) { contact_named('Paciente Parceiro', '+5511999990051') }
    let!(:maria) { contact_named('Maria Cevico', '+5511999990052') }

    before do
      consulta(parceiro, '2026-09-28 10:00', source: 'oftalmofacil', source_detail: 'CLINICA X', external_ref: 'p51')
      consulta(maria, '2026-09-28 09:00')
    end

    it 'ligado: parceiro recebe pela caixa liberada, com o modelo dela; CEVICO segue pela caixa de sempre', :aggregate_failures do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('partner' => partner_cfg) } })
      sources = []
      allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
        sources << args
        m.call(*args)
      end
      described_class.perform_now(now)

      of = sources.find { |s| s[3]['name'] == 'confirmacao_oftalmofacil' }
      expect(of[1]).to eq(of_inbox)
      expect(of[3].dig('processed_params', 'body')).to eq('1' => 'Paciente Parceiro', '2' => 'CLINICA X')
      cevico = sources.find { |s| s[3]['name'] == 'confirmacao_consulta_paulista' }
      expect(cevico[1]).to eq(inbox)
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['sent'].find { |e| e['name'] == 'Paciente Parceiro' }).to include('partner' => 'CLINICA X')
      expect(parceiro.reload.additional_attributes['cevico_appt_reminders']).to be_present
    end

    it 'sem modelo próprio, parceiro é pulado (nunca usa o modelo da CEVICO)' do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('partner' => partner_cfg.except('template_params')) } })
      described_class.perform_now(now)
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['skipped'].map { |e| e['why'] }).to include('Oftalmofácil: sem modelo')
    end

    it 'desligado: continua pulado pela cerca' do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('partner' => partner_cfg.merge('enabled' => false)) } })
      described_class.perform_now(now)
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['skipped'].map { |e| e['why'] }).to include('paciente de parceiro (cerca)')
      expect(state['sent'].map { |e| e['name'] }).to eq(['Maria Cevico'])
    end
  end
end
