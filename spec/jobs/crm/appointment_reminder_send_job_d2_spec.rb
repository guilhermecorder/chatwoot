require 'rails_helper'

# 📋 item 250 (26/09): régua D-2 — confirmação completa da consulta pela NOSSA Agenda
RSpec.describe Crm::AppointmentReminderSendJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:now) { tz.parse('2026-09-26 10:05') } # sábado
  let(:vars) { { '1' => '{{nome}}', '2' => '{{data}}', '3' => '{{hora}}', '4' => '{{valor}}' } }
  let(:tpl) { ->(name) { { 'name' => name, 'language' => 'en', 'category' => 'UTILITY', 'processed_params' => { 'body' => vars } } } }
  let(:d2_cfg) do
    { 'enabled' => true, 'hour' => 10, 'inbox_id' => inbox.id, 'mode' => 'live', 'default_value' => '150,00',
      'units' => { 'paulista' => { 'template_params' => tpl.call('confirmacao_consulta_paulista'), 'message_preview' => 'Paulista {{1}}' },
                   'tatuape' => { 'template_params' => tpl.call('confirmao_consulta_tatuape'), 'message_preview' => 'Tatuapé {{1}}' } } }
  end
  let!(:settings) { CrmSetting.create!(account: account, agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg } }) }

  def contact_named(name, phone)
    create(:contact, account: account, name: name, phone_number: phone)
  end

  def consulta(contact, at, unit: 'paulista', **extra)
    account.tasks.create!({ title: "Consulta: #{contact.name}", task_type: 'consulta', modality: 'avaliacao', unit: unit,
                            due_at: tz.parse(at), contact: contact, phone: contact.phone_number, creator: admin }.merge(extra))
  end

  before do
    admin
    allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
      svc = m.call(**kw)
      allow(svc).to receive(:perform).and_return(instance_double(Conversation))
      svc
    end
  end

  it 'dN = hoje + N; com a ponte ligada, na sexta o de 1–2 dias antes adianta a segunda', :aggregate_failures do
    friday = tz.parse('2026-09-25 10:00')
    bridge = { 'weekend_bridge' => true }
    expect(described_class.target_dates('d2', bridge, friday)).to eq([Date.new(2026, 9, 27), Date.new(2026, 9, 28)])
    expect(described_class.target_dates('d1', bridge, friday)).to eq([Date.new(2026, 9, 26), Date.new(2026, 9, 28)])
    expect(described_class.target_dates('d2', {}, friday)).to eq([Date.new(2026, 9, 27)])
    expect(described_class.target_dates('d0', bridge, friday)).to eq([Date.new(2026, 9, 25)])
    expect(described_class.target_dates('d5', {}, now)).to eq([Date.new(2026, 10, 1)])
    expect(described_class.target_dates('d2', {}, now)).to eq([Date.new(2026, 9, 28)])
  end

  # item 310 (02/10, pedido dele): "a mensagem modelo será enviada através da caixa de entrada em que a conversa já existe"
  describe 'caixa do envio = a caixa em que o paciente já conversa' do
    let(:instagram) { create(:inbox, account: account, name: 'INSTAGRAM') }
    let(:sent_by) { [] }

    # item 314: a outra caixa tem os SEUS modelos escolhidos (lista daquele número)
    let(:ig_templates) do
      { 'units' => { 'paulista' => { 'template_params' => tpl.call('confirma_ig_paulista'), 'message_preview' => 'IG Paulista {{1}}' },
                     'tatuape' => { 'template_params' => tpl.call('confirma_ig_tatuape'), 'message_preview' => 'IG Tatuapé {{1}}' } } }
    end
    let(:d2_two_inboxes) { d2_cfg.merge('inbox_ids' => [instagram.id], 'by_inbox' => { instagram.id.to_s => ig_templates }) }

    before do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_two_inboxes } })
      allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
        sent_by << [args[1].name, args[3]['processed_params']['body']['1']]
        m.call(*args)
      end
    end

    it 'quem conversa pelo Instagram recebe pelo Instagram; quem não tem conversa recebe pela caixa padrão', :aggregate_failures do
      insta = contact_named('Veio Do Instagram', '+5511999990061')
      google = contact_named('Veio Do Google', '+5511999990062')
      novo = contact_named('Sem Conversa', '+5511999990063')
      create(:conversation, account: account, inbox: instagram, contact: insta)
      create(:conversation, account: account, inbox: inbox, contact: google)
      [insta, google, novo].each_with_index { |c, i| consulta(c, "2026-09-28 09:#{i}0") }

      described_class.perform_now(now)

      expect(sent_by).to contain_exactly(['INSTAGRAM', 'Veio Do Instagram'], [inbox.name, 'Veio Do Google'], [inbox.name, 'Sem Conversa'])
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['sent'].to_h { |e| [e['name'], e['inbox']] }).to include('Veio Do Instagram' => 'INSTAGRAM', 'Sem Conversa' => inbox.name)
      mark = insta.reload.additional_attributes['cevico_appt_reminders'].values.first
      expect(mark['d2_inbox']).to eq(instagram.id) # o reforço sai pela mesma caixa
    end

    it 'com conversa nas duas caixas, vale a mais recente', :aggregate_failures do
      paciente = contact_named('Duas Caixas', '+5511999990064')
      create(:conversation, account: account, inbox: instagram, contact: paciente, last_activity_at: 10.days.ago)
      create(:conversation, account: account, inbox: inbox, contact: paciente, last_activity_at: 1.day.ago)
      consulta(paciente, '2026-09-28 10:00')

      described_class.perform_now(now)
      expect(sent_by).to eq([[inbox.name, 'Duas Caixas']])
    end

    it 'sem a outra caixa marcada, tudo continua saindo pela caixa do lembrete' do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg } })
      insta = contact_named('Veio Do Instagram', '+5511999990065')
      create(:conversation, account: account, inbox: instagram, contact: insta)
      consulta(insta, '2026-09-28 11:00')

      described_class.perform_now(now)
      expect(sent_by).to eq([[inbox.name, 'Veio Do Instagram']])
    end

    # item 314 (02/10; "quero selecionar exatamente a mensagem modelo correta daquela caixa de entrada")
    it 'pela outra caixa sai o modelo escolhido PARA ELA; sem modelo da unidade lá, sai pela caixa padrão', :aggregate_failures do
      names = []
      allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
        names << [args[1].name, args[3]['name']]
        m.call(*args)
      end
      ig_only_paulista = { 'units' => { 'paulista' => ig_templates['units']['paulista'] } }
      d2 = d2_cfg.merge('inbox_ids' => [instagram.id], 'by_inbox' => { instagram.id.to_s => ig_only_paulista })
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2 } })
      insta_paulista = contact_named('Insta Paulista', '+5511999990071')
      insta_tatuape = contact_named('Insta Tatuape', '+5511999990072')
      google = contact_named('Google Paulista', '+5511999990073')
      create(:conversation, account: account, inbox: instagram, contact: insta_paulista)
      create(:conversation, account: account, inbox: instagram, contact: insta_tatuape)
      create(:conversation, account: account, inbox: inbox, contact: google)
      consulta(insta_paulista, '2026-09-28 09:00')
      consulta(insta_tatuape, '2026-09-28 09:30', unit: 'tatuape')
      consulta(google, '2026-09-28 10:00')

      described_class.perform_now(now)

      expect(names).to contain_exactly(%w[INSTAGRAM confirma_ig_paulista],       # modelo escolhido para a caixa
                                       [inbox.name, 'confirmao_consulta_tatuape'], # Instagram sem modelo da Tatuapé → caixa padrão
                                       [inbox.name, 'confirmacao_consulta_paulista'])
    end

    it 'reforço pela outra caixa: só o modelo do reforço escolhido para ela (sem ele, nil)', :aggregate_failures do
      job = described_class.new
      outra = instance_double(Inbox, id: 77)
      proprio = { 'template_params' => { 'name' => 'reforco_ig' }, 'message_preview' => 'IG' }

      expect(job.send(:followup_template_in, { 'by_inbox' => {} }, outra)).to be_nil
      expect(job.send(:followup_template_in, { 'by_inbox' => { '77' => { 'followup' => proprio } } }, outra)).to eq(proprio)
    end
  end

  # varredura 03/10: bugs achados na revisão
  describe 'varredura 03/10' do
    let(:sources) { [] }

    before do
      allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
        sources << args
        m.call(*args)
      end
    end

    it 'consulta REMARCADA recebe o lembrete de novo (e as marcas antigas, inclusive o "sim", são zeradas)', :aggregate_failures do
      maria = contact_named('Maria Remarcada', '+5511999990081')
      task = consulta(maria, '2026-09-28 09:00')
      described_class.perform_now(now)
      expect(sources.size).to eq(1)

      # confirmou a data antiga; a equipe remarcou para a semana seguinte
      task.update!(confirmed_at: Time.current)
      task.update!(due_at: tz.parse('2026-10-05 09:00'))
      expect(task.reload.confirmed_at).to be_nil # modelo: remarcar zera a confirmação

      described_class.perform_now(tz.parse('2026-10-03 10:05')) # D-2 da nova data
      expect(sources.size).to eq(2)
      marks = maria.reload.additional_attributes.dig('cevico_appt_reminders', task.id.to_s)
      expect(marks['d2_due']).to eq(task.due_at.iso8601)

      described_class.perform_now(tz.parse('2026-10-03 10:20')) # mesma hora: não repete
      expect(sources.size).to eq(2)
    end

    it 'rodadas seguintes da mesma hora não apagam a lista de quem recebeu', :aggregate_failures do
      consulta(contact_named('Primeira Rodada', '+5511999990082'), '2026-09-28 09:00')
      described_class.perform_now(now)
      described_class.perform_now(tz.parse('2026-09-26 10:35'))

      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['sent'].map { |e| e['name'] }).to eq(['Primeira Rodada'])
      expect(sources.size).to eq(1)
    end

    it 'sai na hora seguinte se a rodada da hora certa foi perdida; quem recusou não recebe', :aggregate_failures do
      consulta(contact_named('Hora Perdida', '+5511999990083'), '2026-09-28 09:00')
      consulta(contact_named('Recusou', '+5511999990084'), '2026-09-28 11:00', declined_at: Time.current)
      described_class.perform_now(tz.parse('2026-09-26 11:40'))

      expect(sources.map { |a| a[3].dig('processed_params', 'body', '1') }).to eq(['Hora Perdida'])
    end

    it 'falta de modelo é decidida DEPOIS do roteamento: a caixa do paciente tem o modelo da unidade, a padrão não' do
      instagram = create(:inbox, account: account, name: 'INSTAGRAM')
      ig = { 'units' => { 'tatuape' => { 'template_params' => tpl.call('confirma_ig_tatuape'), 'message_preview' => 'IG {{1}}' } } }
      so_paulista = d2_cfg.merge('units' => d2_cfg['units'].slice('paulista'), 'inbox_ids' => [instagram.id],
                                 'by_inbox' => { instagram.id.to_s => ig })
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => so_paulista } })
      paciente = contact_named('Insta Tatuape', '+5511999990085')
      create(:conversation, account: account, inbox: instagram, contact: paciente)
      consulta(paciente, '2026-09-28 09:00', unit: 'tatuape')

      described_class.perform_now(now)
      expect(sources.map { |a| [a[1].name, a[3]['name']] }).to eq([%w[INSTAGRAM confirma_ig_tatuape]])
    end

    it 'a caixa do paciente é a em que ELE escreveu por último — mensagem automática não puxa a caixa' do
      instagram = create(:inbox, account: account, name: 'INSTAGRAM')
      ig = { 'units' => { 'paulista' => { 'template_params' => tpl.call('confirma_ig_paulista'), 'message_preview' => 'IG {{1}}' } } }
      d2 = d2_cfg.merge('inbox_ids' => [instagram.id], 'by_inbox' => { instagram.id.to_s => ig })
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2 } })
      paciente = contact_named('Fala No Insta', '+5511999990086')
      no_insta = create(:conversation, account: account, inbox: instagram, contact: paciente, last_activity_at: 3.days.ago)
      no_google = create(:conversation, account: account, inbox: inbox, contact: paciente, last_activity_at: 1.hour.ago) # campanha ontem
      create(:message, account: account, inbox: instagram, conversation: no_insta, message_type: :incoming, content: 'oi', created_at: 3.days.ago)
      create(:message, account: account, inbox: inbox, conversation: no_google, message_type: :outgoing, content: 'campanha',
                       created_at: 1.hour.ago, sender: admin)
      consulta(paciente, '2026-09-28 09:00')

      described_class.perform_now(now)
      expect(sources.map { |a| [a[1].name, a[3]['name']] }).to eq([%w[INSTAGRAM confirma_ig_paulista]])
    end
  end

  # item 312 (02/10, pedido dele): "preciso poder escolher a coluna em que isso será enviado"
  describe 'colunas do CRM que recebem' do
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil', position: 1) }
    let(:agendada) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 1, color: '#059669') }
    let(:orcamento) { Crm::Stage.create!(pipeline: pipeline, name: 'Envio de Orçamento', position: 2, color: '#2563EB') }

    it 'com coluna marcada, só recebe quem tem o card nela; os outros vão para as puladas com o motivo', :aggregate_failures do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('stage_ids' => [agendada.id]) } })
      na_coluna = contact_named('Na Coluna', '+5511999990071')
      em_outra = contact_named('Em Outra', '+5511999990072')
      sem_card = contact_named('Sem Card', '+5511999990073')
      Crm::Contact.create!(contact: na_coluna, pipeline: pipeline, stage: agendada)
      Crm::Contact.create!(contact: em_outra, pipeline: pipeline, stage: orcamento)
      [na_coluna, em_outra, sem_card].each_with_index { |c, i| consulta(c, "2026-09-28 09:#{i}0") }

      described_class.perform_now(now)

      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['sent'].pluck('name')).to eq(['Na Coluna'])
      expect(state['skipped'].to_h { |e| [e['name'], e['why']] }).to eq(
        'Em Outra' => 'card na coluna Envio de Orçamento', 'Sem Card' => 'sem card no CRM'
      )
    end

    it 'sem coluna marcada, todos recebem (como era)' do
      qualquer = contact_named('Qualquer Coluna', '+5511999990074')
      Crm::Contact.create!(contact: qualquer, pipeline: pipeline, stage: orcamento)
      consulta(qualquer, '2026-09-28 09:00')

      described_class.perform_now(now)
      expect(settings.reload.agenda_config.dig('appointment_reminders_state', 'd2', 'sent').pluck('name')).to eq(['Qualquer Coluna'])
    end
  end

  # item 308: no N8N todo evento do Google Agenda recebia; aqui a consulta sem paciente vinculado
  # sumia sem aviso — agora aparece em "puladas" com o motivo, para a equipe completar o cadastro
  it 'consulta sem paciente vinculado aparece nas puladas com o motivo (não some em silêncio)', :aggregate_failures do
    ok = contact_named('Com Cadastro', '+5511999990051')
    consulta(ok, '2026-09-28 09:00')
    account.tasks.create!(title: 'Retorno: Sem Telefone', task_type: 'consulta', modality: 'retorno', unit: 'paulista',
                          due_at: tz.parse('2026-09-28 09:15'), creator: admin)
    account.tasks.create!(title: 'Retorno: Telefone Solto', task_type: 'consulta', modality: 'retorno', unit: 'tatuape',
                          due_at: tz.parse('2026-09-28 09:30'), phone: '11 3333-0000', creator: admin)

    described_class.perform_now(now)

    state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
    # item 319: com telefone, o cadastro é criado e o lembrete sai; só quem não tem telefone fica de fora
    expect(state['sent'].pluck('name')).to contain_exactly('Com Cadastro', 'Telefone Solto')
    expect(state['skipped'].to_h { |s| [s['name'], s['why']] }).to eq('Sem Telefone' => 'sem telefone')
  end

  # item 319 (03/10): "precisamos normalizar a forma como o telefone é compreendido… precisa poder sem o +55"
  describe 'consulta com telefone e sem paciente vinculado' do
    def solta(name, phone, at: '2026-09-28 09:30')
      account.tasks.create!(title: "Consulta: #{name}", task_type: 'consulta', modality: 'avaliacao', unit: 'paulista',
                            due_at: tz.parse(at), phone: phone, creator: admin)
    end

    it 'cria o paciente com o telefone normalizado (sem +55, sem DDD, com zero) e envia', :aggregate_failures do
      a = solta('Sem Mais 55', '(11) 98888-0001')
      b = solta('Sem DDD', '98888-0002', at: '2026-09-28 09:45')
      c = solta('Com Zero', '011 98888-0003', at: '2026-09-28 10:00')

      described_class.perform_now(now)

      expect([a, b, c].map { |t| t.reload.contact&.phone_number }).to eq(%w[+5511988880001 +5511988880002 +5511988880003])
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['sent'].pluck('name')).to contain_exactly('Sem Mais 55', 'Sem DDD', 'Com Zero')
      expect(state['skipped']).to be_empty
    end

    it 'acha o cadastro que nasceu DEPOIS do agendamento, em vez de criar outro' do
      task = solta('Chegou Depois', '11 97777-0001')
      later = contact_named('Chegou Depois', '+5511977770001')

      expect { described_class.perform_now(now) }.not_to(change { account.contacts.count })
      expect(task.reload.contact_id).to eq(later.id)
    end

    it 'em sombra não cria nada: aparece nas puladas com o motivo', :aggregate_failures do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('mode' => 'shadow') } })
      solta('Só Sombra', '11 96666-0001')

      expect { described_class.perform_now(now) }.not_to(change { account.contacts.count })
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['skipped'].to_h { |s| [s['name'], s['why']] }).to eq('Só Sombra' => 'telefone sem cadastro de paciente')
    end

    it 'telefone que não dá para entender continua nas puladas' do
      solta('Número Torto', '12345')
      described_class.perform_now(now)
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['skipped'].to_h { |s| [s['name'], s['why']] }).to eq('Número Torto' => 'telefone sem cadastro de paciente')
    end
  end

  # item 319: "nos espaços {{1}} etc, devo deixar sem nenhum preenchimento, para que pegue os contatos da agenda, correto?"
  it 'variável em branco no card vale o dado da Agenda (nome, data, hora, valor)' do
    bodies = []
    allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
      bodies << args[3]['processed_params']['body']
      m.call(*args)
    end
    blank = { 'name' => 'confirmacao_consulta_paulista', 'language' => 'pt_BR',
              'processed_params' => { 'body' => { '1' => '', '2' => ' ' } } }
    cfg = d2_cfg.merge('units' => { 'paulista' => { 'template_params' => blank,
                                                    'message_preview' => 'Paciente:{{1}} Data:{{2}} Horário:{{3}} Valor:{{4}}' } })
    settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => cfg } })
    consulta(contact_named('Julia Adania', '+5511999990071'), '2026-09-28 08:45')

    described_class.perform_now(now)

    expect(bodies).to eq([{ '1' => 'Julia Adania', '2' => '28/09/2026', '3' => '08:45', '4' => '150,00' }])
  end

  # item 320 (03/10): "a possibilidade de um envio manual, como esses casos, seria ótimo eu fazer um reenvio"
  describe 'envio manual pelo card' do
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil', position: 1) }
    let(:orcamento) { Crm::Stage.create!(pipeline: pipeline, name: 'Envio de Orçamento', position: 1, color: '#059669') }
    let(:agendado) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 2, color: '#0F5FA6') }
    let(:afternoon) { tz.parse('2026-09-26 16:20') } # fora da hora do lembrete (10h)
    let(:state) { -> { settings.reload.agenda_config.dig('appointment_reminders_state', 'd2') } }

    def in_stage(name, phone, stage, at)
      person = contact_named(name, phone)
      Crm::Contact.create!(contact: person, pipeline: pipeline, stage: stage)
      consulta(person, at)
    end

    before do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('stage_ids' => [agendado.id]) } })
    end

    it 'o lembrete inteiro fora da hora: manda para quem falta, sem repetir quem já recebeu', :aggregate_failures do
      in_stage('Já Recebeu', '+5511999990091', agendado, '2026-09-28 09:00')
      described_class.perform_now(now)
      in_stage('Marcou Depois', '+5511999990092', agendado, '2026-09-28 09:15')

      result = described_class.new.run_manual(account, 'd2', now: afternoon)

      expect(result).to include(ok: true, sent: 1, skipped: 0)
      expect(state.call['sent'].pluck('name')).to eq(['Já Recebeu', 'Marcou Depois'])
    end

    it 'um paciente: sai mesmo com o card fora das colunas marcadas, e sai das puladas', :aggregate_failures do
      fora = in_stage('Card No Orçamento', '+5511999990093', orcamento, '2026-09-28 09:30')
      described_class.perform_now(now)
      expect(state.call['skipped'].pluck('why')).to eq(['card na coluna Envio de Orçamento'])

      result = described_class.new.run_manual(account, 'd2', task_id: fora.id, now: afternoon)

      expect(result).to include(ok: true, sent: 1)
      expect(state.call['skipped']).to be_empty
      expect(state.call['sent'].last).to include('name' => 'Card No Orçamento', 'manual' => true)
    end

    it 'reenvio: quem já recebeu recebe de novo quando a equipe pede', :aggregate_failures do
      task = in_stage('Mensagem Falhou', '+5511999990094', agendado, '2026-09-28 09:45')
      described_class.perform_now(now)
      expect(Crm::SendTemplateService).to have_received(:new).once

      result = described_class.new.run_manual(account, 'd2', task_id: task.id, now: afternoon)

      expect(result).to include(ok: true, sent: 1)
      expect(Crm::SendTemplateService).to have_received(:new).twice
      expect(state.call['sent'].pluck('name')).to eq(['Mensagem Falhou'])
    end

    it 'não envia com o lembrete desligado, em sombra (um paciente) ou para consulta cancelada', :aggregate_failures do
      task = in_stage('Cancelada', '+5511999990095', agendado, '2026-09-28 10:00')
      task.update!(canceled_at: Time.current)
      expect(described_class.new.run_manual(account, 'd2', task_id: task.id, now: afternoon)).to include(ok: false)
      expect(described_class.new.run_manual(account, 'd9', now: afternoon)).to include(ok: false)

      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('mode' => 'shadow') } })
      expect(described_class.new.run_manual(account, 'd2', task_id: task.id, now: afternoon)[:error]).to match(/sombra/)
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('enabled' => false) } })
      expect(described_class.new.run_manual(account, 'd2', now: afternoon)[:error]).to match(/Ligue/)
      expect(Crm::SendTemplateService).not_to have_received(:new)
    end
  end

  # item 319: às 11:45 ele viu "0 enviada(s)" — os envios tinham saído às 10h
  it 'a lista de enviadas do dia vai somando entre as rodadas (não zera na hora seguinte)', :aggregate_failures do
    consulta(contact_named('Primeira Rodada', '+5511999990081'), '2026-09-28 09:00')
    described_class.perform_now(now)
    consulta(contact_named('Segunda Rodada', '+5511999990082'), '2026-09-28 09:15')
    described_class.perform_now(tz.parse('2026-09-26 11:45'))

    state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
    expect(state['sent'].pluck('name')).to eq(['Primeira Rodada', 'Segunda Rodada'])
  end

  it 'vários lembretes ao mesmo tempo: 2 dias antes e no dia, cada um com sua hora; interruptor geral desliga tudo', :aggregate_failures do
    no_dia = { 'enabled' => true, 'hour' => 7, 'inbox_id' => inbox.id, 'mode' => 'live',
               'template_params' => tpl.call('lembrete_d0_hoje'), 'message_preview' => 'Hoje {{1}}' }
    settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg, 'd0' => no_dia } })
    hoje = contact_named('Paciente De Hoje', '+5511999990041')
    depois = contact_named('Paciente De Segunda', '+5511999990042')
    consulta(hoje, '2026-09-26 15:00', confirmed_at: Time.current) # confirmada também recebe o do dia
    consulta(depois, '2026-09-28 09:00')

    sources = []
    allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
      sources << args[3]['name']
      m.call(*args)
    end
    described_class.perform_now(tz.parse('2026-09-26 07:10'))
    expect(sources).to eq(['lembrete_d0_hoje'])
    described_class.perform_now(now)
    expect(sources).to eq(%w[lembrete_d0_hoje confirmacao_consulta_paulista])
    state = settings.reload.agenda_config['appointment_reminders_state']
    expect(state.keys).to contain_exactly('d0', 'd2')

    settings.update!(agenda_config: settings.agenda_config.merge('appointment_confirmation' => { 'enabled' => false }))
    consulta(contact_named('Outra De Segunda', '+5511999990043'), '2026-09-28 11:00')
    described_class.perform_now(now + 5.minutes)
    expect(sources.size).to eq(2)
  end

  it 'lembrete antigo sem modo continua AO VIVO (nada muda para quem já usava a véspera)' do
    legacy = { 'enabled' => true, 'hour' => 10, 'inbox_id' => inbox.id, 'template_params' => tpl.call('lembrete_d1_confirma') }
    settings.update!(agenda_config: { 'appointment_reminders' => { 'd1' => legacy } })
    consulta(contact_named('Paciente Véspera', '+5511999990051'), '2026-09-27 09:00', modality: 'exames')
    expect(Crm::SendTemplateService).to receive(:new).once.and_call_original
    described_class.perform_now(now)
  end

  it 'AO VIVO: manda o modelo da unidade certa com nome, data, hora e valor preenchidos; pula parceiro e quem já confirmou', :aggregate_failures do
    maria = contact_named('Maria Paulista', '+5511999990001')
    joao = contact_named('João Tatuapé', '+5511999990002')
    ana = contact_named('Ana Confirmada', '+5511999990003')
    consulta(maria, '2026-09-28 09:00', description: 'Valor: 250,00')
    consulta(joao, '2026-09-28 14:30', unit: 'tatuape')
    consulta(ana, '2026-09-28 11:00', confirmed_at: Time.current)
    consulta(contact_named('Hoje Não', '+5511999990004'), '2026-09-27 09:00') # D-1, não é desta régua
    partner = contact_named('Parceiro', '+5511999990005')
    consulta(partner, '2026-09-28 10:00', source: 'oftalmofacil', source_detail: 'CLINICA X', external_ref: 'p1')

    sources = []
    allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
      sources << args
      m.call(*args)
    end
    described_class.perform_now(now)

    names = sources.map { |s| s[3]['name'] }
    expect(names).to contain_exactly('confirmacao_consulta_paulista', 'confirmao_consulta_tatuape')
    paulista = sources.find { |s| s[3]['name'] == 'confirmacao_consulta_paulista' }
    expect(paulista[3].dig('processed_params', 'body')).to eq('1' => 'Maria Paulista', '2' => '28/09/2026', '3' => '09:00', '4' => '250,00')
    tatuape = sources.find { |s| s[3]['name'] == 'confirmao_consulta_tatuape' }
    expect(tatuape[3].dig('processed_params', 'body')['4']).to eq('150,00')
    expect(maria.reload.additional_attributes.dig('cevico_appt_reminders', account.tasks.find_by(contact: maria).id.to_s, 'd2')).to be_present

    state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
    expect(state['mode']).to eq('live')
    expect(state['sent'].map { |e| e['name'] }).to contain_exactly('Maria Paulista', 'João Tatuapé')
    expect(state['skipped'].map { |e| e['why'] }).to include('paciente de parceiro (cerca)')
  end

  it 'SOMBRA: não manda nada, só registra quem receberia', :aggregate_failures do
    settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('mode' => 'shadow') } })
    maria = contact_named('Maria Sombra', '+5511999990011')
    consulta(maria, '2026-09-28 09:00')

    expect(Crm::SendTemplateService).not_to receive(:new)
    described_class.perform_now(now)

    state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
    expect(state['mode']).to eq('shadow')
    expect(state['sent'].first).to include('name' => 'Maria Sombra', 'unit' => 'Av. Paulista', 'template' => 'confirmacao_consulta_paulista')
    expect(maria.reload.additional_attributes).not_to include('cevico_appt_reminders')
  end

  it 'na mesma hora não repete; fora da hora não roda', :aggregate_failures do
    maria = contact_named('Maria Uma Vez', '+5511999990021')
    consulta(maria, '2026-09-28 09:00')
    expect(Crm::SendTemplateService).to receive(:new).once.and_call_original
    described_class.perform_now(now)
    described_class.perform_now(now + 20.minutes)
    described_class.perform_now(tz.parse('2026-09-26 13:00'))
  end

  it 'consulta sem unidade com modelo não é enviada e aparece como pulada' do
    maria = contact_named('Maria Online', '+5511999990031')
    consulta(maria, '2026-09-28 09:00', unit: 'online')
    described_class.perform_now(now)
    state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
    expect(state['skipped'].first).to include('why' => 'sem modelo para Online')
  end

  describe 'pacientes do Oftalmofácil (cerca liberada por UMA caixa)' do
    let(:of_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
    let(:partner_cfg) do
      { 'enabled' => true, 'inbox_id' => of_inbox.id,
        'template_params' => tpl.call('confirmacao_oftalmofacil').merge('processed_params' => { 'body' => { '1' => '{{nome}}', '2' => '{{parceiro}}' } }),
        'message_preview' => 'Olá {{1}}, {{2}}' }
    end
    let!(:parceiro) { contact_named('Paciente Parceiro', '+5511999990051') }
    let!(:maria) { contact_named('Maria Cevico', '+5511999990052') }

    before do
      consulta(parceiro, '2026-09-28 10:00', source: 'oftalmofacil', source_detail: 'CLINICA X', external_ref: 'p51')
      consulta(maria, '2026-09-28 09:00')
    end

    it 'ligado: parceiro recebe pela caixa liberada, com o modelo dela; CEVICO segue pela caixa de sempre', :aggregate_failures do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('partner' => partner_cfg) } })
      sources = []
      allow(Crm::TemplateSource).to receive(:new).and_wrap_original do |m, *args|
        sources << args
        m.call(*args)
      end
      described_class.perform_now(now)

      of = sources.find { |s| s[3]['name'] == 'confirmacao_oftalmofacil' }
      expect(of[1]).to eq(of_inbox)
      expect(of[3].dig('processed_params', 'body')).to eq('1' => 'Paciente Parceiro', '2' => 'CLINICA X')
      cevico = sources.find { |s| s[3]['name'] == 'confirmacao_consulta_paulista' }
      expect(cevico[1]).to eq(inbox)
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['sent'].find { |e| e['name'] == 'Paciente Parceiro' }).to include('partner' => 'CLINICA X')
      expect(parceiro.reload.additional_attributes['cevico_appt_reminders']).to be_present
    end

    it 'sem modelo próprio, parceiro é pulado (nunca usa o modelo da CEVICO)' do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('partner' => partner_cfg.except('template_params')) } })
      described_class.perform_now(now)
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['skipped'].map { |e| e['why'] }).to include('Oftalmofácil: sem modelo')
    end

    it 'desligado: continua pulado pela cerca' do
      settings.update!(agenda_config: { 'appointment_reminders' => { 'd2' => d2_cfg.merge('partner' => partner_cfg.merge('enabled' => false)) } })
      described_class.perform_now(now)
      state = settings.reload.agenda_config.dig('appointment_reminders_state', 'd2')
      expect(state['skipped'].map { |e| e['why'] }).to include('paciente de parceiro (cerca)')
      expect(state['sent'].map { |e| e['name'] }).to eq(['Maria Cevico'])
    end
  end
end
