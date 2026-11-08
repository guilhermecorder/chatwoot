require 'rails_helper'

# 🪞 08/11: prova virtual pelo WhatsApp — da foto da cliente às imagens na conversa
RSpec.describe Otica::VirtualTryOn do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:rosto) { { 'pessoas' => 1, 'frontal' => true, 'formato' => 'redondo', 'usa_oculos' => false, 'adulto' => true, 'qualidade' => 'ok', 'observacao' => '' } }

  before do
    CrmSetting.create!(account: account, ai_config: { 'gemini_api_key' => 'AIza-teste' })
    Cevico::Company.save!(account, 'segment' => 'otica')
  end

  def armacao(name, shape, quantity: 2, photo: true)
    p = Otica::Product.create!(account: account, kind: 'armacao', name: name, frame_shape: shape, list_price: 300, quantity: quantity)
    p.photo.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'armacao.png', content_type: 'image/png') if photo
    p
  end

  def selfie!(rosto_meta = rosto, tipo: 'selfie')
    msg = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil)
    msg.attachments.create!(account_id: account.id, file_type: :image,
                            file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png'),
                            meta: { 'cevico_media' => { 'status' => 'done', 'tipo' => tipo, 'descricao' => 'mulher sorrindo', 'rosto' => rosto_meta } })
  end

  def service(live: true)
    described_class.new(account: account, conversation: conversation, live: live, agent_key: 'atendente_agendamento')
  end

  it 'em sombra escolhe pelo rosto e NÃO gera nem envia nada', :aggregate_failures do
    retangular = armacao('Retangular preta', 'retangular')
    armacao('Redonda', 'redonda')
    armacao('Sem foto', 'gatinho', photo: false)
    selfie!
    expect(Otica::TryOnImage).not_to receive(:new)

    out = service(live: false).run(quantidade: 3)
    expect(out).to include(ok: true, simulado: true, rosto: 'redondo', rosto_label: 'redondo')
    expect(out[:armacoes].pluck(:id)).to eq([retangular.id, Otica::Product.find_by(name: 'Redonda').id]) # sem foto fica de fora
    expect(out[:visagismo]).to include('Rosto redondo')
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'ao vivo gera a foto de cada armação e envia como mensagem com imagem e legenda; registra o lote', :aggregate_failures do
    retangular = armacao('Retangular preta', 'retangular')
    gatinho = armacao('Gatinho', 'gatinho')
    selfie!
    fake = instance_double(Otica::TryOnImage)
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)
    allow(fake).to receive(:generate).and_return({ bytes: File.binread(Rails.root.join('spec/assets/sample.png')), mime: 'image/png', model: 'gemini-nano-banana-2.1' })

    out = service.run(quantidade: 2, preferencia: nil)
    expect(out).to include(ok: true, enviadas: 2)
    expect(out[:armacoes].pluck(:id)).to eq([retangular.id, gatinho.id])
    expect(out[:aviso]).to include('JÁ FORAM ENVIADAS')
    expect(fake).to have_received(:generate).twice

    sent = conversation.messages.outgoing.order(:id).to_a
    expect(sent.map(&:content)).to eq(['Opção 1 de 2: Retangular preta', 'Opção 2 de 2: Gatinho'])
    expect(sent).to all(satisfy { |m| m.attachments.one? && m.attachments.first.file_type == 'image' && m.attachments.first.file.attached? })
    expect(sent.first.additional_attributes['cevico_ia_agent']).to eq('atendente_agendamento')
    expect(sent.first.additional_attributes.dig('cevico_visagismo', 'product_id')).to eq(retangular.id)
    expect(sent.map { |m| m.additional_attributes.dig('cevico_visagismo', 'lote') }.uniq.size).to eq(1)
    # 08/11: o anexo tem que existir no commit da mensagem — senão o Message dispara o SendReplyJob sem
    # espera e o WhatsApp recebe só a legenda (o Message só agenda com wait quando já há anexo)
    reply_jobs = enqueued_jobs.select { |j| j[:job] == SendReplyJob && sent.map(&:id).include?(j[:args].first) }
    expect(reply_jobs.size).to eq(2)
    expect(reply_jobs).to all(satisfy { |j| j['scheduled_at'].present? })
  end

  it 'recusa com motivo claro: sem foto, foto que não serve, limite do dia, ramo clínica', :aggregate_failures do
    armacao('Retangular', 'retangular')
    expect(service.run[:motivo]).to include('Ainda não há foto')

    selfie!(rosto.merge('pessoas' => 2))
    expect(service.run[:motivo]).to include('mais de uma pessoa')

    selfie!(rosto.merge('adulto' => false))
    expect(service.run[:motivo]).to include('menor de idade')

    selfie!
    fake = instance_double(Otica::TryOnImage, generate: { bytes: 'x', mime: 'image/png', model: 'm' })
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)
    expect(service.run(quantidade: 1)[:ok]).to be(true)
    expect(described_class.new(account: account, conversation: conversation, live: true).run(quantidade: 1)[:ok]).to be(true)
    third = service.run(quantidade: 1)
    expect(third[:ok]).to be(false)
    expect(third[:motivo]).to include('já recebeu 2')

    Cevico::Company.save!(account, 'segment' => 'clinica')
    expect(service.run[:motivo]).to include('ramo ótica')
  end

  it 'quando o Gemini falha em todas, não promete foto; teto diário da conta trava antes de gastar', :aggregate_failures do
    armacao('Retangular', 'retangular')
    selfie!
    fake = instance_double(Otica::TryOnImage)
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)
    allow(fake).to receive(:generate).and_raise(Otica::TryOnImage::Error.new('Gemini respondeu 500', 500))
    out = service.run(quantidade: 1)
    expect(out[:ok]).to be(false)
    expect(out[:motivo]).to include('não prometa a foto')
    expect(conversation.messages.outgoing.count).to eq(0)

    CrmSetting.find_by(account: account).update!(ai_config: { 'gemini_api_key' => 'AIza-teste', 'visagismo_daily_cap' => 1 })
    Crm::AiUsage.create!(account: account, agent_key: 'visagismo', model: 'm', cost_usd: 0.067)
    expect(service.run(quantidade: 1)[:motivo]).to include('limite diário')
  end

  describe 'ferramenta do agente (Crm::ResponderTools)' do
    it 'aparece só na ótica e nos atendentes de texto; em sombra devolve simulado e registra a ação', :aggregate_failures do
      armacao('Retangular', 'retangular')
      selfie!
      tools = Crm::ResponderTools.new(conversation: conversation, agent_key: 'atendente_agendamento', live: false)
      expect(tools.definitions.pluck(:name)).to include('experimentar_armacoes')
      expect(Crm::ResponderTools.new(conversation: conversation, agent_key: 'voice', live: false).definitions.pluck(:name)).not_to include('experimentar_armacoes')

      out = tools.call('experimentar_armacoes', { 'quantidade' => 1, 'preferencia' => 'preta' })
      expect(out).to include(ok: true, simulado: true)
      expect(tools.acoes.last).to include('ferramenta' => 'experimentar_armacoes', 'ok' => true, 'simulado' => true)
      expect(tools.acoes.last['resumo']).to include('simulado (rosto redondo): Retangular')

      Cevico::Company.save!(account, 'segment' => 'clinica')
      clinic = Crm::ResponderTools.new(conversation: conversation, agent_key: 'atendente_agendamento', live: false)
      expect(clinic.definitions.pluck(:name)).to eq(Crm::ResponderTools::ALL_NAMES)
      expect(clinic.call('experimentar_armacoes', {})[:ok]).to be(false)
    end
  end
end
