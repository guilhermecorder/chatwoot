# 💸 Gasto do WhatsApp (item 303, 30/09) — passos reais de
# app/jobs/crm/whatsapp_pricing_sync_job.rb + whatsapp_pricing_sync_service.rb
# (fatura da Meta) e do webhook de status (marca de cobrança em cada mensagem).
class Crm::FlowMap::Flows::WhatsappSpend
  FLOW = Crm::FlowMap::Flow.define(:whatsapp_spend) do # rubocop:disable Metrics/BlockLength
    name 'Gasto do WhatsApp'
    group 'Infraestrutura'
    icon 'i-lucide-receipt'
    color '#25D366'
    what 'lê na Meta quanto cada dia custou (fatura) e guarda em cada mensagem se foi cobrada e por quê — a tela mostra quem gastou'
    config route: 'whatsapp_spend_reports'
    trigger :cron, 'Toda madrugada 04:40 (SP) ou botão "Atualizar da Meta"'
    jobs 'Crm::WhatsappPricingSyncJob'

    node :caixas, 'Caixa do WhatsApp oficial com conta (WABA) e chave?', kind: :decision
    node :trava, 'Trava por conta (Redis) livre?', kind: :decision
    node :moeda, 'Pergunta a moeda da conta (BRL/USD)', kind: :external
    node :fatura, 'Busca pricing_analytics: dia × número × categoria × tipo', kind: :external
    node :grava, 'Grava/atualiza crm_whatsapp_charges (volume e custo)', kind: :output
    node :webhook, 'Status de cada mensagem traz "pricing" → cevico_wa_billing', kind: :external
    node :tela, 'Tela: fatura · quem gastou · regra de 01/10 · tarifas'
    node :painel, 'Meu Painel: 3 indicadores de WhatsApp no cesto', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :caixas
    edge :caixas, :fim, 'não'
    edge :caixas, :trava, 'sim'
    edge :trava, :fim, 'ocupada'
    edge :trava, :moeda, 'sim'
    edge :moeda, :fatura
    edge :fatura, :grava
    edge :grava, :tela
    edge :webhook, :tela
    edge :tela, :painel
    edge :painel, :fim

    live do |account|
      charges = Crm::WhatsappCharge.where(account_id: account.id)
      month = charges.where(day: Date.current.beginning_of_month..).where(pricing_type: 'regular')
      {
        enabled: account.inboxes.exists?(channel_type: 'Channel::Whatsapp'),
        last_run_at: charges.maximum(:updated_at)&.iso8601,
        counters: {
          'dias na fatura' => charges.distinct.count(:day),
          'cobrado neste mês' => "#{month.sum(:cost).to_f.round(2)} #{charges.first&.currency}".strip,
          'mensagens cobradas no mês' => month.sum(:volume)
        },
        note: charges.exists? ? nil : 'ainda sem leitura da Meta — abra Análises → Gasto do WhatsApp e clique "Atualizar da Meta"'
      }
    end
  end

  def self.flow
    FLOW
  end
end
