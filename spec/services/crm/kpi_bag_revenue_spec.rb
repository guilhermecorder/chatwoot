require 'rails_helper'

# 💰 Auditoria 12/10 — Rodada 5 "Números certos" (#198): o "Faturamento
# fechado" do Meu Painel (KpiBag) e do PRO MAX (Dashboard CRM) somava o valor
# do card em TODA entrada em "Cirurgia Realizada" — cargas em massa (`bulk`,
# item 309) e cada volta do mesmo card para a coluna (o valor dobrava).
# Agora: só entrada de verdade e 1 valor por card (1ª entrada no período).
# E o "Entrou em Agendamento de Consulta" ignora a REMARCAÇÃO (`rescheduled`,
# contrato com o R5-G1: remarcar não é agendamento novo).
RSpec.describe 'Faturamento fechado sem carga em massa (Meu Painel e PRO MAX)' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil', position: 1) }
  let(:booking) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta', position: 1, color: '#2563EB') }
  let(:done) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Realizada', position: 2, color: '#059669') }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:since) { tz.local(2026, 7, 1) }
  let(:until_at) { tz.local(2026, 7, 31).end_of_day }

  # cartão com valor, sem o histórico que ele grava ao nascer
  def card(value)
    c = Crm::Contact.create!(contact: create(:contact, account: account), pipeline: pipeline, stage: done, value: value)
    Crm::StageLog.where(crm_contact_id: c.id).delete_all
    c
  end

  def enter(target_card, stage, at, event_type: 'entered')
    Crm::StageLog.create!(crm_contact: target_card, stage_id: stage.id, stage_name: stage.name, event_type: event_type, entered_at: at)
  end

  def metric(key, from: since, to: until_at)
    Crm::KpiBagService.new(account: account, since: from, until_at: to).call[:metrics][key]
  end

  describe 'faturamento fechado (revenue)' do
    it 'carga em massa não entra no faturamento', :aggregate_failures do
      enter(card(5000), done, tz.local(2026, 7, 10, 5, 44), event_type: 'bulk') # importação de 10/07
      enter(card(3000), done, tz.local(2026, 7, 15, 14, 0))

      # antes do conserto: 8.000 (a carga de 10/07 somava junto)
      expect(metric('revenue')[:value]).to eq(3000.0)
    end

    it 'card que sai e volta para "Cirurgia Realizada" no período conta o valor UMA vez (na 1ª entrada)', :aggregate_failures do
      vai_e_volta = card(4000)
      enter(vai_e_volta, done, tz.local(2026, 7, 5, 10, 0))
      enter(vai_e_volta, booking, tz.local(2026, 7, 6, 10, 0))
      enter(vai_e_volta, done, tz.local(2026, 7, 20, 10, 0))

      revenue = metric('revenue')
      # antes do conserto: 8.000 (o valor dobrava)
      expect(revenue[:value]).to eq(4000.0)
      # o dinheiro cai no dia da 1ª entrada (série diária: 05/07 é o 5º balde)
      expect(revenue[:series][4]).to eq(4000.0)
      expect(revenue[:series][19]).to eq(0.0)
    end

    it 'a 1ª entrada vale por período: o mesmo card em julho e de novo em agosto aparece nos dois meses', :aggregate_failures do
      segundo_olho = card(2500)
      enter(segundo_olho, done, tz.local(2026, 7, 8, 9, 0))
      enter(segundo_olho, done, tz.local(2026, 8, 12, 9, 0))

      expect(metric('revenue')[:value]).to eq(2500.0)
      expect(metric('revenue', from: tz.local(2026, 8, 1), to: tz.local(2026, 8, 31).end_of_day)[:value]).to eq(2500.0)
    end

    it 'o ticket médio do KpiSweep (faturamento ÷ cirurgias) herda o faturamento sem carga', :aggregate_failures do
      enter(card(9000), done, tz.local(2026, 7, 10, 5, 44), event_type: 'bulk')
      enter(card(6000), done, tz.local(2026, 7, 12, 11, 0))

      expect(Crm::KpiSweep::OFFICIAL[:ticket]).to eq('revenue / surgeries_done')
      expect(metric('revenue')[:value]).to eq(6000.0)
    end
  end

  describe 'entrou em agendamento (appointments_created)' do
    it 'remarcação (`rescheduled`) não conta como agendamento novo', :aggregate_failures do
      paciente = card(0)
      enter(paciente, booking, tz.local(2026, 7, 3, 9, 0))
      enter(paciente, booking, tz.local(2026, 7, 9, 9, 0), event_type: 'rescheduled')
      remarcou_so = card(0)
      enter(remarcou_so, booking, tz.local(2026, 7, 9, 9, 0), event_type: 'rescheduled')

      created = metric('appointments_created')
      expect(created[:value]).to eq(1.0)
      expect(created[:series][8]).to eq(0.0) # 09/07: só remarcações
    end
  end

  # revisão da Rodada 5: as Metas e o Gerente automático ("Faturamento
  # fechado" = revenue_closed) seguem a MESMA régua — 1 valor por card em
  # cada janela do histórico, sem carga em massa
  describe 'Metas e Gerente automático (revenue_closed do histórico)' do
    it 'card que sai e volta na mesma janela conta 1x; em outra janela conta de novo', :aggregate_failures do
      travel_to(tz.local(2026, 7, 25, 12, 0)) do
        enter(card(5000), done, tz.local(2026, 7, 10, 5, 44), event_type: 'bulk')
        vai_e_volta = card(4000)
        enter(vai_e_volta, done, tz.local(2026, 7, 5, 10, 0))
        enter(vai_e_volta, booking, tz.local(2026, 7, 6, 10, 0))
        enter(vai_e_volta, done, tz.local(2026, 7, 20, 10, 0))
        segundo_olho = card(2500)
        enter(segundo_olho, done, tz.local(2026, 6, 8, 9, 0))
        enter(segundo_olho, done, tz.local(2026, 7, 8, 9, 0))

        history = Crm::GoalPeriodHistoryService.new(account, 'month').history(account.cevico_goal_plans.none)
        by_month = history.to_h { |w| [w[:month], w[:values]['revenue_closed']] }
        # antes do conserto: julho = 10.500 (4.000 duas vezes + 2.500)
        expect(by_month['2026-07-01']).to eq(6500)
        expect(by_month['2026-06-01']).to eq(2500)
      end
    end
  end

  describe 'PRO MAX do Dashboard CRM (pro_series)', type: :request do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'a série de faturamento usa a mesma régua: sem carga em massa e 1 valor por card', :aggregate_failures do
      enter(card(5000), done, tz.local(2026, 7, 10, 5, 44), event_type: 'bulk')
      vai_e_volta = card(4000)
      enter(vai_e_volta, done, tz.local(2026, 7, 5, 10, 0))
      enter(vai_e_volta, done, tz.local(2026, 7, 20, 10, 0))

      get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/dashboard/pro_series",
          params: { from: '2026-07-01', to: '2026-07-31' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      revenue = response.parsed_body['series'].find { |s| s['key'] == 'revenue' }
      # antes do conserto: 13.000 (5.000 da carga + 4.000 duas vezes)
      expect(revenue['values'].sum).to eq(4000.0)
      expect(revenue['values'][4]).to eq(4000.0)
    end
  end
end
