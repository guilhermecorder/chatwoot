require 'rails_helper'

# rubocop:disable Layout/LineLength

# 💳 22/11: exame com a Fabi pago antecipado no PIX (28/11: R$ 19,90; na hora R$ 50)
RSpec.describe Otica::ExamPix do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { Otica::TZ }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Aquisição') }
  let!(:agendou) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento da visita', position: 1) }
  let!(:pix) { Crm::Stage.create!(pipeline: pipeline, name: 'PIX do exame enviado', position: 2) }
  let!(:pago) { Crm::Stage.create!(pipeline: pipeline, name: 'Exame pago (PIX)', position: 3) }
  let(:exame) do
    Task.create!(account: account, creator: admin, title: 'Consulta: Maria', task_type: 'consulta', contact_id: contact.id,
                 due_at: tz.parse('2026-11-28 09:10'), modality: 'exame')
  end

  before do
    Cevico::Company.save!(account, 'segment' => 'otica')
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: agendou.id)
  end

  def comprovante!(texto)
    msg = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil)
    msg.attachments.create!(account_id: account.id, file_type: :image,
                            file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png'),
                            meta: { 'cevico_media' => { 'status' => 'done', 'tipo' => 'comprovante', 'descricao' => 'comprovante de PIX', 'texto' => texto } })
    [msg, msg.attachments.last]
  end

  def card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id)
  def state = conversation.reload.additional_attributes['cevico_exame_pix']

  it 'marcou o exame no Pix: manda só a chave e o pedido do comprovante, guarda o estado e move o card', :aggregate_failures do
    travel_to tz.parse('2026-11-27 10:00') do
      described_class.request!(account: account, conversation: conversation, contact: contact, task: exame)
    end

    msgs = conversation.messages.outgoing.order(:id)
    expect(msgs.size).to eq(2)
    # 🗣️ 23/11: a oferta (150 × 19,90 × 50) já foi feita pela Val antes de marcar
    expect(msgs.first.content).to include('chave Pix é o CNPJ').and include('pode me enviar o comprovante?')
    expect(msgs.last.content).to eq('32.951.767/0001-92')
    expect(msgs).to all(satisfy { |m| m.cevico_send_wait.present? || m.additional_attributes['cevico_exame_pix_msg'] })
    expect(state).to include('status' => 'aguardando', 'task_id' => exame.id, 'valor' => 19.9)
    expect(card.stage_id).to eq(pix.id)
    expect(exame.reload.comments.last['text']).to include('aguardando o comprovante')

    # remarcou antes de pagar: não manda a chave de novo
    described_class.request!(account: account, conversation: conversation, contact: contact, task: exame)
    expect(conversation.messages.outgoing.count).to eq(2)
  end

  it 'comprovante com R$ 19,90: etiqueta, coluna "Exame pago", nota no agendamento, confirmação e tarefa pra conferir', :aggregate_failures do
    described_class.request!(account: account, conversation: conversation, contact: contact, task: exame)
    msg, att = comprovante!('Pix enviado · R$ 19,90 · para SUA OTICA LTDA · CNPJ 32.951.767/0001-92')
    described_class.receipt!(msg, att)

    expect(state).to include('status' => 'pago', 'attachment_id' => att.id)
    expect(contact.reload.label_list).to include('exame-pago')
    expect(card.stage_id).to eq(pago.id)
    expect(exame.reload.comments.last['text']).to include('recebido')
    outs = conversation.messages.outgoing.order(:id).last(2).map(&:content)
    expect(outs.first).to eq('Um instante, estou terminando o seu agendamento.')
    expect(outs.last).to start_with('Deu certo. Parabéns!').and include('Agendamento de Maria Silva')
      .and include('sábado, 28/11, às 9h10').and include('Valor pago: R$ 19,90').and include('Brg. Vilela Júnior')
    expect(account.tasks.where.not(task_type: 'consulta').last.title.to_s + account.tasks.where.not(task_type: 'consulta').last.description.to_s)
      .to include('Conferir PIX do exame')
  end

  it 'transição de 28/11: quem recebeu a oferta antiga e paga R$ 29,90 também tem o horário confirmado', :aggregate_failures do
    described_class.request!(account: account, conversation: conversation, contact: contact, task: exame)
    msg, att = comprovante!('Transferência Pix R$ 29.90 SUA OTICA')
    described_class.receipt!(msg, att)

    expect(state['status']).to eq('pago')
    expect(conversation.messages.outgoing.order(:id).last.content).to include('Valor pago: R$ 29,90')
  end

  it 'R$ 119,90 ou R$ 1.290,90 não passam por 19,90/29,90' do
    %w[119,90 1.290,90 219.90].each { |v| expect(v).not_to match(described_class::AMOUNT) }
  end

  it 'comprovante com outro valor: não confirma, só pede pra equipe conferir; sem PIX pedido ou fora da ótica, nada acontece', :aggregate_failures do
    msg, att = comprovante!('R$ 15,00')
    described_class.receipt!(msg, att)
    expect(state).to be_nil # sem PIX pedido: o comprovante é de outra coisa

    described_class.request!(account: account, conversation: conversation, contact: contact, task: exame)
    described_class.receipt!(msg, att)
    expect(state['status']).to eq('conferir')
    expect(contact.reload.label_list).not_to include('exame-pago')
    expect(card.stage_id).to eq(pix.id)

    Cevico::Company.save!(account, 'segment' => 'clinica')
    expect(described_class.enabled?(account)).to be(false)
  end

  it 'quem escolhe pagar na hora (R$ 50) não recebe Pix; o resto escolheu o Pix', :aggregate_failures do
    expect(described_class.pix_chosen?('Visita com exame - paga na hora')).to be(false)
    expect(described_class.pix_chosen?('Visita com exame - na loja')).to be(false)
    expect(described_class.pix_chosen?('Visita com exame - Pix')).to be(true)
    expect(described_class.pix_chosen?('Visita com exame')).to be(true)
  end

  it 'prazo do valor: até 24 h, no máximo até as 20 h da véspera, nunca menos de 1 h antes', :aggregate_failures do
    travel_to tz.parse('2026-11-24 10:00') do
      expect(described_class.deadline_for(tz.parse('2026-11-28 09:10'))).to eq(tz.parse('2026-11-25 10:00'))
    end
    travel_to tz.parse('2026-11-27 18:30') do
      expect(described_class.deadline_for(tz.parse('2026-11-28 09:10'))).to eq(tz.parse('2026-11-27 20:00'))
    end
    travel_to tz.parse('2026-11-28 07:00') do
      expect(described_class.deadline_for(tz.parse('2026-11-28 10:00'))).to eq(tz.parse('2026-11-28 09:00'))
    end
  end
end
# rubocop:enable Layout/LineLength
