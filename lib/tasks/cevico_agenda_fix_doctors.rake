# 🩺 item 311: consultas gravadas com o médico ERRADO (a IA usava o 1º médico do dia na unidade:
# terça à tarde na Av. Paulista saía como Dr. Henrique, mas a faixa é da Dra. Roberta)
#   DRY=1 (padrão) só lista; DRY=0 corrige; ALL=1 inclui as que já passaram
#   bundle exec rake cevico:agenda_fix_doctors ACCOUNT_ID=1 DRY=1
namespace :cevico do
  desc 'Agenda: corrige o médico das consultas cujo horário cai na faixa de OUTRO médico'
  task agenda_fix_doctors: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    dry = ENV.fetch('DRY', '1') != '0'
    tz = Crm::AgendaSlots::TZ
    scope = account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil, source: nil)
                   .where(unit: %w[paulista tatuape]).where.not(doctor: [nil, ''])
    scope = scope.where(due_at: tz.now.beginning_of_day..) unless ENV['ALL'] == '1'
    official = Crm::AgendaSlots.windows(account).pluck('doctor').uniq
    fixes = scope.order(:due_at).filter_map do |task|
      at = task.due_at.in_time_zone(tz)
      modality = Crm::AgendaSlots.slot_modality(task)
      wins = Crm::AgendaSlots.windows(account).select { |w| w['dow'] == at.wday && w['unit'] == task.unit }
      minutes = (at.hour * 60) + at.min
      covering = wins.select { |w| minutes >= Crm::AgendaSlots.hm_to_min(w['start']) && minutes < Crm::AgendaSlots.hm_to_min(w['end']) }
      # só mexe quando o médico gravado é EXATAMENTE o nome de um médico das faixas (é como a IA grava) e a
      # faixa do horário é de OUTRO — nome escrito pela equipe (outro profissional, grafia diferente) fica como está
      next if covering.empty? || official.exclude?(task.doctor) || covering.any? { |w| w['doctor'] == task.doctor }

      right = (covering.find { |w| Crm::AgendaSlots.accepts?(w, modality) } || covering.first)['doctor']
      [task, at, right]
    end
    puts "conta #{account.id} · #{fixes.size} consulta(s) com médico diferente do da faixa#{dry ? ' (DRY: nada mudou)' : ''}"
    fixes.each do |task, at, right|
      puts "- #{at.strftime('%a %d/%m %H:%M')} · #{task.unit} · #{task.title.to_s.truncate(40)}: #{task.doctor} → #{right}"
      task.update_columns(doctor: right, updated_at: Time.current) unless dry # rubocop:disable Rails/SkipsModelValidations
    end
    puts dry ? 'Para corrigir: DRY=0' : 'CORRIGIDO.'
  end
end
