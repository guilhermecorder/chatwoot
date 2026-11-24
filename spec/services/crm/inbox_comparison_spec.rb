require 'rails_helper'

# 🆚 item 413 — COMPARATIVO DE CAIXAS: a turma que chegou por cada caixa no
# período e o que virou dela, com base de comparação, quem atendeu e o custo.
RSpec.describe Crm::InboxComparison do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:insta) { create(:inbox, account: account, name: 'INSTAGRAM') }
  let(:insta2) { create(:inbox, account: account, name: 'INSTAGRAM 2') }
  let(:confirma) { create(:inbox, account: account, name: 'CONFIRMAÇÃO DE CONSULTA') }
  let!(:pipeline) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      ['Novos Contatos', 'Envio de Orçamento', 'Agendamento de Consulta'].each_with_index do |name, i|
        p.stages.create!(name: name, color: '#000', position: i)
      end
    end
  end
  let(:now) { ActiveSupport::TimeZone['America/Sao_Paulo'].now }
  let(:since) { (now - 6.days).beginning_of_day }
  let(:until_at) { now.end_of_day }
  let(:compare) { Crm::PeriodComparison.new(since, until_at) }

  before do
    travel_to Time.current.in_time_zone('America/Sao_Paulo').change(hour: 12)
    Rails.cache.clear
    Current.reset
    CrmSetting.create!(account: account, agenda_config: {}, ai_config: { 'agents' => { 'atendente_agendamento' => {
                         'enabled' => true, 'inbox_ids' => [insta.id, insta2.id], 'model' => 'gpt-6-luna',
                         'ab' => { 'enabled' => true, 'name' => 'Prompt novo', 'script_b' => 'v2', 'started_at' => (now - 3.days).iso8601,
                                   'inboxes' => { insta2.id.to_s => 'b' } }
                       } } })
  end

  after { Current.reset }

  def person(name, inbox, arrived, usage: nil, ad_id: nil)
    attrs = ad_id ? { 'meta_ads' => { 'source_id' => ad_id } } : {}
    create(:contact, account: account, name: name, created_at: arrived, additional_attributes: attrs).tap do |contact|
      # o anúncio fica carimbado no contato E na conversa (Crm::AdAttributionService)
      create(:conversation, account: account, inbox: inbox, contact: contact, created_at: arrived,
                            additional_attributes: attrs.merge(usage ? { Crm::AttendanceUsage::STAMP => usage } : {}))
    end
  end

  def enter(contact, stage_name, moment)
    stage = pipeline.stages.find_by(name: stage_name)
    card = Crm::Contact.find_by(contact: contact, pipeline: pipeline) ||
           Crm::Contact.new(contact: contact, pipeline: pipeline, stage: stage).tap { |c| c.save!(validate: false) }
    card.update_columns(stage_id: stage.id, updated_at: moment) # rubocop:disable Rails/SkipsModelValidations
    Crm::StageLog.create!(crm_contact_id: card.id, stage_id: stage.id, stage_name: stage.name, event_type: 'entered', entered_at: moment)
  end

  def say(contact, type, moment, sender: nil)
    conversation = contact.conversations.first
    Message.insert_all!([{ account_id: account.id, inbox_id: conversation.inbox_id, conversation_id: conversation.id, # rubocop:disable Rails/SkipsModelValidations
                           message_type: Message.message_types[type], content: 'oi', private: false,
                           sender_type: sender && 'User', sender_id: sender&.id, created_at: moment, updated_at: moment }])
  end

  def task(attrs = {})
    Task.create!({ account: account, creator: user, title: 'Consulta: Paciente', task_type: 'consulta' }.merge(attrs))
  end

  def report(invest: nil)
    described_class.new(account: account, since: since, until_at: until_at, compare: compare, invest: invest).call
  end

  def box(payload, inbox)
    payload[:caixas].find { |row| row[:inbox_id] == inbox.id }
  end

  # INSTAGRAM: Ana (orçamento → agendou → compareceu → cirurgia) e Bia (só chegou).
  # INSTAGRAM 2: Caio (respondeu, orçamento, não agendou). Semana passada: Duda agendou no INSTAGRAM.
  def scenario # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    luna = { 'respostas' => 2, 'chamadas' => 2, 'custo_usd' => 0.002, 'modelos' => { 'gpt-6-luna' => { 'n' => 2, 'usd' => 0.002 } },
             'roteiros' => { 'v1' => 2 } }
    sonnet = { 'respostas' => 1, 'chamadas' => 1, 'custo_usd' => 0.03, 'modelos' => { 'claude-sonnet-5' => { 'n' => 1, 'usd' => 0.03 } },
               'roteiros' => { 'v2' => 1 }, 'humano_at' => now.iso8601 }
    ana = person('Ana', insta, now - 2.days, usage: luna, ad_id: 'A1')
    bia = person('Bia', insta, now - 1.day)
    caio = person('Caio', insta2, now - 1.day, usage: sonnet, ad_id: 'A1')
    duda = person('Duda', insta, now - 9.days)
    say(ana, :incoming, now - 2.days)
    say(ana, :outgoing, now - 2.days + 4.minutes)
    say(ana, :incoming, now - 2.days + 10.minutes)
    say(caio, :incoming, now - 1.day)
    say(caio, :outgoing, now - 1.day + 30.minutes, sender: user)
    say(caio, :incoming, now - 1.day + 40.minutes)
    say(bia, :incoming, now - 1.day)
    enter(ana, 'Envio de Orçamento', now - 2.days + 20.minutes)
    enter(ana, 'Agendamento de Consulta', now - 2.days + 3.hours)
    enter(caio, 'Envio de Orçamento', now - 1.day + 1.hour)
    enter(duda, 'Agendamento de Consulta', now - 9.days + 1.hour)
    task(contact: ana, due_at: now - 1.hour, attendance: 'attended', surgery_indication: 'indicated', created_at: now - 2.days + 3.hours)
    task(contact: ana, task_type: 'cirurgia', title: 'Cirurgia: Ana', due_at: now + 5.days, created_at: now - 30.minutes)
  end

  it 'segue a turma de cada caixa, etapa por etapa, e compara com o período anterior', :aggregate_failures do
    scenario
    payload = report

    expect(box(payload, insta)[:funil]).to eq(chegaram: 2, responderam: 1, orcamento: 1, agendaram: 1, compareceram: 1,
                                              indicacoes: 1, cirurgias: 1)
    expect(box(payload, insta)[:anterior]).to include(chegaram: 1, agendaram: 1)
    expect(box(payload, insta2)[:funil]).to eq(chegaram: 1, responderam: 1, orcamento: 1, agendaram: 0, compareceram: 0,
                                               indicacoes: 0, cirurgias: 0)
    expect(payload[:total][:funil]).to include(chegaram: 3, agendaram: 1)
    expect(payload[:caixas].pluck(:nome)).to eq(['INSTAGRAM', 'INSTAGRAM 2'])
    expect(payload[:caixas].pluck(:cor).uniq.size).to eq(2)
    expect(payload[:financeiro]).to be(false)
    expect(box(payload, insta)[:custo]).to be_nil
  end

  it 'mede o tempo de resposta, o tempo até agendar e quem teve gente da equipe', :aggregate_failures do
    scenario
    payload = report

    expect(box(payload, insta)[:tempos]).to eq(primeira_resposta_min: 4.0, ate_agendar_h: 3.0, com_humano: 0)
    expect(box(payload, insta2)[:tempos]).to eq(primeira_resposta_min: 30.0, ate_agendar_h: nil, com_humano: 1)
  end

  it 'mostra quem atendeu de verdade (motor e Roteiro de cada conversa) e como a caixa está hoje', :aggregate_failures do
    scenario
    payload = report
    ia = box(payload, insta)[:ia]
    ia2 = box(payload, insta2)[:ia]

    expect(ia).to include(conversas: 2, com_registro: 1, atendidas: 1, respostas: 2, humano: 0, custo_usd: 0.002)
    expect(ia[:modelos]).to eq([{ id: 'gpt-6-luna', nome: 'GPT-6 Luna', conversas: 1 }])
    expect(ia[:roteiros]).to eq([{ id: 'v1', nome: 'Roteiro 1', conversas: 1 }])
    expect(ia2).to include(conversas: 1, atendidas: 1, humano: 1, custo_usd: 0.03, custo_por_conversa_usd: 0.03)
    expect(ia2[:roteiros]).to eq([{ id: 'v2', nome: 'Roteiro 2', conversas: 1 }])
    expect(box(payload, insta)[:config]).to eq([{ agente: 'atendente_agendamento', nome: 'Agendamento', modo: nil, motor: 'GPT-6 Luna',
                                                  motores_por_coluna: [], teste: nil }])
    expect(box(payload, insta2)[:config].first[:teste]).to eq(nome: 'Prompt novo', modo: 'b', roteiro_b: 'v2', motor_b: nil)
  end

  it 'diz em que coluna a turma está agora, de qual campanha veio e a linha do dia a dia', :aggregate_failures do
    scenario
    Crm::AdCreative.create!(account: account, ad_id: 'A1', campaign_id: 'C1', campaign_name: 'Réveillon sem óculos')
    payload = report
    row = box(payload, insta)

    expect(row[:colunas]).to eq([{ nome: 'Agendamento de Consulta', n: 1 }, { nome: 'Sem card no funil', n: 1 }])
    expect(row[:campanhas]).to eq([{ chegaram: 1, agendaram: 1, nome: 'Réveillon sem óculos' },
                                   { chegaram: 1, agendaram: 0, nome: 'Sem anúncio do Meta carimbado' }])
    expect(payload[:rotulos].size).to eq(7)
    expect(row[:serie][:chegaram].sum).to eq(2)
    expect(row[:serie][:agendaram].sum).to eq(1)
    expect(row[:serie][:taxa].compact).to eq([100.0, 0.0])
  end

  it 'reparte o gasto do Meta pelas caixas e calcula o custo por etapa (só com o financeiro)', :aggregate_failures do
    scenario
    Crm::AdCreative.create!(account: account, ad_id: 'A1', campaign_id: 'C1', campaign_name: 'Réveillon')
    Crm::AdInsight.create!(account: account, ad_id: 'A1', date: (now - 1.day).to_date, metrics: { 'spend' => 100 })
    Crm::AdInsight.create!(account: account, ad_id: 'SITE', date: now.to_date, metrics: { 'spend' => 50 })
    payload = report(invest: { meta_total: 150.0, meta_note: nil, google: nil, config: {} })

    expect(payload[:financeiro]).to be(true)
    expect(payload[:meta]).to eq(total: 150.0, sem_caixa: 50.0, metodo: 'anuncio', aviso: nil)
    expect(box(payload, insta)[:custo]).to include(investimento: 50.0, por_lead: 25.0, por_agendamento: 50.0, por_cirurgia: 50.0, ia_usd: 0.002)
    expect(box(payload, insta)[:custo][:partes]).to eq([{ origem: 'Meta Ads', valor: 50.0 }])
    expect(box(payload, insta2)[:custo]).to include(investimento: 50.0, por_lead: 50.0, por_agendamento: nil)
    expect(payload[:total][:investimento]).to eq(100.0)
  end

  it 'soma o Google e o valor informado nas caixas configuradas', :aggregate_failures do
    scenario
    config = { insta.id.to_s => { 'mode' => 'google_auto' }, insta2.id.to_s => { 'mode' => 'manual', 'monthly' => 304.4 } }
    payload = report(invest: { meta_total: nil, meta_note: 'Meta Ads não configurado em Integrações',
                               google: { configured: true, cost: 80.0 }, config: config })

    expect(payload[:meta]).to include(total: nil, aviso: 'Meta Ads não configurado em Integrações')
    expect(box(payload, insta)[:custo][:partes]).to eq([{ origem: 'Google (GA4)', valor: 80.0 }])
    expect(box(payload, insta2)[:custo][:partes].first[:origem]).to eq('Valor informado')
    expect(box(payload, insta2)[:custo][:investimento]).to be_within(0.5).of(70.0)
  end

  it 'a caixa de chegada é a primeira PORTA DE ENTRADA, mesmo se a pessoa falou antes numa operacional', :aggregate_failures do
    eva = create(:contact, account: account, name: 'Eva', created_at: now - 1.day)
    create(:conversation, account: account, inbox: confirma, contact: eva, created_at: now - 1.day)
    create(:conversation, account: account, inbox: insta2, contact: eva, created_at: now - 2.hours)
    payload = report

    expect(box(payload, insta2)[:funil][:chegaram]).to eq(1)
    expect(box(payload, insta2)[:porta]).to be(true)
    expect(box(payload, confirma)[:funil][:chegaram]).to eq(0) # aparece só pelas conversas abertas nela
    expect(box(payload, confirma)[:porta]).to be(false)
  end

  it 'deixa de fora o 🧪 Simulador e as caixas de parceiro', :aggregate_failures do
    simulator = create(:inbox, account: account, name: Crm::AgentSimulator::INBOX_NAME)
    partner = create(:inbox, account: account, name: 'OFTALMOFÁCIL')
    allow(Crm::PartnerGuard).to receive(:partner_inbox_ids).and_return([partner.id])
    person('Paciente de teste', simulator, now)
    person('Paciente do parceiro', partner, now)
    person('Gil', insta, now)

    expect(report[:caixas].pluck(:nome)).to eq(['INSTAGRAM'])
  end

  it 'a base de comparação só conta o que a turma de antes fez no MESMO prazo', :aggregate_failures do
    travel_to now.end_of_day - 1.minute # o período de agora ainda não teve folga
    duda = person('Duda', insta, now - 9.days)
    enter(duda, 'Agendamento de Consulta', now - 2.days) # agendou só DEPOIS de a semana dela acabar
    person('Hugo', insta, now - 1.day)
    payload = report

    expect(box(payload, insta)[:anterior]).to include(chegaram: 1, agendaram: 0)
  end

  it 'período sem ninguém devolve a lista vazia, sem quebrar' do
    expect(report).to include(caixas: [], total: include(funil: include(chegaram: 0)))
  end
end
