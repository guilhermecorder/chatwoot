# 💸 #444 (13/10): corrige o histórico do Gasto da IA do Sonnet 5 (preço velho 3/15 → 2/10)
#   DRY=1 (padrão) só mostra o resumo; DRY=0 aplica. Pode rodar de novo sem medo
#   (linha já corrigida não é mexida). ACCOUNT_ID opcional (sem ele: todas as contas).
#   ANTES do DRY=0: conferir na fatura da Anthropic que o Sonnet 5 sempre custou 2/10.
#   bundle exec rake cevico:ai_usage_reprice DRY=1
namespace :cevico do
  desc 'Gasto da IA: refaz o custo das chamadas antigas do Sonnet 5 com o preço certo (US$ 2 / US$ 10)'
  task ai_usage_reprice: :environment do
    account_id = ENV['ACCOUNT_ID'].presence&.to_i
    reprice = Crm::AiUsageReprice.new(account_id: account_id)
    s = reprice.summary
    tz = ActiveSupport::TimeZone['America/Sao_Paulo']
    periodo = s[:first_at] ? "#{s[:first_at].in_time_zone(tz).strftime('%d/%m/%Y')} a #{s[:last_at].in_time_zone(tz).strftime('%d/%m/%Y')}" : '—'

    puts "Sonnet 5 · #{account_id ? "conta #{account_id}" : 'todas as contas'} · #{s[:total]} chamadas com custo"
    puts "- com o preço velho (seriam corrigidas): #{s[:stale]} (#{periodo})"
    puts "  custo hoje US$ #{s[:stale_cost_usd]} → com o preço certo US$ #{s[:new_cost_usd]}"
    puts "- já com o preço certo: #{s[:current]}"
    puts "- não batem com nenhuma conta (ficam como estão): #{s[:unmatched]}"

    if ENV.fetch('DRY', '1') == '0'
      puts "APLICADO: #{reprice.apply!} chamadas corrigidas."
    else
      puts 'DRY: nada mudou. Para aplicar: DRY=0'
    end
  end
end
