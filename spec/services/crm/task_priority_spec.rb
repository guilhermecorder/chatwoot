require 'rails_helper'

# 🌡️ 11/11/2026 (LIFE): temperatura das tarefas do Meu Painel — a regra de pontos e os dados do cartão.
RSpec.describe Crm::TaskPriority do
  let(:now) { Time.zone.local(2026, 11, 11, 15, 0) }
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life') }
  let!(:stages) do
    ['Novos Contatos', 'Solicitação da Conta', 'Orçamento a fazer', 'Orçamento pronto', 'Orçamento Enviado'].each_with_index.map do |name, i|
      Crm::Stage.create!(pipeline: pipeline, name: name, position: i, color: '#2563eb')
    end
  end

  def client(name)
    create(:contact, account: account, name: name)
  end

  def card(contact, stage, value: nil, moved_at: now - 1.day)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, value: value, stage_moved_at: moved_at)
  end

  def task(contact, due_at:, comments: [])
    account.tasks.create!(title: "⏰ #{contact.name} — Montar e enviar o orçamento", creator: admin, assignee: admin, contact: contact,
                          task_type: 'pos_op', priority: :high, status: :todo, due_at: due_at, comments: comments)
  end

  def talk(contact, client_at:, reply_at: nil)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: client_at)
    return if reply_at.nil?

    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: reply_at)
  end

  describe '.score (a regra, sem banco)' do
    it 'soma fala do cliente, espera, etapa e prazo', :aggregate_failures do
      hot = described_class.score(now: now, due_at: now - 2.hours, last_client_at: now - 3.hours, waiting: true, stage_step: 2)
      expect(hot).to eq(level: 'quente', points: 9,
                        parts: [{ key: 'fala', points: 3 }, { key: 'espera', points: 1 }, { key: 'etapa', points: 2 },
                                { key: 'prazo', points: 3 }])

      warm = described_class.score(now: now, due_at: now + 5.hours, last_client_at: now - 2.days, stage_step: 0)
      expect(warm).to include(level: 'morna', points: 4)

      cold = described_class.score(now: now, due_at: now + 3.days, last_client_at: now - 10.days, stage_step: 9)
      expect(cold).to eq(level: 'fria', points: 3, parts: [{ key: 'etapa', points: 3 }])
    end

    it 'faixas da fala do cliente e do prazo', :aggregate_failures do
      expect(described_class.talk_points(now, now - 24.hours)).to eq(3)
      expect(described_class.talk_points(now, now - 3.days)).to eq(2)
      expect(described_class.talk_points(now, now - 7.days)).to eq(1)
      expect(described_class.talk_points(now, now - 8.days)).to eq(0)
      expect(described_class.talk_points(now, nil)).to eq(0)
      expect(described_class.due_points(now, now - 1.minute)).to eq(3)
      expect(described_class.due_points(now, now + 24.hours)).to eq(2)
      expect(described_class.due_points(now, now + 25.hours)).to eq(0)
      expect(described_class.due_points(now, nil)).to eq(0)
    end

    it 'sem nenhum sinal a tarefa é fria e não inventa motivo' do
      expect(described_class.score(now: now)).to eq(level: 'fria', points: 0, parts: [])
    end
  end

  describe '#call (com os dados do sistema)' do
    it 'leva cliente, etapa, valor, última fala e a temperatura', :aggregate_failures do
      ivan = client('Ivan Coral')
      cartao = card(ivan, stages[2], value: 24_800)
      talk(ivan, client_at: now - 3.hours)
      tarefa = task(ivan, due_at: now - 1.hour)

      row = described_class.new(account, [tarefa], now: now).call[tarefa.id]

      expect(row[:contact]).to include(id: ivan.id, name: 'Ivan Coral')
      expect(row[:card]).to include(id: cartao.id, value: 24_800.0)
      expect(row[:card][:stage]).to include(name: 'Orçamento a fazer', step: 2)
      expect(row[:last_client_at]).to be_within(1.second).of(now - 3.hours)
      expect(row[:client_waiting]).to be(true)
      expect(row[:heat]).to include(level: 'quente', points: 9)
    end

    it 'quem já recebeu resposta não está esperando; tarefa sem cliente fica só com o prazo', :aggregate_failures do
      ana = client('Ana Paula')
      talk(ana, client_at: now - 2.days, reply_at: now - 1.day)
      com_resposta = task(ana, due_at: now + 3.days)
      solta = account.tasks.create!(title: 'Ligar para o fornecedor', creator: admin, assignee: admin, due_at: now - 1.day)

      rows = described_class.new(account, [com_resposta, solta], now: now).call

      expect(rows[com_resposta.id]).to include(client_waiting: false, card: nil)
      expect(rows[com_resposta.id][:heat]).to eq(level: 'fria', points: 2, parts: [{ key: 'fala', points: 2 }])
      expect(rows[solta.id]).to include(contact: nil, card: nil, last_client_at: nil)
      expect(rows[solta.id][:heat]).to eq(level: 'fria', points: 3, parts: [{ key: 'prazo', points: 3 }])
    end

    it 'usa o cartão marcado pelo compromisso da etapa, mesmo com outro funil mais recente' do
      rui = client('Rui Barbosa')
      certo = card(rui, stages[4], moved_at: now - 5.days)
      outro = Crm::Pipeline.create!(account: account, name: 'Pós-venda')
      Crm::Contact.create!(contact: rui, pipeline: outro, stage: Crm::Stage.create!(pipeline: outro, name: 'Entrada', position: 0),
                           stage_moved_at: now - 1.hour)
      marca = { 'name' => 'Sistema', 'text' => 'x', 'etapa' => { 'stage_id' => stages[4].id, 'card_id' => certo.id } }
      tarefa = task(rui, due_at: now + 2.days, comments: [marca])

      row = described_class.new(account, [tarefa], now: now).call[tarefa.id]

      expect(row[:card]).to include(id: certo.id)
      expect(row[:card][:stage]).to include(name: 'Orçamento Enviado', step: 4)
    end
  end

  describe '.sort' do
    it 'mais pontos primeiro; no empate, maior orçamento e depois o prazo mais antigo' do
      items = [
        { id: 1, due_at: now, heat: { points: 5 }, card: { value: nil } },
        { id: 2, due_at: now - 1.day, heat: { points: 5 }, card: nil },
        { id: 3, due_at: now + 1.day, heat: { points: 5 }, card: { value: 30_000.0 } },
        { id: 4, due_at: nil, heat: { points: 9 }, card: nil }
      ]
      expect(described_class.sort(items).pluck(:id)).to eq([4, 3, 2, 1])
    end
  end
end
