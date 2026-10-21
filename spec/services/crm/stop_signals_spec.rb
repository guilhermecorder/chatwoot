require 'rails_helper'

# 🚦 Saúde do WhatsApp (16/10/2026): quem não quer mais receber — CERTO
# (pediu por escrito / Meta 131050) × SUSPEITA (bloqueio provável / frase)
RSpec.describe Crm::StopSignals do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }

  def patient(name = 'Marlene')
    create(:contact, account: account, name: name, phone_number: "+55119#{rand(10_000_000..99_999_999)}")
  end

  def conv_for(contact)
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end

  def out!(conv, status, hours_ago, attrs = {}, source_id: "wamid.#{SecureRandom.hex(6)}")
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, sender: admin,
                     content: 'Oi! Conseguiu ver o orçamento?', status: status, source_id: source_id,
                     created_at: hours_ago.hours.ago, additional_attributes: attrs)
  end

  def in!(conv, hours_ago, text = 'oi')
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :incoming, sender: conv.contact,
                     content: text, created_at: hours_ago.hours.ago)
  end

  describe 'frases (Crm::OptOut.classify)' do
    it 'só é CERTO quando a mensagem inteira é o pedido de parar' do
      ['PARE', 'Sair', 'stop!', 'Não quero mais receber mensagens, obrigado', 'pare de me mandar mensagem',
       'me tira da lista por favor', 'Descadastrar'].each do |text|
        expect(Crm::OptOut.classify(text)).to eq(:certo), text
      end
    end

    it 'frase no meio da conversa é só SUSPEITA' do
      ['Vou bloquear esse número', 'isso é spam?', 'por favor remova meu número do cadastro de vocês',
       'Não quero mais', 'quem te deu meu número?', 'boa tarde, pare de mandar isso todo dia'].each do |text|
        expect(Crm::OptOut.classify(text)).to eq(:suspeita), text
      end
    end

    it 'não confunde conversa normal (os falsos positivos do detector antigo)' do
      ['Sair de casa às 8h dá tempo?', 'Cancelar a consulta de amanhã', 'cancelar', 'quero remarcar a consulta',
       'Remover o curativo quando?', 'Para quando tem horário?', 'não quero mais esperar, pode ser hoje?',
       # frases reais da base (cópia até 21/09) que o detector antigo marcava ou que parecem pedido e não são
       'Parar de usar óculos perto e longe.', 'Não quero mais usar óculos', 'Cancelar fazendo favor passa vaga p.outro',
       'Perdão, chamei no número errado, já enviei mensagem no correto.'].each do |text|
        expect(Crm::OptOut.classify(text)).to be_nil, text
      end
    end

    it 'aplica nao_perturbe com o motivo, e a suspeita vira etiqueta própria' do
      contact = patient
      conv = conv_for(contact)
      out!(conv, :read, 5)
      Crm::OptOut.handle_incoming!(in!(conv, 1, 'PARE'), contact)
      expect(contact.reload.label_list).to include('nao_perturbe')
      expect(described_class.evidence(contact).dig('nao_perturbe', 'texto')).to eq('PARE')

      other = patient('Fabio')
      Crm::OptOut.handle_incoming!(in!(conv_for(other), 1, 'vou denunciar vocês'), other)
      expect(other.reload.label_list).to include('suspeita_nao_quer')
      expect(other.label_list).not_to include('nao_perturbe')
    end
  end

  describe 'aviso da Meta 131050' do
    it 'marca certo_sem_marketing com o motivo e solta quando o marketing volta a entregar' do
      contact = patient
      conv = conv_for(contact)
      out!(conv, :read, 30)
      msg = out!(conv, :failed, 1)
      msg.update!(external_error: '131050: Unable to deliver the message. This recipient has chosen to stop receiving marketing messages')
      described_class.on_status_change(msg)

      expect(contact.reload.label_list).to include('certo_sem_marketing')
      proof = described_class.evidence(contact)['certo_sem_marketing']
      expect(proof['codigo']).to eq('131050')
      expect(proof.dig('ultima_entregue', 'origem')).to eq('equipe')

      back = out!(conv, :delivered, 0, { 'cevico_wa_billing' => { 'category' => 'marketing' } })
      described_class.on_status_change(back)
      expect(contact.reload.label_list).not_to include('certo_sem_marketing')
    end

    it 'erro da recusa no envio também conta: "(#131050) …"' do
      expect(described_class.error_code('(#131050) recipient stopped marketing')).to eq('131050')
      expect(described_class.error_code('131026: Message undeliverable')).to eq('131026')
      expect(described_class.error_code('Template not found')).to be_nil
    end
  end

  describe 'varredura da suspeita de bloqueio' do
    # o número está entregando para os outros pacientes na mesma época
    def healthy_inbox!(hours_ago)
      3.times { out!(conv_for(patient('Outro')), :delivered, hours_ago - 1) }
    end

    def blocked_case(name = 'Marlene')
      contact = patient(name)
      conv = conv_for(contact)
      out!(conv, :read, 200)
      out!(conv, :sent, 72, { 'cevico_followup_bot_id' => 3 })
      out!(conv, :sent, 50)
      [contact, conv]
    end

    it 'marca quem já recebia e agora fica só em "enviado", com o motivo' do
      contact, = blocked_case
      healthy_inbox!(70)
      result = Crm::BlockSuspicionScan.new(account).call

      expect(result[:marcados]).to eq(1)
      expect(contact.reload.label_list).to include('suspeita_bloqueio')
      proof = described_class.evidence(contact)['suspeita_bloqueio']
      expect(proof['presas']).to eq(2)
      expect(proof.dig('primeira_presa', 'origem')).to eq('followup:3')
      expect(proof.dig('ultima_entregue', 'origem')).to eq('equipe')
    end

    it 'não marca quando falta alguma trava' do
      healthy_inbox!(70)
      never = patient('Nunca recebeu')
      c1 = conv_for(never)
      out!(c1, :sent, 72)
      out!(c1, :sent, 60)

      wrote = patient('Respondeu')
      c2 = conv_for(wrote)
      out!(c2, :read, 200)
      out!(c2, :sent, 72)
      out!(c2, :sent, 60)
      in!(c2, 10)

      recent = patient('Recente')
      c3 = conv_for(recent)
      out!(c3, :read, 200)
      out!(c3, :sent, 30)
      out!(c3, :sent, 20)

      one = patient('Só uma')
      c4 = conv_for(one)
      out!(c4, :read, 200)
      out!(c4, :sent, 72)

      Crm::BlockSuspicionScan.new(account).call
      [never, wrote, recent, one].each { |c| expect(c.reload.label_list).not_to include('suspeita_bloqueio'), c.name }
    end

    it 'não marca ninguém se o número inteiro parou de entregar (problema da caixa, não da pessoa)' do
      contact, = blocked_case
      Crm::BlockSuspicionScan.new(account).call
      expect(contact.reload.label_list).not_to include('suspeita_bloqueio')
    end

    it 'sai sozinha quando volta a entregar, e quem tirou à mão não volta pelo mesmo sinal' do
      contact, conv = blocked_case
      healthy_inbox!(70)
      Crm::BlockSuspicionScan.new(account).call
      expect(contact.reload.label_list).to include('suspeita_bloqueio')

      described_class.unmark!(contact, 'suspeita_bloqueio', motivo: 'teste', by: admin, dismiss: true)
      Crm::BlockSuspicionScan.new(account).call
      expect(contact.reload.label_list).not_to include('suspeita_bloqueio')

      other, = blocked_case('Fabio')
      Crm::BlockSuspicionScan.new(account).call
      expect(other.reload.label_list).to include('suspeita_bloqueio')
      described_class.on_status_change(out!(Conversation.find_by(contact: other), :delivered, 0))
      expect(other.reload.label_list).not_to include('suspeita_bloqueio')
      expect(conv).to be_present
    end
  end

  describe 'chavinhas dos robôs' do
    it 'certo_sem_marketing para os robôs por padrão; as suspeitas só se ligar' do
      expect(described_class.robot_stop_labels(account)).to eq(['certo_sem_marketing'])
      expect(Crm::OptOut.quiet_titles(account)).to include('nao_perturbe', 'certo_sem_marketing')
      expect(Crm::OptOut.quiet_titles(account)).not_to include('suspeita_bloqueio')

      described_class.save_settings!(account, 'robos' => { 'suspeita_bloqueio' => true, 'certo_sem_marketing' => false })
      expect(described_class.robot_stop_labels(account)).to eq(['suspeita_bloqueio'])
      expect(Crm::OptOut.quiet_titles(account)).to include('suspeita_bloqueio')
    end
  end

  it 'o painel monta os 4 blocos' do
    conv = conv_for(patient)
    out!(conv, :read, 5, { 'template_params' => { 'name' => 'orcamento_v2' } })
    allow(Crm::WhatsappHealthLog).to receive_messages(health: { quality_rating: 'RED', messaging_limit_tier: 'TIER_1K' }, templates: [])
    report = Crm::WhatsappHealthReport.new(account: account).call

    expect(report[:numbers].first).to include(quality: 'RED', limit_tier: 'TIER_1K')
    expect(report[:numbers].first[:week][:read]).to eq(1)
    expect(report[:people][:counts]).to include('suspeita_bloqueio' => 0)
    expect(report[:silence][:by_template].first[:key]).to eq('orcamento_v2')
    expect(report[:rules][:robots]).to include('certo_sem_marketing' => true)
  end
end
