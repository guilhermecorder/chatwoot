require 'rails_helper'

# ✅ item 305: agendamento feito na Agenda (consulta, retorno, exame, cirurgia)
# não é cartão do quadro de Tarefas — fica só na Agenda
RSpec.describe Task do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def make(attrs)
    described_class.create!({ account: account, creator: user, assignee: user, title: 'Maria' }.merge(attrs))
  end

  it 'board_cards deixa de fora consulta, retorno, exame e cirurgia', :aggregate_failures do
    retorno = make(task_type: 'consulta', modality: 'retorno', unit: 'tatuape', due_at: 1.day.from_now)
    exame = make(task_type: 'consulta', modality: 'exames', unit: 'paulista', due_at: 1.day.from_now)
    cirurgia = make(task_type: 'cirurgia', due_at: 2.days.from_now)
    antigo = make(task_type: nil, unit: 'tatuape', due_at: 1.day.from_now) # agendamento antigo, só com unidade

    cards = account.tasks.board_cards
    expect(cards).not_to include(retorno, exame, cirurgia, antigo)
  end

  it 'board_cards mantém os cartões comuns, com tipo, sem tipo e com tipo vazio', :aggregate_failures do
    com_tipo = make(title: 'Ligar para o laboratório', task_type: 'Administrativo')
    sem_tipo = make(title: 'Conferir estoque', task_type: nil)
    tipo_vazio = make(title: 'Responder e-mail', task_type: '', unit: '')

    expect(account.tasks.board_cards).to include(com_tipo, sem_tipo, tipo_vazio)
  end
end
