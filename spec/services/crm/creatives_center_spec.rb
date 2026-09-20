require 'rails_helper'

# Central de Criativos (item 172): parser do criativo, normalização das métricas,
# sincronização (simulação) e leitura gancho/corpo/CTA × jornada do CRM.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Central de Criativos' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let!(:settings) do
    CrmSetting.create!(account: account, meta_ads_config: { 'access_token' => 'simulate', 'ad_account_id' => 'act_1' })
  end

  describe Crm::AdCreativeParser do
    it 'detecta formato e extrai gancho/corpo/CTA do vídeo' do
      creative = { 'object_story_spec' => { 'video_data' => { 'video_id' => 'v1', 'title' => 'Gancho', 'message' => 'Corpo',
                                                              'call_to_action' => { 'type' => 'WHATSAPP_MESSAGE' }, 'image_url' => 'http://x/1.jpg' } } }
      expect(described_class.format_for(creative)).to eq('video')
      expect(described_class.parse(creative)).to include('title' => 'Gancho', 'body' => 'Corpo', 'cta_type' => 'WHATSAPP_MESSAGE',
                                                         'video_id' => 'v1', 'thumbnail_url' => 'http://x/1.jpg')
    end

    it 'criativo dinâmico traz as listas de ganchos, corpos e CTAs' do
      creative = { 'asset_feed_spec' => { 'titles' => [{ 'text' => 'A' }, { 'text' => 'B' }], 'bodies' => [{ 'text' => 'c' }],
                                          'call_to_action_types' => ['LEARN_MORE'] } }
      expect(described_class.format_for(creative)).to eq('dynamic')
      expect(described_class.parse(creative)).to include('titles' => %w[A B], 'title' => 'A', 'cta_type' => 'LEARN_MORE')
    end

    it 'imagem, carrossel e rótulo do CTA' do
      expect(described_class.format_for({ 'image_url' => 'x' })).to eq('image')
      expect(described_class.format_for({ 'object_story_spec' => { 'link_data' => { 'child_attachments' => [{}, {}] } } })).to eq('carousel')
      expect(described_class.cta_label('WHATSAPP_MESSAGE')).to eq('Enviar mensagem (WhatsApp)')
      expect(described_class.cta_label(nil)).to eq('Sem botão')
    end
  end

  describe Crm::AdMetrics do
    it 'normaliza a linha da Meta e calcula as taxas de gancho, corpo e CTA' do
      row = { 'spend' => '10.5', 'impressions' => '1000', 'reach' => '800', 'inline_link_clicks' => '20',
              'actions' => [{ 'action_type' => 'video_view', 'value' => '300' },
                            { 'action_type' => 'onsite_conversion.messaging_conversation_started_7d', 'value' => '5' }],
              'video_thruplay_watched_actions' => [{ 'action_type' => 'video_view', 'value' => '90' }],
              'video_p25_watched_actions' => [{ 'action_type' => 'video_view', 'value' => '200' }] }
      metrics = described_class.from_meta(row)
      expect(metrics).to include('spend' => 10.5, 'plays_3s' => 300, 'thruplay' => 90, 'conversations' => 5, 'p25' => 200)
      rates = described_class.rates(described_class.sum([metrics]))
      expect(rates).to include('hook_rate' => 0.3, 'hold_rate' => 0.3, 'link_ctr' => 0.02, 'conv_rate' => 0.25, 'cost_conversation' => 2.1)
      expect(rates['retention']).to eq([0.3, 0.2, 0, 0, 0])
    end
  end

  describe Crm::AdInsightsSyncService do
    it 'primeira carga traz 90 dias na simulação e grava o estado; a seguinte refaz 3 dias sem duplicar' do
      result = described_class.new(account: account).call
      expect(result[:ads]).to eq(8)
      expect(result[:recovered]).to eq(1) # o anúncio apagado (2309) volta por id
      expect(Crm::AdCreative.where(account: account).count).to eq(9)
      expect(Crm::AdInsight.where(account: account).count).to eq((8 * 90) + 44) # apagado só tem dias com 46+ de idade
      expect(Crm::AdCreative.find_by(account: account, ad_id: '2307').format).to eq('dynamic')
      state = described_class.state(account)
      expect(state['synced_at']).to be_present
      expect(state['running_since']).to be_nil

      second = described_class.new(account: account)
      expect(second.since_date).to eq(Date.current - 2)
      expect(second.call[:rows]).to eq(8 * 3)
      expect(Crm::AdInsight.where(account: account).count).to eq((8 * 90) + 44)
    end

    it 'carga longa vai em janelas de 90 dias, da mais recente para a mais antiga, e guarda o progresso' do
      service = described_class.new(account: account, days: 200)
      expect(service.windows.size).to eq(3)
      expect(service.windows.first.last).to eq(Date.current)
      expect(service.windows.last.first).to eq(Date.current - 199)
      result = service.call
      expect(result[:windows]).to eq(3)
      expect(Crm::AdInsight.where(account: account).count).to eq((8 * 200) + (200 - 46))
      state = described_class.state(account)
      expect(state['history_days']).to eq(200)
      expect(state['progress']).to be_nil
      expect(described_class::MAX_DAYS).to eq(1125)
    end

    it 'anúncio apagado na Meta fica guardado aqui com nome, criativo e status' do
      described_class.new(account: account).call
      gone = Crm::AdCreative.find_by(account: account, ad_id: '2309')
      expect(gone.effective_status).to eq('DELETED')
      expect(gone.ad_name).to include('Antigo')
      expect(gone.hook).to be_present
      expect(gone.creative['thumbnail_url']).to be_present
    end

    it 'sem token não faz nada' do
      settings.update!(meta_ads_config: {})
      expect(described_class.new(account: account).call).to eq(configured: false)
    end
  end

  describe Crm::AdCreativeMediaJob do
    it 'guarda a miniatura no nosso armazenamento e a tela passa a usar a cópia' do
      Crm::AdInsightsSyncService.new(account: account).call
      allow(Down).to receive(:download) do
        file = Tempfile.new(['thumb', '.jpg'])
        file.binmode
        file.write("\xFF\xD8\xFF".b)
        file.rewind
        file.define_singleton_method(:content_type) { 'image/jpeg' }
        file
      end
      expect(described_class.perform_now(account.id, 2)).to eq(2)
      stored = Crm::AdCreative.where(account: account).joins(:thumbnail_attachment)
      expect(stored.count).to eq(2)
      expect(stored.first.thumbnail_stored?).to be(true)
      expect(stored.first.thumbnail_src).to include('rails/active_storage')
      expect(Crm::AdCreative.where(account: account).where.missing(:thumbnail_attachment).first.thumbnail_src).to include('picsum')
    end
  end

  describe Crm::CreativesExport do
    it 'exporta em CSV (ponto e vírgula) tudo que está guardado, com o criativo ao lado' do
      Crm::AdInsightsSyncService.new(account: account).call
      csv = described_class.new(account: account).call
      expect(csv).to include('Data;ID do anúncio;Anúncio')
      expect(CSV.parse(csv, col_sep: ';').size).to eq(1 + (8 * 90) + 44)
      expect(csv).to include('Enxergar sem óculos')
      partial = described_class.new(account: account, since_date: Date.current - 6, until_date: Date.current).call
      expect(CSV.parse(partial, col_sep: ';').size).to eq(1 + (8 * 7))
    end
  end

  describe Crm::CreativeAnalyticsService do
    before { Crm::AdInsightsSyncService.new(account: account).call }

    let(:service) { described_class.new(account: account, since_date: Date.current - 29, until_date: Date.current) }

    it 'monta um card por anúncio com taxas, diagnóstico contra a média e fadiga' do
      overview = service.overview
      expect(overview[:rows].size).to eq(8)
      row = overview[:rows].find { |r| r[:ad_id] == '2304' }
      expect(row[:hook]).to eq('Cansou das lentes?')
      expect(row[:rates]['hook_rate']).to be > overview[:averages]['hook_rate']
      expect(row[:diagnosis][:bands]).to include(hook: 'bom', hold: 'ruim')
      expect(row[:diagnosis][:vs_avg][:hook]).to eq('acima')
      expect(row[:diagnosis][:focus]).to eq('corpo')
      expect(row[:diagnosis][:text]).to include('corpo perde')
      expect(row[:prev]).to include(:link_ctr, :conversations)
      expect(overview[:targets]['hook_rate']).to include('good' => 0.35)
      expect(overview[:prev_daily].size).to eq(30)
      expect(row[:diagnosis][:fatigue]).to be(true)
      image = overview[:rows].find { |r| r[:ad_id] == '2305' }
      expect(image[:rates]['hook_rate']).to be_nil
      expect(overview[:totals]['ads']).to eq(8)
      expect(overview[:daily].size).to eq(30)
    end

    it 'filtra por formato, campanha e busca, e ordena por custo' do
      expect(service.overview(format: 'image')[:rows].map { |r| r[:format] }.uniq).to eq(['image'])
      expect(service.overview(campaign_id: '9001')[:rows].size).to eq(4)
      expect(service.overview(query: 'depoimento')[:rows].map { |r| r[:ad_id] }).to eq(['2303'])
      cheapest = service.overview[:rows].filter_map { |r| r[:rates]['cost_conversation'] }.min
      expect(service.overview(sort: 'cost')[:rows].first[:rates]['cost_conversation']).to eq(cheapest)
    end

    it 'detalha com série diária, metades, quebras, frequência real e ativos' do
      detail = service.detail('2307')
      expect(detail[:daily].size).to eq(30)
      expect(detail[:halves][:first][:impressions]).to be > 0
      expect(detail[:placements][:rows].map { |r| r[:label] }).to include('Instagram · Reels')
      expect(detail[:age_gender][:rows].first[:label]).to match(/Mulheres|Homens/)
      expect(detail[:assets][:titles][:rows].map { |r| r[:label] }).to include('Enxergar sem óculos é possível')
      expect(detail[:summary]).to include(:frequency)
    end

    it 'conta os leads do CRM atribuídos ao anúncio (CTWA) dentro do período' do
      create(:contact, account: account,
                       additional_attributes: { 'meta_ads' => { 'source_id' => '2301', 'captured_at' => 2.days.ago.iso8601 } })
      create(:contact, account: account,
                       additional_attributes: { 'meta_ads' => { 'source_id' => '2301', 'captured_at' => 80.days.ago.iso8601 } })
      row = service.overview[:rows].find { |r| r[:ad_id] == '2301' }
      expect(row[:funnel][:leads]).to eq(1)
    end

    it 'v2: custo por consulta, custo por cirurgia, ROAS e % de agendamento por anúncio, com campeões de dinheiro' do
      creator = create(:user, account: account)
      pipeline = Crm::Pipeline.create!(account: account, name: 'Funil')
      stage = Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Realizada', position: 1, color: '#0F5FA6')
      leads = Array.new(6) do |i|
        create(:contact, account: account, phone_number: "+55119999000#{i}",
                         additional_attributes: { 'meta_ads' => { 'source_id' => '2301', 'captured_at' => 3.days.ago.iso8601 } })
      end
      leads.first(3).each { |c| account.tasks.create!(title: 'consulta', task_type: 'consulta', contact_id: c.id, creator: creator, attendance: 'attended') }
      Crm::Contact.create!(contact_id: leads.first.id, pipeline: pipeline, stage: stage, value: 9000)
      row = service.overview[:rows].find { |r| r[:ad_id] == '2301' }
      spend = row[:totals]['spend'].to_f
      expect(row[:funnel]).to include(leads: 6, booked: 3, surgeries: 1, revenue: 9000.0)
      expect(row[:rates]['cost_booked']).to eq((spend / 3).round(2))
      expect(row[:rates]['cost_surgery']).to eq(spend.round(2))
      expect(row[:rates]['roas']).to eq((9000 / spend).round(2))
      expect(row[:rates]['booking_rate']).to eq(0.5)
      # 2301 é o único com jornada suficiente → não há disputa (precisa de 2 no páreo)
      expect(row[:champion_of]).not_to include('roas')
      other = create(:contact, account: account, phone_number: '+5511988880000',
                               additional_attributes: { 'meta_ads' => { 'source_id' => '2302', 'captured_at' => 2.days.ago.iso8601 } })
      Crm::Contact.create!(contact_id: other.id, pipeline: pipeline, stage: stage, value: 100)
      fresh = described_class.new(account: account, since_date: Date.current - 29, until_date: Date.current)
      champions = fresh.overview[:rows].to_h { |r| [r[:ad_id], r[:champion_of]] }
      expect(champions['2301']).to include('roas')
      expect(champions.values.flatten).to include('cac')
      records = Crm::CreativeRecords.new(account: account).call
      expect(records[:all_time][:roas][:ad_id]).to eq('2301')
      expect(records[:all_time][:cac][:funnel][:surgeries]).to eq(1)
    end

    it 'v2.1: transcreve o vídeo (simulação) e o gancho/corpo passam a vir da fala; a carga preserva' do
      creative = Crm::AdCreative.find_by!(account: account, ad_id: '2304')
      expect(creative.text_source).to eq('ad')
      expect(Crm::AdVideoTranscriptionService.new(creative).perform).to be(true)
      creative.reload
      expect(creative.text_source).to eq('video')
      expect(creative.hook).to eq('Cansou das lentes?')
      expect(creative.video_cta).to include('WhatsApp')
      expect(creative.transcript['angle']).to eq('pergunta')
      Crm::AdInsightsSyncService.new(account: account).call
      expect(creative.reload.transcript_done?).to be(true)
      row = service.overview[:rows].find { |r| r[:ad_id] == '2304' }
      expect(row[:text_source]).to eq('video')
      video = service.assets_for(nil)[:video]
      expect(video[:hooks].map { |h| h[:ad_id] }).to eq(['2304'])
      expect(video[:transcribed]).to eq(1)
      image = Crm::AdCreative.find_by!(account: account, ad_id: '2305')
      expect(Crm::AdVideoTranscriptionService.new(image).perform).to be(false)
      expect(image.reload.transcript['status']).to eq('skipped')
      expect(Crm::AdVideoTranscribeJob.pending_for(account).pluck(:ad_id)).not_to include('2304', '2305')
    end

    it 'respeita parâmetros editados pelo admin' do
      settings.update!(meta_ads_config: settings.meta_ads_config.merge('creative_targets' => { 'hook_rate' => { 'good' => 0.6, 'bad' => 0.5 } }))
      row = service.overview[:rows].find { |r| r[:ad_id] == '2304' }
      expect(row[:diagnosis][:bands][:hook]).to eq('ruim')
      expect(Crm::CreativeTargets.band('cost_conversation', 8.0, Crm::CreativeTargets.for(account))).to eq('bom')
      expect(Crm::CreativeTargets.band('cost_conversation', 30.0, Crm::CreativeTargets.for(account))).to eq('ruim')
    end

    it 'marca os campeões do recorte e resume as campanhas' do
      overview = service.overview
      champions = overview[:rows].to_h { |r| [r[:ad_id], r[:champion_of]] }
      expect(champions['2301']).to include('cost')
      expect(champions['2304']).to include('hook')
      expect(overview[:campaign_stats].map { |c| c[:name] }).to include('Campanha Catarata · CTWA')
      expect(overview[:campaign_stats].first[:bands].keys).to contain_exactly('bom', 'atencao', 'ruim')
    end

    it 'recordes do próprio histórico e metas automáticas com passo de superação' do
      records = Crm::CreativeRecords.new(account: account).call
      hook = records[:records]['hook_rate']
      expect(hook[:best_week][:value]).to be > 0
      expect(hook[:median_week]).to be > 0
      expect(records[:months].size).to be >= 3
      expect(records[:all_time][:cost][:ad_name]).to be_present
      expect(records[:all_time][:cost][:rates]).to include('link_ctr', 'cost_conversation') # teia dos campeões
      settings.update!(meta_ads_config: settings.meta_ads_config.merge('creative_targets' => { 'mode' => 'auto', 'step' => 0.05 }))
      targets = Crm::CreativeTargets.for(account)
      expect(targets['mode']).to eq('auto')
      expect(targets['hook_rate']['source']).to eq('auto')
      expect(targets['hook_rate']['good']).to be_within(0.0001).of((hook[:best_week][:value] * 1.05).round(4))
      expect(targets['cost_conversation']['good']).to be < targets['cost_conversation']['record']
    end

    it 'ranqueia ganchos, corpos e CTAs da conta inteira' do
      assets = service.assets_for(nil)
      expect(assets[:dynamic_ads]).to eq(1)
      expect(assets[:ctas][:rows].map { |r| r[:label] }).to include('Enviar mensagem (WhatsApp)')
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
