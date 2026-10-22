# 📅 ITEM 364: RE-DATAR as cargas em massa (ver Crm::StageLogRedate). Só
# Novos Contatos, Envio de Orçamento e Pós-operatório, com a data real provada.
#   bundle exec rake cevico:redatar_carga ACCOUNT_ID=1          → ensaio (só mostra)
#   bundle exec rake cevico:redatar_carga ACCOUNT_ID=1 DRY=0    → aplica
#   bundle exec rake cevico:redatar_carga ACCOUNT_ID=1 UNDO=1   → desfaz (volta para a hora da carga, fora dos indicadores)
namespace :cevico do
  desc 'Item 364: entradas das cargas em massa voltam a contar no dia real (só colunas seguras; DRY=1 padrão)'
  task redatar_carga: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    min = ENV.fetch('MIN', Crm::StageLogBulk::THRESHOLD).to_i
    if ENV['UNDO'] == '1'
      undone = Crm::StageLogRedate.undo!(account, min: min)
      puts "conta #{account.id} · DESFEITO: #{undone} entradas voltaram para a hora da carga (fora dos indicadores)"
      next
    end

    dry = ENV.fetch('DRY', '1') != '0'
    plans = Crm::StageLogRedate.plan(account, min: min)
    ready = plans.select(&:real_at)
    puts "conta #{account.id} · entradas das cargas: #{plans.size} · voltam a contar no dia real: #{ready.size}"
    plans.group_by { |p| [p.burst_day, p.stage_name] }.sort.each do |(day, stage), list|
      ok = list.select(&:real_at)
      puts "\n#{day.strftime('%d/%m/%Y')} · #{stage}: #{list.size} · re-datadas #{ok.size} (#{(100.0 * ok.size / list.size).round}%)"
      puts "    fonte: #{Crm::StageLogRedate::LABELS[list.first.kind]}" if ok.any?
      list.reject(&:real_at).group_by(&:skip).each { |why, l| puts "    ficam fora (#{why}): #{l.size}" }
      months = ok.group_by { |p| p.real_at.in_time_zone(Crm::StageLogRedate::TZ).strftime('%Y-%m') }.transform_values(&:size)
      puts "    meses: #{months.sort.map { |m, n| "#{m}=#{n}" }.join(' ')}" if months.any?
    end
    if dry
      puts "\nENSAIO: nada mudou. Para aplicar: DRY=0 (desfaz com UNDO=1)"
    else
      puts "\nAPLICADO: #{Crm::StageLogRedate.apply!(plans)} entradas voltaram a contar no dia real. Para desfazer: UNDO=1"
    end
  end
end
