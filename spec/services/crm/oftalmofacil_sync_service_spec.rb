require 'rails_helper'

# 🏥 item 228 (24/09): hub de parceiros + Agenda unificada
RSpec.describe Crm::OftalmofacilSyncService do
  let(:account) { create(:account) }
  let!(:cevico) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0).tap do |p|
      p.stages.create!(name: 'Lead', color: '#000', position: 0)
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 1)
      p.stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 2)
    end
  end
  let!(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 0)
      p.stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 1)
    end
  end
  let(:config) do
    { 'db_host' => 'h', 'db_name' => 'd', 'db_user' => 'u', 'db_password' => 'p', 'provider_name' => 'CATARATA_SP',
      'partners_enabled' => true, 'partner_pipeline_id' => partners.id, 'agenda_enabled' => true,
      'agenda_from' => '2026-09-21', 'doctors' => { '170937' => 'Dr. Henrique Gemelli' },
      'clinics' => { 'IOP Paulista' => 'iop' } }
  end
  let(:service) { described_class.new(account: account, config: config, silent: true, since: nil) }
  before { create(:user, account: account, role: :administrator) } # criador dos agendamentos

  def row(overrides = {})
    {
      'SCH_ITE_ID' => 1, 'SCH_ITE_SCH_ID' => 10, 'SCH_ITE_TOKEN' => 'tok-1', 'SCH_ITE_STATUS' => '1',
      'SCH_ITE_DATE' => '30/09/2026', 'SCH_ITE_HOUR' => '09:30', 'SCH_ITE_AMOUNT' => 4500, 'SCH_ITE_CLINIC_PRICE' => 3000,
      'SCH_ITE_PROFIT' => 1500, 'SCH_ITE_REBATE' => 0, 'SCH_ITE_DATE_CREATION' => '2026-09-01 10:00:00',
      'SCH_ITE_LAST_MODIFICATION' => '2026-09-20 10:00:00', 'SCH_ITE_CLINIC' => 5, 'SCH_DOCTOR' => '170937',
      'SCH_PATIENT_NAME' => 'Maria Parceira', 'SCH_PATIENT_CPF' => '12345678901', 'SCH_PATIENT_PHONE' => '11988887777',
      'SCH_PATIENT_MAIL' => nil, 'PROV_NAME' => 'CLINICA VISAO NORTE', 'CLI_NAME' => 'IOP Paulista',
      'PRO_NAME' => 'Facoemulsificação', 'PRO_TYP_VALUE' => 'Cirurgia', 'EYE_VALUE' => 'OD',
      'STATUS_LABEL' => 'Ativo', 'PAT_CPF' => nil, 'PAT_EMAIL' => nil, 'PAT_PHONE' => nil, 'PAID_AMOUNT' => 0
    }.merge(overrides)
  end

  def run_with(rows)
    allow(service).to receive(:query).and_return(rows, [])
    service.call
  end

  it 'parceiro → contato com etiqueta de origem, card só no funil dos parceiros e agendamento na Agenda', :aggregate_failures do
    result = run_with([row])
    expect(result.errors).to be_empty
    expect(result.partners).to eq(1)
    contact = account.contacts.find_by(phone_number: '+5511988887777')
    expect(contact.additional_attributes).to include('origem' => 'oftalmofacil', 'parceiro' => 'CLINICA VISAO NORTE')
    expect(contact.label_list).to include('oftalmofacil', 'of_clinica_visao_norte')
    expect(Crm::Contact.where(contact_id: contact.id, pipeline_id: partners.id).count).to eq(1)
    expect(Crm::Contact.where(contact_id: contact.id, pipeline_id: cevico.id).count).to eq(0)
    expect(Crm::Contact.find_by(contact_id: contact.id).origin).to eq('oftalmofacil')

    task = account.tasks.find_by(external_ref: 'tok-1')
    expect(task).to be_present
    expect(task.task_type).to eq('cirurgia')
    expect(task.title).to eq('Cirurgia: Maria Parceira')
    expect(task.due_at.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-%d %H:%M')).to eq('2026-09-30 09:30')
    expect(task.unit).to eq('iop')
    expect(task.doctor).to eq('Dr. Henrique Gemelli')
    expect(task.source).to eq('oftalmofacil')
    expect(task.source_detail).to eq('CLINICA VISAO NORTE')
    expect(task.booking_kind).to eq('registro')
    expect(task.description).to start_with('Oftalmofácil · CLINICA VISAO NORTE · IOP Paulista')
    expect(result.tasks_created).to eq(1)
  end

  # 🕐 item 242: o MySQL do hub manda a hora em SEGUNDOS ("39600.0" = 11:00) e o
  # app roda em UTC — o agendamento tem que cair às 11:00 de São Paulo
  it 'hora em segundos vira HH:MM e o agendamento cai na hora certa de São Paulo', :aggregate_failures do
    run_with([row('SCH_ITE_HOUR' => '39600.0', 'SCH_ITE_TOKEN' => 'tok-h')])
    surgery = Crm::OftalmofacilSurgery.find_by(item_token: 'tok-h')
    expect(surgery.surgery_hour).to eq('11:00')
    task = account.tasks.find_by(external_ref: 'tok-h')
    expect(task.due_at.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-%d %H:%M')).to eq('2026-09-30 11:00')
    expect(Crm::OftalmofacilSurgery.normalize_hour('40800.0')).to eq('11:20')
    expect(Crm::OftalmofacilSurgery.normalize_hour('14:05:00')).to eq('14:05')
    expect(Crm::OftalmofacilSurgery.normalize_hour('0')).to be_nil
    expect(Crm::OftalmofacilSurgery.new(surgery_hour: '54000.0').hour_hhmm).to eq('15:00')
  end

  it 'nosso (CATARATA_SP) → card no funil da CEVICO, sem etiqueta de parceiro, agendamento sem parceiro', :aggregate_failures do
    run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-2')])
    contact = account.contacts.find_by(phone_number: '+5511988887777')
    expect(contact.label_list).to include('oftalmofacil')
    expect(contact.label_list.grep(/^of_/)).to be_empty
    expect(contact.additional_attributes).not_to have_key('parceiro')
    expect(Crm::Contact.find_by(contact_id: contact.id).pipeline_id).to eq(cevico.id)
    expect(account.tasks.find_by(external_ref: 'tok-2').source_detail).to be_nil
  end

  it 'acompanha o OftalmoFácil: realizada conclui, cancelada cancela, exame vai para o trilho de exames', :aggregate_failures do
    run_with([row])
    run_with([row('STATUS_LABEL' => 'Realizado', 'SCH_ITE_STATUS' => '2', 'SCH_ITE_DATE' => '22/09/2026')])
    task = account.tasks.find_by(external_ref: 'tok-1')
    expect(task.status).to eq('done')
    expect(task.attendance).to eq('attended')
    expect(account.tasks.where(external_ref: 'tok-1').count).to eq(1)

    run_with([row('STATUS_LABEL' => 'Cancelado', 'SCH_ITE_STATUS' => '0')])
    expect(task.reload.canceled_at).to be_present

    run_with([row('SCH_ITE_TOKEN' => 'tok-3', 'PRO_TYP_VALUE' => 'Exame', 'PRO_NAME' => 'OCT')])
    exam = account.tasks.find_by(external_ref: 'tok-3')
    expect(exam.task_type).to eq('consulta')
    expect(exam.modality).to eq('exames')
    expect(exam.title).to eq('Exame: Maria Parceira')
  end

  # 🧩 item 344 (13/10): "retorno vindo do oftalmofácil é consulta de retorno" e
  # consulta do hub não vai mais para "Cirurgia Agendada"
  it 'retorno do hub vira consulta de RETORNO e o card do parceiro vai para a coluna de consulta', :aggregate_failures do
    booked = partners.stages.create!(name: 'Consulta Agendada', color: '#000', position: -1)
    run_with([row('SCH_ITE_TOKEN' => 'tok-r', 'PRO_TYP_VALUE' => 'Retorno', 'PRO_NAME' => 'Retorno')])
    task = account.tasks.find_by(external_ref: 'tok-r')
    expect(task.task_type).to eq('consulta')
    expect(task.modality).to eq('retorno')
    expect(task.title).to eq('Retorno: Maria Parceira')
    card = Crm::Contact.find_by(contact_id: task.contact_id, pipeline_id: partners.id)
    expect(card.stage_id).to eq(booked.id)
    expect(Crm::OftalmofacilSyncService.kind_for(Struct.new(:procedure_type).new('Retorno pós-operatório'))[:modality]).to eq('pos_op')
  end

  it 'consulta de paciente NOSSO (CATARATA_SP) não move card no funil da CEVICO (quem move consulta é a Agenda)' do
    run_with([row('SCH_ITE_TOKEN' => 'tok-c', 'PROV_NAME' => 'CATARATA_SP', 'PRO_TYP_VALUE' => 'Consulta', 'PRO_NAME' => 'Consulta')])
    contact = account.contacts.find_by(phone_number: '+5511988887777')
    expect(Crm::Contact.where(contact_id: contact.id, pipeline_id: cevico.id, stage_id: cevico.stages.find_by(name: 'Cirurgia Agendada').id)).to be_empty
  end

  it 'respeita a janela da Agenda e não cria card de parceiro sem funil configurado', :aggregate_failures do
    old = row('SCH_ITE_TOKEN' => 'tok-old', 'SCH_ITE_DATE' => '10/09/2026', 'SCH_PATIENT_PHONE' => '11955554444',
              'SCH_PATIENT_CPF' => '11122233344')
    run_with([old])
    expect(account.tasks.find_by(external_ref: 'tok-old')).to be_nil
    # parceiro antes da janela: só no espelho, sem paciente nem card
    expect(account.contacts.find_by(phone_number: '+5511955554444')).to be_nil
    expect(Crm::OftalmofacilSurgery.find_by(item_token: 'tok-old').applied_action).to eq('mirror_only')
    # a CEVICO (CATARATA_SP) antiga continua ganhando paciente e card
    run_with([row('SCH_ITE_TOKEN' => 'tok-own-old', 'SCH_ITE_DATE' => '10/09/2026', 'PROV_NAME' => 'CATARATA_SP',
                  'SCH_PATIENT_PHONE' => '11933332222', 'SCH_PATIENT_CPF' => '55566677788')])
    expect(account.contacts.find_by(phone_number: '+5511933332222')).to be_present

    svc = described_class.new(account: account, config: config.merge('partner_pipeline_id' => nil), silent: true, since: nil)
    allow(svc).to receive(:query).and_return([row('SCH_ITE_TOKEN' => 'tok-4', 'SCH_PATIENT_PHONE' => '11977776666',
                                                  'SCH_PATIENT_CPF' => '99988877766', 'SCH_PATIENT_NAME' => 'João Novo')], [])
    result = svc.call
    expect(result.skipped_partners).to eq(1)
    contact = account.contacts.find_by(phone_number: '+5511977776666')
    expect(Crm::Contact.where(contact_id: contact.id).count).to eq(0)
    expect(account.tasks.find_by(external_ref: 'tok-4')).to be_present
  end

  # 🛡️ auditoria 07/10 (#170): homônimo nunca é a mesma pessoa. Antes, nome igual e
  # único na base virava o paciente da cirurgia — e o CPF, a etiqueta do parceiro,
  # o card e o lembrete de confirmação iam parar no WhatsApp da pessoa errada.
  describe 'casamento do paciente' do
    let!(:homonimo) { account.contacts.create!(name: 'Teste Nome', phone_number: '+5511900001111') }

    it 'nome igual com telefone diferente e sem CPF NÃO casa: cria paciente novo e deixa o homônimo intacto',
       :aggregate_failures do
      run_with([row('SCH_ITE_TOKEN' => 'tok-nome', 'SCH_PATIENT_NAME' => 'Teste Nome',
                    'SCH_PATIENT_PHONE' => '11900002222', 'SCH_PATIENT_CPF' => nil)])
      surgery = Crm::OftalmofacilSurgery.find_by(item_token: 'tok-nome')
      expect(surgery.match_via).to eq('created')
      expect(surgery.contact_id).not_to eq(homonimo.id)

      homonimo.reload
      expect(homonimo.custom_attributes.to_h['cpf']).to be_blank
      expect(homonimo.label_list).to be_empty
      expect(homonimo.additional_attributes.to_h).not_to have_key('parceiro')
      expect(Crm::Contact.where(contact_id: homonimo.id).count).to eq(0)

      novo = account.contacts.find_by(phone_number: '+5511900002222')
      expect(novo).to be_present
      expect(novo.label_list).to include('oftalmofacil', 'of_clinica_visao_norte')
      expect(account.tasks.find_by(external_ref: 'tok-nome').contact_id).to eq(novo.id)
    end

    it 'nome igual SEM telefone e sem CPF também não casa: paciente novo sem telefone (nenhum lembrete sai)',
       :aggregate_failures do
      run_with([row('SCH_ITE_TOKEN' => 'tok-sem-fone', 'SCH_PATIENT_NAME' => 'Teste Nome',
                    'SCH_PATIENT_PHONE' => nil, 'SCH_PATIENT_CPF' => '98765432100')])
      surgery = Crm::OftalmofacilSurgery.find_by(item_token: 'tok-sem-fone')
      expect(surgery.match_via).to eq('created')
      expect(surgery.contact_id).not_to eq(homonimo.id)
      expect(homonimo.reload.custom_attributes.to_h['cpf']).to be_blank
      task = account.tasks.find_by(external_ref: 'tok-sem-fone')
      expect(task.phone).to be_blank
      expect(task.contact_id).to eq(surgery.contact_id)
    end

    it 'nome igual + e-mail igual casa (e-mail é chave forte); e-mail igual com nome diferente não casa',
       :aggregate_failures do
      homonimo.update!(email: 'teste@exemplo.com')
      run_with([row('SCH_ITE_TOKEN' => 'tok-mail', 'SCH_PATIENT_NAME' => 'Teste Nome', 'SCH_PATIENT_PHONE' => nil,
                    'SCH_PATIENT_CPF' => nil, 'SCH_PATIENT_MAIL' => 'Teste@Exemplo.com')])
      expect(Crm::OftalmofacilSurgery.find_by(item_token: 'tok-mail').match_via).to eq('name_email')
      expect(Crm::OftalmofacilSurgery.find_by(item_token: 'tok-mail').contact_id).to eq(homonimo.id)

      result = run_with([row('SCH_ITE_ID' => 2, 'SCH_ITE_TOKEN' => 'tok-mail-2', 'SCH_PATIENT_NAME' => 'Outra Pessoa',
                             'SCH_PATIENT_PHONE' => nil, 'SCH_PATIENT_CPF' => nil, 'SCH_PATIENT_MAIL' => 'teste@exemplo.com')])
      expect(result.errors).to be_empty # o e-mail ocupado não pode derrubar o item (antes: erro do banco, sem card/agenda)
      expect(Crm::OftalmofacilSurgery.find_by(item_token: 'tok-mail-2').match_via).to eq('created')
      expect(Crm::OftalmofacilSurgery.find_by(item_token: 'tok-mail-2').contact_id).not_to eq(homonimo.id)
    end

    # e-mail da família: o mesmo e-mail já é de outro paciente — o telefone novo
    # não pode ser jogado fora junto (sem telefone, nenhum lembrete sai e cada
    # sincronização da mesma cirurgia criava mais um duplicado)
    it 'e-mail já usado por outro paciente: nasce COM o telefone, e a cirurgia não duplica na próxima rodada',
       :aggregate_failures do
      homonimo.update!(email: 'familia@exemplo.com')
      linha = row('SCH_ITE_TOKEN' => 'tok-familia', 'SCH_PATIENT_NAME' => 'Ana Souza', 'SCH_PATIENT_PHONE' => '11900003333',
                  'SCH_PATIENT_CPF' => nil, 'SCH_PATIENT_MAIL' => 'familia@exemplo.com')
      result = run_with([linha])
      expect(result.errors).to be_empty
      surgery = Crm::OftalmofacilSurgery.find_by(item_token: 'tok-familia')
      expect(surgery.match_via).to eq('created')
      novo = account.contacts.find(surgery.contact_id)
      expect(novo.phone_number).to eq('+5511900003333')
      expect(novo.email).to be_blank
      expect(homonimo.reload.email).to eq('familia@exemplo.com')

      antes = account.contacts.count
      run_with([linha.merge('SCH_ITE_LAST_MODIFICATION' => '2026-09-21 10:00:00')])
      expect(surgery.reload.contact_id).to eq(novo.id)
      expect(surgery.match_via).to eq('phone')
      expect(account.contacts.count).to eq(antes)
    end

    # cirurgia que ANTES do #170 já tinha casado só pelo nome: o CPF e o e-mail que
    # o sync gravou no homônimo não valem como prova — na próxima mudança lá, a
    # cirurgia vai para um paciente novo (com o telefone do hub) e o homônimo
    # não é mais mexido. O rastro antigo (CPF, etiqueta, card) fica para a ação
    # pós-deploy de limpeza.
    it 'casada só por nome no passado: não volta a casar pelo CPF/e-mail que o próprio sync gravou e troca para paciente novo',
       :aggregate_failures do
      allow(service).to receive(:resolve_contact) do
        service.instance_variable_set(:@match_via, 'name')
        homonimo
      end
      run_with([row('SCH_ITE_TOKEN' => 'tok-antigo', 'SCH_PATIENT_NAME' => 'Teste Nome', 'SCH_PATIENT_PHONE' => nil,
                    'SCH_PATIENT_CPF' => '98765432100', 'SCH_PATIENT_MAIL' => 'teste.nome@exemplo.com')])
      surgery = Crm::OftalmofacilSurgery.find_by(item_token: 'tok-antigo')
      expect(surgery.match_via).to eq('name')
      expect(homonimo.reload.custom_attributes.to_h['cpf']).to eq('98765432100') # o estrago antigo
      expect(homonimo.email).to eq('teste.nome@exemplo.com')
      card_antigo = Crm::Contact.find_by(contact_id: homonimo.id, pipeline_id: partners.id)
      expect(card_antigo.stage.name).to eq('Cirurgia Agendada')
      expect(account.tasks.find_by(external_ref: 'tok-antigo').contact_id).to eq(homonimo.id)

      allow(service).to receive(:resolve_contact).and_call_original
      run_with([row('SCH_ITE_TOKEN' => 'tok-antigo', 'SCH_PATIENT_NAME' => 'Teste Nome', 'SCH_PATIENT_PHONE' => '11900004444',
                    'SCH_PATIENT_CPF' => '98765432100', 'SCH_PATIENT_MAIL' => 'teste.nome@exemplo.com',
                    'STATUS_LABEL' => 'Realizado', 'SCH_ITE_STATUS' => '2', 'SCH_ITE_DATE' => '22/09/2026',
                    'SCH_ITE_LAST_MODIFICATION' => '2026-09-22 10:00:00')])
      surgery.reload
      expect(surgery.match_via).to eq('created')
      expect(surgery.contact_id).not_to eq(homonimo.id)
      novo = account.contacts.find(surgery.contact_id)
      expect(novo.phone_number).to eq('+5511900004444')
      expect(account.tasks.find_by(external_ref: 'tok-antigo').contact_id).to eq(novo.id)
      expect(Crm::Contact.find_by(contact_id: novo.id, pipeline_id: partners.id).stage.name).to eq('Cirurgia Realizada')
      # o homônimo não anda mais: o card antigo fica onde estava (limpeza é da ação pós-deploy)
      expect(card_antigo.reload.stage.name).to eq('Cirurgia Agendada')
    end

    it 'heal_agenda! também não confia em cirurgia casada só por nome: passa pelo casamento de novo' do
      allow(service).to receive(:resolve_contact) do
        service.instance_variable_set(:@match_via, 'name')
        homonimo
      end
      run_with([row('SCH_ITE_TOKEN' => 'tok-heal', 'SCH_PATIENT_NAME' => 'Teste Nome', 'SCH_PATIENT_PHONE' => '11900005555',
                    'SCH_PATIENT_CPF' => nil, 'SCH_ITE_DATE' => (Date.current + 2).strftime('%d/%m/%Y'))])
      account.tasks.find_by(external_ref: 'tok-heal').update!(due_at: 10.days.from_now) # dia errado: entra na cura
      allow(service).to receive(:resolve_contact).and_call_original
      service.heal_agenda!(days: 5)
      surgery = Crm::OftalmofacilSurgery.find_by(item_token: 'tok-heal')
      expect(surgery.match_via).to eq('created')
      expect(surgery.contact_id).not_to eq(homonimo.id)
      expect(account.tasks.find_by(external_ref: 'tok-heal').contact_id).to eq(surgery.contact_id)
    end
  end

  # 🔁 auditoria 10/2026 (#462/#472): a recepção lança a consulta na Agenda E ela
  # chega pelo hub (CATARATA_SP, o fornecedor da própria CEVICO) → nasciam DUAS
  # tasks no mesmo dia, dois lembretes pagos e o "sim" confirmava só uma.
  # 📱 item 346 (15/10): caso Francislene — WhatsApp sem o 9, OftalmoFácil com o 9
  describe 'paciente da CEVICO (CATARATA_SP) que já tinha cadastro' do
    let(:own) { { 'PROV_NAME' => 'CATARATA_SP', 'SCH_PATIENT_PHONE' => '35987017046', 'SCH_PATIENT_CPF' => '11122233344' } }

    it 'acha o cadastro do WhatsApp pelo celular sem o 9, os dados do OftalmoFácil mandam e não ganha etiqueta oftalmofacil',
       :aggregate_failures do
      zap = account.contacts.create!(name: 'Fran Borges', phone_number: '+553587017046', email: 'antigo@exemplo.com')
      zap.update!(label_list: ['cevico'])
      run_with([row(own.merge('SCH_ITE_TOKEN' => 'tok-fran', 'SCH_PATIENT_NAME' => 'Francislene Pereira Borges',
                              'SCH_PATIENT_MAIL' => 'francislene@exemplo.com'))])

      expect(Crm::OftalmofacilSurgery.find_by(item_token: 'tok-fran').contact_id).to eq(zap.id)
      expect(account.contacts.count).to eq(1)
      zap.reload
      expect(zap.name).to eq('Francislene Pereira Borges')
      expect(zap.email).to eq('francislene@exemplo.com')
      expect(zap.phone_number).to eq('+553587017046') # o número do WhatsApp continua o principal
      expect(zap.custom_attributes['cpf']).to eq('11122233344')
      expect(zap.label_list).to eq(['cevico'])
      expect(Crm::Contact.where(contact_id: zap.id, pipeline_id: cevico.id).count).to eq(1)
    end

    it 'mesmo telefone com OUTRO primeiro nome (mãe × filho): não troca o nome e deixa alerta para conferir',
       :aggregate_failures do
      mae = account.contacts.create!(name: 'Vera Lima', phone_number: '+5535987017046')
      run_with([row(own.merge('SCH_ITE_TOKEN' => 'tok-filho', 'SCH_PATIENT_NAME' => 'Ricardo Lima'))])
      mae.reload
      expect(mae.name).to eq('Vera Lima')
      expect(Crm::PatientReview.list(mae).map { |e| e['tipo'] }).to eq(['nome_diferente'])
    end

    it 'cadastro com o nome de DUAS pessoas não é renomeado: fica para conferir', :aggregate_failures do
      dupla = account.contacts.create!(name: 'Francislene Pereira Borges E Alice Quadros Schimit', phone_number: '+553587017046')
      run_with([row(own.merge('SCH_ITE_TOKEN' => 'tok-dupla', 'SCH_PATIENT_NAME' => 'Francislene Pereira Borges'))])
      dupla.reload
      expect(dupla.name).to eq('Francislene Pereira Borges E Alice Quadros Schimit')
      expect(Crm::PatientReview.list(dupla).map { |e| e['tipo'] }).to include('duas_pessoas')
    end
  end

  describe 'consulta já lançada na Agenda pela equipe' do
    let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
    let(:admin) { account.users.first }
    let(:paciente) { account.contacts.create!(name: 'Maria Parceira', phone_number: '+5511988887777') }

    def lancada(overrides = {})
      account.tasks.create!({ title: 'Cirurgia: Maria (recepção)', task_type: 'cirurgia', creator: admin, contact: paciente,
                              phone: paciente.phone_number, due_at: tz.parse('2026-09-30 09:40'), unit: 'paulista',
                              description: 'Paciente pediu de manhã. Ligar antes.' }.merge(overrides))
    end

    it 'o hub ADOTA a consulta da equipe (vínculo + origem) em vez de criar outra; o resto fica como a equipe deixou',
       :aggregate_failures do
      task = lancada
      result = run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-2')])
      expect(result.errors).to be_empty
      expect(result.tasks_adopted).to eq(1)
      expect(result.tasks_created).to eq(0)
      expect(account.tasks.where(contact_id: paciente.id).count).to eq(1)

      task.reload
      expect(task.external_ref).to eq('tok-2')
      expect(task.source).to eq('oftalmofacil')
      expect(task.source_detail).to be_nil
      expect(task.creator).to eq(admin)
      expect(task.description).to eq('Paciente pediu de manhã. Ligar antes.')
      expect(task.due_at.in_time_zone(tz).strftime('%H:%M')).to eq('09:40')
      expect(task.booking_kind).to be_nil # continua contando como agendamento da equipe
      expect(task.cevico_born_via).not_to eq('sync') # é o que diz ao sync que ela é da equipe

      # na próxima rodada o item já é achado pelo vínculo: realizada conclui a MESMA
      # task — e SÓ o status muda. O item agora vem sem hora (o hub mandaria 08:00),
      # em outra clínica e com outro nome: título, hora, unidade, tipo e o "sim" do
      # paciente continuam os da equipe (revisão: antes tudo era sobrescrito)
      task.update!(confirmed_at: Time.current)
      run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-2', 'STATUS_LABEL' => 'Realizado', 'SCH_ITE_STATUS' => '2',
                    'SCH_ITE_HOUR' => '0', 'CLI_NAME' => 'IOP Paulista', 'SCH_PATIENT_NAME' => 'MARIA PARCEIRA DA SILVA',
                    'SCH_ITE_LAST_MODIFICATION' => '2026-10-01 10:00:00')])
      expect(account.tasks.where(contact_id: paciente.id).count).to eq(1)
      task.reload
      expect(task.status).to eq('done')
      expect(task.attendance).to eq('attended')
      expect(task.title).to eq('Cirurgia: Maria (recepção)')
      expect(task.due_at.in_time_zone(tz).strftime('%H:%M')).to eq('09:40')
      expect(task.unit).to eq('paulista')
      expect(task.booking_kind).to be_nil
      expect(task.confirmed_at).to be_present
      expect(task.completed_at).to be_present
    end

    it 'item visto pela primeira vez já REALIZADO adota a consulta da equipe e já conclui', :aggregate_failures do
      task = lancada
      result = run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-feita', 'STATUS_LABEL' => 'Realizado',
                             'SCH_ITE_STATUS' => '2')])
      expect(result.tasks_adopted).to eq(1)
      task.reload
      expect(task.external_ref).to eq('tok-feita')
      expect(task.status).to eq('done')
      expect(task.attendance).to eq('attended')
    end

    it 'consulta de OUTRA pessoa com o mesmo telefone (família) não é adotada: nasce a do hub', :aggregate_failures do
      filha = account.contacts.create!(name: 'Julia Filha') # consulta no número da mãe
      da_filha_com_contato = lancada(title: 'Cirurgia: Julia Filha', contact: filha, due_at: tz.parse('2026-09-30 09:35'))
      # "marca para a minha mãe" (#101): sem contato, só com o telefone e o nome de outra pessoa no título
      sem_contato = account.tasks.create!(title: 'Cirurgia: Julia Filha', task_type: 'cirurgia', creator: admin,
                                          phone: '+5511988887777', due_at: tz.parse('2026-09-30 09:45'), unit: 'paulista')
      result = run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-mae')])
      expect(result.tasks_adopted).to eq(0)
      expect(result.tasks_created).to eq(1)
      expect(da_filha_com_contato.reload.external_ref).to be_nil
      expect(da_filha_com_contato.contact_id).to eq(filha.id)
      expect(sem_contato.reload.external_ref).to be_nil
      expect(account.tasks.find_by(external_ref: 'tok-mae')).to be_present
    end

    it 'consulta só com o telefone (paciente ainda não existia) também é adotada e ganha o paciente que o hub criou',
       :aggregate_failures do
      # nenhum contato na conta ainda (sem passar pelo helper, que cria a paciente)
      task = account.tasks.create!(title: 'Cirurgia: Maria (recepção)', task_type: 'cirurgia', creator: admin,
                                   phone: '+5511988887777', due_at: tz.parse('2026-09-30 09:40'), unit: 'paulista')
      expect(task.contact_id).to be_nil
      run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-fone')])
      task.reload
      expect(task.external_ref).to eq('tok-fone')
      expect(task.contact_id).to eq(account.contacts.find_by(phone_number: '+5511988887777').id)
      expect(account.tasks.where(external_ref: 'tok-fone').count).to eq(1)
    end

    it 'não é a mesma consulta: outro DDD, outra hora, outro tipo ou já cancelada → nasce a do hub', :aggregate_failures do
      outra_pessoa = account.contacts.create!(name: 'Maria do Rio', phone_number: '+5521988887777') # mesmos 8 dígitos, outro DDD
      outro_ddd = lancada(contact: outra_pessoa, phone: outra_pessoa.phone_number)
      outra_hora = lancada(due_at: tz.parse('2026-09-30 14:00'))
      outro_tipo = lancada(task_type: 'consulta', modality: 'avaliacao')
      cancelada = lancada(canceled_at: Time.current)
      result = run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-nova')])
      expect(result.tasks_adopted).to eq(0)
      expect(result.tasks_created).to eq(1)
      [outro_ddd, outra_hora, outro_tipo, cancelada].each { |t| expect(t.reload.external_ref).to be_nil }
      expect(account.tasks.find_by(external_ref: 'tok-nova')).to be_present
    end

    it 'item do hub SEM hora casa pelo dia inteiro' do
      task = lancada(due_at: tz.parse('2026-09-30 15:30'))
      run_with([row('PROV_NAME' => 'CATARATA_SP', 'SCH_ITE_TOKEN' => 'tok-sem-hora', 'SCH_ITE_HOUR' => '0')])
      expect(task.reload.external_ref).to eq('tok-sem-hora')
    end

    it 'paciente dos dois lados: item de PARCEIRO adota a consulta da equipe e a carimba como do parceiro' do
      task = lancada
      run_with([row('SCH_ITE_TOKEN' => 'tok-parc')])
      task.reload
      expect(task.external_ref).to eq('tok-parc')
      expect(task.source_detail).to eq('CLINICA VISAO NORTE')
      expect(account.tasks.where(contact_id: paciente.id).count).to eq(1)
    end

    it 'consulta que a recepção marcou como "CEVICO" (origem do formulário) continua da CEVICO ao ser adotada por item de parceiro',
       :aggregate_failures do
      task = lancada(origin: 'cevico')
      run_with([row('SCH_ITE_TOKEN' => 'tok-parc-cev')])
      task.reload
      expect(task.external_ref).to eq('tok-parc-cev')
      expect(task.source_detail).to be_nil
      expect(Crm::PartnerGuard.partner_task?(task)).to be(false)
      expect(task.cevico_source_id).to eq(Crm::Sources.own_id(account))
    end
  end

  # 🔁 ordem inversa: o hub trouxe o item PRIMEIRO e a recepção lançou depois
  describe '#dedupe_tasks!' do
    let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
    let(:admin) { account.users.first }
    let(:paciente) { account.contacts.create!(name: 'Maria Teste', phone_number: '+5511988887777') }
    let(:dia) { tz.now.beginning_of_day + 2.days + 9.hours }

    def consulta(overrides = {})
      account.tasks.create!({ title: 'Consulta: Maria Teste', task_type: 'consulta', modality: 'avaliacao', creator: admin,
                              contact: paciente, phone: paciente.phone_number, due_at: dia, unit: 'paulista' }.merge(overrides))
    end

    it 'une a cópia do hub à consulta da equipe (vínculo, resposta e marcas de lembrete passam; a cópia vai para a Lixeira)',
       :aggregate_failures do
      hub = Crm::Stamp.with(via: 'sync') do
        consulta(due_at: dia + 15.minutes, external_ref: 'tok-dup', source: 'oftalmofacil', booking_kind: 'registro',
                 description: 'Oftalmofácil · IOP', confirmed_at: Time.current)
      end
      recepcao = consulta(description: 'Ligar antes')
      sozinha = consulta(due_at: dia + 1.day, external_ref: 'tok-ok', source: 'oftalmofacil', booking_kind: 'registro', phone: nil, contact: nil)
      paciente.update!(additional_attributes: { 'cevico_appt_reminders' => { hub.id.to_s => { 'd2' => '2026-10-10T09:00:00Z' } } })

      expect(service.dedupe_tasks!(dry: true).map(&:first)).to eq([recepcao])
      expect(recepcao.reload.external_ref).to be_nil # dry não grava

      pairs = service.dedupe_tasks!
      expect(pairs.size).to eq(1)
      expect(service.result.tasks_adopted).to eq(1)
      recepcao.reload
      expect(recepcao.external_ref).to eq('tok-dup')
      expect(recepcao.source).to eq('oftalmofacil')
      expect(recepcao.description).to eq('Ligar antes')
      expect(recepcao.due_at).to eq(dia)
      expect(recepcao.confirmed_at).to be_present
      expect(recepcao.cevico_born_via).not_to eq('sync')
      hub.reload
      expect(hub.canceled_at).to be_present
      expect(hub.cancel_reason).to eq('duplicada_hub')
      expect(hub.external_ref).to be_nil
      expect(sozinha.reload.canceled_at).to be_nil
      marks = paciente.reload.additional_attributes['cevico_appt_reminders']
      expect(marks[recepcao.id.to_s]['d2']).to be_present # o D-2 já mandado não sai de novo
      expect(service.dedupe_tasks!).to be_empty # idempotente

      # a adotada só acompanha o STATUS do hub daqui em diante (sem hora lá = 08:00 NÃO entra)
      surgery = Crm::OftalmofacilSurgery.create!(account: account, item_token: 'tok-dup', status_kind: 'ausente', surgery_date: dia.to_date,
                                                 surgery_hour: nil, provider_name: 'CATARATA_SP', patient_name: 'Maria Teste',
                                                 patient_phone: '11988887777', procedure_type: 'Consulta', contact_id: paciente.id)
      Crm::Stamp.with(via: 'sync') { service.send(:sync_task!, paciente, surgery, false) }
      recepcao.reload
      expect(recepcao.attendance).to eq('missed')
      expect(recepcao.due_at).to eq(dia)
      expect(recepcao.title).to eq('Consulta: Maria Teste')
      expect(recepcao.booking_kind).to be_nil
    end

    it 'cirurgia OD+OE (dois itens do hub) conta a mesma consulta da equipe uma vez só e não adota consulta de outra pessoa',
       :aggregate_failures do
      od = consulta(task_type: 'cirurgia', title: 'Cirurgia: Maria Teste', external_ref: 'tok-od', source: 'oftalmofacil')
      consulta(task_type: 'cirurgia', title: 'Cirurgia: Maria Teste', external_ref: 'tok-oe', source: 'oftalmofacil')
      equipe = consulta(task_type: 'cirurgia', title: 'Cirurgia: Maria Teste')
      filha = consulta(task_type: 'cirurgia', title: 'Cirurgia: Julia Filha', contact: nil, due_at: dia + 10.minutes)
      pairs = service.dedupe_tasks!(dry: true)
      expect(pairs.map(&:first)).to eq([equipe])
      expect(pairs.map(&:last)).to eq([od])
      expect(filha.reload.external_ref).to be_nil
    end
  end

  it 'com parceiros desligados, a consulta filtra pelo fornecedor da CEVICO' do
    svc = described_class.new(account: account, config: config.merge('partners_enabled' => false), silent: true, since: nil)
    captured = nil
    allow(svc).to receive(:query) { |sql, binds|
      captured = [sql, binds]
      []
    }
    svc.call
    expect(captured[0]).to include('PROV_NAME LIKE ?')
    expect(captured[1]).to eq(['%CATARATA_SP%', '%CATARATA_SP%'])
  end

  # 🩹 item 254 (26/09): caso real de 28/09 — 11 itens ativos no hub, só 3 na Agenda
  describe 'a Agenda se conserta sozinha' do
    include ActiveSupport::Testing::TimeHelpers

    let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

    around { |ex| travel_to(tz.parse('2026-09-26 10:00')) { ex.run } }

    def read_without_agenda(rows)
      off = described_class.new(account: account, config: config.merge('agenda_enabled' => false), silent: true, since: nil)
      allow(off).to receive(:query).and_return(rows, [])
      off.call
    end

    it 'item lido ANTES de ligar a Agenda ganha o agendamento na próxima rodada, sem o hub', :aggregate_failures do
      read_without_agenda([row('SCH_ITE_TOKEN' => 'antes', 'SCH_ITE_DATE' => '28/09/2026', 'SCH_ITE_HOUR' => '27000.0',
                               'PROV_NAME' => 'CATARATA_SP')])
      expect(account.tasks.find_by(external_ref: 'antes')).to be_nil

      result = service.heal_agenda!
      task = account.tasks.find_by(external_ref: 'antes')
      expect(result.healed).to eq(1)
      expect(task.due_at.in_time_zone(tz).strftime('%d/%m %H:%M')).to eq('28/09 07:30')
      expect(task.unit).to eq('iop')
      expect(described_class.new(account: account, config: config, since: nil).heal_agenda!.healed).to eq(0) # idempotente
    end

    it 'corrige dia errado e cancelamento do hub; não reabre o que a equipe cancelou nem mexe fora da janela', :aggregate_failures do
      run_with([row('SCH_ITE_TOKEN' => 'hora', 'SCH_ITE_DATE' => '29/09/2026', 'SCH_ITE_HOUR' => '09:00'),
                row('SCH_ITE_ID' => 2, 'SCH_ITE_TOKEN' => 'canc', 'SCH_ITE_DATE' => '29/09/2026', 'SCH_PATIENT_PHONE' => '11911112222'),
                row('SCH_ITE_ID' => 3, 'SCH_ITE_TOKEN' => 'equipe', 'SCH_ITE_DATE' => '29/09/2026', 'SCH_PATIENT_PHONE' => '11933334444'),
                row('SCH_ITE_ID' => 4, 'SCH_ITE_TOKEN' => 'longe', 'SCH_ITE_DATE' => '30/11/2026', 'SCH_PATIENT_PHONE' => '11955556666')])
      account.tasks.find_by(external_ref: 'hora').update!(due_at: tz.parse('2026-09-28 21:00'))
      Crm::OftalmofacilSurgery.find_by(item_token: 'canc').update!(status_kind: 'cancelada')
      account.tasks.find_by(external_ref: 'equipe').update!(canceled_at: Time.current)
      Crm::OftalmofacilSurgery.find_by(item_token: 'longe').update!(surgery_date: Date.new(2026, 9, 29))
      account.tasks.find_by(external_ref: 'longe').update!(due_at: tz.parse('2026-11-30 09:30'))

      described_class.new(account: account, config: config, since: nil).heal_agenda!(days: 3)
      expect(account.tasks.find_by(external_ref: 'hora').due_at.in_time_zone(tz).to_date).to eq(Date.new(2026, 9, 29))
      expect(account.tasks.find_by(external_ref: 'canc').canceled_at).to be_present
      expect(account.tasks.find_by(external_ref: 'equipe').canceled_at).to be_present
      expect(account.tasks.find_by(external_ref: 'longe').due_at.in_time_zone(tz).to_date).to eq(Date.new(2026, 9, 29))
    end

    it 'uma vez por hora traz do hub o que nunca foi lido nos próximos dias (e ignora o que já está no espelho)', :aggregate_failures do
      run_with([row('SCH_ITE_TOKEN' => 'lido', 'SCH_ITE_DATE' => '28/09/2026')])
      fresh = described_class.new(account: account, config: config, since: nil)
      novos = [row('SCH_ITE_TOKEN' => 'lido', 'SCH_ITE_DATE' => '28/09/2026'),
               row('SCH_ITE_ID' => 9, 'SCH_ITE_TOKEN' => 'nunca-lido', 'SCH_ITE_DATE' => '28/09/2026',
                   'SCH_PATIENT_NAME' => 'Carmem de Azevedo', 'SCH_PATIENT_PHONE' => '11977770000')]
      allow(fresh).to receive(:query).and_return(novos)
      result = fresh.refresh_upcoming!
      expect(result.unread_found).to eq(1)
      expect(account.tasks.find_by(external_ref: 'nunca-lido').title).to eq('Cirurgia: Carmem de Azevedo')
    end

    it 'a busca por dia aceita a data do hub em qualquer formato (DATE, texto com e sem zero)' do
      captured = nil
      allow(service).to receive(:query) { |sql, binds|
        captured = [sql, binds]
        []
      }
      service.pull_day(Date.new(2026, 9, 8))
      expect(captured[1]).to include('2026-09-08', '08/09/2026', '8/9/2026')
      expect(captured[0]).to include('DATE(i.SCH_ITE_DATE) IN')
    end
  end
end
