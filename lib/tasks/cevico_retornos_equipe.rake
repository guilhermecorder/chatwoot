# 🔁 item 343 (13/10) "Retornos para a equipe dos retornos": daqui para
# frente o retorno novo nasce sem dono individual (as duas da equipe veem
# tudo). Os retornos JÁ marcados continuam no nome de quem marcou — nada é
# mudado sozinho. Esta tarefa LISTA os retornos FUTUROS ainda abertos que
# estão no nome de alguém FORA da equipe e, com DRY=0, tira o dono (a
# consulta continua na Agenda para todos; a equipe recebe os avisos).
#   DRY=1 (padrão) só lista; DRY=0 aplica
#   bundle exec rake cevico:retornos_equipe ACCOUNT_ID=1 DRY=1
namespace :cevico do
  desc 'Retornos futuros no nome de alguém fora da Equipe dos retornos: lista (DRY=1) ou tira o dono (DRY=0)'
  task retornos_equipe: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    dry = ENV.fetch('DRY', '1') != '0'
    tz = ActiveSupport::TimeZone['America/Sao_Paulo']
    team = Crm::TaskOwner.retorno_team_ids(account)
    if team.empty?
      puts "conta #{account.id} · a Equipe dos retornos ainda não foi escolhida (Agenda → Configurações → Conferência do dia). Nada feito."
      next
    end

    names = account.users.where(id: team).pluck(:name)
    tasks = account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil, status: %i[todo doing])
                   .where('due_at >= ?', Time.current)
                   .where.not(assignee_id: nil).where.not(assignee_id: team)
                   .includes(:assignee).order(:due_at)
                   .select { |t| Crm::TaskOwner.retorno?(t) }
    puts "conta #{account.id} · equipe dos retornos: #{names.join(', ')}"
    puts "#{tasks.size} retorno(s) futuro(s) no nome de alguém fora da equipe:"
    tasks.group_by { |t| t.assignee&.name || '?' }.each do |name, list|
      puts "- #{name}: #{list.size}"
      list.first(30).each { |t| puts "    ##{t.id} · #{t.due_at.in_time_zone(tz).strftime('%d/%m %H:%M')} · #{t.title}" }
    end

    if dry
      puts 'DRY-RUN — nada gravado (rode com DRY=0 para tirar o dono e deixar com a equipe).'
    else
      # update_all de propósito: só o dono muda — sem mexer em lembrete, remarcação ou carimbos
      count = account.tasks.where(id: tasks.map(&:id)).update_all(assignee_id: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      puts "APLICADO: #{count} retorno(s) sem dono individual, com a equipe dos retornos."
    end
  end
end
