# 🧹 item 309: tira as CARGAS EM MASSA dos indicadores de "Entrou em…"
#   DRY=1 (padrão) só lista; DRY=0 aplica; UNDO=1 desfaz tudo; MIN=30 = tamanho da rajada
#   bundle exec rake cevico:stage_logs_bulk ACCOUNT_ID=1 DRY=1
namespace :cevico do
  desc 'Histórico de colunas: marca as cargas em massa (30+ cartões na mesma coluna no mesmo minuto) para não contarem nos indicadores'
  task stage_logs_bulk: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    min = ENV.fetch('MIN', Crm::StageLogBulk::THRESHOLD).to_i
    tz = ActiveSupport::TimeZone['America/Sao_Paulo']

    if ENV['UNDO'] == '1'
      puts "conta #{account.id} · DESFEITO: #{Crm::StageLogBulk.undo!(account)} entradas voltaram a contar"
      next
    end

    dry = ENV.fetch('DRY', '1') != '0'
    rows = Crm::StageLogBulk.summary(account, min: min)
    total = Crm::StageLogBulk.scope(account).where(event_type: Crm::StageLogBulk::ENTERED).count
    puts "conta #{account.id} · #{total} entradas contando hoje · já fora dos indicadores: #{Crm::StageLogBulk.marked_count(account)}"
    puts "cargas em massa (#{min}+ cartões na mesma coluna no mesmo minuto) — horário de São Paulo:"
    rows.each do |r|
      from = r[:from].in_time_zone(tz).strftime('%H:%M')
      to = r[:to].in_time_zone(tz).strftime('%H:%M')
      puts format('- %<day>s · %<stage>-28s %<entries>6d entradas em %<minutes>d min (%<from>s–%<to>s)',
                  day: r[:from].in_time_zone(tz).strftime('%d/%m/%Y'), stage: r[:stage_name], entries: r[:entries],
                  minutes: r[:minutes], from: from, to: to)
    end
    sum = rows.sum { |r| r[:entries] }
    if dry
      puts "TOTAL: #{sum} entradas sairiam dos indicadores (DRY: nada mudou). Para aplicar: DRY=0"
    else
      puts "APLICADO: #{Crm::StageLogBulk.mark!(account, min: min)} entradas fora dos indicadores. Para desfazer: UNDO=1"
    end
  end
end
