require 'rails_helper'

# 🔁 item 288 (29/09): reforço das mensagens da jornada (confirmação de
# cirurgia / consulta) para quem não respondeu — envio real stubado.
RSpec.describe Crm::Journey::Followup do # rubocop:disable RSpec/MultipleMemoizedHelpers
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tz) { Crm::Journey::Settings::TZ }
  let(:sent_at) { tz.local(2026, 9, 28, 10, 5) } # segunda: confirmação da cirurgia de quarta
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:body) { { '1' => '{{primeiro_nome}}', '2' => '{{data}}', '3' => '{{hora}}' } }
  let(:tpl) { ->(name) { { 'name' => name, 'language' => 'pt_BR', 'category' => 'UTILITY', 'processed_params' => { 'body' => body } } } }
  let(:followup) do
    { 'enabled' => true, 'hours' => 6, 'max' => 2, 'template_params' => tpl.call('reforco_cirurgia'),
      'message_preview' => '{{1}}, ainda não tivemos sua resposta sobre {{2}} às {{3}}' }
  end
  let(:content) do
    { 'mode' => 'template', 'template_params' => tpl.call('confirmar_cirurgia'),
      'message_preview' => 'Olá {{1}}, sua cirurgia é {{2}} às {{3}}. Confirma?', 'followup' => followup }
  end
  let!(:message) do
    Crm::JourneyMessage.create!(account: account, name: 'Confirmação de cirurgia', step: 'cirurgia', inbox: inbox,
                                trigger: { 'kind' => 'surgery', 'offset_days' => -2, 'at' => '10:00' },
                                content: content, expects_reply: true, confirm_label: 'cirurgia_confirmada')
  end
  let!(:surgery) do
    Crm::OftalmofacilSurgery.create!(account: account, contact: contact, item_token: 'tok1', patient_name: 'Maria Teste',
                                     surgery_date: Date.new(2026, 9, 30), surgery_hour: '08:30', status_kind: 'agendada',
                                     procedure_name: 'Catarata', clinic_name: 'IOP', raw: {})
  end
  let(:templates) { [] }

  def run_at(time)
    travel_to(time) { Crm::JourneyRunJob.perform_now(account.id, now: time) }
  end

  def followups
    Crm::JourneySend.where(journey_message: message).where('event_key ~ ?', ':f[0-9]+$').order(:id)
  end

  before do
    CrmSetting.create!(account: account, agenda_config: {})
    allow(Crm::SendTemplateService).to receive(:new) do |source:, contact: nil| # rubocop:disable Lint/UnusedBlockArgument
      templates << source.template_params['name']
      instance_double(Crm::SendTemplateService, perform: conversation)
    end
    run_at(sent_at) # a confirmação sai às 10h05
  end

  it 'envia o reforço depois de 6 horas sem resposta, com o modelo do reforço, e aparece no histórico', :aggregate_failures do
    expect(templates).to eq(['confirmar_cirurgia'])
    run_at(tz.local(2026, 9, 28, 15, 50))
    expect(templates).to eq(['confirmar_cirurgia'])

    run_at(tz.local(2026, 9, 28, 16, 20))
    expect(templates).to eq(%w[confirmar_cirurgia reforco_cirurgia])
    row = followups.first
    expect(row.event_key).to eq("surgery:#{surgery.id}:f1")
    expect(row.status).to eq('sent')
    expect(row.preview).to eq('Maria, ainda não tivemos sua resposta sobre 30/09 às 08:30')
    expect(row.to_payload).to include(followup_number: 1, status_label: 'Enviada')
    expect(row.sent_at).to be_present
  end

  it 'nunca duas vezes; o 2º reforço sai 6 horas depois do 1º (só a partir das 07h) e para no máximo', :aggregate_failures do
    # na Jornada o reforço também obedece o "horário de envio" da Jornada (padrão 08h): aqui ele começa às 07h
    crm = CrmSetting.find_or_create_by!(account: account)
    crm.update!(agenda_config: (crm.agenda_config || {}).deep_merge('journey' => { 'hours' => { 'start' => '07:00' } }))
    run_at(tz.local(2026, 9, 28, 16, 20))
    run_at(tz.local(2026, 9, 28, 16, 35))
    run_at(tz.local(2026, 9, 28, 19, 50))
    expect(templates.count('reforco_cirurgia')).to eq(1)

    run_at(tz.local(2026, 9, 28, 23, 0))
    run_at(tz.local(2026, 9, 29, 6, 50))
    expect(templates.count('reforco_cirurgia')).to eq(1)
    run_at(tz.local(2026, 9, 29, 7, 5))
    expect(templates.count('reforco_cirurgia')).to eq(2)

    run_at(tz.local(2026, 9, 29, 14, 30))
    expect(templates.count('reforco_cirurgia')).to eq(2)
    expect(followups.map(&:event_key)).to eq(["surgery:#{surgery.id}:f1", "surgery:#{surgery.id}:f2"])
  end

  it 'o banco recusa o mesmo reforço em dobro (índice único) e nada é enviado', :aggregate_failures do
    parent = Crm::JourneySend.find_by(event_key: "surgery:#{surgery.id}")
    Crm::JourneySend.create!(account: account, journey_message: message, contact: contact, source: surgery,
                             event_key: "surgery:#{surgery.id}:f1", scheduled_for: parent.sent_at, status: 'failed')
    service = described_class.new(account: account, now: tz.local(2026, 9, 28, 16, 20))
    draft = Crm::JourneySend.new(account: account, journey_message: message, contact: contact, source: surgery,
                                 event_key: "surgery:#{surgery.id}:f1", scheduled_for: Time.current, status: 'queued')
    expect(service.send(:claim, draft)).to be(false)
    run_at(tz.local(2026, 9, 28, 16, 20)) # reforço que falhou não é tentado de novo sozinho
    expect(templates).to eq(['confirmar_cirurgia'])
  end

  it 'não envia se o paciente escreveu qualquer coisa depois da mensagem' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'bom dia, tenho uma dúvida', created_at: tz.local(2026, 9, 28, 11, 0))
    run_at(tz.local(2026, 9, 28, 16, 20))
    expect(templates).to eq(['confirmar_cirurgia'])
  end

  it 'não envia se o paciente confirmou ou recusou' do
    Crm::JourneySend.find_by(event_key: "surgery:#{surgery.id}").update!(reply: 'confirmed', replied_at: Time.current)
    run_at(tz.local(2026, 9, 28, 16, 20))
    expect(templates).to eq(['confirmar_cirurgia'])
  end

  it 'não envia se a cirurgia foi cancelada ou mudou de data/hora', :aggregate_failures do
    surgery.update!(status_kind: 'cancelada')
    run_at(tz.local(2026, 9, 28, 16, 20))
    surgery.update!(status_kind: 'agendada', surgery_date: Date.new(2026, 10, 2))
    run_at(tz.local(2026, 9, 28, 16, 35))
    surgery.update!(surgery_date: Date.new(2026, 9, 30), surgery_hour: '13:00')
    run_at(tz.local(2026, 9, 28, 16, 50))
    expect(templates).to eq(['confirmar_cirurgia'])
    expect(followups).to be_empty
  end

  it 'nunca depois do horário da cirurgia; reforço vencido há mais de um dia não sai', :aggregate_failures do
    message.update!(content: content.merge('followup' => followup.merge('hours' => 46)))
    run_at(tz.local(2026, 9, 30, 8, 35)) # venceu 30/09 08h05, mas a cirurgia foi 08h30
    expect(templates).to eq(['confirmar_cirurgia'])

    message.update!(content: content)
    run_at(tz.local(2026, 9, 29, 16, 30)) # venceu 28/09 16h05, há mais de 24 h
    expect(templates).to eq(['confirmar_cirurgia'])
  end

  it 'DESLIGADO por padrão: mensagem sem o bloco (ou com ele desligado) não manda reforço', :aggregate_failures do
    message.update!(content: content.except('followup'))
    expect(message.followup?).to be(false)
    run_at(tz.local(2026, 9, 28, 16, 20))
    message.update!(content: content.merge('followup' => followup.merge('enabled' => false)))
    run_at(tz.local(2026, 9, 28, 16, 35))
    expect(templates).to eq(['confirmar_cirurgia'])
  end

  it 'paciente de parceiro do Oftalmofácil e quem pediu silêncio não recebem reforço', :aggregate_failures do
    contact.update!(additional_attributes: (contact.additional_attributes || {}).merge('parceiro' => 'CLINICA X'))
    run_at(tz.local(2026, 9, 28, 16, 20))
    expect(templates).to eq(['confirmar_cirurgia'])
    expect(followups.first&.status).to eq('skipped')
  end

  it 'a resposta ao reforço vale também para o envio original', :aggregate_failures do
    run_at(tz.local(2026, 9, 28, 16, 20))
    travel_to(tz.local(2026, 9, 28, 17, 0)) do
      incoming = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Sim, confirmo')
      expect(Crm::Journey::ReplyService.handle(incoming, contact)).to eq('confirmed')
    end
    expect(Crm::JourneySend.where(journey_message: message).pluck(:reply)).to eq(%w[confirmed confirmed])
  end

  it 'confirmação de CONSULTA pela jornada: reforço sai; consulta confirmada na Agenda não recebe', :aggregate_failures do
    message.update!(active: false)
    consulta_content = content.merge('followup' => followup.merge('template_params' => tpl.call('reforco_consulta')))
    consulta_msg = Crm::JourneyMessage.create!(account: account, name: 'Confirmação de consulta', step: 'consulta', inbox: inbox,
                                               trigger: { 'kind' => 'appointment', 'offset_days' => -2, 'at' => '10:00' },
                                               content: consulta_content)
    ana = create(:contact, account: account, name: 'Ana', phone_number: '+5511999990009')
    base = { task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin }
    account.tasks.create!(base.merge(title: 'Consulta: Maria', due_at: tz.local(2026, 9, 30, 15, 0), contact: contact))
    confirmada = account.tasks.create!(base.merge(title: 'Consulta: Ana', due_at: tz.local(2026, 9, 30, 16, 0), contact: ana))
    templates.clear
    run_at(sent_at + 15.minutes)
    expect(templates.size).to eq(2)

    confirmada.update!(confirmed_at: Time.current)
    templates.clear
    run_at(tz.local(2026, 9, 28, 16, 30))
    expect(templates).to eq(['reforco_consulta'])
    expect(Crm::JourneySend.where(journey_message: consulta_msg).where('event_key ~ ?', ':f1$').pluck(:contact_id)).to eq([contact.id])
  end

  it 'a mensagem exige o modelo do reforço quando ele está ligado' do
    message.content = content.merge('followup' => { 'enabled' => true, 'hours' => 6 })
    expect(message).not_to be_valid
  end
end
