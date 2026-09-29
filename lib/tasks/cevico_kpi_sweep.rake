# 🧹 item 278: varredura dos indicadores do "+" do Meu Painel
#   DRY=1 (padrão) só lista; DRY=0 aplica
#   bundle exec rake cevico:kpi_sweep ACCOUNT_ID=1 DRY=1
namespace :cevico do
  desc 'Varre os indicadores do "+" (custom_kpis): corrige fórmulas, apaga duplicados e os que não resolvem'
  task kpi_sweep: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    dry = ENV.fetch('DRY', '1') != '0'
    sweep = Crm::KpiSweep.new(account)
    result = dry ? sweep.plan : sweep.apply!
    puts "conta #{account.id} · #{result[:total]} indicadores do \"+\" · #{result[:actions].size} ações#{dry ? ' (DRY: nada mudou)' : ' APLICADAS'}"
    result[:actions].each do |a|
      puts "- #{a.kind == :delete ? 'APAGAR ' : 'CORRIGIR'} #{a.id} \"#{a.label}\": #{a.before}#{a.after ? " → #{a.after}" : ''} · #{a.why}"
    end
    puts 'nada a fazer' if result[:actions].empty?
  end
end
