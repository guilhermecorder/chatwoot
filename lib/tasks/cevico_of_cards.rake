# 🗂️ PONTA 3 (22/10): arruma os cards parados em "Cirurgia Agendada" do funil
# da CEVICO (regra em Crm::OfSurgeryCards). Já operou com prova → Cirurgia
# Realizada (até 30 dias) ou Pós Operatório; cancelada → Não Fechou Ainda; o
# resto fica. A entrada na coluna nova leva a data real e fica FORA dos
# indicadores (carga), sem disparar automação.
#   bundle exec rake cevico:of_cards_cirurgia ACCOUNT_ID=1          → ensaio (só mostra)
#   bundle exec rake cevico:of_cards_cirurgia ACCOUNT_ID=1 DRY=0    → move
namespace :cevico do
  desc 'Ponta 3: cards em Cirurgia Agendada de cirurgia que já passou ou foi cancelada (DRY=1 padrão)'
  task of_cards_cirurgia: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    dry = ENV.fetch('DRY', '1') != '0'
    service = Crm::OftalmofacilSyncService.new(account: account, silent: true)
    cards = service.surgery_cards
    rows = cards.rows
    puts "Cirurgia Agendada (funil #{service.send(:own_pipeline)&.name}): #{rows.size} card(s)"
    Crm::OfSurgeryCards.tally(rows).each { |k, n| puts format('  %-20<k>s %<n>5d  %<l>s', k: k, n: n, l: Crm::OfSurgeryCards::LABELS[k]) }
    moving = rows.select(&:target)
    moving.group_by { |r| r.target.name }.each { |stage, list| puts "  → #{stage}: #{list.size}" }
    moving.first(40).each do |r|
      puts "    #{r.card.contact&.name} · #{r.surgery&.surgery_date} · #{r.klass} → #{r.target.name}"
    end
    puts "    … e mais #{moving.size - 40}" if moving.size > 40
    if dry
      puts 'ENSAIO: nada mudou. Para mover: DRY=0'
    else
      done = cards.settle!(catch_up: true)
      puts "MOVIDOS: #{done.size} (entrada com a data real, fora dos indicadores)"
    end
  end
end
