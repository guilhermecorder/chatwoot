require 'rails_helper'

# 🧹 item 309: carga em massa no histórico de colunas não conta como "entrou na coluna"
RSpec.describe Crm::StageLogBulk do
  let(:account) { create(:account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil', position: 1) }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Envio de Orçamento', position: 1, color: '#2563EB') }
  let(:other) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 2, color: '#059669') }
  let(:load_at) { Time.utc(2026, 7, 10, 5, 44, 10) }

  def card
    Crm::Contact.create!(contact: create(:contact, account: account), pipeline: pipeline, stage: other)
  end

  def enter(target, at, count)
    Array.new(count) do |i|
      Crm::StageLog.create!(crm_contact: card, stage_id: target.id, stage_name: target.name, event_type: 'entered', entered_at: at + i.seconds)
    end
  end

  before do
    enter(stage, load_at, 30)                    # carga: 30 no mesmo minuto
    enter(stage, load_at + 1.hour, 29)           # 29 no mesmo minuto: abaixo da régua
    enter(stage, load_at + 3.days, 4)            # movimento normal
    Crm::StageLog.where(stage_id: other.id).delete_all # entradas criadas pelo próprio cartão ao nascer
  end

  it 'acha só a rajada de 30+ na mesma coluna no mesmo minuto', :aggregate_failures do
    bursts = described_class.bursts(account)
    expect(bursts.size).to eq(1)
    expect(bursts.first).to include(stage_id: stage.id, stage_name: 'Envio de Orçamento', count: 30)
    expect(described_class.summary(account).first).to include(day: Date.new(2026, 7, 10), entries: 30, minutes: 1)
  end

  it 'marcar tira a carga dos indicadores, sem apagar nada, e tem volta', :aggregate_failures do
    expect(described_class.mark!(account)).to eq(30)
    expect(Crm::StageLog.where(stage_id: stage.id).count).to eq(63)
    expect(Crm::StageLog.where(stage_id: stage.id, event_type: 'entered').count).to eq(33)
    expect(described_class.mark!(account)).to eq(0) # rodar de novo não muda nada

    bag = Crm::KpiBagService.new(account: account, since: Time.utc(2026, 7, 1), until_at: Time.utc(2026, 7, 31))
    expect(bag.send(:stage_entries, pipeline, stage.id, Time.utc(2026, 7, 1), Time.utc(2026, 7, 31)).count).to eq(33)

    expect(described_class.undo!(account)).to eq(30)
    expect(Crm::StageLog.where(stage_id: stage.id, event_type: 'entered').count).to eq(63)
  end

  it '`since` limita a varredura diária aos últimos dias e não mexe em outra conta', :aggregate_failures do
    expect(described_class.mark!(account, since: load_at + 1.day)).to eq(0)
    expect(described_class.mark!(create(:account))).to eq(0)
    expect(Crm::StageLog.where(event_type: 'bulk').count).to eq(0)
  end
end
