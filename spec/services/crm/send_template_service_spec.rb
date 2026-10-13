require 'rails_helper'

# 📨 Porta única da mensagem modelo — Rodada 3 da auditoria (12/10):
#   #45  o serviço expõe a mensagem gravada (a Meta responde DEPOIS; quem chama
#        guarda o id e confere na rodada seguinte se foi recusada)
#   #62  telefone corrigido na ficha: a conversa reaproveitada é a do número
#        ATUAL — a conversa presa ao número velho não recebe mais nada
RSpec.describe Crm::SendTemplateService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tpl) do
    { 'name' => 'lembrete', 'language' => 'pt_BR', 'category' => 'UTILITY', 'processed_params' => { 'body' => { '1' => 'Maria' } } }
  end
  let(:contact) { create(:contact, account: account, name: 'Maria', phone_number: '+5511999990001') }
  let(:source) { Crm::TemplateSource.new(account, inbox, nil, tpl, 'Oi {{1}}', 'Lembrete de consulta (D1)') }

  def conversation_in(the_inbox, phone_digits)
    ci = create(:contact_inbox, contact: contact, inbox: the_inbox, source_id: phone_digits)
    create(:conversation, account: account, inbox: the_inbox, contact: contact, contact_inbox: ci)
  end

  it 'devolve a conversa e expõe a mensagem gravada (status e erro da Meta chegam depois)', :aggregate_failures do
    svc = described_class.new(source: source, contact: contact)
    conversation = svc.perform

    expect(conversation).to be_a(Conversation)
    expect(svc.message).to be_a(Message)
    expect(svc.message.conversation).to eq(conversation)
    expect(svc.message.content).to eq('Oi Maria')
    expect(svc.message.additional_attributes.dig('template_params', 'name')).to eq('lembrete')
    expect(svc.message).to be_sent # ainda sem resposta da Meta
  end

  it 'sem telefone não envia nada e não expõe mensagem', :aggregate_failures do
    sem_fone = create(:contact, account: account, name: 'Sem Fone', phone_number: nil)
    svc = described_class.new(source: source, contact: sem_fone)
    expect(svc.perform).to be_nil
    expect(svc.message).to be_nil
  end

  # 🛡️ Rodada 6 (#257): a porta única provada até a linha gravada no banco
  # (os specs de lembrete/jornada/NPS trocam este serviço por um dublê)
  describe 'a mensagem nasce na conversa certa (Channel::Whatsapp de verdade)' do
    let(:google_inbox) { create(:inbox, account: account, name: 'GOOGLE') }

    it 'reaproveita a conversa que o paciente já tem NESTA caixa — não abre conversa paralela', :aggregate_failures do
      existing = conversation_in(inbox, '5511999990001')
      # conversa mais recente em OUTRA caixa não puxa a mensagem para lá
      create(:conversation, account: account, inbox: google_inbox, contact: contact, created_at: 1.minute.from_now)

      svc = described_class.new(source: source, contact: contact)
      expect { svc.perform }.not_to change(Conversation, :count)

      expect(svc.message.conversation_id).to eq(existing.id)
      expect(svc.message.inbox_id).to eq(inbox.id)
      expect(existing.messages.outgoing.count).to eq(1)
    end

    it 'sem conversa na caixa, cria UMA conversa nela, presa ao telefone do paciente', :aggregate_failures do
      svc = described_class.new(source: source, contact: contact)
      conversation = nil
      expect { conversation = svc.perform }.to change(Conversation, :count).by(1)

      expect(conversation.inbox_id).to eq(inbox.id)
      expect(conversation.contact_id).to eq(contact.id)
      expect(conversation.contact_inbox.source_id).to eq('5511999990001')
      expect(svc.message).to have_attributes(conversation_id: conversation.id, inbox_id: inbox.id, account_id: account.id)
      expect(svc.message).to be_outgoing

      # o 2º envio para a mesma paciente cai na MESMA conversa
      expect { described_class.new(source: source, contact: contact).perform }.not_to change(Conversation, :count)
      expect(conversation.messages.outgoing.count).to eq(2)
    end

    it 'grava a marca cevico_auto (é ela que impede a automação "mensagem enviada" e a pausa da IA de dispararem)', :aggregate_failures do
      svc = described_class.new(source: source, contact: contact)
      svc.perform
      expect(svc.message.reload.additional_attributes['cevico_auto']).to eq('TemplateSource')

      label = account.labels.create!(title: 'reativar')
      campaign = Crm::Campaign.create!(account: account, inbox: inbox, name: 'Reativação', template_params: tpl,
                                       message_preview: 'Oi {{1}}', audience: { 'include_label_ids' => [label.id] })
      by_campaign = described_class.new(source: campaign, contact: contact)
      by_campaign.perform
      expect(by_campaign.message.reload.additional_attributes['cevico_auto']).to eq('Campaign')
    end

    it 'sem modelo (template_params vazio) ou com variável que ficaria em branco: nil e nada gravado', :aggregate_failures do
      sem_modelo = Crm::TemplateSource.new(account, inbox, nil, nil, 'Oi', 'Lembrete')
      variavel_vazia = Crm::TemplateSource.new(account, inbox, nil,
                                               tpl.merge('processed_params' => { 'body' => { '1' => '{{contact.email}}' } }),
                                               'Oi {{1}}', 'Lembrete')
      contact.update!(email: nil)

      expect do
        expect(described_class.new(source: sem_modelo, contact: contact).perform).to be_nil
        expect(described_class.new(source: variavel_vazia, contact: contact).perform).to be_nil
      end.not_to(change { [Conversation.count, Message.count] })
    end

    it 'sem telefone: nil e nenhuma conversa/mensagem criada' do
      sem_fone = create(:contact, account: account, name: 'Sem Fone', phone_number: nil)

      expect { expect(described_class.new(source: source, contact: sem_fone).perform).to be_nil }
        .not_to(change { [Conversation.count, Message.count, ContactInbox.count] })
    end
  end

  describe '.refused' do
    it 'devolve só as mensagens que a Meta recusou, com o erro dela', :aggregate_failures do
      ok = described_class.new(source: source, contact: contact).tap(&:perform).message
      refused = described_class.new(source: source, contact: contact).tap(&:perform).message
      refused.update!(status: :failed, external_error: '132012: Parameter format does not match')
      sem_erro = described_class.new(source: source, contact: contact).tap(&:perform).message
      sem_erro.update!(status: :failed)

      result = described_class.refused([ok.id, refused.id, sem_erro.id, nil])
      expect(result.keys).to contain_exactly(refused.id, sem_erro.id)
      expect(result[refused.id]).to eq('132012: Parameter format does not match')
      expect(result[sem_erro.id]).to eq('a Meta recusou o envio')
      expect(described_class.refused([])).to eq({})
    end
  end

  describe 'telefone corrigido na ficha (#62)' do
    it 'com o mesmo número, reaproveita a conversa que já existe' do
      existing = conversation_in(inbox, '5511999990001')
      expect(described_class.new(source: source, contact: contact).perform).to eq(existing)
    end

    it 'número trocado: a mensagem nasce em conversa nova no número NOVO; a conversa velha fica com o antigo', :aggregate_failures do
      old = conversation_in(inbox, '5511999990001')
      contact.update!(phone_number: '+5511999990002')

      svc = described_class.new(source: source, contact: contact)
      conversation = svc.perform

      expect(conversation).not_to eq(old)
      expect(conversation.contact_inbox.source_id).to eq('5511999990002')
      expect(svc.message.conversation.contact_inbox.source_id).to eq('5511999990002')
      expect(old.reload.contact_inbox.source_id).to eq('5511999990001')
      expect(old.messages.outgoing).to be_empty
      # a conversa velha fica aberta (decisão registrada no serviço), só com a nota do número novo
      expect(old).to be_open
      nota = old.messages.where(message_type: :activity).last
      expect(nota.content).to include('…0001 → …0002', "conversa ##{conversation.display_id}")
      expect(nota).to be_private
      # o número novo passa a ter a sua conversa: a próxima mensagem vai nela
      expect(described_class.new(source: source, contact: contact).perform).to eq(conversation)
    end

    it 'caixa que não amarra o número (site/API) continua na conversa mais recente do paciente' do
      web_inbox = create(:inbox, account: account)
      web_source = Crm::TemplateSource.new(account, web_inbox, nil, tpl, 'Oi {{1}}', 'Teste')
      existing = create(:conversation, account: account, inbox: web_inbox, contact: contact)

      expect(described_class.new(source: web_source, contact: contact).perform).to eq(existing)
    end
  end
end
