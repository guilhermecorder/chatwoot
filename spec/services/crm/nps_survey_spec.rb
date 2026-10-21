require 'rails_helper'

# 📊 item 256 (26/09): pesquisa de satisfação pós-cirurgia (substitui o N8N)
RSpec.describe Crm::NpsSurvey do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:tz) { described_class::TZ }
  let(:now) { tz.parse('2026-09-26 10:05') }
  let(:tpl) do
    { 'name' => 'pesquisa_nps', 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => { 'body' => { '1' => '{{nome}}' } } }
  end
  let(:cfg) do
    { 'enabled' => true, 'mode' => 'live', 'hour' => 10, 'inbox_id' => inbox.id, 'template_params' => tpl, 'message_preview' => 'Oi {{1}}' }
  end
  let!(:settings) { CrmSetting.create!(account: account, agenda_config: { 'nps_survey' => cfg }) }

  def patient(name, phone)
    create(:contact, account: account, name: name, phone_number: phone)
  end

  def surgery(contact, days_ago, procedure:, done: true, **extra)
    account.tasks.create!({ title: "Cirurgia: #{contact.name}", task_type: 'cirurgia', procedure: procedure, contact: contact,
                            creator: admin, due_at: tz.parse("#{(now.to_date - days_ago)} 09:00"),
                            attendance: done ? 'attended' : nil, status: done ? :done : :todo }.merge(extra))
  end

  def sent_names
    names = []
    allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
      names << args[3].dig('processed_params', 'body', '1')
      m.call(*args)
    end
    allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
      svc = m.call(**kw)
      allow(svc).to receive(:perform).and_return(instance_double(Conversation))
      svc
    end
    names
  end

  it 'classifica o tipo pelo procedimento com os dias do N8N (LASIK 1, PRK 29, catarata 15)', :aggregate_failures do
    rules = described_class::DEFAULT_RULES
    c = patient('Ana', '+5511911110001')
    kind = ->(proc) { described_class.rule_for(rules, surgery(c, 1, procedure: proc)) }
    expect(kind.call('FACECTOMIA COM LIO IMPORTADA · Olho Direito')).to include('key' => 'catarata', 'days_after' => 15)
    expect(kind.call('CIRURGIA REFRATIVA - LASIK (MONOCULAR)')).to include('key' => 'lasik', 'days_after' => 1)
    expect(kind.call('PRK · Ambos')).to include('key' => 'prk', 'days_after' => 29)
    expect(kind.call('Cirurgia refrativa')['key']).to eq('refrativa')
    expect(kind.call('Pterígio')['key']).to eq('outras')
  end

  it 'manda no dia certo de cada tipo, só para cirurgia realizada, sem parceiro e sem repetir', :aggregate_failures do
    settings.update!(agenda_config: { 'nps_survey' => cfg.merge('catch_up_days' => 0) })
    names = sent_names
    surgery(patient('Catarata Quinze', '+5511911110002'), 15, procedure: 'Facoemulsificação')
    surgery(patient('Lasik Ontem', '+5511911110003'), 1, procedure: 'LASIK')
    surgery(patient('Lasik Quinze', '+5511911110004'), 15, procedure: 'LASIK') # LASIK é 1 dia, não 15
    surgery(patient('Nao Realizada', '+5511911110005'), 15, procedure: 'Catarata', done: false)
    surgery(patient('Parceiro', '+5511911110006'), 15, procedure: 'Catarata', source: 'oftalmofacil', source_detail: 'CLINICA X', external_ref: 'p1')

    described_class.run_all(now)
    expect(names).to contain_exactly('Catarata', 'Lasik')
    state = settings.reload.agenda_config['nps_survey_state']
    expect(state['skipped'].map { |e| e['why'] }).to include('cirurgia não marcada como realizada na Agenda', 'paciente de parceiro (cerca)')

    described_class.run_all(now + 10.minutes) # mesma hora: nada de novo
    expect(names.size).to eq(2)
  end

  it 'em sombra só lista; fora da hora não roda; segundo olho dentro do intervalo não recebe', :aggregate_failures do
    settings.update!(agenda_config: { 'nps_survey' => cfg.merge('mode' => 'shadow') })
    expect(Crm::SendTemplateService).not_to receive(:new)
    c = patient('Dois Olhos', '+5511911110007')
    surgery(c, 15, procedure: 'Catarata OD')
    described_class.run_all(tz.parse('2026-09-26 14:00'))
    expect(settings.reload.agenda_config['nps_survey_state']).to be_nil
    described_class.run_all(now)
    expect(settings.reload.agenda_config.dig('nps_survey_state', 'sent').map { |e| e['name'] }).to eq(['Dois Olhos'])

    c.update!(additional_attributes: { described_class::MARK_KEY => { 'pending_at' => 10.days.ago.iso8601, 'task_ids' => [] } })
    described_class.run_all(now + 1.minute)
    expect(settings.reload.agenda_config.dig('nps_survey_state', 'skipped').first['why']).to include('menos de 60 dias')
  end

  it 'quem ficou para trás recebe dentro da janela de recuperação, uma vez só', :aggregate_failures do
    names = sent_names
    surgery(patient('Atrasada Cinco', '+5511911110021'), 20, procedure: 'Catarata') # 15 + 5 dias
    surgery(patient('Atrasada Dez', '+5511911110022'), 25, procedure: 'Catarata')   # fora dos 7 dias
    described_class.run_all(now)
    described_class.run_all(now + 1.day)
    expect(names).to eq(['Atrasada'])
  end

  # 🔒 auditoria 10/2026 (achados #47/#65 + "NPS sem trava de rodada"): a marca
  # era gravada DEPOIS do envio e não havia trava por conta → duas rodadas
  # sobrepostas (ou a marca falhando) mandavam a pesquisa duas vezes.
  describe 'sem pesquisa duplicada' do
    let(:contact) { patient('Uma Vez', '+5511911110041') }
    let!(:task) { surgery(contact, 15, procedure: 'Catarata') }

    # conta os envios; `on_send` roda no meio de cada envio (simula outra rodada)
    def count_sends(results: [], &on_send)
      sends = 0
      allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
        svc = m.call(**kw)
        allow(svc).to receive(:perform) do
          sends += 1
          on_send&.call(sends)
          results.fetch(sends - 1, instance_double(Conversation))
        end
        svc
      end
      -> { sends }
    end

    it 'duas rodadas sobrepostas mandam a pesquisa uma vez só (marca gravada ANTES do envio)', :aggregate_failures do
      sends = count_sends do |n|
        described_class.new(account, now).run if n == 1 # a rodada das :20 começa no meio da das :05
      end
      described_class.new(account, now).run
      expect(sends.call).to eq(1)
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'task_ids')).to eq([task.id])
    end

    it 'se a marca falhar, a pesquisa NÃO sai e a próxima rodada manda uma vez só (achado #65)', :aggregate_failures do
      sends = count_sends
      calls = 0
      allow(Cevico::AttributeMerge).to receive(:merge!).and_wrap_original do |m, *args, &blk|
        calls += 1
        raise ActiveRecord::Deadlocked, 'contato disputado' if calls == 1

        m.call(*args, &blk)
      end
      described_class.new(account, now).run
      expect(sends.call).to eq(0)
      expect(settings.reload.agenda_config.dig('nps_survey_state', 'skipped').first['why']).to start_with('erro:')
      described_class.new(account, now).run
      expect(sends.call).to eq(1)
    end

    # guarda do caminho release_sent! (o código antigo também não marcava quando o envio devolvia nil)
    it 'release_sent!: envio que devolve nil deixa a marca como estava (a cirurgia continua candidata)', :aggregate_failures do
      old_mark = { 'pending_at' => 100.days.ago.iso8601, 'task_ids' => [999], 'task_id' => 999, 'answered_at' => 99.days.ago.iso8601 }
      contact.update!(additional_attributes: { described_class::MARK_KEY => old_mark })
      sends = count_sends(results: [nil])
      described_class.new(account, now).run
      expect(sends.call).to eq(1)
      expect(contact.reload.additional_attributes[described_class::MARK_KEY]).to eq(old_mark)
      expect(settings.reload.agenda_config.dig('nps_survey_state', 'skipped').first['why']).to eq('envio não saiu (contato/caixa)')

      described_class.new(account, now + 15.minutes).run
      expect(sends.call).to eq(2)
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'task_ids')).to eq([999, task.id])
    end

    # o envio LEVANTA erro (caixa errada, validação…) depois da reserva: a marca
    # volta ao que era, nada de lembrete de pesquisa que nunca chegou, e a
    # próxima rodada manda uma vez só
    it 'erro no meio do envio (sem mensagem gravada) solta a marca; sem lembrete fantasma; próxima rodada manda 1 vez', :aggregate_failures do
      settings.update!(agenda_config: { 'nps_survey' => cfg.merge('reminder' => { 'enabled' => true, 'hours' => 6, 'template_params' => tpl }) })
      sends = count_sends do |n|
        raise ActiveRecord::RecordInvalid, Conversation.new if n == 1
      end
      described_class.new(account, now).run
      expect(sends.call).to eq(1)
      expect(settings.reload.agenda_config.dig('nps_survey_state', 'skipped').first['why']).to start_with('erro:')
      expect(contact.reload.additional_attributes[described_class::MARK_KEY]).to be_nil

      travel_to(now + 7.hours) { described_class.new(account, now + 7.hours).send_reminders }
      expect(sends.call).to eq(1) # nenhum lembrete: a pesquisa não saiu
      expect(described_class.context_text(contact.reload)).to be_nil

      described_class.new(account, now + 15.minutes).run
      expect(sends.call).to eq(2)
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'task_ids')).to eq([task.id])
    end

    it 'erro DEPOIS da mensagem já gravada mantém a marca (não reenvia)', :aggregate_failures do
      sends = count_sends do |n|
        next unless n == 1

        conv = create(:conversation, account: account, inbox: inbox, contact: contact)
        create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, content: 'Oi Uma',
                         additional_attributes: { 'template_params' => tpl, 'cevico_auto' => 'TemplateSource' })
        raise 'webhook do envio falhou'
      end
      described_class.new(account, now).run
      expect(sends.call).to eq(1)
      mark = contact.reload.additional_attributes[described_class::MARK_KEY]
      expect(mark['task_ids']).to eq([task.id])
      expect(mark['pending_at']).to be_present

      described_class.new(account, now + 15.minutes).run
      expect(sends.call).to eq(1)
    end

    it 'segundo olho na mesma rodada: uma pesquisa só para a pessoa', :aggregate_failures do
      other = surgery(contact, 15, procedure: 'Catarata OE')
      sends = count_sends
      described_class.new(account, now).run
      expect(sends.call).to eq(1)
      ids = contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'task_ids')
      expect(ids.size).to eq(1)
      expect([task.id, other.id]).to include(ids.first)
    end

    it 'a rodada pega a trava da conta no Redis com senha própria e solta só a sua no fim', :aggregate_failures do
      sends = count_sends
      key = "CRM_NPS_LOCK::#{account.id}"
      token = nil
      allow(Redis::Alfred).to receive(:set).and_wrap_original do |m, *args, **kw|
        token = args[1] if args[0] == key
        m.call(*args, **kw)
      end
      allow(Redis::Alfred).to receive(:delete_if_equals).and_call_original
      described_class.run_all(now)
      expect(Redis::Alfred).to have_received(:set).with(key, anything, nx: true, ex: 600)
      expect(token).to be_present
      expect(Redis::Alfred).to have_received(:delete_if_equals).with(key, token)
      expect(Redis::Alfred.get(key)).to be_nil
      expect(sends.call).to eq(1)
    end

    it 'com a trava ocupada por outra rodada, sai sem enviar e sem soltar a trava alheia', :aggregate_failures do
      sends = count_sends
      allow(Redis::Alfred).to receive(:set).and_return(false)
      allow(Redis::Alfred).to receive(:delete_if_equals).and_call_original
      allow(Rails.logger).to receive(:info).and_call_original
      described_class.run_all(now)
      expect(sends.call).to eq(0)
      expect(Redis::Alfred).not_to have_received(:delete_if_equals)
      expect(Rails.logger).to have_received(:info).with(/rodada anterior ainda rodando/)
    end

    it 'Redis fora do ar: a rodada desta conta é pulada com erro no log, sem derrubar o job', :aggregate_failures do
      sends = count_sends
      allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError, 'sem redis')
      allow(Rails.logger).to receive(:error).and_call_original
      expect { described_class.run_all(now) }.not_to raise_error
      expect(sends.call).to eq(0)
      expect(Rails.logger).to have_received(:error).with(/\[CEVICO NPS\] conta #{account.id}: sem redis/)
    end
  end

  describe 'lembrete para quem não respondeu' do
    let(:rem_tpl) { tpl.merge('name' => 'nps_lembrete') }
    let(:contact) { patient('Sem Resposta', '+5511911110031') }

    before do
      settings.update!(agenda_config: { 'nps_survey' => cfg.merge('reminder' => { 'enabled' => true, 'hours' => 6, 'template_params' => rem_tpl }) })
      contact.update!(additional_attributes: { described_class::MARK_KEY => { 'pending_at' => (now - 7.hours).iso8601, 'task_ids' => [1] } })
    end

    it 'manda 1 vez depois das N horas, das 8h às 20h', :aggregate_failures do
      names = sent_names
      travel_to(now + 12.hours) { described_class.run_all(now + 12.hours) } # 22h: fora da janela
      expect(names).to be_empty
      travel_to(now) { described_class.run_all(now) }
      travel_to(now + 15.minutes) { described_class.run_all(now + 15.minutes) }
      expect(names).to eq(['Sem'])
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'reminded_at')).to be_present
    end

    it 'não manda se o paciente já escreveu depois da pesquisa' do
      conv = create(:conversation, account: account, inbox: inbox, contact: contact)
      create(:message, account: account, inbox: inbox, conversation: conv, message_type: :incoming, content: 'oi, tudo bem')
      names = sent_names
      travel_to(now) { described_class.run_all(now) }
      expect(names).to be_empty
    end

    # 🔒 auditoria 10/2026: 'reminded_at' também era gravado DEPOIS do envio
    it 'duas rodadas sobrepostas mandam o lembrete uma vez só (marca ANTES do envio)', :aggregate_failures do
      sends = 0
      allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
        svc = m.call(**kw)
        allow(svc).to receive(:perform) do
          sends += 1
          described_class.new(account, now).send_reminders if sends == 1 # outra rodada no meio do envio
          instance_double(Conversation)
        end
        svc
      end
      travel_to(now) { described_class.new(account, now).send_reminders }
      expect(sends).to eq(1)
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'reminded_at')).to be_present
    end

    # guarda do caminho release_reminder! (o código antigo também não marcava quando o envio devolvia nil)
    it 'release_reminder!: lembrete que devolve nil deixa a marca livre (tenta de novo na próxima rodada)', :aggregate_failures do
      allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
        svc = m.call(**kw)
        allow(svc).to receive(:perform).and_return(nil)
        svc
      end
      travel_to(now) { described_class.new(account, now).send_reminders }
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'reminded_at')).to be_nil
      expect(settings.reload.agenda_config.dig('nps_survey_state', 'reminders')).to be_nil
    end

    it 'lembrete que LEVANTA erro no envio (sem mensagem gravada) solta a marca e a próxima rodada manda 1 vez', :aggregate_failures do
      sends = 0
      allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
        svc = m.call(**kw)
        allow(svc).to receive(:perform) do
          sends += 1
          raise 'Unsupported operation for this channel' if sends == 1

          instance_double(Conversation)
        end
        svc
      end
      travel_to(now) { described_class.new(account, now).send_reminders }
      expect(sends).to eq(1)
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'reminded_at')).to be_nil
      travel_to(now + 15.minutes) { described_class.new(account, now + 15.minutes).send_reminders }
      expect(sends).to eq(2)
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'reminded_at')).to be_present
    end
  end

  describe 'resposta' do
    let(:contact) { patient('Carlos Nota', '+5511911110010') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    before do
      contact.update!(additional_attributes: { described_class::MARK_KEY => { 'pending_at' => 1.day.ago.iso8601, 'task_ids' => [1] } })
    end

    def reply(text)
      msg = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: text)
      described_class.handle_reply(msg, contact.reload)
    end

    it 'o toque no botão grava a faixa, a etiqueta e a nota; nota alta não abre tarefa', :aggregate_failures do
      expect(reply('🟢 9 a 10')).to eq('9-10')
      contact.reload
      expect(contact.label_list).to include('nps-9-10')
      expect(contact.additional_attributes['nps']).to include('band' => '9-10', 'source' => 'pesquisa')
      expect(account.tasks.where(task_type: 'pos_op')).to be_empty
      expect(reply('🟡 5 a 6')).to be_nil # já respondeu
    end

    it 'nota baixa abre tarefa urgente; frase comum não é nota', :aggregate_failures do
      expect(reply('pingo de 3 a 4 vezes?')).to be_nil
      expect(reply('🟠 3 a 4')).to eq('3-4')
      task = account.tasks.find_by(task_type: 'pos_op')
      expect(task.priority).to eq('urgent')
      expect(task.title).to include('NPS 3 a 4')
      expect(contact.reload.label_list).to include('nps-3-4')
    end

    it 'nota 9–10 ganha agradecimento com o link do Google quando o Pós-operatório não está ao vivo', :aggregate_failures do
      reply('🟢 9 a 10')
      out = conversation.messages.where(message_type: :outgoing, private: false).last
      expect(out.content).to include(described_class::DEFAULT_LINKS['google_review_url'])
      expect(contact.reload.additional_attributes.dig(described_class::MARK_KEY, 'thanked_at')).to be_present
    end

    it 'com o Pós-operatório ao vivo, quem agradece é ele (nada automático)' do
      pos_op = { 'enabled' => true, 'mode' => 'live', 'inbox_ids' => [inbox.id] }
      CrmSetting.find_by(account: account).update!(ai_config: { 'agents' => { 'atendente_pos_op' => pos_op } })
      stub_const('Crm::ResponderAgentJob::LIVE_ENABLED', true)
      reply('🟢 9 a 10')
      expect(conversation.messages.where(message_type: :outgoing, private: false)).to be_empty
    end

    it 'sem pesquisa pendente, um "10" solto não vira nota' do
      contact.update!(additional_attributes: {})
      expect(reply('10')).to be_nil
    end

    it 'quem recebeu a pesquisa há pouco é do Atendente de Pós-operatório' do
      agents = { 'atendente_pos' => { 'enabled' => true, 'inbox_ids' => [inbox.id], 'no_card' => true },
                 'atendente_pos_op' => { 'enabled' => true, 'inbox_ids' => [inbox.id] } }
      expect(CrmListener.instance.send(:responder_owner_for, conversation, agents)).to eq('atendente_pos_op')
    end
  end
end
