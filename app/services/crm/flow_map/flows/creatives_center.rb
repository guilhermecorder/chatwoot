# 🎯 Central de Criativos (item 172) — passos reais de
# app/jobs/crm/ad_insights_sync_job.rb + app/services/crm/ad_insights_sync_service.rb
# + creative_analytics_service.rb (leitura gancho / corpo / CTA).
class Crm::FlowMap::Flows::CreativesCenter
  FLOW = Crm::FlowMap::Flow.define(:creatives_center) do # rubocop:disable Metrics/BlockLength
    name 'Central de Criativos'
    group 'Marketing e aquisição'
    icon 'i-lucide-clapperboard'
    color '#7C3AED'
    what 'guarda os anúncios da Meta com o criativo e as métricas por dia, e lê cada um como gancho, corpo e CTA'
    config route: 'creatives_reports'
    trigger :cron, 'Toda madrugada 04:20 (SP) ou botão "Atualizar dados"'
    jobs 'Crm::AdInsightsSyncJob'

    node :config, 'Meta Ads configurado (token + conta de anúncios)?', kind: :decision
    node :trava, 'Trava por conta (Redis) livre?', kind: :decision
    node :janela, 'Janela: 3 dias (cron) · 30 (botão) · 90 (1ª carga)'
    node :ads, 'Busca /ads com o criativo (gancho, corpo, CTA, mídia)', kind: :external
    node :formato, 'Classifica o formato: vídeo · imagem · carrossel · dinâmico'
    node :insights, 'Busca /insights por anúncio e por dia', kind: :external
    node :grava, 'Grava/atualiza cevico_ad_creatives e cevico_ad_insights', kind: :output
    node :estado, 'Anota synced_at / erro em meta_ads_config.creatives_sync', kind: :output
    node :tela, 'Tela: taxas contra a média → forte / na média / fraco'
    node :diagnostico, 'Diagnóstico em 1 frase + fadiga (CTR caiu na 2ª metade)', kind: :output
    node :quebras, 'Sob demanda: posicionamento, idade × sexo e ativos', kind: :external
    node :fim, 'Fim', kind: :end

    edge :trigger, :config
    edge :config, :fim, 'não'
    edge :config, :trava, 'sim'
    edge :trava, :fim, 'ocupada'
    edge :trava, :janela, 'sim'
    edge :janela, :ads
    edge :ads, :formato
    edge :formato, :insights
    edge :insights, :grava
    edge :grava, :estado
    edge :estado, :tela
    edge :tela, :diagnostico
    edge :tela, :quebras
    edge :diagnostico, :fim
    edge :quebras, :fim

    live do |account|
      cfg = (setting&.meta_ads_config || {})
      state = cfg['creatives_sync'] || {}
      {
        enabled: cfg['access_token'].present? && cfg['ad_account_id'].present?,
        last_run_at: state['synced_at'],
        counters: {
          'anúncios guardados' => Crm::AdCreative.where(account_id: account.id).count,
          'dias com métricas' => Crm::AdInsight.where(account_id: account.id).distinct.count(:date),
          'última carga' => state['ads'] ? "#{state['ads']} anúncios · #{state['rows']} linhas" : 'nenhuma ainda'
        },
        note: state['last_error'].presence
      }
    end
  end

  def self.flow
    FLOW
  end
end
