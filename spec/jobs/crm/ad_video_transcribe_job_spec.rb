require 'rails_helper'

# 🎬 Achado #410 (auditoria, Rodada 4 "Dados que não se perdem"): a fila de
# transcrição não marcava "na fila" nem conferia "já transcrito" — dois disparos
# antes de a fila andar (botão de novo, "Atualizar agora", cron) mandavam o
# MESMO vídeo ao Gemini duas vezes. Agora: marca antes de enfileirar, e o job
# que chega atrasado sai sem gravar nada.
RSpec.describe Crm::AdVideoTranscribeJob do
  let(:account) { create(:account) }

  def video(ad_id, transcript: {}, extra: {})
    Crm::AdCreative.create!(account: account, ad_id: ad_id, format: 'video', synced_at: Time.current,
                            creative: { 'video_id' => "v#{ad_id}", 'transcript' => transcript }.merge(extra))
  end

  describe '.enqueue_pending' do
    it 'marca cada vídeo como "na fila" (com a hora) ANTES de enfileirar o job', :aggregate_failures do
      pendente = video('1')

      expect { described_class.enqueue_pending(account) }.to have_enqueued_job(described_class).with(pendente.id).once

      pendente.reload
      expect(pendente.transcript['status']).to eq('queued')
      expect(Time.zone.parse(pendente.transcript['status_at'])).to be_within(5.seconds).of(Time.current)
    end

    it 'chamado duas vezes com a fila parada, o segundo pedido não acha nada e não enfileira o mesmo vídeo', :aggregate_failures do
      pendente = video('1')

      expect(described_class.enqueue_pending(account)).to eq(1)
      expect(described_class.pending_for(account).pluck(:id)).not_to include(pendente.id)

      expect { expect(described_class.enqueue_pending(account)).to eq(0) }.not_to have_enqueued_job(described_class)
      expect(described_class.enqueue_pending(account)).to eq(0) # "Atualizar agora" ou cron logo em seguida
    end

    it 'vídeo "na fila" há mais que a janela de travado volta a ser enfileirado (deploy no meio, fila caiu)' do
      travado = video('1', transcript: { 'status' => 'queued', 'status_at' => (described_class::STUCK_AFTER + 1.minute).ago.iso8601 })

      expect { described_class.enqueue_pending(account) }.to have_enqueued_job(described_class).with(travado.id).once
      expect(travado.reload.transcript['status_at']).to be > 1.minute.ago.iso8601
    end

    it 'preserva o link colado pela pessoa quando tenta de novo um vídeo que falhou' do
      falhou = video('1', transcript: { 'status' => 'failed', 'error' => 'Gemini respondeu com erro 503', 'link' => 'https://youtu.be/abc123' })

      described_class.enqueue_pending(account)

      expect(falhou.reload.transcript).to include('status' => 'queued', 'link' => 'https://youtu.be/abc123', 'error' => nil)
    end

    it 'respeita o limite por vez e deixa o resto para a próxima rodada', :aggregate_failures do
      3.times { |i| video((i + 1).to_s) }

      expect(described_class.enqueue_pending(account, limit: 2)).to eq(2)
      expect(described_class.pending_for(account).count).to eq(1)
    end
  end

  describe 'job atrasado (Crm::AdVideoTranscriptionService#perform)' do
    before do
      CrmSetting.create!(account: account, meta_ads_config: { 'access_token' => 'simulate', 'ad_account_id' => 'act_1' })
      allow(HTTParty).to receive(:post)
    end

    it 'vídeo já transcrito não vai de novo à IA e a transcrição fica como estava', :aggregate_failures do
      pronto = video('1', transcript: { 'status' => 'done', 'text' => 'Cansou das lentes? Chama no WhatsApp.', 'hook' => 'Cansou das lentes?' })

      expect(Crm::AdVideoTranscriptionService.new(pronto).perform).to be(false)

      expect(pronto.reload.transcript).to include('status' => 'done', 'hook' => 'Cansou das lentes?')
      expect(HTTParty).not_to have_received(:post)
    end

    it 'outro job marcou "transcrevendo" há pouco: o segundo sai sem mexer em nada', :aggregate_failures do
      em_andamento = video('1', transcript: { 'status' => 'processing', 'status_at' => 2.minutes.ago.iso8601 })

      expect(Crm::AdVideoTranscriptionService.new(em_andamento).perform).to be(false)

      expect(em_andamento.reload.transcript['status']).to eq('processing')
      expect(HTTParty).not_to have_received(:post)
    end

    it '"transcrevendo" há mais que a janela de travado é tentado de novo e termina', :aggregate_failures do
      travado = video('1', transcript: { 'status' => 'processing', 'status_at' => 1.hour.ago.iso8601 })

      expect(Crm::AdVideoTranscriptionService.new(travado).perform).to be(true)

      expect(travado.reload.transcript_done?).to be(true)
    end

    it 'pedido novo (link novo) chega enquanto a IA trabalha: o resultado velho não marca "pronto" e o pedido novo segue', :aggregate_failures do
      na_fila = video('1', transcript: { 'status' => 'queued', 'status_at' => Time.current.iso8601 })
      service = Crm::AdVideoTranscriptionService.new(na_fila)
      # no meio da "chamada à IA", alguém cola um link novo (aba desatualizada)
      allow(service).to(receive(:simulated_result).and_wrap_original do |original|
        travel_to(1.minute.from_now) { Crm::AdCreative.find(na_fila.id).queue_transcript!(link: 'https://youtu.be/novo123') }
        original.call
      end)

      expect(service.perform).to be(false)

      expect(na_fila.reload.transcript).to include('status' => 'queued', 'link' => 'https://youtu.be/novo123')
      expect(na_fila.transcript_done?).to be(false)
    end

    it 'o job inteiro: na fila → transcrito uma vez; rodar de novo não refaz', :aggregate_failures do
      na_fila = video('1')
      described_class.enqueue_pending(account)

      described_class.perform_now(na_fila.id)
      primeira = na_fila.reload.transcript['transcribed_at']
      expect(na_fila.transcript_done?).to be(true)

      travel_to(5.minutes.from_now) { described_class.perform_now(na_fila.id) }
      expect(na_fila.reload.transcript['transcribed_at']).to eq(primeira)
    end
  end

  # Dois jobs do MESMO vídeo no MESMO instante (fila com 10 trabalhadores): a
  # reserva do "transcrevendo" é uma gravação só com trava na linha, então o
  # segundo espera o primeiro e sai. Precisa de dados gravados de verdade
  # (sem a transação do teste) para as duas linhas de execução se enxergarem.
  describe 'dois jobs do mesmo vídeo ao mesmo tempo' do
    self.use_transactional_tests = false

    let(:resposta_gemini) do
      instance_double(HTTParty::Response, success?: true, code: 200,
                                          parsed_response: { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => {
                                            'transcricao' => 'Cansou das lentes? Chama no WhatsApp.', 'gancho' => 'Cansou das lentes?',
                                            'corpo' => 'Chama no WhatsApp.', 'cta' => 'Chama no WhatsApp.', 'angulo' => 'pergunta'
                                          }.to_json }] } }] })
    end

    before do
      CrmSetting.create!(account: account, ai_config: { 'gemini_api_key' => 'chave-de-teste' })
      allow(Crm::AdVideoInput).to receive(:new)
        .and_return(instance_double(Crm::AdVideoInput, part: { inline_data: { mime_type: 'video/mp4', data: 'x' } }, origin: 'meta', cleanup!: true))
      allow(HTTParty).to receive(:post).and_return(resposta_gemini)
    end

    after do
      Crm::AiUsage.where(account_id: account.id).delete_all
      Crm::AdCreative.where(account_id: account.id).delete_all
      CrmSetting.where(account_id: account.id).delete_all
      account.destroy
    end

    it 'só um chama a IA; o outro espera a trava e sai ao ver "transcrevendo"', :aggregate_failures do
      na_fila = video('1', transcript: { 'status' => 'queued', 'status_at' => Time.current.iso8601 })
      primeiro = Crm::AdVideoTranscriptionService.new(Crm::AdCreative.find(na_fila.id))
      segundo = Crm::AdVideoTranscriptionService.new(Crm::AdCreative.find(na_fila.id))
      # o primeiro demora dentro da trava, para o segundo chegar enquanto ele ainda não marcou
      allow(primeiro).to(receive(:precheck).and_wrap_original { |original| sleep(0.4) && original.call })

      resultados = [primeiro, segundo].each_with_index.map do |service, i|
        Thread.new do
          sleep(0.1) if i == 1
          service.perform
        ensure
          ActiveRecord::Base.connection_pool.release_connection
        end
      end.map(&:value)

      expect(resultados).to eq([true, false])
      expect(HTTParty).to have_received(:post).once
      expect(na_fila.reload.transcript).to include('status' => 'done', 'hook' => 'Cansou das lentes?')
    end
  end

  describe 'quantos a tela mostra na confirmação (Central de Criativos)' do
    it 'conta o que o servidor enfileiraria: inclui dinâmico com vídeo e deixa de fora o que já está na fila ou pronto' do
      video('1')
      video('2', transcript: { 'status' => 'done', 'text' => 'pronto' })
      video('3', transcript: { 'status' => 'queued', 'status_at' => Time.current.iso8601 })
      Crm::AdCreative.create!(account: account, ad_id: '4', format: 'dynamic', synced_at: Time.current, creative: { 'video_id' => 'v4' })

      video = Crm::CreativeAnalyticsService.new(account: account, since_date: 7.days.ago.to_date, until_date: Date.current)
                                           .assets_for(nil)[:video]

      expect(video[:pending]).to eq(2)
    end
  end

  describe 'carga da Meta no mesmo instante em que o job grava (Crm::AdInsightsSyncService)' do
    it 'a gravação da carga não volta a transcrição para o que leu antes', :aggregate_failures do
      criativo = video('1', transcript: { 'status' => 'queued', 'status_at' => 1.minute.ago.iso8601 })
      sync = Crm::AdInsightsSyncService.new(account: account)
      agora = Time.current
      rows = [{ account_id: account.id, ad_id: '1', ad_name: 'Novo nome', adset_id: nil, adset_name: nil, campaign_id: nil,
                campaign_name: nil, effective_status: 'ACTIVE', format: 'video', creative: { 'video_id' => 'v1', 'title' => 'Novo título' },
                synced_at: agora, created_at: agora, updated_at: agora }]
      sync.send(:keep_transcripts!, rows) # leu 'queued'…
      criativo.reload.update!(creative: criativo.creative.merge('transcript' => { 'status' => 'done', 'text' => 'já pago' })) # …o job gravou

      sync.send(:upsert_creatives, rows)

      expect(criativo.reload.transcript).to include('status' => 'done', 'text' => 'já pago')
      expect(criativo.creative['title']).to eq('Novo título')
      expect(criativo.ad_name).to eq('Novo nome')
    end
  end

  describe 'POST /crm/creatives/transcribe_videos (botão da tela)', type: :request do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'usa o mesmo limite do job e devolve quantos entraram de verdade', :aggregate_failures do
      allow(described_class).to receive(:enqueue_pending).and_return(3)

      post "/api/v1/accounts/#{account.id}/crm/creatives/transcribe_videos", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(described_class).to have_received(:enqueue_pending).with(account, limit: described_class::LIMIT)
      expect(response.parsed_body).to include('enqueued' => 3, 'limit' => described_class::LIMIT)
    end
  end

  # endpoint de UM vídeo: tela desatualizada clicando "Transcrever" por cima de
  # um vídeo que já está na fila/transcrevendo não enfileira um segundo job
  describe 'POST /crm/creatives/:ad_id/transcribe (um vídeo)', type: :request do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:url) { "/api/v1/accounts/#{account.id}/crm/creatives/1/transcribe" }

    it 'já transcrevendo há pouco e sem material novo: responde 409 com o estado atual e não enfileira', :aggregate_failures do
      em_andamento = video('1', transcript: { 'status' => 'processing', 'status_at' => 3.minutes.ago.iso8601 })

      expect { post url, headers: admin.create_new_auth_token, as: :json }.not_to have_enqueued_job(described_class)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to include('já está na fila').and include('libera às')
      expect(response.parsed_body['transcript']).to include('status' => 'processing')
      expect(em_andamento.reload.transcript['status']).to eq('processing')
    end

    it 'na fila há pouco: também não enfileira de novo' do
      video('1', transcript: { 'status' => 'queued', 'status_at' => 1.minute.ago.iso8601 })

      expect { post url, headers: admin.create_new_auth_token, as: :json }.not_to have_enqueued_job(described_class)
      expect(response).to have_http_status(:conflict)
    end

    it 'travado há mais que a janela: enfileira de novo normalmente', :aggregate_failures do
      travado = video('1', transcript: { 'status' => 'processing', 'status_at' => 1.hour.ago.iso8601 })

      expect { post url, headers: admin.create_new_auth_token, as: :json }.to have_enqueued_job(described_class).with(travado.id)
      expect(response).to have_http_status(:ok)
      expect(travado.reload.transcript['status']).to eq('queued')
    end

    it 'com link novo é retentativa de propósito: enfileira mesmo transcrevendo', :aggregate_failures do
      em_andamento = video('1', transcript: { 'status' => 'processing', 'status_at' => 3.minutes.ago.iso8601 })

      expect do
        post url, params: { video_link: 'https://exemplo.com.br/video.mp4' }, headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(described_class).with(em_andamento.id)
      expect(response).to have_http_status(:ok)
      expect(em_andamento.reload.transcript).to include('status' => 'queued', 'link' => 'https://exemplo.com.br/video.mp4')
    end
  end
end
