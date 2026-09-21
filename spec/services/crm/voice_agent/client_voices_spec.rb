require 'rails_helper'

# 21/09: conta free sem vozes em português → a busca cai na biblioteca pública
RSpec.describe Crm::VoiceAgent::Client do
  let(:client) { described_class.new('xi-teste') }

  before do
    stub_request(:get, %r{api\.elevenlabs\.io/v2/voices}).to_return(status: 200, body: { voices: [] }.to_json,
                                                                    headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{api\.elevenlabs\.io/v1/shared-voices})
      .with(query: hash_including('language' => 'pt', 'gender' => 'female'))
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { voices: [{ voice_id: 'v1', name: 'Ana', public_owner_id: 'owner1', gender: 'female', age: 'young',
                                    accent: 'brazilian', language: 'pt', preview_url: 'https://x/ana.mp3' }] }.to_json)
  end

  it '"feminina" vira o filtro gender=female e devolve a voz da biblioteca marcada' do
    voices = client.voices(search: 'feminina')
    expect(voices.size).to eq(1)
    expect(voices.first).to include('voice_id' => 'v1', 'library' => true, 'public_owner_id' => 'owner1')
    expect(voices.first['labels']).to include('gender' => 'female', 'accent' => 'brazilian')
  end
end
