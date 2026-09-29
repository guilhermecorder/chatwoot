require 'rails_helper'

# 🎨 item 290: cor do agendamento na Agenda (organização livre da equipe)
RSpec.describe Task do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:task) do
    described_class.new(account: account, creator: user, title: 'Maria', task_type: 'consulta', due_at: 1.day.from_now)
  end

  it 'tem 12 cores, todas diferentes e no formato #RRGGBB' do
    expect(described_class::COLORS.size).to eq(12)
    expect(described_class::COLORS.uniq.size).to eq(12)
    expect(described_class::COLORS).to all(match(/\A#[0-9A-F]{6}\z/))
  end

  it 'aceita sem cor (cor padrão do tipo)' do
    task.color = nil
    expect(task).to be_valid
  end

  it 'aceita qualquer cor da lista' do
    described_class::COLORS.each do |hex|
      task.color = hex
      expect(task).to be_valid
    end
  end

  it 'recusa cor fora da lista', :aggregate_failures do
    ['#123456', 'red', '#dc2626', '', 'javascript:alert(1)'].each do |bad|
      task.color = bad
      expect(task).not_to be_valid
      expect(task.errors[:color]).to be_present
    end
  end

  it 'guarda a cor no banco' do
    task.color = '#16A34A'
    task.save!
    expect(task.reload.color).to eq('#16A34A')
  end
end
