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
