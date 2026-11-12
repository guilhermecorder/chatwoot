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

  # 🔔 11/11 (tarde): fila de lembretes — cada baixa faz nascer o próximo
  describe 'lembretes em sequência' do
    let(:acompanhar) do
      Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento Enviado (com lembretes)', position: 3,
                         settings: { 'task_owner_id' => admin.id,
                                     'prazo' => { 'modo' => 'dia_util', 'hora' => '09:00', 'tarefa' => 'Confirmar se recebeu o orçamento',
                                                  'lembretes' => [{ 'dias' => 2, 'tarefa' => 'Ligar: o que achou do orçamento?' },
                                                                  { 'dias' => 5, 'tarefa' => 'Retomar a conversa' }] } })
    end

    it 'limpa a fila que vem da tela: só linhas completas, no máximo 6, e só quando há o primeiro compromisso', :aggregate_failures do
      fila = [{ 'dias' => '2', 'tarefa' => '  Ligar   para o cliente ' }, { 'dias' => 0, 'tarefa' => 'sem dias' },
              { 'dias' => 3, 'tarefa' => '' }, { 'dias' => 400, 'tarefa' => 'Muito longe' }]
      limpo = described_class.sanitize('modo' => 'horas', 'horas' => 24, 'tarefa' => 'Confirmar', 'lembretes' => fila)
      expect(limpo['lembretes']).to eq([{ 'dias' => 2, 'tarefa' => 'Ligar para o cliente' }, { 'dias' => 90, 'tarefa' => 'Muito longe' }])

      muitos = Array.new(9) { |i| { 'dias' => i + 1, 'tarefa' => "Passo #{i + 1}" } }
      expect(described_class.sanitize('modo' => 'horas', 'horas' => 24, 'tarefa' => 'Confirmar', 'lembretes' => muitos)['lembretes'].size).to eq(6)
      expect(described_class.sanitize('modo' => 'horas', 'horas' => 24, 'lembretes' => fila)).not_to have_key('lembretes')
    end

    it 'o lembrete vence N dias depois, em dia útil, na hora da coluna', :aggregate_failures do
      cfg = described_class.config(acompanhar)
      expect(described_class.reminder_due_at(cfg, 2, tz.local(2026, 11, 10, 16, 0))).to eq(tz.local(2026, 11, 12, 9, 0)) # terça → quinta
      expect(described_class.reminder_due_at(cfg, 2, tz.local(2026, 11, 12, 16, 0))).to eq(tz.local(2026, 11, 16, 9, 0)) # quinta → sábado → segunda
      expect(described_class.reminder_due_at({ 'modo' => 'horas' }, 1, tz.local(2026, 11, 10, 16, 0))).to eq(tz.local(2026, 11, 11, 9, 0))
    end

    it 'cada baixa faz nascer o próximo lembrete; no fim da fila não nasce mais nada', :aggregate_failures do
      travel_to(tz.local(2026, 11, 10, 15, 0)) do # terça
        card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: acompanhar)
        primeiro = account.tasks.sole
        expect(primeiro.title).to eq('⏰ Ivan Coral — Confirmar se recebeu o orçamento')

        primeiro.update!(status: :done)
        segundo = described_class.open_tasks(account, acompanhar.id, card.id).sole
        expect(segundo.title).to eq('⏰ Ivan Coral — Ligar: o que achou do orçamento?')
        expect(segundo.due_at).to eq(tz.local(2026, 11, 12, 9, 0))
        expect(segundo.assignee).to eq(admin)
        expect(segundo.comments.last['text']).to start_with('Lembrete 1 de 2')

        segundo.update!(status: :done)
        terceiro = described_class.open_tasks(account, acompanhar.id, card.id).sole
        expect(terceiro.title).to eq('⏰ Ivan Coral — Retomar a conversa')
        expect(terceiro.due_at).to eq(tz.local(2026, 11, 16, 9, 0)) # terça + 5 = domingo → segunda

        terceiro.update!(status: :done)
        expect(described_class.open_tasks(account, acompanhar.id, card.id)).to be_empty
        expect(account.tasks.count).to eq(3)
      end
    end

    it 'o cartão saiu da coluna: a baixa automática não puxa lembrete; baixa depois de sair também não', :aggregate_failures do
      card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: acompanhar)
      primeiro = account.tasks.sole

      card.update!(stage: novos)
      expect(primeiro.reload).to be_done
      expect(account.tasks.count).to eq(1)

      primeiro.update!(status: :todo)
      primeiro.update!(status: :done)
      expect(account.tasks.count).to eq(1)
    end

    it 'tarefa comum (sem marca de etapa) não puxa lembrete' do
      Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: novos)
      solta = account.tasks.create!(title: 'Ligar para o fornecedor', creator: admin, assignee: admin)
      expect { solta.update!(status: :done) }.not_to(change { account.tasks.count })
    end
  end
end
