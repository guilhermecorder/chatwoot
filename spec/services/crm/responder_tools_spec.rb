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
    it 'expõe as ferramentas da Agenda + abrir_tarefa (#458) com input_schema; o Agente de Ligação só as da Agenda' do
      defs = tools.definitions
      expect(defs.pluck(:name)).to eq(described_class::ALL_NAMES)
      expect(tools(agent_key: 'voice').definitions.pluck(:name)).to eq(described_class::NAMES)
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

    # 🔒 auditoria 10/10 (#99/#442): sem o telefone casar, a consulta de terceiro NÃO entra na lista: só a contagem
    it 'por nome sem acento acha a consulta de outra pessoa, mas não a lista até o telefone casar: só terceiros_ocultos', :aggregate_failures do
      result = tools.call('buscar_consulta', { nome: 'maisa' })
      expect(result[:consultas].pluck(:id)).to eq([own.id]) # a própria sempre entra; a Maísa fica fora
      expect(result[:total]).to eq(1)
      expect(result[:terceiros_ocultos]).to eq(1)
      expect(result.to_json).not_to include('Maísa')
      expect(result.to_json).not_to include('7777')
      expect(result[:aviso]).to include('terceiros_ocultos').and include('telefone COMPLETO').and include('chamar_humano')
      # a própria continua inteira
      expect(result[:consultas].first).to include(paciente: 'Maria Silva', hora: '14:00', medico: 'Dr. Gustavo Bittar')
    end

    it 'com nome + telefone (com DDD) cadastrado na consulta devolve a consulta de outra pessoa inteira', :aggregate_failures do
      result = tools.call('buscar_consulta', { nome: 'Maísa Teste', telefone: '(11) 98888-7777' })
      found = result[:consultas].find { |c| c[:id] == mother.id }
      expect(found).to include(paciente: 'Maísa Teste', hora: '14:00', unidade: 'Av. Paulista', medico: 'Dr. Gustavo Bittar',
                               do_proprio_contato: false)
      expect(found.to_json).not_to include('988887777')
      expect(result[:terceiros_ocultos]).to be_nil
      expect(result[:aviso]).to be_nil

      # telefone de OUTRA linha não abre a Maísa (fica oculta); abre só a consulta daquela linha
      wrong = tools.call('buscar_consulta', { nome: 'Maísa', telefone: '(11) 97777-6666' })
      expect(wrong[:consultas].pluck(:id)).to contain_exactly(own.id, other.id)
      expect(wrong[:terceiros_ocultos]).to eq(1)

      # telefone SEM DDD (8–9 dígitos) também não abre: mesma régua da prova forte (10+ dígitos)
      short = tools.call('buscar_consulta', { nome: 'Maísa', telefone: '98888-7777' })
      expect(short[:consultas].pluck(:id)).to eq([own.id])
      expect(short[:terceiros_ocultos]).to eq(1)
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
      expect(result[:consultas].pluck(:paciente)).to eq(['Maria Silva'])
      expect(result[:terceiros_ocultos]).to eq(1) # só a Maísa Teste válida conta
    end

    it 'homônimos de outra pessoa não são listados (só a contagem); nome curto demais nem procura', :aggregate_failures do
      6.times { |i| consulta("Consulta: Ana #{i}", today_14 + (i + 1).days) }
      result = tools.call('buscar_consulta', { nome: 'Ana' })
      expect(result[:consultas].pluck(:id)).to eq([own.id])
      expect(result[:terceiros_ocultos]).to eq(6)
      expect(result.to_json).not_to include('Ana')

      short = tools.call('buscar_consulta', { nome: 'a' })
      expect(short[:consultas].pluck(:id)).to eq([own.id])
      expect(short[:terceiros_ocultos]).to be_nil
      expect(short[:aviso]).to include('nome completo')
    end

    it 'com muitas consultas visíveis limita a 5 e pede o dia' do
      6.times { |i| consulta("Consulta: Maria Silva #{i}", today_14 + (i + 1).days, contact: contact) }
      result = tools.call('buscar_consulta', {})
      expect(result[:consultas].size).to eq(5)
      expect(result[:total]).to eq(7)
      expect(result[:aviso]).to include('DIA')
    end

    it 'registra a ação para a nota/balão' do
      tools_obj = tools
      tools_obj.call('buscar_consulta', { nome: 'Maísa' })
      expect(tools_obj.acoes.first).to include('ferramenta' => 'buscar_consulta', 'ok' => true)
      expect(tools_obj.acoes.first['resumo']).to include('buscou consulta: 1 encontrada').and include('1 de outra pessoa oculta')
    end
  end

  describe 'remarcar_consulta' do
    # consulta do PRÓPRIO contato (o nome do título pode ser de quem vai à consulta)
    let!(:task) do
      consulta('Consulta: Maísa Teste', today_14 + 1.day, contact: contact, phone: '+5511999990000', description: 'Valor da consulta: R$ 150')
    end
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

    # 🗂️ item 307: pós-operatório é remarcado na faixa dele (quarta 13h–14h do Dr. Henrique), não no período das consultas
    it 'AO VIVO remarca PÓS-OPERATÓRIO só para a faixa reservada', :aggregate_failures do
      task.update!(canceled_at: Time.current) # só o pós-operatório como consulta futura deste contato
      wednesday = tz.now.to_date + 14
      wednesday += 1 until wednesday.wednesday?
      posop = consulta('Pós-operatório: Maria Silva', today_14 + 2.days,
                       contact: contact, phone: '+5511999990000', modality: 'pos_op', doctor: 'Dr. Henrique Gemelli')
      base = { id: posop.id, dia: wednesday.to_s, unidade: 'paulista' }

      recusa = tools(live: true).call('remarcar_consulta', base.merge(hora: '14:15'))
      expect(recusa[:ok]).to be(false)
      expect(posop.reload.rescheduled_count).to eq(0)

      result = tools(live: true).call('remarcar_consulta', base.merge(hora: '13:15'))
      expect(result[:ok]).to be(true)
      expect(posop.reload.due_at.in_time_zone(tz).strftime('%Y-%m-%d %H:%M')).to eq("#{wednesday} 13:15")
      expect(posop.doctor).to eq('Dr. Henrique Gemelli')

      vagas = tools(live: true).call('horarios_do_dia', { 'dia' => wednesday.to_s })[:vagas].to_s
      expect(vagas).to include('13:00').and include('13:30')
      expect(vagas).not_to include('14:00')
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
      expect(task.comments.last).to include('kind' => 'rescheduled', 'name' => 'Robô') # 🔁 auditoria #2/#133
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

    # 🔒 auditoria 10/10 (#99/#442): consulta de outra pessoa não é remarcada sem prova forte
    it 'não remarca consulta que não é do contato nem do telefone: abre tarefa para a equipe', :aggregate_failures do
      other = consulta('Consulta: João Pereira', today_14 + 2.days, phone: '+5511977776666')
      tools_obj = tools(live: true)
      result = tools_obj.call('remarcar_consulta', input.merge(id: other.id))
      expect(result).to include(ok: false, outra_pessoa: true)
      expect(result[:motivo]).to include('OUTRA pessoa').and include('chamar_humano')
      expect(other.reload.rescheduled_count).to eq(0)
      expect(other.due_at).to be_within(1.second).of(today_14 + 2.days)
      expect(tools_obj.acoes.last).to include('ferramenta' => 'remarcar_consulta', 'ok' => false)
      expect(account.tasks.where(task_type: 'pos_op').last.title).to include('remarcar a consulta de outra pessoa (João Pereira')

      # com telefone completo + nome completo ditados, remarca
      proof = input.merge(id: other.id, telefone: '11 97777-6666', nome_completo: 'João Pereira')
      expect(tools(live: true).call('remarcar_consulta', proof)).to include(ok: true)
      expect(other.reload.rescheduled_count).to eq(1)
    end
  end

  describe 'cancelar_consulta e confirmar_presenca' do
    let!(:task) { consulta('Consulta: Maísa Teste', today_14 + 1.day, contact: contact, phone: '+5511999990000') }

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

    # 🔒 auditoria 10/10 (#99/#442): qualquer WhatsApp conseguia cancelar a consulta de outra pessoa só pelo nome
    describe 'consulta de OUTRA pessoa (telefone diferente, sem vínculo com o contato)' do
      let!(:other) { consulta('Consulta: João Pereira', today_14 + 2.days, phone: '+5511977776666') }

      it 'não cancela nem confirma: devolve ok=false, abre UMA tarefa para a equipe e orienta', :aggregate_failures do
        tools_obj = tools(live: true)
        result = tools_obj.call('cancelar_consulta', { id: other.id, motivo: 'viagem' })
        expect(result).to include(ok: false, outra_pessoa: true)
        expect(result).not_to have_key(:simulado) # recusa não é "faça de conta"
        expect(result[:motivo]).to include('NADA foi alterado').and include('A equipe já recebeu uma tarefa')
          .and include('chamar_humano').and include('telefone COMPLETO')
        expect(other.reload.canceled_at).to be_nil
        expect(other.description.to_s).not_to include('Cancelada')
        expect(CrmSetting.find_by(account: account)&.ai_config&.dig('opportunity_state', 'alerts')).to be_blank
        expect(tools_obj.acoes.last).to include('ferramenta' => 'cancelar_consulta', 'ok' => false, 'outra_pessoa' => true, 'tarefa_aberta' => true)
        expect(tools_obj.acoes.last['resumo']).to include('tarefa aberta para a equipe')

        handoff = account.tasks.where(task_type: 'pos_op').to_a
        expect(handoff.size).to eq(1)
        expect(handoff.first.title).to include('cancelar a consulta de outra pessoa (João Pereira')
        expect(handoff.first.contact).to eq(contact)
        expect(handoff.first.description).to include('Quem conversa: Maria Silva').and include('conferir com o titular')
        expect(conversation.messages.where(message_type: :activity).last.content).to include('abriu a tarefa')

        # confirmar presença também não mexe; a 2ª chamada só complementa a mesma tarefa
        expect(tools_obj.call('confirmar_presenca', { id: other.id })).to include(ok: false, outra_pessoa: true)
        expect(other.reload.description.to_s).not_to include('Presença confirmada')
        expect(account.tasks.where(task_type: 'pos_op').count).to eq(1)
      end

      it 'em sombra também recusa, sem criar tarefa, e diz à IA que a tarefa não foi aberta', :aggregate_failures do
        tools_obj = tools(live: false)
        result = tools_obj.call('cancelar_consulta', { id: other.id })
        expect(result).to include(ok: false, outra_pessoa: true)
        expect(result).not_to have_key(:simulado)
        expect(result[:motivo]).to include('Em sombra a recusa vale igual').and include('chamar_humano')
        expect(result[:motivo]).not_to include('já recebeu uma tarefa')
        expect(other.reload.canceled_at).to be_nil
        expect(account.tasks.where(task_type: 'pos_op')).to be_empty
        expect(tools_obj.acoes.last).to include('outra_pessoa' => true, 'tarefa_aberta' => false)
        expect(tools_obj.acoes.last['resumo']).to include('simulado')
      end

      it 'ao vivo, se a tarefa para a equipe falhar, não diz que a equipe foi avisada', :aggregate_failures do
        allow(Crm::HandoffTask).to receive(:open!).and_raise(StandardError, 'banco fora')
        tools_obj = tools(live: true)
        result = tools_obj.call('cancelar_consulta', { id: other.id })
        expect(result).to include(ok: false, outra_pessoa: true)
        expect(result[:motivo]).to include('Não foi possível avisar a equipe').and include('chamar_humano')
        expect(result[:motivo]).not_to include('já recebeu uma tarefa')
        expect(other.reload.canceled_at).to be_nil
        expect(tools_obj.acoes.last).to include('outra_pessoa' => true, 'tarefa_aberta' => false)
        expect(tools_obj.acoes.last['resumo']).to include('NÃO foi aberta')
      end

      it 'palavras de ligação (da/de/do) não contam como prova de nome: "Joao da Silva" não abre "Maria da Silva"', :aggregate_failures do
        maria = consulta('Consulta: Maria da Silva', today_14 + 3.days, phone: '+5511966665555')
        bad = tools(live: true).call('cancelar_consulta', { id: maria.id, telefone: '11966665555', nome_completo: 'Joao da Silva' })
        expect(bad).to include(ok: false, outra_pessoa: true)
        expect(maria.reload.canceled_at).to be_nil
        # sem o primeiro nome também não
        no_first = tools(live: true).call('cancelar_consulta', { id: maria.id, telefone: '11966665555', nome_completo: 'Silva Santos' })
        expect(no_first).to include(ok: false)
        expect(maria.reload.canceled_at).to be_nil

        good = tools(live: true).call('cancelar_consulta', { id: maria.id, telefone: '11966665555', nome_completo: 'maria silva' })
        expect(good[:ok]).to be(true)
        expect(maria.reload.canceled_at).to be_present
      end

      it 'com prova forte (telefone completo da consulta + nome completo) cancela', :aggregate_failures do
        # telefone certo mas nome errado / só primeiro nome / sem DDD: continua recusando
        [{ telefone: '11977776666', nome_completo: 'Maria Silva' }, { telefone: '11977776666', nome_completo: 'João' },
         { telefone: '97777-6666', nome_completo: 'João Pereira' }, { telefone: '21977776666', nome_completo: 'João Pereira' }].each do |proof|
          expect(tools(live: true).call('cancelar_consulta', { id: other.id }.merge(proof))).to include(ok: false)
        end
        expect(other.reload.canceled_at).to be_nil

        result = tools(live: true).call('cancelar_consulta',
                                        { id: other.id, telefone: '(11) 97777-6666', nome_completo: 'joao pereira', motivo: 'viagem' })
        expect(result[:ok]).to be(true)
        expect(other.reload.canceled_at).to be_present
      end
    end
  end

  it 'ferramenta desconhecida não quebra' do
    expect(tools.call('apagar_tudo', {})).to include(ok: false)
  end
end
