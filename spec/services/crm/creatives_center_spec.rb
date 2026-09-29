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

    it 'item 289: agendamento NÃO vira cirurgia; cada degrau cabe no anterior e o CAC nunca fica abaixo do custo da consulta' do
      pipeline = Crm::Pipeline.create!(account: account, name: 'Jornada', position: 0)
      names = ['Novos Contatos', 'Agendamento de Consulta', 'Consulta Realizada', 'Cirurgia Agendada', 'Cirurgia Realizada']
      stages = names.each_with_index.to_h { |name, i| [name, Crm::Stage.create!(pipeline: pipeline, name: name, position: i)] }
      # a configuração de produção que causava o erro: agendamento como "conversão"
      CrmSetting.find_or_create_by!(account: account).update!(
        meta_ads_config: { 'conversion_stage_ids' => [stages['Agendamento de Consulta'].id, stages['Cirurgia Realizada'].id] }
      )
      leads = Array.new(5) do |i|
        create(:contact, account: account, phone_number: "+55119777000#{i}",
                         additional_attributes: { 'meta_ads' => { 'source_id' => '2301', 'captured_at' => 3.days.ago.iso8601 } })
      end
      put = ->(contact, name, value = nil) { Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stages[name], value: value) }
      put.call(leads[0], 'Agendamento de Consulta', 8000)
      put.call(leads[1], 'Consulta Realizada', 8000)
      put.call(leads[2], 'Cirurgia Agendada', 8000)
      put.call(leads[3], 'Cirurgia Realizada', 9000)

      row = service.overview[:rows].find { |r| r[:ad_id] == '2301' }

      expect(row[:funnel]).to include(leads: 5, booked: 4, attended: 3, surgeries: 1, revenue: 9000.0)
      expect(row[:funnel][:sources]).to include(booked_crm: 4, booked_agenda: 0, surgeries_crm: 1, surgeries_of: 0)
      expect(row[:rates]['cost_surgery']).to be > row[:rates]['cost_booked']
    end

    it 'item 286: pulado por falta de chave, falha e fila travada voltam a ser tentados; dinâmico com vídeo também' do
      video = Crm::AdCreative.find_by!(account: account, ad_id: '2304')
      set = ->(fields) { video.update!(creative: video.creative.merge('transcript' => fields)) }
      pending = -> { Crm::AdVideoTranscribeJob.pending_for(account).pluck(:ad_id) }

      set.call('status' => 'skipped', 'error' => Crm::AdVideoTranscriptionService::NO_KEY)
      expect(pending.call).to include('2304')
      set.call('status' => 'skipped', 'error' => 'Este anúncio não tem vídeo identificado na Meta.')
      expect(pending.call).not_to include('2304')
      set.call('status' => 'failed', 'error' => 'Gemini respondeu com erro 503')
      expect(pending.call).to include('2304')
      set.call('status' => 'processing', 'status_at' => 2.minutes.ago.iso8601)
      expect(pending.call).not_to include('2304')
      set.call('status' => 'processing', 'status_at' => 1.hour.ago.iso8601)
      expect(pending.call).to include('2304')

      image = Crm::AdCreative.find_by!(account: account, ad_id: '2305')
      image.update!(format: 'dynamic', creative: image.creative.merge('video_id' => '998877'))
      expect(image.transcribable?).to be(true)
      expect(pending.call).to include('2305')
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

    it 'item 287: a curva detalhada (segundo a segundo) entra no detalhe, com marcos, maior queda, média e cliques' do
      creative = Crm::AdCreative.find_by!(account: account, ad_id: '2301')
      expect(creative.creative['video_length']).to eq(28.0) # duração veio na carga (simulação)
      expect(Crm::AdInsight.find_by(account: account, ad_id: '2301').metrics).to include('play_curve', 'plays', 'p95', 'plays_30s')

      curve = service.detail('2301')[:retention_detail]
      expect(curve).to include(source: 'meta_curve', axis: 'seconds', base: 'plays', duration: 28.0, duration_estimated: false, curve_days: 30)
      expect(curve[:points].first).to include(t: 0, pct: 1.0)
      expect(curve[:points].last).to include(t: 28.0, label: 'fim')
      expect(curve[:points].size).to be > 15
      expect(curve[:points].pluck(:pct)).to eq(curve[:points].pluck(:pct).sort.reverse) # só desce
      expect(curve[:points].first[:people]).to eq(curve[:base_total])
      expect(curve[:average].size).to be > 10
      expect(curve[:marks].pluck(:key)).to eq(%w[3s p25 p50 p75 p100])
      expect(curve[:marks].pluck(:t)).to eq([3, 7.0, 14.0, 21.0, 28.0])
      expect(curve[:biggest_drop]).to include(:from_label, :to_label, :drop, :people_lost)
      expect(curve[:biggest_drop_after_hook][:from_t]).to be >= 3

      # rodada 2: as 3 a 5 maiores quedas, numeradas, sem trechos vizinhos e só as que contam
      drops = curve[:top_drops]
      expect(drops.size).to be_between(3, 5)
      expect(drops.pluck(:rank)).to eq((1..drops.size).to_a)
      expect(drops.first.slice(:from_t, :to_t, :drop)).to eq(curve[:biggest_drop].slice(:from_t, :to_t, :drop))
      expect(drops.pluck(:drop)).to all(be >= 0.01)
      expect(drops).to all(include(:from_label, :to_label, :from_pct, :to_pct, :people_lost, :after_hook))
      starts = drops.pluck(:from_t).sort
      expect(starts.each_cons(2).map { |a, b| b - a }).to all(be > 1)

      clicks = curve[:clicks]
      expect(clicks[:note]).to include('não informa em que segundo')
      expect(clicks[:marks].pluck(:key)).to eq(%w[impressions 3s p25 p50 p75 p100])
      fim = clicks[:marks].last
      expect(fim[:rate]).to eq((clicks[:link_clicks] / fim[:reached].to_f).round(4))
      expect(fim[:before_min]).to eq([clicks[:link_clicks] - fim[:reached], 0].max)
    end

    it 'rodada 3: o veredito dos indicadores vem da MÉDIA da conta (custo invertido) e some o "bom a partir de"' do
      card = service.detail('2304')[:scorecard]
      expect(card[:indicators].pluck(:key)).to eq(%w[hook_rate hold_rate link_ctr conv_rate cost_conversation])
      hook, hold = card[:indicators].first(2)
      expect(hook).to include(label: 'Gancho', verdict: 'good', verdict_label: 'acima da média', money: false, lower: false)
      expect(hook[:phrase]).to match(/pontos? acima da média da conta/)
      expect(hold).to include(verdict: 'bad', verdict_label: 'abaixo da média')
      cost = card[:indicators].last
      expect(cost).to include(money: true, lower: true, verdict: 'bad', verdict_label: 'mais caro que a média')
      expect(card[:indicators].flat_map(&:keys).uniq).not_to include(:good, :bad, :good_text, :band)
      expect(card.to_json).not_to match(/bom a partir|bom até/i)
      expect(service.detail('2305')[:scorecard][:indicators].pluck(:key)).not_to include('hook_rate') # imagem não tem gancho

      # dentro de ±5 % da média = "na média"; custo menor que a média = verde
      near = Crm::CreativeScorecard.new(rates: { 'link_ctr' => 0.0104, 'cost_conversation' => 5.0 },
                                        averages: { 'link_ctr' => 0.01, 'cost_conversation' => 8.0 }).call[:indicators]
      expect(near.first).to include(verdict: 'even', verdict_label: 'na média')
      expect(near.last).to include(verdict: 'good', verdict_label: 'mais barato que a média')
    end

    it 'rodada 3: recorde da conta por indicador, com o recordista marcado e quanto falta' do
      records = Crm::CreativeRecords.new(account: account).ad_records
      expect(records.keys).to include('hook_rate', 'hold_rate', 'link_ctr', 'conv_rate', 'cost_conversation')
      expect(records['hook_rate']).to include(ad_id: '2304', ad_name: a_string_including('Cansou das lentes'))
      expect(records['hook_rate'][:since]).to be <= records['hook_rate'][:until]
      expect(records['cost_conversation'][:ad_id]).to eq('2301') # menor custo = recorde

      champion = service.detail('2304')[:scorecard]
      hook = champion[:indicators].find { |i| i[:key] == 'hook_rate' }
      expect(hook).to include(is_record: true, record_phrase: Crm::CreativeScorecard::IS_RECORD)
      hold = champion[:indicators].find { |i| i[:key] == 'hold_rate' }
      expect(hold).to include(is_record: false, record_ad: a_string_including('Depoimento Ana'))
      expect(hold[:record]).to be > hold[:value]
      expect(hold[:record_phrase]).to match(/\Afaltam \d+(,\d)? pontos para o recorde\z/)
      expect(hold[:record_when]).to match(%r{\Ade \d{2}/\d{2}/\d{4} a \d{2}/\d{2}/\d{4}\z})

      axes = champion[:radar][:axes]
      expect(axes.pluck(:label)).to include('Gancho', 'Corpo', 'CTA', 'Conversa')
      expect(axes.pluck(:score)).to all(be_between(0, 100))
      expect(axes.pluck(:record_score).compact).to all(eq(100)) # recorde = borda de fora
      expect(axes.find { |a| a[:key] == 'hook_rate' }).to include(is_record: true)
      expect(champion[:radar][:note]).to include('recorde da conta')
    end

    it 'rodada 3: o recorde respeita o volume mínimo (anúncio pequeno não vira recorde por acaso)' do
      now = Time.current
      Crm::AdCreative.create!(account: account, ad_id: 'mini', ad_name: 'Anúncio pequeno', format: 'video', creative: {})
      tiny = { 'impressions' => 400, 'plays_3s' => 380, 'thruplay' => 370, 'link_clicks' => 20, 'conversations' => 20, 'spend' => 1.0 }
      Crm::AdInsight.create!(account: account, ad_id: 'mini', date: Date.current, metrics: tiny, created_at: now, updated_at: now)
      records = Crm::CreativeRecords.new(account: account).ad_records
      expect(records.values.pluck(:ad_id)).not_to include('mini')

      # com impressões de sobra mas poucos cliques, não vale para "conversa por clique"
      bigger = tiny.merge('impressions' => 5000, 'plays_3s' => 4900, 'thruplay' => 4800)
      Crm::AdInsight.find_by(account: account, ad_id: 'mini').update!(metrics: bigger)
      records = Crm::CreativeRecords.new(account: account).ad_records
      expect(records['hook_rate'][:ad_id]).to eq('mini')
      expect(records['conv_rate'][:ad_id]).not_to eq('mini')
      expect(Crm::CreativeRecords::RECORD_MIN_IMPRESSIONS).to eq(1000)
      expect(Crm::CreativeRecords::RECORD_MIN_CLICKS).to eq(30)
    end

    it 'rodada 3: "os mais e os menos" aponta vencedor único, ignora pouco volume e não inventa quando tudo é igual' do
      rows = [
        { key: 'a', label: 'Instagram · Reels', impressions: 20_000, link_clicks: 400, conversations: 269 },
        { key: 'b', label: 'Instagram · Feed', impressions: 15_000, link_clicks: 450, conversations: 120 },
        { key: 'c', label: 'Audience Network', impressions: 9000, link_clicks: 200, conversations: 32 },
        { key: 'd', label: 'Sorte', impressions: 60, link_clicks: 6, conversations: 6 }
      ]
      ranking = Crm::BreakdownHighlights.new(rows).call
      expect(ranking[:rows].pluck(:key)).to eq(%w[a b c d]) # do melhor para o pior
      badges = ranking[:rows].to_h { |r| [r[:key], r[:badges].pluck(:label)] }
      expect(badges['a']).to include('mais conversas', 'melhor aproveitamento')
      expect(badges['c']).to include('pior aproveitamento')
      expect(badges['d']).to eq(['menos conversas']) # 60 exibições: não disputa aproveitamento
      expect(ranking[:rows].first).to include(clicks_per_100: 2.0, conversations_per_100: 67.25, yield_1000: 13.45)
      expect(ranking[:summary]).to include('rende mais em Instagram · Reels (269 conversas)', 'menos em Sorte (6 conversas)')
      expect(ranking[:no_difference]).to be(false)

      same = Array.new(4) { |i| { key: "k#{i}", label: "Faixa #{i}", impressions: 5000, link_clicks: 100, conversations: 40 } }
      tie = Crm::BreakdownHighlights.new(same, kind: 'audience').call
      expect(tie[:rows].flat_map { |r| r[:badges] }).to be_empty
      expect(tie[:no_difference]).to be(true)
      expect(tie[:summary]).to include('Não há diferença relevante')

      # diferença pequena demais para o volume (8 × 9 conversas) não vira selo de aproveitamento
      noisy = [{ key: 'x', label: 'X', impressions: 3000, link_clicks: 30, conversations: 9 },
               { key: 'y', label: 'Y', impressions: 3000, link_clicks: 30, conversations: 8 }]
      expect(Crm::BreakdownHighlights.new(noisy).call[:rows].flat_map { |r| r[:badges].pluck(:key) }).not_to include('best', 'worst')

      detail = service.detail('2301')
      expect(detail[:placement_ranking][:summary]).to include('rende mais em Instagram · Reels')
      expect(detail[:audience_ranking][:no_difference]).to be(true) # na simulação os números se repetem
      expect(detail[:analysis_text]).to include('ONDE APARECEU: OS MAIS E OS MENOS', '[MAIS CONVERSAS]', 'RECORDE DA CONTA'.downcase)
    end

    it 'rodada 2: poucas quedas relevantes → mostra só as que contam (nunca inventa)' do
      creative = Crm::AdCreative.find_by!(account: account, ad_id: '2301')
      flat = [100, 60] + Array.new(20, 59.9)
      list = [{ 'impressions' => 1000, 'plays_3s' => 500, 'plays' => 900, 'p25' => 400, 'p50' => 300, 'p75' => 200, 'p100' => 100,
                'play_curve' => flat, 'date' => Date.current }]
      curve = Crm::AdRetentionCurve.new(creative: creative, list: list).call
      expect(curve[:top_drops].size).to be < 3
      expect(curve[:top_drops].first).to include(rank: 1, from_t: 0, to_t: 1)
    end

    it 'item 287: a transcrição com tempo mostra o que é falado em cada trecho; a antiga (sem tempo) segue funcionando' do
      creative = Crm::AdCreative.find_by!(account: account, ad_id: '2304')
      Crm::AdVideoTranscriptionService.new(creative).perform
      expect(creative.reload.transcript['segments'].first).to include('start' => 0.0, 'end' => 3.0, 'text' => 'Cansou das lentes?')
      Crm::AdInsightsSyncService.new(account: account).call # a carga preserva trechos e duração
      expect(creative.reload.transcript['segments'].size).to eq(3)
      expect(creative.creative['video_length']).to be_present

      detail = service.detail('2304')
      segments = detail[:retention_detail][:segments]
      expect(segments.size).to eq(3)
      expect(segments.first).to include(text: 'Cansou das lentes?', pct_start: 1.0)
      expect(segments.first[:people_lost]).to be > 0
      expect(detail[:retention_detail][:biggest_drop][:speech]).to include('Cansou das lentes?')
      expect(detail[:analysis_text]).to include('TRANSCRIÇÃO DO VÍDEO', 'Fala por trecho', 'CURVA DE RETENÇÃO', 'CLIQUES POR QUEM CHEGOU ATÉ AQUI')

      old = creative.transcript.except('segments', 'duration')
      creative.update!(creative: creative.creative.merge('transcript' => old))
      again = described_class.new(account: account, since_date: Date.current - 29, until_date: Date.current).detail('2304')
      expect(again[:retention_detail][:segments]).to eq([])
      expect(again[:transcript]['text']).to be_present
    end

    it 'item 287: dados antigos (sem a curva da Meta) caem nos marcos de sempre, sem quebrar' do
      Crm::AdInsight.where(account: account, ad_id: '2302').find_each do |row|
        row.update!(metrics: row.metrics.except('play_curve', 'plays', 'p95', 'plays_30s'))
      end
      video = Crm::AdCreative.find_by!(account: account, ad_id: '2302')
      video.update!(creative: video.creative.except('video_length'))
      curve = service.detail('2302')[:retention_detail]
      expect(curve).to include(source: 'milestones', axis: 'marks', base: 'impressions')
      expect(curve[:points].pluck(:label)).to eq(['Impressões', '3 s', '25%', '50%', '75%', 'fim'])
      expect(curve[:clicks][:marks].size).to eq(6)
      expect(service.detail('2305')[:retention_detail]).to be_nil # imagem não tem curva
    end

    it 'item 287: se a Meta recusar a curva detalhada, a carga desce um degrau e mantém as métricas de vídeo' do
      simulator = Crm::MetaSimulator.new(account: account)
      allow(Crm::MetaSimulator).to receive(:new).and_return(simulator)
      allow(simulator).to receive(:fetch_all).and_wrap_original do |original, edge, query|
        raise Crm::MetaGraph::Error, 'campo recusado' if edge == 'insights' && query[:fields].to_s.include?('video_play_curve_actions')

        original.call(edge, query)
      end
      Crm::AdInsight.where(account: account).delete_all
      Crm::AdInsightsSyncService.new(account: account, days: 3).call
      metrics = Crm::AdInsight.find_by(account: account, ad_id: '2301').metrics
      expect(metrics['plays_3s']).to be > 0
      expect(metrics['p25']).to be > 0
      expect(Crm::AdInsightsSyncService.state(account)['last_warning']).to include('curva detalhada')
    end

    it 'ranqueia ganchos, corpos e CTAs da conta inteira' do
      assets = service.assets_for(nil)
      expect(assets[:dynamic_ads]).to eq(1)
      expect(assets[:ctas][:rows].map { |r| r[:label] }).to include('Enviar mensagem (WhatsApp)')
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
