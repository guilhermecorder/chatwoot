# Correção das DATAS DO LOTE IMPORTADO (pedido 19/07).
#
# Problema: a migração do Robomaster criou ~20k contatos de uma vez — todos
# com created_at do DIA DA IMPORTAÇÃO. Qualquer indicador por período
# ("novos leads no mês/semana/dia") enxerga o lote inteiro num dia só.
#
# Correção: para contatos criados na janela da importação, a data de
# chegada passa a ser a da PRIMEIRA CONVERSA do contato (as conversas
# migraram com as datas reais). Sem conversa = fica como está (não há
# informação melhor). Os cards do CRM (crm_contacts) acompanham.
#
# Uso (SEMPRE conferir o dry-run antes):
#   bundle exec rails "cevico:fix_imported_dates[1]"            # só relatório
#   APPLY=1 bundle exec rails "cevico:fix_imported_dates[1]"    # grava
# Janela da importação (padrão 2026-07-01..2026-07-11) pode ser ajustada:
#   FROM=2026-07-01 TO=2026-07-11
namespace :cevico do
  desc 'Corrige created_at dos contatos do lote importado usando a 1ª conversa'
  task :fix_imported_dates, [:account_id] => :environment do |_, args|
    account = Account.find(args[:account_id] || 1)
    window_from = Date.parse(ENV.fetch('FROM', '2026-07-01')).beginning_of_day
    window_to = Date.parse(ENV.fetch('TO', '2026-07-11')).end_of_day
    apply = ENV['APPLY'] == '1'

    scope = account.contacts.where(created_at: window_from..window_to)
    puts "Conta #{account.id} · contatos criados na janela da importação: #{scope.count}"

    first_conv = Conversation.where(account_id: account.id)
                             .group(:contact_id)
                             .minimum(:created_at)

    fixable = []
    scope.find_each do |contact|
      real = first_conv[contact.id]
      next if real.blank?
      next if real >= contact.created_at # 1ª conversa depois da importação = contato novo mesmo

      fixable << [contact.id, contact.created_at, real]
    end

    puts "Com 1ª conversa ANTERIOR à importação (corrigíveis): #{fixable.size}"
    dist = fixable.group_by { |(_, _, real)| real.strftime('%Y-%m') }
                  .transform_values(&:size).sort
    dist.each { |month, n| puts "  #{month}: #{n} contato(s)" }

    unless apply
      puts "\nDRY-RUN (nada gravado). Rode com APPLY=1 para corrigir."
      next
    end

    puts "\nGravando…"
    fixed = 0
    fixable.each_slice(500) do |batch|
      batch.each do |(id, _old, real)|
        # rubocop:disable Rails/SkipsModelValidations
        Contact.where(id: id).update_all(created_at: real)
        Crm::Contact.where(contact_id: id)
                    .where(created_at: window_from..window_to)
                    .update_all(created_at: real)
        # rubocop:enable Rails/SkipsModelValidations
        fixed += 1
      end
      print "  #{fixed}/#{fixable.size}\r"
    end
    puts "\nPronto: #{fixed} contato(s) com a data real de chegada."
  end
end
