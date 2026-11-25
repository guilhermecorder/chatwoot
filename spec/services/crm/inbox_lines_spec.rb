require 'rails_helper'

# 📈 item 418 — MINI GRÁFICOS DE LINHA do Comparativo de caixas: a mesma turma
# do Crm::InboxComparison, em média móvel, por caixa, campanha e criativo.
RSpec.describe Crm::InboxLines do
  let(:account) { create(:account) }
  let(:insta) { create(:inbox, account: account, name: 'INSTAGRAM') }
  let(:google) { create(:inbox, account: account, name: 'GOOGLE') }
  let!(:pipeline) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      ['Novos Contatos', 'Envio de Orçamento', 'Agendamento de Consulta'].each_with_index do |name, i|
        p.stages.create!(name: name, color: '#000', position: i)
      end
    end
  end
  let(:now) { ActiveSupport::TimeZone['America/Sao_Paulo'].now }

  before do
    travel_to Time.current.in_time_zone('America/Sao_Paulo').change(hour: 12)
    Rails.cache.clear
    Current.reset
    CrmSetting.create!(account: account, agenda_config: {})
    Crm::AdCreative.create!(account: account, ad_id: 'A1', ad_name: 'Gancho policial', campaign_id: 'C1', campaign_name: 'Concurso PM')
    Crm::AdCreative.create!(account: account, ad_id: 'A2', ad_name: 'Gancho edital', campaign_id: 'C1', campaign_name: 'Concurso PM')
  end

  after { Current.reset }

  def person(inbox, arrived, ad_id: nil, booked: false)
    attrs = ad_id ? { 'meta_ads' => { 'source_id' => ad_id } } : {}
    contact = create(:contact, account: account, created_at: arrived, additional_attributes: attrs)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: arrived, additional_attributes: attrs)
    return contact unless booked

    stage = pipeline.stages.find_by(name: 'Agendamento de Consulta')
    card = Crm::Contact.new(contact: contact, pipeline: pipeline, stage: stage).tap { |c| c.save!(validate: false) }
    Crm::StageLog.create!(crm_contact_id: card.id, stage_id: stage.id, stage_name: stage.name, event_type: 'entered',
                          entered_at: arrived + 30.minutes)
    contact
  end

  def lines(since, until_at)
    described_class.new(account: account, since: since, until_at: until_at, compare: Crm::PeriodComparison.new(since, until_at)).call
  end

  describe 'com 7 dias (dia a dia, média móvel de 7 dias)' do
    let(:since) { (now - 6.days).beginning_of_day }
    let(:payload) { lines(since, now.end_of_day) }

    before do
      # antes do período (só entra na folga da linha): 4 pelo A1, 2 agendaram
      4.times { |i| person(insta, now - 8.days, ad_id: 'A1', booked: i < 2) }
      # no período: 6 pelo A1 (1 agendou), 2 pelo A2 (2 agendaram), 5 sem anúncio no GOOGLE (1 agendou)
      6.times { |i| person(insta, now - 2.days, ad_id: 'A1', booked: i.zero?) }
      2.times { person(insta, now - 1.day, ad_id: 'A2', booked: true) }
      5.times { |i| person(google, now - 1.day, booked: i.zero?) }
      # a base de comparação (7 dias anteriores): os 4 de cima + 6 que não agendaram
      6.times { person(insta, now - 10.days, ad_id: 'A1') }
    end

    it 'escolhe o balde pelo tamanho do período', :aggregate_failures do
      expect(payload[:regime]).to include(balde: 'dia', janela: 7, texto: 'média móvel de 7 dias')
      expect(payload[:rotulos].size).to eq(7)
      expect(payload[:rotulos].last).to eq(now.strftime('%d/%m'))
    end

    it 'soma no cartão só quem chegou no período (bate com o Lado a lado)', :aggregate_failures do
      caixa = payload[:caixas].find { |row| row[:inbox_id] == insta.id }

      expect(caixa).to include(nome: 'INSTAGRAM', chegaram: 8, agendaram: 3, taxa: 37.5)
      expect(caixa[:chegaram_por].sum).to eq(8)
      expect(caixa[:anterior]).to eq(chegaram: 10, agendaram: 2)
    end

    it 'usa a folga de antes do período para a linha já nascer com a janela cheia', :aggregate_failures do
      linha = payload[:caixas].find { |row| row[:inbox_id] == insta.id }[:linha]

      # 6 dias atrás: a janela pega os 10 de antes do período (2 agendaram)
      expect(linha[0]).to eq(20.0)
      # 3 dias atrás: a janela só tem os 4 de 8 dias atrás → pouca gente, sem ponto
      expect(linha[3]).to be_nil
      # 2 dias atrás: 4 de antes (2 agendaram) + 6 do dia (1 agendou) = 3 de 10
      expect(linha[4]).to eq(30.0)
      # hoje: os 4 de 8 dias atrás já saíram da janela → 3 de 8
      expect(linha[6]).to eq(37.5)
    end

    it 'separa por campanha e, dentro dela, por criativo', :aggregate_failures do
      campanha = payload[:campanhas].find { |row| row[:nome] == 'Concurso PM' }

      expect(campanha).to include(chegaram: 8, agendaram: 3, caixa_id: insta.id, meta: true)
      expect(campanha[:criativos].map { |ad| [ad[:nome], ad[:chegaram], ad[:agendaram]] })
        .to eq([['Gancho policial', 6, 1], ['Gancho edital', 2, 2]])
      expect(campanha[:criativos].first[:anterior]).to eq(chegaram: 10, agendaram: 2)
    end

    it 'deixa quem não tem anúncio carimbado separado por caixa', :aggregate_failures do
      sem = payload[:campanhas].find { |row| row[:chave] == "sem:#{google.id}" }

      expect(sem).to include(nome: 'Sem anúncio do Meta carimbado · GOOGLE', chegaram: 5, agendaram: 1, taxa: 20.0, meta: false)
      expect(sem[:criativos]).to eq([])
    end
  end

  it 'em até 2 dias anda hora a hora, com janela de 24 horas', :aggregate_failures do
    6.times { |i| person(insta, now - 20.hours, booked: i < 3) }
    payload = lines(now.yesterday.beginning_of_day, now.end_of_day)

    expect(payload[:regime]).to include(balde: 'hora', janela: 24)
    expect(payload[:rotulos].first).to eq(now.yesterday.strftime('%d/%m 00h'))
    expect(payload[:rotulos].last).to eq(now.strftime('%d/%m %Hh'))
    expect(payload[:caixas].first[:linha].last).to eq(50.0)
  end

  it 'em período longo anda semana a semana, com janela de 4 semanas', :aggregate_failures do
    5.times { |i| person(insta, now - 10.days, booked: i < 2) }
    payload = lines((now - 89.days).beginning_of_day, now.end_of_day)

    expect(payload[:regime]).to include(balde: 'semana', janela: 4)
    expect(payload[:rotulos].last).to eq(now.beginning_of_week.strftime('%d/%m'))
    expect(payload[:caixas].first).to include(chegaram: 5, agendaram: 2)
    expect(payload[:caixas].first[:linha].last).to eq(40.0)
  end
end
