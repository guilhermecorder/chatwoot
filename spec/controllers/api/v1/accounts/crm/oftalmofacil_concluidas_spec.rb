require 'rails_helper'

# 🩺 Auditoria 12/10 — Rodada 5 "Números certos" (#151/#173): o Oftalmofácil
# NUNCA marca a cirurgia como "realizada" (lá ela fica "Ativa" = agendada).
# O Painel do Empresário e o ambiente Oftalmofácil contavam só o rótulo
# "realizada" → faturamento, cirurgias e ticket do mês sempre ZERO.
# Agora vale a régua do Financeiro (item 318): ativa/realizada com a data já
# PASSADA = realizada (scope `concluidas`, no fuso de São Paulo).
RSpec.describe 'CEVICO Oftalmofácil — realizada = ativa com a data passada', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:today) { ActiveSupport::TimeZone['America/Sao_Paulo'].today }

  # extra: provider_name, amount, clinic_name, procedure_name (padrão: nossa, R$ 1.000, IOP, Faco)
  def surgery(token, kind, date, **extra)
    Crm::OftalmofacilSurgery.create!({ account: account, item_token: token, status_kind: kind, patient_name: "Paciente #{token}",
                                       provider_name: 'CATARATA_SP', clinic_name: 'IOP Paulista', procedure_name: 'Faco',
                                       procedure_type: 'Cirurgia', surgery_date: date, amount: 1000 }.merge(extra))
  end

  before do
    Current.reset
    CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'provider_name' => 'CATARATA_SP' } })
  end

  describe 'scope concluidas' do
    it 'conta a ativa (agendada) e a realizada com data passada; fora a de hoje, a futura e a aguardando pagamento', :aggregate_failures do
      passada = surgery('a1', 'agendada', today - 3)
      rotulo = surgery('a2', 'realizada', today - 1)
      surgery('a3', 'agendada', today)
      surgery('a4', 'agendada', today + 2)
      surgery('a5', 'aguardando_pagamento', today - 5)
      surgery('a6', 'cancelada', today - 5)

      expect(Crm::OftalmofacilSurgery.concluidas).to contain_exactly(passada, rotulo)
      # a scope antiga foi renomeada para ninguém contar realizada por ela
      expect(Crm::OftalmofacilSurgery).not_to respond_to(:realizadas)
    end
  end

  describe 'Painel do Empresário (business_metrics)' do
    it 'faturamento, cirurgias e ticket do mês vêm das ativas que já passaram (antes: R$ 0)', :aggregate_failures do
      # a data passada precisa estar no MÊS corrente: no dia 1º não há "ontem" no mês
      skip 'dia 1º do mês: ainda não há data passada no mês' if today.day == 1

      surgery('b1', 'agendada', today.beginning_of_month, amount: 5000)
      surgery('b2', 'agendada', today - 1, amount: 3000)
      surgery('b3', 'agendada', today.end_of_month, amount: 7000) if today < today.end_of_month
      surgery('b4', 'agendada', today - 1, provider_name: 'CLINICA NORTE', amount: 9999) # parceiro fica fora

      get "/api/v1/accounts/#{account.id}/crm/strategy", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      of = response.parsed_body.dig('metrics', 'oftalmofacil')
      expect(of['cirurgias']).to eq(2)
      expect(of['faturamento']).to eq(8000.0)
      expect(of['ticket']).to eq(4000.0)
      # "ainda agendadas" = de hoje em diante (as que passaram viraram realizadas)
      expect(of['agendadas']).to eq(today < today.end_of_month ? 1 : 0)
    end
  end

  describe 'ambiente Oftalmofácil (overview)' do
    it 'valor realizado, meses, clínicas, procedimentos, parceiros e totais contam a ativa que já passou', :aggregate_failures do
      surgery('c1', 'agendada', today - 4, amount: 2000)
      surgery('c2', 'agendada', today - 2, amount: 1500, clinic_name: 'Clínica Norte', procedure_name: 'Lasik')
      surgery('c3', 'agendada', today + 3, amount: 9000)
      surgery('c4', 'cancelada', today - 1, amount: 500)

      get "/api/v1/accounts/#{account.id}/crm/oftalmofacil/overview",
          params: { from: (today - 10).iso8601, to: (today + 10).iso8601 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      own = body['partners'].find { |p| p['name'] == 'CATARATA_SP' }
      # antes do conserto: tudo zero (ninguém tem o rótulo "realizada")
      expect(own['amount_done']).to eq(3500.0)
      expect(own).to include('realizada' => 2, 'agendada' => 1, 'cancelada' => 1, 'total' => 4)
      expect(body['totals']).to include('realizada' => 2, 'agendada' => 1, 'total' => 4)
      expect(body['months'].sum { |m| m['realizada'] }).to eq(2)
      iop = body['clinics'].find { |c| c['name'] == 'IOP Paulista' }
      expect(iop).to include('realizada' => 1, 'agendada' => 1)
      expect(body['clinics'].find { |c| c['name'] == 'Clínica Norte' }).to include('realizada' => 1, 'agendada' => 0)
      expect(body['procedures'].find { |x| x['name'] == 'Faco' }).to include('total' => 3, 'realizada' => 1)
      expect(body['procedures'].find { |x| x['name'] == 'Lasik' }).to include('realizada' => 1)
    end
  end
end
