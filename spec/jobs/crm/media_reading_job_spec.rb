require 'rails_helper'

# 🔁 item 340 (13/10): o arquivo do WhatsApp sobe DEPOIS do aviso da mensagem —
# a leitura que chega antes tenta de novo (3 s, 6 s, 12 s) em vez de falhar para sempre
RSpec.describe Crm::MediaReadingJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil) }
  let!(:audio) do
    message.attachments.create!(account_id: account.id, file_type: :audio,
                                file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.ogg'), 'audio/ogg'))
  end

  before { CrmSetting.create!(account: account, ai_config: { 'gemini_api_key' => 'AIza-teste' }) }

  def gemini_ok(text)
    parsed = { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => { 'texto' => text }.to_json }] } }] }
    allow(HTTParty).to receive(:post).and_return(double('gemini', success?: true, code: 200, parsed_response: parsed)) # rubocop:disable RSpec/VerifiedDoubles
  end

  it 'arquivo ainda subindo: marca falha passageira e volta em 3 s (sem contar como falha definitiva)', :aggregate_failures do
    allow_any_instance_of(ActiveStorage::Blob).to receive(:open).and_raise(ActiveStorage::FileNotFoundError) # rubocop:disable RSpec/AnyInstance

    expect { described_class.perform_now(message.id) }.to have_enqueued_job(described_class).with(message.id, 1)
    expect(audio.reload.meta['cevico_media']).to include('status' => 'failed', 'transient' => true, 'attempts' => 1)
  end

  it 'na volta o arquivo já chegou: transcreve e não agenda mais nada', :aggregate_failures do
    audio.update!(meta: { 'cevico_media' => { 'status' => 'failed', 'transient' => true, 'attempts' => 1, 'at' => Time.current.iso8601 } })
    gemini_ok('oi, quero marcar')

    expect { described_class.perform_now(message.id, 1) }.not_to have_enqueued_job(described_class)
    expect(audio.reload.meta).to include('transcribed_text' => 'oi, quero marcar')
    expect(audio.meta['cevico_media']).to include('status' => 'done', 'attempts' => 2)
  end

  it 'esgotou as voltas (3, 6, 12 s): para de tentar e o anexo fica como falhou', :aggregate_failures do
    allow_any_instance_of(ActiveStorage::Blob).to receive(:open).and_raise(ActiveStorage::FileNotFoundError) # rubocop:disable RSpec/AnyInstance

    expect { described_class.perform_now(message.id, 3) }.not_to have_enqueued_job(described_class)
    expect(audio.reload.meta['cevico_media']).to include('status' => 'failed')
  end

  it 'erro definitivo do Gemini (400) não volta para a fila' do
    response = double('gemini', success?: false, code: 400, parsed_response: { 'error' => { 'message' => 'invalid argument' } }) # rubocop:disable RSpec/VerifiedDoubles
    allow(HTTParty).to receive(:post).and_return(response)

    expect { described_class.perform_now(message.id) }.not_to have_enqueued_job(described_class)
  end
end
