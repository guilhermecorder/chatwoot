require 'rails_helper'

# ✉️ item 410 (24/11): mensagem modelo da tela de Indicações cirúrgicas.
#   · a prévia sai preenchida com nome, médico e procedimento; quem assina é
#     sempre Elizângela (com Z), campo fixo;
#   · fora das 24 h só o modelo APROVADO pela Meta sai (campos editáveis);
#   · dentro das 24 h o texto vai livre, do jeito que a pessoa editou;
#   · o envio desliga o Atendente IA na conversa (pausa 'indicacao', com prazo)
#     e fica anotado na consulta.
RSpec.describe Crm::IndicationMessages do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, name: 'Natália Souza') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'VANESSA TAVEIRA', phone_number: '+5511999990001') }
  let(:task) do
    Task.create!(account: account, creator: user, title: 'Consulta: VANESSA TAVEIRA', task_type: 'consulta',
                 contact_id: contact.id, phone: '+5511999990001', doctor: 'gustavo bittar', attendance: 'attended',
                 due_at: 2.days.ago, surgery_indication: 'indicated', indicated_procedure: 'Refrativa Lasik')
  end
  let(:service) { described_class.new(account: account, task: task, user: user) }

  def approve!(name, body)
    channel.update_columns(message_templates: [ # rubocop:disable Rails/SkipsModelValidations
                             { 'name' => name, 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
                               'components' => [{ 'type' => 'BODY', 'text' => body }] }
                           ])
  end

  def conversation_with_incoming(at)
    ci = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999990001')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi', created_at: at)
    conversation
  end

  before { inbox }

  describe '#preview' do
    it 'preenche os campos com o paciente, quem assina, o médico oficial e o procedimento em frase', :aggregate_failures do
      data = service.preview
      fields = data[:models].first[:fields].to_h { |f| [f[:key], f[:value]] }

      expect(data[:outcome]).to eq('indicado')
      expect(data[:models].pluck(:key)).to eq(%w[boa_noticia boa_noticia_curta])
      expect(fields).to eq('nome' => 'Vanessa', 'atendente' => 'Elizângela', 'medico' => 'Dr. Gustavo Bittar',
                           'procedimento' => 'cirurgia refrativa')
      expect(data[:inbox_id]).to eq(inbox.id)
      expect(data[:inboxes].first[:templates]['boa_noticia'][:status]).to eq('missing')
      expect(data[:blocked]).to be_nil
    end

    it 'sem indicação oferece só o retorno sem indicação' do
      task.update!(surgery_indication: 'not_indicated', indicated_procedure: nil)
      expect(service.preview[:models].pluck(:key)).to eq(%w[sem_indicacao])
    end

    it 'aguardando exame não tem mensagem' do
      task.update!(surgery_indication: 'awaiting_exam', indicated_procedure: nil)
      expect(service.preview[:error]).to be_present
    end

    it 'paciente que pediu para não receber fica bloqueado' do
      contact.add_labels([Crm::OptOut::LABEL])
      expect(service.preview[:blocked]).to include('não receber')
    end
  end

  # 📱 pedido dele (24/11): a mensagem sai pelo número em que a pessoa JÁ TEM conversa
  describe 'por qual número a mensagem sai' do
    let(:second_channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    end
    let(:second) { second_channel.inbox }
    let(:third_channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    end
    let(:third) { third_channel.inbox }

    def talk_in(the_inbox, at:, type: :incoming)
      ci = ContactInbox.find_by(contact: contact, inbox: the_inbox) ||
           create(:contact_inbox, contact: contact, inbox: the_inbox, source_id: '5511999990001')
      conversation = Conversation.find_by(inbox: the_inbox, contact: contact) ||
                     create(:conversation, account: account, inbox: the_inbox, contact: contact, contact_inbox: ci)
      create(:message, account: account, inbox: the_inbox, conversation: conversation, message_type: type, content: 'oi', created_at: at)
      conversation.update_columns(last_activity_at: at) # rubocop:disable Rails/SkipsModelValidations
      conversation
    end

    it 'conversa em mais de um número: vale aquele em que o paciente FALOU por último', :aggregate_failures do
      talk_in(inbox, at: 20.days.ago)
      talk_in(second, at: 3.days.ago)
      # lembrete que só a clínica mandou, mais recente que tudo, não é conversa
      talk_in(third, at: 1.day.ago, type: :outgoing)

      data = service.preview
      expect(data[:inbox_id]).to eq(second.id)
      expect(data[:inbox_reason]).to eq('conversa')
      expect(data[:inboxes].to_h { |i| [i[:id], i[:talks]] }).to eq(inbox.id => true, second.id => true, third.id => false)
    end

    it 'o modelo aprovado em outro número não desvia a mensagem do número da conversa', :aggregate_failures do
      approve!('boas_noticias_indicacao', described_class.model('boa_noticia')[:body]) # aprovado só no 1º número
      talk_in(second, at: 3.days.ago)

      data = service.preview
      expect(data[:inbox_id]).to eq(second.id)
      expect(data[:inboxes].find { |i| i[:id] == second.id }[:templates]['boa_noticia'][:status]).to eq('missing')
    end

    it 'paciente que nunca respondeu: vale o número do último contato com ele', :aggregate_failures do
      talk_in(inbox, at: 10.days.ago, type: :outgoing)
      talk_in(second, at: 2.days.ago, type: :outgoing)

      data = service.preview
      expect(data[:inbox_id]).to eq(second.id)
      expect(data[:inbox_reason]).to eq('ultimo_contato')
    end

    it 'paciente sem conversa nenhuma: vai pelo número que já tem o modelo aprovado', :aggregate_failures do
      second
      second_channel.update_columns(message_templates: [ # rubocop:disable Rails/SkipsModelValidations
                                      { 'name' => 'boas_noticias_indicacao', 'status' => 'APPROVED', 'language' => 'pt_BR',
                                        'category' => 'UTILITY', 'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}' }] }
                                    ])

      data = service.preview
      expect(data[:inbox_id]).to eq(second.id)
      expect(data[:inbox_reason]).to eq('sem_conversa')
    end

    describe 'paciente do Oftalmofácil' do
      before do
        second
        CrmSetting.find_or_create_by!(account: account).update!(agenda_config: { 'oftalmofacil' => { 'partner_inbox_ids' => [second.id] } })
        allow(Crm::PartnerGuard).to receive(:partner_task?).and_return(true)
      end

      it 'só oferece a caixa do parceiro, mesmo que ele tenha conversa em outro número', :aggregate_failures do
        talk_in(inbox, at: 1.hour.ago)

        data = service.preview
        expect(data[:partner]).to be(true)
        expect(data[:inboxes].pluck(:id)).to eq([second.id])
        expect(data[:inbox_id]).to eq(second.id)
      end

      it 'não envia por outro número, nem que a tela peça', :aggregate_failures do
        talk_in(inbox, at: 1.hour.ago)

        result = service.deliver(model_key: 'boa_noticia', inbox_id: inbox.id, mode: 'text', text: 'Oi')
        expect(result[:ok]).to be(false)
        expect(Message.outgoing.count).to eq(0)
      end

      it 'o envio pela caixa do parceiro também deixa a IA desligada na conversa', :aggregate_failures do
        conversation = talk_in(second, at: 1.hour.ago)

        result = service.deliver(model_key: 'boa_noticia', inbox_id: second.id, mode: 'text', text: 'Oi, tudo bem?')
        expect(result[:ok]).to be(true)
        expect(Crm::ResponderPause.active?(conversation.reload)).to be(true)
      end
    end

    it 'paciente da CEVICO nunca recebe pela caixa do parceiro', :aggregate_failures do
      second
      CrmSetting.find_or_create_by!(account: account).update!(agenda_config: { 'oftalmofacil' => { 'partner_inbox_ids' => [second.id] } })
      talk_in(inbox, at: 3.days.ago)

      data = service.preview
      expect(data[:inboxes].pluck(:id)).to eq([inbox.id])
      expect(data[:inbox_id]).to eq(inbox.id)
    end
  end

  describe '#deliver' do
    it 'fora das 24 h, sem modelo aprovado no número, não envia', :aggregate_failures do
      result = service.deliver(model_key: 'boa_noticia', inbox_id: inbox.id, mode: 'template')

      expect(result[:ok]).to be(false)
      expect(result[:error]).to include('ainda não está aprovado')
      expect(Message.outgoing.count).to eq(0)
    end

    it 'fora das 24 h, com o modelo aprovado: sai o modelo com os campos, IA desligada e envio anotado', :aggregate_failures do
      approve!('boas_noticias_indicacao', described_class.model('boa_noticia')[:body])

      # a assinatura é fixa: mesmo que a tela mande outro nome em {{2}}, sai Elizângela
      result = service.deliver(model_key: 'boa_noticia', inbox_id: inbox.id, mode: 'template', values: { '1' => 'Vá', '2' => 'Outra' })
      message = Message.outgoing.last
      state = message.conversation.reload.additional_attributes[Crm::ResponderAgentJob::STATE_KEY]

      expect(result[:ok]).to be(true)
      expect(message.content).to include('Saudações, Vá, tudo bem?', 'Elizângela', 'Dr. Gustavo Bittar', 'a cirurgia refrativa é indicada')
      expect(message.additional_attributes.dig('template_params', 'processed_params', 'body'))
        .to eq('1' => 'Vá', '2' => 'Elizângela', '3' => 'Dr. Gustavo Bittar', '4' => 'cirurgia refrativa')
      expect(message.additional_attributes['cevico_auto']).to eq('indicacao')
      expect(message.sender).to eq(user)
      expect(state).to include('paused' => true, 'reason' => 'indicacao')
      expect(Time.zone.parse(state['until'])).to be_within(1.minute).of(described_class::HUMAN_ONLY_DAYS.days.from_now)
      expect(described_class.history(task.reload).last).to include('model' => 'boa_noticia', 'mode' => 'template', 'message_id' => message.id)
    end

    it 'dentro das 24 h o texto vai livre, do jeito que a pessoa editou', :aggregate_failures do
      conversation = conversation_with_incoming(1.hour.ago)

      result = service.deliver(model_key: 'boa_noticia', inbox_id: inbox.id, mode: 'text', text: 'Oi, Vanessa! Tenho uma boa notícia.')
      message = conversation.messages.outgoing.last

      expect(result[:ok]).to be(true)
      expect(message.content).to eq('Oi, Vanessa! Tenho uma boa notícia.')
      expect(message.additional_attributes['template_params']).to be_nil
      expect(Crm::ResponderPause.state_of(conversation.reload)).to include('paused' => true, 'reason' => 'indicacao')
    end

    it 'texto livre com a janela de 24 h fechada é recusado' do
      conversation_with_incoming(3.days.ago)

      result = service.deliver(model_key: 'boa_noticia', inbox_id: inbox.id, mode: 'text', text: 'Oi')
      expect(result).to include(ok: false)
      expect(result[:error]).to include('24 horas')
    end

    it 'modelo de outra decisão é recusado' do
      result = service.deliver(model_key: 'sem_indicacao', inbox_id: inbox.id, mode: 'template')
      expect(result[:ok]).to be(false)
    end
  end

  describe 'a pausa da indicação no Crm::ResponderPause' do
    let(:conversation) { conversation_with_incoming(1.hour.ago) }

    def pause!(until_at)
      conversation.update!(additional_attributes: { Crm::ResponderAgentJob::STATE_KEY => {
                             'paused' => true, 'reason' => 'indicacao', 'at' => 1.day.ago.iso8601, 'until' => until_at.iso8601
                           } })
    end

    it 'vale até a data gravada e depois religa sozinha', :aggregate_failures do
      pause!(5.days.from_now)
      expect(Crm::ResponderPause.active?(conversation)).to be(true)

      pause!(1.minute.ago)
      expect(Crm::ResponderPause.active?(conversation)).to be(false)
      expect(Crm::ResponderPause.refresh!(conversation)['paused']).to be_nil
    end
  end
end
