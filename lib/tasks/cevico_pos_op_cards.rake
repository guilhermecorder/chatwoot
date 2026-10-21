# 🩹 21/10: leva para "Consulta Pós Op" os cards de quem JÁ tem consulta de
# pós-op marcada (as novas andam sozinhas pelo Crm::PosOpReflector).
#   DRY=1 (padrão) só lista · DRY=0 move e dispara as automações da coluna
#   bundle exec rake cevico:pos_op_cards ACCOUNT_ID=1 DRY=1
namespace :cevico do
  desc 'Cards de quem tem consulta de pós-op futura → coluna Consulta Pós Op'
  task pos_op_cards: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    dry = ENV.fetch('DRY', '1') != '0'
    stage = Crm::PosOpReflector.stage_for(account)
    abort 'Coluna "Consulta Pós Op" não encontrada no CRM.' if stage.nil?

    tasks = account.tasks.where(task_type: 'consulta', modality: Crm::PosOpReflector::MODALITY, canceled_at: nil, archived_at: nil)
                   .where(due_at: Crm::PosOpReflector::TZ.now.beginning_of_day..)
                   .where("tasks.source IS DISTINCT FROM 'oftalmofacil'").order(:due_at)
    puts "Coluna: #{stage.name} (id #{stage.id}) · #{tasks.count} consulta(s) de pós-op futura(s) · #{dry ? 'ENSAIO' : 'VALENDO'}"
    moved = 0
    tasks.find_each do |task|
      contact = task.contact || Task.match_contact(account, task.phone)
      card = contact && Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
      quando = task.due_at.in_time_zone(Crm::PosOpReflector::TZ).strftime('%d/%m %H:%M')
      line = "#{quando} · #{task.title} · card em: #{card&.stage&.name || 'sem card'}"
      next puts("  = #{line}") if card&.stage_id == stage.id

      result = dry ? '(andaria)' : (Crm::PosOpReflector.call(task) || '(ficou: parceiro ou sem paciente)')
      moved += 1 if !dry && result.is_a?(String) && result == stage.name
      puts "  → #{line} #{result}"
    end
    puts dry ? 'Ensaio: nada mudou. Rode com DRY=0 para mover.' : "#{moved} card(s) movido(s)."
  end
end
