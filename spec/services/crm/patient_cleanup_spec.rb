require 'rails_helper'

# 🧹 item 346 — etapa 2: casos tirados do levantamento de produção (15/10)
RSpec.describe Crm::PatientCleanup do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let(:lead) { Crm::Stage.create!(pipeline: pipeline, name: 'Lead', position: 0) }
  let(:agendada) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Agendada', position: 1) }

  let!(:zap) { account.contacts.create!(name: 'Roberta Camilo', phone_number: '+556596585953', email: 'velho@exemplo.com') }
  let!(:of) do
    account.contacts.create!(name: 'Roberta Camilo De Araujo', phone_number: '+5565996585953', email: 'roberta@exemplo.com',
                             custom_attributes: { 'cpf' => '11122233344' }, additional_attributes: { 'origem' => 'oftalmofacil' })
  end

  before do
    create(:conversation, account: account, inbox: inbox, contact: zap)
    zap.update!(label_list: %w[cevico refrativa])
    of.update!(label_list: %w[oftalmofacil])
  end

  def run(dry:)
    described_class.new(account: account, dry: dry).call
  end

  it 'SIMULAÇÃO: lista o que faria e não muda nada', :aggregate_failures do
    report = run(dry: true)
    expect(report[:merges].map { |m| [m[:base_id], m[:merge_ids], m[:final_name]] })
      .to eq([[zap.id, [of.id], 'Roberta Camilo De Araujo']])
    expect(account.contacts.count).to eq(2)
    expect(zap.reload.name).to eq('Roberta Camilo')
    expect(Crm::PatientReview.list(zap)).to be_empty
  end

  it 'APLICA: fica o cadastro do WhatsApp (número dele), com nome, e-mail e CPF do OftalmoFácil e o card na etapa atual',
     :aggregate_failures do
    Crm::Contact.create!(contact_id: zap.id, pipeline_id: pipeline.id, stage_id: lead.id, stage_moved_at: 3.days.ago)
    Crm::Contact.create!(contact_id: of.id, pipeline_id: pipeline.id, stage_id: agendada.id, stage_moved_at: 1.hour.ago)

    run(dry: false)
    expect(Contact.exists?(of.id)).to be(false)
    zap.reload
    expect(zap.phone_number).to eq('+556596585953')
    expect(zap.name).to eq('Roberta Camilo De Araujo')
    expect(zap.email).to eq('roberta@exemplo.com')
    expect(zap.custom_attributes['cpf']).to eq('11122233344')
    expect(zap.label_list).to contain_exactly('cevico', 'refrativa') # oftalmofacil saiu (tem cevico)
    expect(Crm::Contact.find_by(contact_id: zap.id, pipeline_id: pipeline.id).stage_id).to eq(agendada.id)
  end

  it 'nome de DUAS pessoas, outro nome no mesmo celular e mesmo CPF não são juntados: viram alerta', :aggregate_failures do
    dupla = account.contacts.create!(name: 'Francislene Pereira Borges E Alice Quadros Schimit', phone_number: '+553587017046')
    fran = account.contacts.create!(name: 'Francislene Pereira Borges', phone_number: '+5535987017046')
    mae = account.contacts.create!(name: 'Vera Lima', phone_number: '+551187654321')
    filho = account.contacts.create!(name: 'Ricardo Lima', phone_number: '+5511987654321')

    report = run(dry: false)
    expect(report[:merged]).to eq(1) # só a Roberta
    expect([dupla, fran, mae, filho].all? { |c| Contact.exists?(c.id) }).to be(true)
    expect(Crm::PatientReview.list(dupla.reload).map { |e| e['tipo'] }).to include('duas_pessoas')
    expect(Crm::PatientReview.list(fran.reload).map { |e| e['tipo'] }).to include('duas_pessoas')
    expect(Crm::PatientReview.list(mae.reload).map { |e| e['tipo'] }).to eq(['nome_diferente'])
  end

  it 'mesmo nome de 2 palavras só vira alerta quando os dois já têm agendamento (Ana Lucia × Samuel)', :aggregate_failures do
    ana1 = account.contacts.create!(name: 'Ana Lucia', phone_number: '+5511952475509')
    account.contacts.create!(name: 'Ana Lúcia', phone_number: '+5511973562148')
    sam1 = account.contacts.create!(name: 'Samuel De Andrade', phone_number: '+556984930293')
    sam2 = account.contacts.create!(name: 'Samuel de andrade', phone_number: '+5569981341130')
    admin = create(:user, account: account, role: :administrator)
    [sam1, sam2].each do |c|
      account.tasks.create!(title: "Cirurgia: #{c.name}", contact: c, due_at: 2.days.from_now, creator: admin, task_type: 'cirurgia')
    end

    run(dry: false)
    expect(Crm::PatientReview.list(ana1.reload)).to be_empty
    expect(Crm::PatientReview.list(sam1.reload).map { |e| e['detalhe'] }).to include(start_with('Mesmo nome completo'))
  end

  it 'cadastro que fica com +1 na frente do número brasileiro passa a usar o +55 do grupo', :aggregate_failures do
    mais_um = account.contacts.create!(name: 'Rodrigo Mamede', phone_number: '+11964516277')
    certo = account.contacts.create!(name: 'Rodrigo dos Santos Mamede', phone_number: '+5511964516277')
    create(:conversation, account: account, inbox: inbox, contact: mais_um)

    plan = run(dry: true)[:merges].find { |m| m[:base_id] == mais_um.id }
    expect(plan[:phone]).to eq('+5511964516277')
    run(dry: false)
    expect(Contact.exists?(certo.id)).to be(false)
    expect(mais_um.reload.phone_number).to eq('+5511964516277')
  end
end
