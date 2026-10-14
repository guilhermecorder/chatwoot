# 🧭 item 341 (13/10): AMBIENTES DO CRM — passa para o funil do Oftalmofácil
# (ou do ambiente de cada um) quem é de lá e ainda tem card no CRM da CEVICO.
#   DRY=1 (padrão) só lista, uma linha por paciente; DRY=0 grava (só os MOVER)
#   MODO=resumo só conta MOVER / MANTER / REVISAR
#   CONTACT_IDS=1,2,3 só esses pacientes · LIMIT=50 no máximo N pacientes
#   bundle exec rake cevico:ambientes_migrar ACCOUNT_ID=1 DRY=1
#   bundle exec rake cevico:ambientes_migrar ACCOUNT_ID=1 DRY=0   (antes: backup!)
namespace :cevico do
  desc 'Ambientes do CRM: tira do funil da CEVICO os pacientes de outro ambiente (Oftalmofácil) e põe no funil deles'
  task ambientes_migrar: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    dry = ENV.fetch('DRY', '1') != '0'
    ids = ENV['CONTACT_IDS'].to_s.split(',').map(&:strip).reject(&:empty?).map(&:to_i)
    migration = Crm::EnvironmentMigration.new(account, contact_ids: ids, limit: ENV.fetch('LIMIT', nil))

    names = Crm::Sources.list(account).to_h { |s| [s.id, s.name] }
    puts "conta #{account.id} · ambientes: #{names.values.join(', ')}"
    if ENV['MODO'] == 'resumo'
      migration.summary.each { |bucket, n| puts format('- %<bucket>-8s %<n>d pacientes', bucket: bucket, n: n) }
      next
    end

    migration.rows.each { |row| puts migration.describe(row) }
    totals = migration.summary
    puts "TOTAL: #{totals.map { |bucket, n| "#{bucket} #{n}" }.join(' · ')}"
    if dry
      puts 'DRY: nada mudou. Para gravar os MOVER: DRY=0 (faça o backup antes)'
    else
      puts "MOVIDOS: #{migration.run!} pacientes (MANTER e REVISAR ficaram como estavam)"
    end
  end
end
