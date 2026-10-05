# 🏷️ item 322: FONTES DE PACIENTES — carimba o passado (o mesmo que o botão da
# tela Fontes de pacientes e o robô da madrugada fazem).
#   DRY=1 (padrão) só mostra o que seria carimbado; DRY=0 grava
#   bundle exec rake cevico:sources ACCOUNT_ID=1 DRY=1
namespace :cevico do
  desc 'Fontes de pacientes: carimba a fonte (CEVICO × Oftalmofácil) no que nasceu antes do carimbo'
  task sources: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    dry = ENV.fetch('DRY', '1') != '0'
    names = { contacts: 'pacientes', cards: 'cards do CRM', stage_logs: 'entradas em coluna', tasks: 'agendamentos e tarefas',
              surgeries: 'itens do hub' }

    puts "conta #{account.id} · fontes: #{Crm::Sources.list(account).map { |s| "#{s.name} (#{s.key})" }.join(', ')}"
    puts "sem carimbo hoje: #{Crm::SourceBackfill.pending(account).map { |t, n| "#{names[t]} #{n}" }.join(' · ')}"
    result = dry ? Crm::SourceBackfill.preview(account) : Crm::SourceBackfill.run!(account)
    puts dry ? 'SERIA carimbado (DRY: nada mudou). Para gravar: DRY=0' : 'CARIMBADO:'
    result.each do |table, by_source|
      puts format('- %<name>-24s %<list>s', name: names[table], list: by_source.map { |key, n| "#{key} #{n}" }.join(' · ').presence || 'nada')
    end
  end
end
