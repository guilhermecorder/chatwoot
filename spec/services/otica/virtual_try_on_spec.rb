require 'rails_helper'

# rubocop:disable Layout/LineLength

# 🪞 08/11: prova virtual pelo WhatsApp — da foto da cliente às imagens na conversa
RSpec.describe Otica::VirtualTryOn do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:png) { File.binread(Rails.root.join('spec/assets/sample.png')) }
  let(:rosto) { { 'pessoas' => 1, 'frontal' => true, 'formato' => 'redondo', 'usa_oculos' => false, 'adulto' => true, 'qualidade' => 'ok', 'observacao' => '', 'genero' => 'feminino' } }

  before do
    CrmSetting.create!(account: account, ai_config: { 'gemini_api_key' => 'AIza-teste' })
    Cevico::Company.save!(account, 'segment' => 'otica')
    # os testes antigos fazem várias provas seguidas; o catálogo (22/11) tem teste próprio
    stub_const('Otica::VirtualTryOn::ROUNDS_BEFORE_CATALOG', 99)
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
    expect(out).to include(ok: true, simulado: true, rosto: 'redondo', rosto_label: 'redondo', combinacao: 'exata')
    # 🔁 08/11 (noite): sem foto fica de fora; a redonda FOGE do rosto redondo e nunca vai pra cliente
    expect(out[:armacoes].pluck(:id)).to eq([retangular.id])
    expect(out[:armacoes].first[:combinacao]).to eq('exata')
    expect(out[:visagismo]).to include('Rosto redondo')
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  # 🔁 08/11 (noite, Guilherme): "se não combinar perfeitamente, o mais aproximado; se não tiver, fala a verdade"
  it 'é honesta: só aproximadas avisam o agente e a legenda; nada que combine recusa pedindo a verdade e o retorno', :aggregate_failures do
    aviador = armacao('Aviador dourado', 'aviador') # rosto redondo: nem recomendada nem foge
    selfie!
    out = service(live: false).run(quantidade: 2)
    expect(out).to include(ok: true, combinacao: 'aproximada')
    expect(out[:aviso_honesto]).to include('MAIS PRÓXIMAS').and include('agendar_retorno')
    expect(out[:armacoes].first).to include(id: aviador.id, combinacao: 'aproximada')
    expect(service.send(:caption_for, aviador, 1, 1, rosto, nil)).to include('É a mais próxima do ideal pro seu rosto que temos hoje')

    aviador.update!(frame_shape: 'redonda') # agora só há o que foge
    out = service(live: false).run(quantidade: 2)
    expect(out[:ok]).to be(false)
    expect(out[:motivo]).to start_with('SEM MODELO PRO ROSTO').and include('retangular').and include('agendar_retorno {dias: 7')
  end

  it 'ao vivo gera a foto de cada armação e envia UMA imagem com moldura (rosto + modelos ideais + 1 e 2); registra o lote', :aggregate_failures do
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
    sent = all_out.drop(1).select { |m| m.attachments.any? } # a moldura (a pergunta de fechamento vem depois, sem anexo)
    expect(sent.size).to eq(1) # 🖼️ 22/11: as 2 opções numa imagem só
    # legenda = as 2 opções, cada uma com nome (formato) + o MOTIVO em palavras simples
    expect(sent.first.content).to eq("Opção 1 de 2 · Retangular preta (retangular): no seu rosto redondo, a retangular dá definição e alonga o olhar.\n\n" \
                                     'Opção 2 de 2 · Gatinho (gatinho): no seu rosto redondo, a gatinho levanta o olhar e valoriza as maçãs do rosto.')
    expect(sent).to all(satisfy { |m| m.attachments.one? && m.attachments.first.file_type == 'image' && m.attachments.first.file.attached? })
    expect(out[:armacoes].first).to include(motivo: 'no seu rosto redondo, a retangular dá definição e alonga o olhar')
    expect(out[:aviso]).to include('Qual você já se imagina usando: o 1 ou o 2?').and include('TAMBÉM JÁ FOI ENVIADA')
    # 08/11 (noite, teste real: o agente ficou mudo): o sistema manda a pergunta depois da última foto
    pergunta = conversation.messages.outgoing.where("additional_attributes ? 'cevico_prova_pergunta'").last
    expect(pergunta.content).to eq('Qual você já se imagina usando: o 1 ou o 2?')
    expect(pergunta.id).to be > conversation.messages.outgoing.joins(:attachments).maximum(:id)
    expect(out[:foto_usada]).to eq('de frente')
    # a moldura: 1080×1350 (4:5) JPEG (sem marca: a loja ainda não subiu o logo)
    card = MiniMagick::Image.read(sent.first.attachments.first.file.blob.open(&:read))
    expect([card.width, card.height, card.type]).to eq([1080, 1350, 'JPEG'])
    expect(sent.first.additional_attributes['cevico_ia_agent']).to eq('atendente_agendamento')
    expect(sent.first.additional_attributes.dig('cevico_visagismo', 'product_id')).to eq(retangular.id)
    expect(sent.first.additional_attributes.dig('cevico_visagismo', 'product_ids')).to eq([retangular.id, gatinho.id])
    # 08/11: o anexo tem que existir no commit da mensagem — senão o Message dispara o SendReplyJob sem
    # espera e o WhatsApp recebe só a legenda (o Message só agenda com wait quando já há anexo)
    reply_jobs = enqueued_jobs.select { |j| j[:job] == SendReplyJob && sent.map(&:id).include?(j[:args].first) }
    expect(reply_jobs.size).to eq(1)
    expect(reply_jobs).to all(satisfy { |j| j['scheduled_at'].present? })
    # a pergunta sai DEPOIS da última foto (agendada com espera maior que a das imagens)
    ask_job = enqueued_jobs.find { |j| j[:job] == SendReplyJob && j[:args].first == pergunta.id }
    expect(ask_job['scheduled_at']).to be_present
    expect(ask_job['scheduled_at']).to be > reply_jobs.map { |j| j['scheduled_at'] }.max
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

  it 'parecida_com: 2 do mesmo estilo (top de linha × mais acessível) com o valor na legenda; "outra" não repete', :aggregate_failures do
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
    retas = [ref, cara, media, boa, barata]
    # 🔀 22/11: a ordem entre as retangulares (mesma pontuação) varia por conversa; as 2 saem das retangulares
    expect(first[:armacoes].pluck(:id)).to all(be_in(retas.map(&:id)))

    ela_responde!
    out = service.run(quantidade: 3, parecida_com: ref.id) # 22/11: no máximo 2 ("só duas opções")
    expect(out).to include(ok: true, enviadas: 2, parecidas: true)
    # "outra" não repete: só as retangulares que ainda não saíram (nem a de referência); a mais cara e a mais barata
    resto = (retas - [ref]).reject { |p| first[:armacoes].pluck(:id).include?(p.id) }.sort_by(&:price)
    expect(out[:armacoes].map { |a| [a[:id], a[:faixa]] }).to eq([[resto.last.id, 'Top de linha'], [resto.first.id, 'Mais acessível']])
    texts = conversation.messages.outgoing.order(:id).pluck(:content)
    expect(texts.last).to eq('Qual você já se imagina usando: o 1 ou o 2?') # 08/11 (noite): a pergunta sai do sistema
    texts = texts[0...-1]
    expect(texts).to include("Boa escolha!\n\nVou te mandar 2 opções nesse mesmo estilo pra você comparar.\n\nSó um instante.")
    expect(texts.last).to start_with('Top de linha · R$ ').and include("\n\nMais acessível · R$ ")

    expect(service.run(quantidade: 3, parecida_com: 999_999)[:motivo]).to include('Não achei')
  end

  it 'vale sempre a ÚLTIMA foto boa (o formato é lido nela) e sai ANTES/DEPOIS com a marca; perfil (lado) não serve', :aggregate_failures do
    armacao('Aviador', 'aviador') # combina (ou aproxima) com redondo, oval e quadrado: a escolha honesta não recusa
    selfie!(rosto.merge('angulo' => 'frente', 'formato' => 'redondo'))
    tres_quartos = selfie!(rosto.merge('angulo' => 'tres_quartos', 'formato' => 'oval'))
    CrmSetting.find_by(account: account).otica_logo.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'logo.png', content_type: 'image/png')
    fake = instance_double(Otica::TryOnImage, generate: { bytes: png, mime: 'image/png', model: 'm' })
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)
    allow(Otica::TryOnCard).to receive(:compose).and_call_original
    Otica::SalesTools.save_config!(account, 'cartao' => 'antes_depois') # o cartão antigo segue disponível

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

  # 🕶️🚹 22/11: óculos de sol fora da prova de grau; foto antiga (sem gênero) é relida uma vez ao vivo
  it 'tira óculos de sol (a não ser que peça sol) e relê homem/mulher de foto antiga, guardando na foto', :aggregate_failures do
    sol = Otica::Product.create!(account: account, kind: 'solar', name: 'HB Switch polarizado', frame_shape: 'retangular', list_price: 300, quantity: 2)
    sol.photo.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'a.png', content_type: 'image/png')
    fem = armacao('Jean Marcell JM6105 roxa e rosa', 'retangular').tap { |p| p.update!(frame_fit: 'feminina', color: 'roxa e rosa') }
    masc = armacao('Bulget BG8040M', 'retangular').tap { |p| p.update!(frame_fit: 'masculina') }

    selfie!(rosto.merge('genero' => 'feminino'))
    expect(service(live: false).run(quantidade: 2)[:armacoes].pluck(:id)).to eq([fem.id])
    expect(service(live: false).run(quantidade: 2, preferencia: 'quero de sol')[:armacoes].pluck(:id)).to include(sol.id)

    antiga = selfie!(rosto.except('genero')) # lida antes de 22/11
    fake = instance_double(Otica::TryOnImage, generate: { bytes: png, mime: 'image/png', model: 'm' })
    allow(Otica::TryOnImage).to receive(:new).and_return(fake)
    allow_any_instance_of(described_class).to receive(:read_face).and_return(rosto.merge('genero' => 'masculino')) # rubocop:disable RSpec/AnyInstance
    out = service.run(quantidade: 2)
    expect(out).to include(ok: true, publico: 'masculino')
    expect(out[:armacoes].pluck(:id)).to eq([masc.id])
    expect(antiga.reload.meta.dig('cevico_media', 'rosto', 'genero')).to eq('masculino')
  end

  # 📖 22/11 (Guilherme): homem ou mulher primeiro; 2 provas sem acerto → catálogo de estilos com código
  describe 'catálogo de estilos e público' do
    before { stub_const('Otica::VirtualTryOn::ROUNDS_BEFORE_CATALOG', 2) }

    def prova_enviada!(lote)
      conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: 'prova',
                                    additional_attributes: { 'cevico_visagismo' => { 'lote' => lote, 'product_ids' => [] } })
    end

    it 'foto sem gênero claro: pergunta antes de mostrar', :aggregate_failures do
      armacao('Retangular', 'retangular')
      selfie!(rosto.merge('genero' => 'incerto'))
      out = service(live: false).run(quantidade: 2)
      expect(out[:ok]).to be(false)
      expect(out[:motivo]).to include('homem ou pra mulher')
      expect(service(live: false).run(quantidade: 2, publico: 'feminino')[:ok]).to be(true)
    end

    it 'depois de 2 provas manda o catálogo; o código escolhido traz só aquele estilo, escura e clara', :aggregate_failures do
      gat_preta = armacao('Gatinho preta', 'gatinho').tap { |p| p.update!(color: 'preto', frame_fit: 'feminina') }
      gat_nude = armacao('Gatinho nude', 'gatinho').tap { |p| p.update!(color: 'nude', frame_fit: 'feminina') }
      armacao('Retangular', 'retangular')
      selfie!
      prova_enviada!('a1')
      prova_enviada!('b2')
      ela_responde!

      out = service.run(quantidade: 2)
      expect(out).to include(ok: true, catalogo: true, publico: 'feminino')
      catalogo = conversation.messages.outgoing.where("additional_attributes ? 'cevico_catalogo_estilos'").last
      expect(catalogo.attachments.size).to eq(1)
      expect(catalogo.content).to include('F1 Gatinho')
      expect(conversation.messages.outgoing.last.content).to include('código')

      ela_responde!
      expect(service.run(quantidade: 2)[:motivo]).to include('JÁ foi enviado')
      expect(service(live: false).run(quantidade: 2, estilo: 'x9')[:motivo]).to include('não reconhecido')

      out = service(live: false).run(quantidade: 2, estilo: 'f1')
      expect(out).to include(ok: true, estilo: 'F1 Gatinho')
      expect(out[:armacoes].pluck(:id)).to contain_exactly(gat_preta.id, gat_nude.id)
      expect(out[:armacoes].pluck(:tom)).to contain_exactly('escura', 'clara')
      expect(out[:aviso]).to include('NADA substitui')
    end

    it 'o código aceita "o 1" e o público do código vale quando a foto não diz' do
      expect(Otica::CatalogoEstilos.normalize('o 3', 'masculino')).to eq('M3')
      expect(Otica::CatalogoEstilos.normalize('f2')).to eq('F2')
      expect(Otica::CatalogoEstilos.normalize('M9')).to be_nil
      expect(File).to exist(Otica::CatalogoEstilos.image_path('masculino'))
      expect(File).to exist(Otica::CatalogoEstilos.image_path('feminino'))
    end
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
