require 'rails_helper'

# ⏳ 11/11/2026 (LIFE): prazo e compromisso por coluna do funil.
RSpec.describe Crm::StageDeadline do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:tz) { described_class::TZ }
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:contact) { create(:contact, account: account, name: 'Ivan Coral', phone_number: '+5519999990002') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life') }
  let(:novos) { Crm::Stage.create!(pipeline: pipeline, name: 'Novos Contatos', position: 0) }
  let(:a_fazer) do
    Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento a fazer', position: 1,
                       settings: { 'task_owner_id' => admin.id,
                                   'prazo' => { 'modo' => 'dia_util', 'hora' => '09:00', 'tarefa' => 'Montar e enviar o orçamento' } })
  end
  let(:enviado) { Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento Enviado', position: 2, settings: { 'prazo' => { 'modo' => 'horas', 'horas' => 24 } }) }

  it 'limpa a configuração que vem da tela', :aggregate_failures do
    expect(described_class.sanitize('modo' => 'dia_util', 'hora' => '25:99', 'tarefa' => '  Montar   o orçamento '))
      .to eq('modo' => 'dia_util', 'hora' => '09:00', 'tarefa' => 'Montar o orçamento')
    expect(described_class.sanitize('modo' => 'horas', 'horas' => '48')).to eq('modo' => 'horas', 'horas' => 48)
    expect(described_class.sanitize('modo' => 'horas', 'horas' => 0)).to be_nil
    expect(described_class.sanitize('modo' => 'qualquer')).to be_nil
    expect(described_class.sanitize(nil)).to be_nil
  end

  it 'próximo dia útil: quinta → sexta; sexta, sábado e domingo → segunda; horas somam', :aggregate_failures do
    cfg = described_class.config(a_fazer)
    expect(described_class.due_at(cfg, tz.local(2026, 11, 12, 15, 0))).to eq(tz.local(2026, 11, 13, 9, 0))  # quinta
    expect(described_class.due_at(cfg, tz.local(2026, 11, 13, 8, 0))).to eq(tz.local(2026, 11, 16, 9, 0))   # sexta
    expect(described_class.due_at(cfg, tz.local(2026, 11, 14, 10, 0))).to eq(tz.local(2026, 11, 16, 9, 0))  # sábado
    expect(described_class.due_at(cfg, tz.local(2026, 11, 15, 22, 0))).to eq(tz.local(2026, 11, 16, 9, 0))  # domingo
    expect(described_class.due_at(enviado, tz.local(2026, 11, 12, 15, 0))).to eq(tz.local(2026, 11, 13, 15, 0))
    expect(described_class.due_at(novos, Time.current)).to be_nil
  end

  it 'entrou na coluna: nasce o compromisso datado para quem cuida dela; saiu: baixa sozinha', :aggregate_failures do
    travel_to(tz.local(2026, 11, 12, 15, 0)) do
      card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: novos)
      expect(account.tasks.count).to eq(0)

      card.update!(stage: a_fazer)
      task = account.tasks.sole
      expect(task.title).to eq('⏰ Ivan Coral — Montar e enviar o orçamento')
      expect(task.due_at).to eq(tz.local(2026, 11, 13, 9, 0))
      expect(task.assignee).to eq(admin)
      expect(task).to be_todo

      card.update!(stage: enviado) # coluna só com prazo, sem compromisso
      expect(task.reload).to be_done
      expect(task.comments.last['text']).to include('Orçamento Enviado')
      expect(account.tasks.count).to eq(1)
    end
  end

  it 'adota a tarefa datada que o Atendente já abriu para o mesmo dia (não duplica)', :aggregate_failures do
    travel_to(tz.local(2026, 11, 12, 15, 0)) do
      card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: novos)
      da_ia = Crm::HandoffTask.open!(account: account, contact: contact, conversation: nil, agent_key: 'atendente_agendamento',
                                     motivo: 'Orçamento: conta recebida', detalhes: 'conta de 450, telhado 2',
                                     due_at: tz.local(2026, 11, 13, 9, 0))[:task]

      card.update!(stage: a_fazer)
      expect(account.tasks.count).to eq(1)
      expect(described_class.open_tasks(account, a_fazer.id, card.id).sole).to eq(da_ia)

      card.update!(stage: a_fazer) # nada muda
      card.update!(stage: novos)
      expect(da_ia.reload).to be_done
    end
  end

  it 'cartão que nasce direto na coluna com prazo já ganha o compromisso' do
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: a_fazer)
    expect(account.tasks.where("title LIKE '%Montar e enviar o orçamento'").count).to eq(1)
  end
end
