require 'rails_helper'

# 🗂️ Ponta 3 (22/10): card em "Cirurgia Agendada" de cirurgia que não vai
# acontecer ali — classe, destino e a arrumação (rake/sync).
RSpec.describe Crm::OfSurgeryCards do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:today) { Crm::OftalmofacilSurgery.today_sp }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0) }
  let!(:not_closed) { pipeline.stages.create!(name: 'Não Fechou Ainda', color: '#000', position: 1) }
  let!(:booked) { pipeline.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 2) }
  let!(:realized) { pipeline.stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 3) }
  let!(:postop) { pipeline.stages.create!(name: 'Pós Operatório', color: '#000', position: 4) }
  let(:service) { described_class.new(account, pipeline: pipeline, own_provider: 'CATARATA_SP') }

  before { CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'provider_name' => 'CATARATA_SP' } }) }

  def patient_in(stage, name)
    contact = create(:contact, account: account, name: name)
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage.id)
    contact
  end

  def item(contact, token, kind, date, **extra)
    Crm::OftalmofacilSurgery.create!({ account: account, item_token: token, status_kind: kind, contact_id: contact.id,
                                       patient_name: contact.name, provider_name: 'CATARATA_SP', procedure_type: 'Cirurgias',
                                       procedure_name: 'Faco', surgery_date: date, amount: 5000 }.merge(extra))
  end

  def setup_cases # rubocop:disable Metrics/AbcSize
    item(patient_in(booked, 'Ana Futura'), 'f1', 'agendada', today + 5)
    item(patient_in(booked, 'Bia Paga Recente'), 'p1', 'agendada', today - 3, paid_amount: 5000)
    item(patient_in(booked, 'Cris Paga Antiga'), 'p2', 'agendada', today - 90, paid_amount: 5000)
    item(patient_in(booked, 'Dani Sem Prova'), 's1', 'agendada', today - 10)
    item(patient_in(booked, 'Eva Aguardando'), 'a1', 'aguardando_pagamento', today - 20)
    item(patient_in(booked, 'Fê Cancelou'), 'c1', 'cancelada', today - 2, of_modified_at: 3.days.ago)
    patient_in(booked, 'Gil Sem Item')
    item(patient_in(booked, 'Hel Só Exame'), 'e1', 'agendada', today - 4, procedure_type: 'Exames', paid_amount: 130)
  end

  it 'classifica cada card e aponta o destino', :aggregate_failures do
    setup_cases
    rows = service.rows.index_by { |r| r.card.contact.name }

    expect(described_class.tally(rows.values)).to eq('futura' => 1, 'operou_com_prova' => 2, 'operou_sem_prova' => 1,
                                                     'aguardando_vencido' => 1, 'cancelada' => 1, 'sem_item' => 2)
    expect(rows['Bia Paga Recente'].target).to eq(realized)
    expect(rows['Cris Paga Antiga'].target).to eq(postop)
    expect(rows['Fê Cancelou'].target).to eq(not_closed)
    # exame do hub não é cirurgia: não tira ninguém da coluna
    expect(rows['Hel Só Exame'].klass).to eq('sem_item')
    expect(rows.values.reject(&:target).map { |r| r.card.contact.name })
      .to contain_exactly('Ana Futura', 'Dani Sem Prova', 'Eva Aguardando', 'Gil Sem Item', 'Hel Só Exame')
  end

  it 'arrumação do passado: move com a data real e a entrada fica fora dos indicadores', :aggregate_failures do
    setup_cases
    service.settle!(catch_up: true)

    card = Crm::Contact.joins(:contact).find_by(contacts: { name: 'Cris Paga Antiga' })
    log = Crm::StageLog.where(crm_contact_id: card.id, stage_id: postop.id).last
    expect(card.stage_id).to eq(postop.id)
    expect(log.entered_at.in_time_zone('America/Sao_Paulo').to_date).to eq(today - 90)
    expect(log.event_type).to eq('bulk')
    expect(Crm::Contact.joins(:contact).find_by(contacts: { name: 'Fê Cancelou' }).stage_id).to eq(not_closed.id)
    expect(Crm::Contact.joins(:contact).find_by(contacts: { name: 'Dani Sem Prova' }).stage_id).to eq(booked.id)
  end

  it 'no dia a dia a entrada conta e a cirurgia recente dispara as automações da coluna' do
    contact = patient_in(booked, 'Ivo Ontem')
    item(contact, 'r1', 'agendada', today - 1, paid_amount: 5000)
    trigger = instance_double(CrmAutomationTriggerService, call: true)
    allow(CrmAutomationTriggerService).to receive(:new).and_return(trigger)

    service.settle!(contact_ids: [contact.id])

    card = Crm::Contact.find_by(contact_id: contact.id)
    expect(Crm::StageLog.where(crm_contact_id: card.id, stage_id: realized.id).last.event_type).to eq('entered')
    expect(CrmAutomationTriggerService).to have_received(:new).with(hash_including(new_stage: realized, event_type: 'card_entered'))
  end

  it 'card em outra coluna nunca é mexido' do
    contact = patient_in(postop, 'Jó Já No Pós')
    item(contact, 'x1', 'cancelada', today - 1)

    expect(service.settle!).to be_empty
    expect(Crm::Contact.find_by(contact_id: contact.id).stage_id).to eq(postop.id)
  end
end
