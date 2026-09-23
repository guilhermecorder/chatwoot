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
    expect(audio.meta['cevico_media']).to include('status' => 'failed')
    expect(audio.meta['cevico_media']['error']).to include('429')
    expect(audio.meta['transcribed_text']).to be_nil
    expect(described_class.transcript_label(audio)).to include('peça para o paciente escrever')
    expect(described_class.read?(audio)).to be(true)
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
