require 'rails_helper'

# 🔁 Auditoria 10/2026 (#2/#133): a remarcação ganha carimbo próprio na lista
# `comments` da consulta toda vez que o contador de remarcações sobe — o
# painel deixa de usar o updated_at (que muda com qualquer toque).
RSpec.describe Task do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let(:task) do
    described_class.create!(account: account, creator: admin, title: 'Consulta: Ana', task_type: 'consulta',
                            unit: 'paulista', due_at: tz.parse('2026-10-20 09:00'))
  end

  it 'remarcar (contador sobe) grava o carimbo com de/para; nasce sem carimbo', :aggregate_failures do
    expect(task.rescheduled_at).to be_nil

    task.update!(due_at: tz.parse('2026-10-22 14:00'), rescheduled_count: 1)
    stamp = task.reload.comments.last

    expect(stamp).to include('kind' => 'rescheduled', 'name' => 'Robô', 'by' => nil)
    expect(Time.zone.parse(stamp['from'])).to eq(tz.parse('2026-10-20 09:00'))
    expect(Time.zone.parse(stamp['to'])).to eq(tz.parse('2026-10-22 14:00'))
    expect(stamp['text']).to eq('🔁 Remarcada: 20/10 09:00 → 22/10 14:00')
    expect(task.rescheduled_at).to be_within(2.seconds).of(Time.current)
  end

  it 'qualquer outro toque (presença, médico, cor, Lixeira) NÃO carimba remarcação' do
    task.update!(attendance: 'attended', status: :done)
    task.update!(doctor: 'Dra. Teste', color: '#16A34A')
    task.to_trash!(by: admin)

    expect(task.reload.rescheduled_times).to eq([])
  end

  it 'criar consulta já com contador (carga/importação) não inventa carimbo' do
    imported = described_class.create!(account: account, creator: admin, title: 'Consulta: Beto', task_type: 'consulta',
                                       due_at: 3.days.from_now, rescheduled_count: 2)
    expect(imported.reload.rescheduled_at).to be_nil
  end

  it 'soma no banco sem apagar os comentários da equipe; guarda cada remarcação; rescheduled_at = a última', :aggregate_failures do
    task.update!(comments: [{ 'user_id' => admin.id, 'name' => admin.name, 'text' => 'ligar antes', 'at' => 1.day.ago.iso8601 }])
    travel_to(2.days.ago) { task.update!(due_at: task.due_at + 1.day, rescheduled_count: task.rescheduled_count + 1) }
    task.update!(due_at: task.due_at + 1.day, rescheduled_count: task.rescheduled_count + 1)

    fresh = described_class.find(task.id)
    expect(fresh.comments.first['text']).to eq('ligar antes')
    expect(fresh.rescheduled_times.size).to eq(2)
    expect(fresh.rescheduled_at).to be_within(2.seconds).of(Time.current)
    # o objeto em memória fica igual ao banco e não "sujo" (não regrava a lista inteira depois)
    expect(task.comments).to eq(fresh.comments)
    expect(task.changed).not_to include('comments')
  end

  it 'quem remarcou pela tela fica registrado (Current.user)' do
    Current.user = admin
    task.update!(due_at: task.due_at + 2.hours, rescheduled_count: 1)
    expect(task.reload.comments.last).to include('by' => admin.id, 'user_id' => admin.id, 'name' => admin.name)
  ensure
    Current.reset
  end
end
