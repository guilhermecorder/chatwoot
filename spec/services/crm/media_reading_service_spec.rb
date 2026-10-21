require 'rails_helper'

# 👂🖼️ item 204: áudio e imagem do paciente viram texto (Gemini simulado)
RSpec.describe Crm::MediaReadingService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:gemini_usage) { { 'promptTokenCount' => 1200, 'candidatesTokenCount' => 40 } }

  before { CrmSetting.create!(account: account, ai_config: { 'gemini_api_key' => 'AIza-teste' }) }

  def incoming(content: nil)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def attach(message, kind)
    file = kind == :audio ? ['spec/assets/sample.ogg', 'audio/ogg'] : ['spec/assets/sample.png', 'image/png']
    message.attachments.create!(account_id: account.id, file_type: kind,
                                file: Rack::Test::UploadedFile.new(Rails.root.join(file[0]), file[1]))
  end

  def gemini_answers(json, code: 200)
    parsed = if code == 200
               { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => json.to_json }] } }], 'usageMetadata' => gemini_usage }
             else
               { 'error' => { 'message' => 'quota' } }
             end
    response = double('gemini', success?: code == 200, code: code, parsed_response: parsed) # rubocop:disable RSpec/VerifiedDoubles
    allow(HTTParty).to receive(:post).and_return(response)
    response
  end

  it 'áudio: transcreve, grava onde a tela mostra, registra o gasto e entra na conversa do Atendente', :aggregate_failures do
    audio = attach(incoming, :audio)
    gemini_answers({ 'texto' => 'Oi, quero saber da cirurgia refrativa, uso óculos há dez anos', 'idioma' => 'pt-BR', 'inaudivel' => false })

    expect(described_class.new(audio).perform).to be(true)
    audio.reload
    expect(audio.meta['transcribed_text']).to eq('Oi, quero saber da cirurgia refrativa, uso óculos há dez anos')
    expect(audio.meta['cevico_media']).to include('status' => 'done', 'model' => 'gemini-2.5-flash', 'inaudivel' => false)
    expect(described_class.transcript_label(audio)).to eq('[áudio transcrito: "Oi, quero saber da cirurgia refrativa, uso óculos há dez anos"]')
    expect(described_class.read?(audio)).to be(true)

    use = Crm::AiUsage.where(account: account).last
    expect(use).to have_attributes(agent_key: 'media_reading', model: 'gemini-2.5-flash', input_tokens: 1200, output_tokens: 40)
    expect(use.cost_usd).to be_within(0.000001).of(((1200 * 1.0) + (40 * 2.5)) / 1_000_000.0)

    expect(HTTParty).to have_received(:post) do |url, opts|
      expect(url).to include('gemini-2.5-flash:generateContent')
      expect(opts[:query]).to eq(key: 'AIza-teste')
      body = JSON.parse(opts[:body])
      expect(body.dig('contents', 0, 'parts', 1, 'inline_data', 'mime_type')).to eq('audio/ogg')
      expect(body.dig('contents', 0, 'parts', 0, 'text')).to include('Transcreva FIELMENTE')
    end
  end

  it 'áudio sem fala: marca inaudível e a conversa pede para perguntar o que o paciente precisa' do
    audio = attach(incoming, :audio)
    gemini_answers({ 'texto' => '', 'idioma' => 'pt-BR', 'inaudivel' => true })

    described_class.new(audio).perform
    expect(audio.reload.meta['cevico_media']).to include('status' => 'done', 'inaudivel' => true)
    expect(described_class.transcript_label(audio)).to include('sem fala compreensível')
  end

  it 'imagem: descreve, copia o texto legível e manda a legenda do paciente junto', :aggregate_failures do
    image = attach(incoming(content: 'esse é o pedido do meu médico'), :image)
    gemini_answers({ 'tipo' => 'pedido_exame', 'descricao' => 'Pedido médico impresso com carimbo.',
                     'texto' => 'Topografia de córnea · Paquimetria' })

    expect(described_class.new(image).perform).to be(true)
    image.reload
    expect(image.meta['transcribed_text']).to eq('Pedido médico impresso com carimbo. · Texto: Topografia de córnea · Paquimetria')
    expect(image.meta['cevico_media']).to include('status' => 'done', 'tipo' => 'pedido_exame', 'texto' => 'Topografia de córnea · Paquimetria')
    expect(described_class.transcript_label(image))
      .to eq('[imagem (pedido_exame): Pedido médico impresso com carimbo. · texto na imagem: "Topografia de córnea · Paquimetria"]')
    # a tela recebe o texto lido no payload do anexo (imagem também, não só áudio)
    expect(image.push_event_data[:transcribed_text]).to include('Pedido médico impresso')

    expect(HTTParty).to have_received(:post) do |_url, opts|
      body = JSON.parse(opts[:body])
      expect(body.dig('contents', 0, 'parts', 0, 'text')).to include('Legenda que o paciente escreveu junto: "esse é o pedido do meu médico"')
      expect(body.dig('contents', 0, 'parts', 1, 'inline_data', 'mime_type')).to eq('image/png')
    end
  end

  it 'Gemini com erro: marca a falha, não insiste a cada mensagem e a conversa pede para escrever', :aggregate_failures do
    audio = attach(incoming, :audio)
    gemini_answers({}, code: 429)

    expect { expect(described_class.new(audio).perform).to be(false) }.not_to change(Crm::AiUsage, :count)
    audio.reload
    expect(audio.meta['cevico_media']).to include('status' => 'failed', 'transient' => true, 'attempts' => 1)
    expect(audio.meta['cevico_media']['error']).to include('429')
    expect(audio.meta['transcribed_text']).to be_nil
    # 🔁 item 340: sem transcrição a IA SEMPRE responde (antes: "uma vez só" → silêncio no 2º áudio)
    expect(described_class.transcript_label(audio)).to include('RESPONDA sempre').and include('pedindo para o paciente escrever')
    expect(described_class.transcript_label(audio)).not_to include('uma vez só')
    expect(described_class.read?(audio)).to be(true) # acabou de falhar: não insiste na mesma hora
  end

  # 🔁 item 340: o arquivo ainda subindo para o armazenamento não vira "falhou para sempre"
  describe 'item 340: falha passageira, tentativas e troca de modelo' do
    def fail_open_with(error)
      allow_any_instance_of(ActiveStorage::Blob).to receive(:open).and_raise(error) # rubocop:disable RSpec/AnyInstance
    end

    it 'arquivo ainda não está no armazenamento: falha PASSAGEIRA, volta a ser lida depois de 20 s', :aggregate_failures do
      audio = attach(incoming, :audio)
      fail_open_with(ActiveStorage::FileNotFoundError)

      expect(described_class.new(audio).perform).to be(false)
      expect(audio.reload.meta['cevico_media']).to include('status' => 'failed', 'transient' => true, 'attempts' => 1,
                                                           'error_class' => 'ActiveStorage::FileNotFoundError')
      expect(described_class.read?(audio)).to be(true)
      expect(described_class.retriable?(audio, retry_now: true)).to be(true)
      travel 25.seconds do
        expect(described_class.read?(audio)).to be(false)
        expect(described_class.pending_attachments(conversation)).to eq([audio])
      end
    end

    it 'o arquivo chegou: a nova tentativa transcreve e conta as tentativas', :aggregate_failures do
      audio = attach(incoming, :audio)
      fail_open_with(ActiveStorage::FileNotFoundError)
      described_class.new(audio).perform
      RSpec::Mocks.space.proxy_for(ActiveStorage::Blob).reset
      allow_any_instance_of(ActiveStorage::Blob).to receive(:open).and_call_original # rubocop:disable RSpec/AnyInstance
      gemini_answers({ 'texto' => 'quero marcar consulta', 'inaudivel' => false })

      expect(described_class.new(audio.reload).perform(retry_now: true)).to be(true)
      expect(audio.reload.meta['cevico_media']).to include('status' => 'done', 'attempts' => 2, 'transient' => nil)
      expect(audio.meta['transcribed_text']).to eq('quero marcar consulta')
    end

    it 'erro definitivo (400 do áudio) e tentativas esgotadas não são lidos de novo', :aggregate_failures do
      audio = attach(incoming, :audio)
      response = double('gemini', success?: false, code: 400, # rubocop:disable RSpec/VerifiedDoubles
                                  parsed_response: { 'error' => { 'message' => 'Request contains an invalid argument.' } })
      allow(HTTParty).to receive(:post).and_return(response)
      described_class.new(audio).perform
      expect(audio.reload.meta['cevico_media']).to include('status' => 'failed', 'transient' => false)
      expect(HTTParty).to have_received(:post).once # 400 que não é de modelo: não troca de modelo
      travel(1.hour) { expect(described_class.read?(audio)).to be(true) }
      expect(described_class.settled?(audio)).to be(true)

      outro = attach(incoming, :audio)
      esgotado = { 'status' => 'failed', 'transient' => true, 'attempts' => described_class::MAX_ATTEMPTS, 'at' => 1.hour.ago.iso8601 }
      outro.update!(meta: { 'cevico_media' => esgotado })
      expect(described_class.read?(outro)).to be(true)
      expect(described_class.settled?(outro)).to be(true)
    end

    it 'falha antiga sem contagem (antes do item 340) volta a ser lida' do
      audio = attach(incoming, :audio)
      audio.update!(meta: { 'cevico_media' => { 'status' => 'failed', 'error' => 'Not found', 'at' => 1.day.ago.iso8601 } })
      expect(described_class.read?(audio)).to be(false)
    end

    it 'modelo aposentado pelo Google (404): tenta o próximo da lista e registra qual respondeu', :aggregate_failures do
      audio = attach(incoming, :audio)
      gone = double('gemini', success?: false, code: 404, # rubocop:disable RSpec/VerifiedDoubles
                              parsed_response: { 'error' => { 'message' => 'models/gemini-2.5-flash is not found for API version v1beta' } })
      ok = double('gemini', success?: true, code: 200, # rubocop:disable RSpec/VerifiedDoubles
                            parsed_response: { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => { 'texto' => 'oi' }.to_json }] } }],
                                               'usageMetadata' => gemini_usage })
      urls = []
      allow(HTTParty).to receive(:post) do |url, _opts|
        urls << url
        url.include?('gemini-2.5-flash') ? gone : ok
      end

      expect(described_class.new(audio).perform).to be(true)
      expect(urls.map { |u| u[%r{models/([^:]+):}, 1] }).to eq(%w[gemini-2.5-flash gemini-flash-latest])
      expect(audio.reload.meta['cevico_media']).to include('status' => 'done', 'model' => 'gemini-flash-latest')
      expect(Crm::AiUsage.where(account: account).last.model).to eq('gemini-flash-latest')
    end

    it 'modelo configurado em Integrações → IA vai primeiro' do
      CrmSetting.find_by(account: account).update!(ai_config: { 'gemini_api_key' => 'AIza-teste', 'gemini_media_model' => 'gemini-3.0-flash' })
      expect(Crm::GeminiModels.chain(account)).to eq(%w[gemini-3.0-flash gemini-2.5-flash gemini-flash-latest gemini-2.0-flash])
      gemini_answers({ 'texto' => 'oi' })
      described_class.new(attach(incoming, :audio)).perform
      expect(HTTParty).to have_received(:post).with(include('gemini-3.0-flash:generateContent'), anything)
    end

    it 'settle!: lê na hora o que não começou e espera quem está lendo (sem passar do tempo)', :aggregate_failures do
      message = incoming
      novo = attach(message, :audio)
      lendo = attach(message, :image)
      lendo.update!(meta: { 'cevico_media' => { 'status' => 'processing', 'at' => Time.current.iso8601 } })
      gemini_answers({ 'texto' => 'quero remarcar', 'inaudivel' => false })
      sleeps = 0
      allow(described_class).to receive(:sleep) do
        sleeps += 1
        lendo.update!(meta: { 'cevico_media' => { 'status' => 'done', 'tipo' => 'print', 'descricao' => 'print' } }) if sleeps == 2
      end

      expect(described_class.settle!(message, timeout: 30, step: 2)).to eq('audio' => 1)
      expect(novo.reload.meta['transcribed_text']).to eq('quero remarcar')
      expect(sleeps).to eq(2)
      expect(HTTParty).to have_received(:post).once # a imagem que outro estava lendo não foi lida de novo
    end

    it 'settle!: o arquivo não chega nunca → para no limite de tempo, e o anexo fica "sem transcrição"', :aggregate_failures do
      message = incoming
      audio = attach(message, :audio)
      fail_open_with(ActiveStorage::FileNotFoundError)
      clock = 0.0
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock }
      allow(described_class).to receive(:sleep) { |step| clock += step }

      expect(described_class.settle!(message, timeout: 6, step: 2)).to eq({})
      expect(audio.reload.meta['cevico_media']['attempts']).to be_between(3, 4)
      expect(described_class.transcript_label(audio)).to include('áudio sem transcrição')
    end
  end

  it 'sem chave do Gemini: não chama nada e o Atendente segue com o marcador antigo', :aggregate_failures do
    CrmSetting.find_by(account: account).update!(ai_config: {})
    audio = attach(incoming, :audio)
    allow(HTTParty).to receive(:post)

    expect(described_class.configured?(account)).to be(false)
    expect(described_class.read_pending!(conversation)).to eq({})
    expect(described_class.new(audio).perform).to be(false)
    expect(HTTParty).not_to have_received(:post)
    expect(audio.reload.meta['cevico_media']).to include('status' => 'skipped')
    expect(described_class.transcript_label(audio)).to include('áudio sem transcrição')
  end

  it 'read_pending! lê só o que falta nas últimas mensagens do paciente e devolve os totais', :aggregate_failures do
    done = attach(incoming, :audio)
    done.update!(meta: { 'transcribed_text' => 'já lido', 'cevico_media' => { 'status' => 'done' } })
    attach(incoming, :audio)
    attach(incoming, :image)
    outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'ok')
    attach(outgoing, :image) # da clínica: não é lido
    gemini_answers({ 'texto' => 'segundo áudio', 'tipo' => 'print', 'descricao' => 'print', 'inaudivel' => false })

    expect(described_class.read_pending!(conversation)).to eq('audio' => 1, 'image' => 1)
    expect(HTTParty).to have_received(:post).twice
    expect(done.reload.meta['transcribed_text']).to eq('já lido')
    expect(described_class.pending_attachments(conversation)).to be_empty
  end
end
