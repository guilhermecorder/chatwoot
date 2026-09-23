require 'rails_helper'

# 🔧 rodada 192: ferramentas do Pós-agendamento (buscar/remarcar/cancelar/confirmar presença)
RSpec.describe Crm::ResponderTools do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { Crm::AgendaSlots::TZ }
  let(:today_14) { tz.now.beginning_of_day + 14.hours }

  def consulta(title, due_at, phone: nil, contact: nil, **extra)
    account.tasks.create!({ title: title, task_type: 'consulta', due_at: due_at, unit: 'paulista', doctor: 'Dr. Gustavo Bittar',
                            phone: phone, contact: contact, creator: admin, status: :todo }.merge(extra))
  end

  def tools(live: false, agent_key: 'atendente_pos')
    described_class.new(conversation: conversation, agent_key: agent_key, live: live)
  end

  describe 'definitions' do
    it 'expõe as 4 ferramentas com input_schema' do
      defs = tools.definitions
      expect(defs.pluck(:name)).to eq(described_class::NAMES)
      expect(defs).to all(include(:description, :input_schema))
      expect(defs.find { |d| d[:name] == 'remarcar_consulta' }.dig(:input_schema, :required)).to eq(%w[id dia hora unidade])
    end
  end

  describe 'buscar_consulta' do
    let!(:own) { consulta('Consulta: Maria Silva', today_14, contact: contact, phone: '+5511999990000') }
    let!(:mother) { consulta('Consulta: Maísa Teste', today_14 + 1.day, phone: '+5511988887777') }
    let!(:other) { consulta('Consulta: João Pereira', today_14 + 2.days, phone: '+5511977776666') }

    it 'sem filtro devolve só as do próprio contato', :aggregate_failures do
      result = tools.call('buscar_consulta', {})
      expect(result[:total]).to eq(1)
      expect(result[:consultas].first).to include(id: own.id, paciente: 'Maria Silva', hora: '14:00', unidade: 'Av. Paulista',
                                                  do_proprio_contato: true, status: 'agendada')
      expect(result[:consultas].first[:dia]).to eq(today_14.strftime('%Y-%m-%d'))
    end

    it 'acha a consulta de outra pessoa pelo nome sem acento, sem entregar o telefone inteiro', :aggregate_failures do
      result = tools.call('buscar_consulta', { nome: 'maisa' })
      ids = result[:consultas].pluck(:id)
      expect(ids).to contain_exactly(own.id, mother.id) # a própria sempre entra
      found = result[:consultas].find { |c| c[:id] == mother.id }
      expect(found).to include(paciente: 'Maísa Teste', telefone_final: '7777', do_proprio_contato: false)
      expect(found.to_json).not_to include('988887777')
    end

    it 'filtra terceiros pelo dia e casa telefone pela mesma linha', :aggregate_failures do
      by_day = tools.call('buscar_consulta', { nome: 'Teste', dia: (today_14 + 2.days).strftime('%Y-%m-%d') })
      expect(by_day[:consultas].pluck(:id)).to eq([own.id]) # Maísa é amanhã, não em 2 dias

      by_phone = tools.call('buscar_consulta', { telefone: '11 97777-6666' })
      expect(by_phone[:consultas].pluck(:id)).to contain_exactly(own.id, other.id)
    end

    it 'ignora canceladas, concluídas, passadas e de outra conta', :aggregate_failures do
      consulta('Consulta: Maísa Cancelada', today_14 + 1.day, canceled_at: Time.current)
      consulta('Consulta: Maísa Feita', today_14 + 1.day, status: :done)
      consulta('Consulta: Maísa Antiga', today_14 - 2.days)
      other_account = create(:account)
      other_admin = create(:user, account: other_account, role: :administrator)
      other_account.tasks.create!(title: 'Consulta: Maísa Alheia', task_type: 'consulta', due_at: today_14 + 1.day, creator: other_admin)

      result = tools.call('buscar_consulta', { nome: 'Maísa' })
      expect(result[:consultas].pluck(:paciente)).to contain_exactly('Maria Silva', 'Maísa Teste')
    end

    it 'com muitos homônimos limita a 5 e pede o dia' do
      6.times { |i| consulta("Consulta: Ana #{i}", today_14 + (i + 1).days) }
      result = tools.call('buscar_consulta', { nome: 'Ana' })
      expect(result[:consultas].size).to eq(5)
      expect(result[:total]).to eq(7) # 6 Anas + a própria
      expect(result[:aviso]).to include('DIA')
    end

    it 'registra a ação para a nota/balão' do
      tools_obj = tools
      tools_obj.call('buscar_consulta', { nome: 'Maísa' })
      expect(tools_obj.acoes.first).to include('ferramenta' => 'buscar_consulta', 'ok' => true)
      expect(tools_obj.acoes.first['resumo']).to include('buscou consulta: 2 encontradas')
    end
  end

  describe 'remarcar_consulta' do
    let!(:task) { consulta('Consulta: Maísa Teste', today_14 + 1.day, phone: '+5511988887777', description: 'Valor da consulta: R$ 150') }
    let(:slot) { Crm::AgendaSlots.free_slots(account, days: 10, per_window: 1).first }

    # 23/09 (teste real #16309): pergunta do paciente ("Tem as 16h?? Ou final de dia?") nunca é confirmação
    let(:input) { { id: task.id, dia: slot[:date].to_s, hora: slot[:time], unidade: slot[:unit] } }

    it 'recusa quando a última fala do paciente é uma pergunta (ainda não confirmou o horário)', :aggregate_failures do
      before_due = task.due_at
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Tem as 16h?? Ou final de dia?')
      tools_obj = tools(live: true)
      result = tools_obj.call('remarcar_consulta', input)
      expect(result[:ok]).to be(false)
      expect(result[:motivo]).to include('não confirmou').and include('Fica bom pra você')
      expect(task.reload.due_at).to eq(before_due)
      expect(tools_obj.acoes.last).to include('ferramenta' => 'remarcar_consulta', 'ok' => false)
    end

    it 'em SOMBRA só valida a vaga e não escreve nada', :aggregate_failures do
      tools_obj = tools(live: false)
      result = tools_obj.call('remarcar_consulta', input)
      expect(result).to include(simulado: true, ok: true)
      expect(result[:mensagem]).to include('nada foi alterado')
      expect(task.reload.due_at).to be_within(1.second).of(today_14 + 1.day)
      expect(task.rescheduled_count).to eq(0)
      expect(tools_obj.acoes.last['resumo']).to include('remarcaria Maísa Teste').and include('simulado')
      expect(CrmSetting.find_by(account: account)&.ai_config&.dig('opportunity_state', 'alerts')).to be_blank
    end

    it 'em sombra avisa quando a vaga NÃO está livre' do
      result = tools(live: false).call('remarcar_consulta', input.merge(hora: '03:07'))
      expect(result).to include(simulado: true, ok: false)
      expect(result[:mensagem]).to include('NÃO está livre')
    end

    it 'AO VIVO move a consulta, deixa rastro e avisa o Meu Painel', :aggregate_failures do
      tools_obj = tools(live: true)
      result = tools_obj.call('remarcar_consulta', input)
      expect(result[:ok]).to be(true)
      expect(result[:consulta]).to include(id: task.id, hora: slot[:time], dia: slot[:date].to_s)

      task.reload
      expect(task.due_at.in_time_zone(tz).strftime('%Y-%m-%d %H:%M')).to eq("#{slot[:date]} #{slot[:time]}")
      expect(task.unit).to eq(slot[:unit])
      expect(task.doctor).to eq(slot[:doctor])
      expect(task.rescheduled_count).to eq(1)
      expect(task.description).to include('Valor da consulta')
        .and include("Remarcada pelo Atendente Pós-agendamento via WhatsApp (conversa ##{conversation.display_id})")

      alert = CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts').last
      expect(alert).to include('kind' => 'agente_remarcou', 'task_id' => task.id, 'contact_name' => 'Maísa Teste', 'acao' => 'Conferir na Agenda')
      expect(alert['motivo']).to include('remarcou a consulta de Maísa Teste para')
      expect(conversation.messages.where(message_type: :activity).last.content).to include('remarcou: Maísa Teste')
      expect(tools_obj.acoes.last).to include('ferramenta' => 'remarcar_consulta', 'ok' => true)
    end

    it 'ao vivo recusa vaga ocupada ou fora da janela, sem mexer na consulta', :aggregate_failures do
      result = tools(live: true).call('remarcar_consulta', input.merge(hora: '03:07'))
      expect(result[:ok]).to be(false)
      expect(result[:motivo]).to include('não está mais livre')
      expect(task.reload.rescheduled_count).to eq(0)
    end

    it 'recusa id de fora do escopo e dados inválidos', :aggregate_failures do
      expect(tools(live: true).call('remarcar_consulta', input.merge(id: 0))).to include(ok: false)
      expect(tools(live: true).call('remarcar_consulta', input.merge(unidade: 'lua'))[:motivo]).to include('unidade')
      done = consulta('Consulta: Feita', today_14 + 1.day, status: :done)
      expect(tools(live: true).call('remarcar_consulta', input.merge(id: done.id))[:motivo]).to include('não encontrada')
    end
  end

  describe 'cancelar_consulta e confirmar_presenca' do
    let!(:task) { consulta('Consulta: Maísa Teste', today_14 + 1.day, phone: '+5511988887777') }

    it 'em sombra simulam; ao vivo cancelar grava canceled_at + aviso', :aggregate_failures do
      expect(tools(live: false).call('cancelar_consulta', { id: task.id, motivo: 'viagem' })).to include(simulado: true, ok: true)
      expect(task.reload.canceled_at).to be_nil

      result = tools(live: true).call('cancelar_consulta', { id: task.id, motivo: 'viagem' })
      expect(result[:ok]).to be(true)
      expect(result[:consulta][:status]).to eq('cancelada')
      expect(task.reload.canceled_at).to be_present
      expect(task.description).to include('Cancelada pelo Atendente Pós-agendamento').and include('motivo: viagem')
      alert = CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts').last
      expect(alert).to include('kind' => 'agente_cancelou', 'task_id' => task.id)
      # cancelada some do escopo: segunda tentativa não acha
      expect(tools(live: true).call('cancelar_consulta', { id: task.id })).to include(ok: false)
    end

    it 'confirmar presença: sombra simula; ao vivo anota na descrição', :aggregate_failures do
      expect(tools(live: false).call('confirmar_presenca', { id: task.id })).to include(simulado: true)
      expect(task.reload.description.to_s).not_to include('Presença confirmada')

      result = tools(live: true).call('confirmar_presenca', { id: task.id })
      expect(result[:ok]).to be(true)
      expect(result[:consulta][:status]).to eq('presença confirmada')
      expect(task.reload.description).to include('Presença confirmada pelo paciente (WhatsApp, Atendente Pós-agendamento) em')
    end
  end

  it 'ferramenta desconhecida não quebra' do
    expect(tools.call('apagar_tudo', {})).to include(ok: false)
  end
end
