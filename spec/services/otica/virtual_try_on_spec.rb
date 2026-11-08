require 'rails_helper'

# rubocop:disable Layout/LineLength

# 🪞 08/11: prova virtual pelo WhatsApp — da foto da cliente às imagens na conversa
RSpec.describe Otica::VirtualTryOn do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:png) { File.binread(Rails.root.join('spec/assets/sample.png')) }
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

  # a cliente responde (uma prova por mensagem dela)
  def ela_responde!(conv = conversation)
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :incoming, content: 'quero ver mais')
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

    all_out = conversation.messages.outgoing.order(:id).to_a
    # 08/11: o AVISO sai antes das imagens ("recebi sua foto…"), sem carimbo de imagem
    aviso = all_out.first
    expect(aviso.content).to include('Recebi sua foto')
    expect(aviso.content).to include("\n\nEm alguns segundos te mando 2 opções pra você comparar.") # anuncia quantas vêm, espaçado
    expect(aviso.attachments).to be_empty
    expect(aviso.additional_attributes).to include('cevico_visagismo_aviso' => true)
    expect(aviso.additional_attributes).not_to have_key('cevico_visagismo')
    sent = all_out.drop(1)
    # legenda = opção + nome (formato) + o MOTIVO em palavras simples
    expect(sent.map(&:content)).to eq(['Opção 1 de 2 · Retangular preta (retangular): no seu rosto redondo, a retangular dá definição e alonga o olhar.',
                                       'Opção 2 de 2 · Gatinho (gatinho): no seu rosto redondo, a gatinho levanta o olhar e valoriza as maçãs do rosto.'])
    expect(sent).to all(satisfy { |m| m.attachments.one? && m.attachments.first.file_type == 'image' && m.attachments.first.file.attached? })
    expect(out[:armacoes].first).to include(motivo: 'no seu rosto redondo, a retangular dá definição e alonga o olhar')
    expect(out[:aviso]).to include('Qual dos dois você já se imagina usando?')
    expect(out[:foto_usada]).to eq('de frente')
    # o cartão: ANTES e DEPOIS lado a lado = 1080×720 JPEG (sem marca: a loja ainda não subiu o logo)
    card = MiniMagick::Image.read(sent.first.attachments.first.file.blob.open(&:read))
    expect([card.width, card.height, card.type]).to eq([1080, 720, 'JPEG'])
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
    fake = instance_double(Otica::TryOnImage, generate: { bytes: png, mime: 'image/png', model: 'm' })
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)
    # 08/11: limite de 12 IMAGENS por cliente por dia, contando todas as conversas dela
    12.times do
      ela_responde!
      expect(service.run(quantidade: 1)[:ok]).to be(true)
    end
    ela_responde!
    third = service.run(quantidade: 1)
    expect(third[:ok]).to be(false)
    expect(third[:motivo]).to include('já recebeu 12')
    outra = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: outra, message_type: :incoming, content: nil).attachments.create!(
      account_id: account.id, file_type: :image, file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png'),
      meta: { 'cevico_media' => { 'status' => 'done', 'tipo' => 'selfie', 'rosto' => rosto } }
    )
    expect(described_class.new(account: account, conversation: outra, live: true).run(quantidade: 1)[:motivo]).to include('já recebeu 12')

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
    expect(conversation.messages.outgoing.joins(:attachments).count).to eq(0)

    CrmSetting.find_by(account: account).update!(ai_config: { 'gemini_api_key' => 'AIza-teste', 'visagismo_daily_cap' => 1 })
    Crm::AiUsage.create!(account: account, agent_key: 'visagismo', model: 'm', cost_usd: 0.067)
    expect(service.run(quantidade: 1)[:motivo]).to include('limite diário')
  end

  it 'parecida_com: 3 do mesmo estilo em faixas (top de linha, custo-benefício, acessível) com o valor na legenda; "outra" não repete', :aggregate_failures do
    ref = armacao('Retangular preta', 'retangular')
    cara = Otica::Product.create!(account: account, kind: 'armacao', name: 'Grife', frame_shape: 'retangular', list_price: 600, quantity: 1)
    media = Otica::Product.create!(account: account, kind: 'armacao', name: 'Meio', frame_shape: 'retangular', list_price: 450, quantity: 1)
    boa = Otica::Product.create!(account: account, kind: 'armacao', name: 'Boa', frame_shape: 'retangular', list_price: 250.5, quantity: 1)
    barata = Otica::Product.create!(account: account, kind: 'armacao', name: 'Básica', frame_shape: 'retangular', list_price: 199, quantity: 1)
    [cara, media, boa, barata].each { |p| p.photo.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'a.png', content_type: 'image/png') }
    armacao('Gatinho', 'gatinho')
    selfie!
    fake = instance_double(Otica::TryOnImage, generate: { bytes: png, mime: 'image/png', model: 'm' })
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)

    ela_responde!
    first = service.run(quantidade: 2)
    expect(first[:armacoes].pluck(:id)).to eq([ref.id, cara.id])

    ela_responde!
    out = service.run(quantidade: 3, parecida_com: ref.id)
    expect(out).to include(ok: true, enviadas: 3, parecidas: true)
    expect(out[:armacoes].map { |a| [a[:id], a[:faixa]] }).to eq([[media.id, 'Top de linha'], [boa.id, 'Melhor custo-benefício'], [barata.id, 'Mais acessível']])
    expect(out[:aviso]).to include('Qual desses 3 você já se imagina usando?')
    texts = conversation.messages.outgoing.order(:id).pluck(:content)
    expect(texts).to include("Boa escolha!\n\nVou te mandar 3 opções nesse mesmo estilo pra você comparar: uma top de linha, uma de melhor " \
                             "custo-benefício e uma mais acessível.\n\nSó um instante.")
    expect(texts.last(3)).to eq(['Top de linha · R$ 450 · Meio (retangular): no seu rosto redondo, a retangular dá definição e alonga o olhar.',
                                 'Melhor custo-benefício · R$ 250,50 · Boa (retangular): no seu rosto redondo, a retangular dá definição e alonga o olhar.',
                                 'Mais acessível · R$ 199 · Básica (retangular): no seu rosto redondo, a retangular dá definição e alonga o olhar.'])

    expect(service.run(quantidade: 3, parecida_com: 999_999)[:motivo]).to include('Não achei')
  end

  it 'vale sempre a ÚLTIMA foto boa (o formato é lido nela) e sai ANTES/DEPOIS com a marca; perfil (lado) não serve', :aggregate_failures do
    armacao('Retangular', 'retangular')
    selfie!(rosto.merge('angulo' => 'frente', 'formato' => 'redondo'))
    tres_quartos = selfie!(rosto.merge('angulo' => 'tres_quartos', 'formato' => 'oval'))
    CrmSetting.find_by(account: account).otica_logo.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'logo.png', content_type: 'image/png')
    fake = instance_double(Otica::TryOnImage, generate: { bytes: png, mime: 'image/png', model: 'm' })
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)
    allow(Otica::TryOnCard).to receive(:compose).and_call_original

    out = service.run(quantidade: 1)
    expect(out).to include(ok: true, rosto: 'oval', foto_usada: 'de 3/4') # a última que ela mandou
    expect(fake).to have_received(:generate).once # uma imagem por armação (o "depois")
    expect(fake).to have_received(:generate).with(hash_including(selfie: tres_quartos.file.blob.open(&:read)))
    expect(Otica::TryOnCard).to have_received(:compose).with(images: [hash_including(bytes: tres_quartos.file.blob.open(&:read)),
                                                                      hash_including(model: 'm')], logo: png, tom: 'vidro')
    Otica::SalesTools.save_config!(account, 'selo_tom' => 'verde')
    expect(Otica::SalesTools.config(account)['selo_tom']).to eq('verde')
    Otica::SalesTools.save_config!(account, 'selo_tom' => 'roxo')
    expect(Otica::SalesTools.config(account)['selo_tom']).to eq('vidro') # só os tons conhecidos (senão o padrão)
    cards = conversation.messages.outgoing.joins(:attachments)
    expect(cards.count).to eq(1) # as duas visões num cartão só
    pair = MiniMagick::Image.read(cards.last.attachments.first.file.blob.open(&:read))
    expect([pair.width, pair.height]).to eq([1080, 720]) # antes | depois, selo de vidro com a marca embaixo
    stamp = cards.last.additional_attributes['cevico_visagismo']
    expect(stamp['selfie_attachment_id']).to eq(tres_quartos.id)

    # ela manda outra (de frente): passa a valer essa
    nova = selfie!(rosto.merge('angulo' => 'frente', 'formato' => 'quadrado'))
    expect(service.run(quantidade: 1)).to include(ok: true, rosto: 'quadrado', foto_usada: 'de frente')
    expect(conversation.messages.outgoing.joins(:attachments).last.additional_attributes.dig('cevico_visagismo', 'selfie_attachment_id')).to eq(nova.id)

    # de lado não serve: continua valendo a última boa
    selfie!(rosto.merge('frontal' => false, 'angulo' => 'lado'))
    expect(Otica::FaceReading.usable(rosto.merge('frontal' => true, 'angulo' => 'lado')).first).to be(false)
    expect(Otica::FaceReading.summary(rosto.merge('angulo' => 'tres_quartos'))).to include('de 3/4')
    expect(service.run(quantidade: 1)).to include(ok: true, rosto: 'quadrado')
  end

  it 'uma prova por mensagem da cliente: a 2ª chamada na mesma resposta é recusada; com a prova em andamento também; "mais uma" não diz "recebi sua foto"', :aggregate_failures do
    armacao('Retangular', 'retangular')
    armacao('Gatinho', 'gatinho')
    selfie!
    fake = instance_double(Otica::TryOnImage, generate: { bytes: png, mime: 'image/png', model: 'm' })
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)

    expect(service.run(quantidade: 1)[:ok]).to be(true)
    avisos = -> { conversation.messages.outgoing.where("additional_attributes ? 'cevico_visagismo_aviso'").order(:id).pluck(:content) }
    expect(avisos.call.last).to include('Recebi sua foto')

    # o caso do Guilherme (08/11 18:34): o agente chama de novo sem ela ter dito nada → nada sai
    count = conversation.messages.outgoing.count
    again = service.run(quantidade: 1)
    expect(again[:ok]).to be(false)
    expect(again[:motivo]).to include('ACABARAM de ser enviadas')
    expect(conversation.messages.outgoing.count).to eq(count)

    # ela pede "mais uma": sai, com o aviso de "mais uma opção" (a foto é a mesma)
    ela_responde!
    expect(service.run(quantidade: 1)[:ok]).to be(true)
    expect(avisos.call.last).to eq("Boa!\n\nVou te mandar mais uma opção no seu rosto pra você comparar.\n\nEm alguns segundos chegam.")

    # duas chamadas ao mesmo tempo: a trava da conversa recusa a segunda
    ela_responde!
    Redis::Alfred.set("otica:prova_virtual:#{conversation.id}", 1, nx: true, ex: 60)
    expect(service.run(quantidade: 1)[:motivo]).to include('ACABARAM de ser enviadas')
    Redis::Alfred.delete("otica:prova_virtual:#{conversation.id}")
    expect(service.run(quantidade: 1)[:ok]).to be(true) # e a trava some no fim de cada prova
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
# rubocop:enable Layout/LineLength
