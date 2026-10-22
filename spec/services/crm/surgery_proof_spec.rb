require 'rails_helper'

# 🧾 Ponta 1 (22/10): "realizada" do OftalmoFácil com PROVA — pagamento,
# card de pós ou Agenda; senão "sem prova". Só rótulo: a receita não muda.
RSpec.describe Crm::SurgeryProof do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:today) { ActiveSupport::TimeZone['America/Sao_Paulo'].today }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0) }
  let!(:stage_booked) { pipeline.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 1) }
  let!(:stage_postop) { pipeline.stages.create!(name: 'Pós Operatório', color: '#000', position: 2) }

  def patient(name)
    create(:contact, account: account, name: name)
  end

  def surgery(token, contact, date: today - 5, **extra)
    Crm::OftalmofacilSurgery.create!({ account: account, item_token: token, status_kind: 'agendada', patient_name: contact&.name,
                                       contact_id: contact&.id, provider_name: 'CATARATA_SP', procedure_name: 'Faco',
                                       procedure_type: 'Cirurgias', surgery_date: date, amount: 5000 }.merge(extra))
  end

  def card(contact, stage)
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage.id)
  end

  before { CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'provider_name' => 'CATARATA_SP' } }) }

  it 'pago > equipe > agenda > sem prova', :aggregate_failures do
    paga = surgery('p1', patient('Ana Paga'), paid_amount: 5000)
    pos = patient('Bia Pos')
    card(pos, stage_postop)
    pela_equipe = surgery('p2', pos)
    presente = patient('Cris Presente')
    pela_agenda = surgery('p3', presente)
    account.tasks.create!(title: 'Cirurgia: Cris', task_type: 'cirurgia', due_at: today - 5, unit: 'paulista', contact: presente,
                          creator: admin, status: :todo, attendance: 'attended', external_ref: 'p3')
    parada = patient('Dani Parada')
    card(parada, stage_booked)
    sem = surgery('p4', parada)

    proofs = described_class.new(account).call([paga, pela_equipe, pela_agenda, sem])

    expect(proofs).to eq(paga.id => 'pago', pela_equipe.id => 'equipe', pela_agenda.id => 'agenda', sem.id => nil)
    expect(described_class.tally(proofs)).to eq('pago' => 1, 'equipe' => 1, 'agenda' => 1, 'sem_prova' => 1)
  end

  it 'card que passou pelo pós ANTES da cirurgia (1º olho) não prova o 2º olho', :aggregate_failures do
    contato = patient('Eva Dois Olhos')
    c = card(contato, stage_booked)
    Crm::StageLog.create!(crm_contact_id: c.id, stage_id: stage_postop.id, stage_name: 'Pós Operatório', entered_at: today - 40)
    primeiro = surgery('o1', contato, date: today - 41)
    segundo = surgery('o2', contato, date: today - 5)

    proofs = described_class.new(account).call([primeiro, segundo])

    expect(proofs[primeiro.id]).to eq('equipe')
    expect(proofs[segundo.id]).to be_nil
  end

  it 'consulta de pós-op na Agenda depois da cirurgia é prova' do
    contato = patient('Fê Retorno')
    s = surgery('r1', contato)
    account.tasks.create!(title: 'Consulta: Fê', task_type: 'consulta', modality: 'pos_op', due_at: today + 2, unit: 'paulista',
                          contact: contato, creator: admin, status: :todo)

    # a Agenda de pós-op também leva o card para "Consulta Pós Op" (item 356) — qualquer das duas provas vale
    expect(described_class.new(account).call([s])[s.id]).to be_present
  end

  describe 'nas telas (o valor não muda)', type: :request do
    before do
      surgery('t1', patient('Gil Paga'), paid_amount: 4000, amount: 4000)
      surgery('t2', patient('Hel Sem'), amount: 6000)
    end

    it 'hub: total de sem prova, prova por tipo, filtro e rótulo do item', :aggregate_failures do
      get "/api/v1/accounts/#{account.id}/crm/oftalmofacil/overview",
          params: { from: (today - 10).iso8601, to: today.iso8601 }, headers: admin.create_new_auth_token, as: :json
      body = response.parsed_body
      own = body['partners'].find { |p| p['name'] == 'CATARATA_SP' }
      expect(body['totals']).to include('realizada' => 2, 'realizada_sem_prova' => 1)
      expect(body['proof']).to eq('pago' => 1, 'equipe' => 0, 'agenda' => 0, 'sem_prova' => 1)
      expect(own).to include('amount_done' => 10_000.0, 'sem_prova' => 1, 'amount_sem_prova' => 6000.0)
      expect(body['months'].sum { |m| m['sem_prova'] }).to eq(1)

      get "/api/v1/accounts/#{account.id}/crm/oftalmofacil/items", params: { status: 'sem_prova' }, headers: admin.create_new_auth_token, as: :json
      rows = response.parsed_body['rows']
      expect(rows.pluck('item_token')).to eq(['t2'])
      expect(rows.first).to include('status_view' => 'realizada', 'proof' => 'sem_prova', 'proof_label' => 'sem prova')
    end

    it 'Financeiro › Lucratividade: receita igual, com a parte sem prova à parte', :aggregate_failures do
      get "/api/v1/accounts/#{account.id}/crm/finance/profitability",
          params: { preset: 'last90' }, headers: admin.create_new_auth_token, as: :json
      summary = response.parsed_body['summary']
      expect(summary).to include('count' => 2, 'receita' => 10_000.0)
      expect(summary['prova']).to include('pago' => 1, 'sem_prova' => 1)
      expect(summary['sem_prova']).to include('count' => 1, 'receita' => 6000.0)
    end
  end
end
