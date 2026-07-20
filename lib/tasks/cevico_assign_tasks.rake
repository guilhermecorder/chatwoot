# Backfill de RESPONSÁVEL nas tarefas abertas (pedido 20/07): as tarefas
# automáticas nasciam sem responsável — depois de configurar o "👤
# Responsável pelas tarefas" nas colunas do CRM (e/ou os responsáveis da
# conferência), rode:
#
#   bundle exec rails "cevico:assign_tasks[1]"          # só MOSTRA (dry-run)
#   APPLY=1 bundle exec rails "cevico:assign_tasks[1]"  # grava de verdade
#
# Só mexe em tarefa ABERTA (a fazer/fazendo), sem responsável e não
# arquivada. Quem já tem responsável fica como está.
namespace :cevico do
  desc 'Atribui responsável às tarefas abertas sem dono, pela coluna do paciente no CRM'
  task :assign_tasks, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id] || 1)
    apply = ENV['APPLY'] == '1'

    scope = account.tasks.where(status: %i[todo doing], assignee_id: nil, archived_at: nil)
    puts "Conta #{account.id} — #{scope.count} tarefas abertas sem responsável"
    puts apply ? '>> APPLY=1: gravando' : '>> DRY-RUN: só mostrando (rode com APPLY=1 para gravar)'

    by_owner = Hash.new(0)
    skipped = 0

    scope.includes(:contact).find_each do |task|
      contact = task.contact || Task.match_contact(account, task.phone)
      owner = Crm::TaskOwner.resolve(account, contact: contact, task_type: task.task_type)
      if owner.nil?
        skipped += 1
        next
      end

      by_owner[owner.name] += 1
      # update_columns de propósito: sem disparar validações/hooks em lote
      task.update_columns(assignee_id: owner.id, updated_at: Time.current) if apply # rubocop:disable Rails/SkipsModelValidations
    end

    puts '— Resultado por responsável:'
    by_owner.sort_by { |_n, c| -c }.each { |name, count| puts format('  %-30<name>s %<count>d', name: name, count: count) }
    puts "  (sem dono possível: #{skipped} — coluna sem responsável e sem fallback da conferência)"
    puts apply ? 'Gravado ✅' : 'Nada gravado (dry-run).'
  end
end
