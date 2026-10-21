require 'rails_helper'

# 🔔 item 346 — Notificações sobre agendamentos: o caso Francislene × Alice de ponta a ponta
RSpec.describe Crm::AppointmentAlerts do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Consulta Confirmada') }
  let!(:fran) { account.contacts.create!(name: 'Francislene Pereira Borges E Alice Quadros Schimit', phone_number: '+553587017046') }
  let!(:fran_of) do
    account.contacts.create!(name: 'Francislene Pereira Borges', phone_number: '+5535987017046',
                             additional_attributes: { 'origem' => 'oftalmofacil' }, custom_attributes: { 'cpf' => '11122233344' })
  end
  let!(:alice) { account.contacts.create!(name: 'Alice Quadros Schimit', phone_number: '+5511956491869') }
  let!(:consulta_alice) do
    account.tasks.create!(title: 'Consulta: Alice Quadros Schimit', contact: fran, due_at: 3.days.from_now, creator: admin, task_type: 'consulta')
  end

  let(:actions) { Crm::AppointmentAlertActions.new(account: account, user: admin) }

  def kinds(admin_view: true, user: admin)
    described_class.new(account: account, user: user, admin: admin_view).items.map { |i| i[:kind] }
  end

  before do
    Crm::Contact.create!(contact_id: fran.id, pipeline_id: pipeline.id, stage_id: stage.id, assignee_id: agent.id)
    Crm::PatientReview.flag!(fran, 'duas_pessoas', fran.name)
    Crm::PatientReview.flag!(fran, 'possivel_duplicado', 'Mesmo celular', other_id: fran_of.id)
    Crm::PatientReview.flag!(fran_of.reload, 'possivel_duplicado', 'Mesmo celular', other_id: fran.id)
  end

  it 'admin vê os alertas de cadastro e a consulta no cadastro de outra pessoa (o par aparece uma vez)' do
    expect(kinds).to contain_exactly('duas_pessoas', 'possivel_duplicado', 'consulta_outro_nome')
  end

  it 'atendente vê só o que é dele (responsável pelo card)', :aggregate_failures do
    other_agent = create(:user, account: account, role: :agent)
    expect(kinds(admin_view: false, user: agent)).to include('consulta_outro_nome', 'duas_pessoas')
    expect(kinds(admin_view: false, user: other_agent)).to be_empty
  end

  it 'mover a consulta da Alice para o cadastro dela amarra os dois e tira o alerta', :aggregate_failures do
    actions.move_task!(task_id: consulta_alice.id, contact_id: alice.id)
    expect(consulta_alice.reload.contact).to eq(alice)
    expect(alice.reload.additional_attributes.dig('agendado_por', 'contact_id')).to eq(fran.id)
    expect(Crm::Contact.find_by(contact_id: alice.id).stage_id).to eq(stage.id) # card na coluna de quem estava com ela
    expect(kinds).not_to include('consulta_outro_nome')
  end

  it 'mover para um paciente NOVO cria o cadastro com nome + telefone' do
    consulta_alice.update!(contact: fran)
    actions.move_task!(task_id: consulta_alice.id, name: 'Joana Quadros', phone: '11 97777-1111')
    expect(consulta_alice.reload.contact).to have_attributes(name: 'Joana Quadros', phone_number: '+5511977771111')
  end

  it 'juntar: fica o do WhatsApp com os dados do OftalmoFácil; corrigir o nome tira "duas pessoas"', :aggregate_failures do
    actions.merge!(keep_id: fran.id, drop_id: fran_of.id)
    expect(Contact.exists?(fran_of.id)).to be(false)
    expect(fran.reload).to have_attributes(name: 'Francislene Pereira Borges', phone_number: '+553587017046')
    expect(fran.custom_attributes['cpf']).to eq('11122233344')
    expect(kinds).not_to include('possivel_duplicado')

    Crm::PatientReview.flag!(fran, 'duas_pessoas', 'x')
    actions.rename!(contact_id: fran.id, name: 'Francislene Pereira Borges')
    expect(kinds).not_to include('duas_pessoas')
  end

  it '"são pessoas diferentes" some dos dois e não volta a alertar', :aggregate_failures do
    actions.not_same!(one_id: fran.id, other_id: fran_of.id)
    expect(kinds).not_to include('possivel_duplicado')
    Crm::PatientReview.flag!(fran.reload, 'possivel_duplicado', 'de novo', other_id: fran_of.id)
    expect(Crm::PatientReview.list(fran.reload).map { |e| e['tipo'] }).not_to include('possivel_duplicado')
  end

  it 'consulta sem cadastro aparece; "conferido" tira da lista', :aggregate_failures do
    solta = account.tasks.create!(title: 'Consulta: Pedro Sem Cadastro', due_at: 2.days.from_now, creator: admin, task_type: 'consulta')
    expect(kinds).to include('consulta_sem_cadastro')
    actions.reviewed!(task_id: solta.id)
    expect(kinds).not_to include('consulta_sem_cadastro')
  end
end
