# 📅 item 217 (23/09): reclassificar consultas LANÇADAS pela equipe como
# "já estava marcada" (booking_kind = 'registro'), para não contarem como
# agendamento novo nos números.
#
# Critério (conferido antes de aplicar): consulta criada pela EQUIPE (sem
# marca de IA na descrição), sem booking_kind, criada no dia informado e com
# a consulta marcada para até 48 h depois da criação (lançamento da consulta
# do dia seguinte na hora da confirmação).
#
#   DRY-RUN (só lista):  bundle exec rails 'cevico:reclassify_bookings[1,2026-09-23]'
#   APLICAR:             DRY=0 bundle exec rails 'cevico:reclassify_bookings[1,2026-09-23]'
#   Janela maior (h):    HOURS=72 …
namespace :cevico do
  desc 'Reclassifica consultas lançadas pela equipe como "já estava marcada" (item 217)'
  task :reclassify_bookings, %i[account_id date] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    tz = ActiveSupport::TimeZone['America/Sao_Paulo']
    day = args[:date].present? ? tz.parse(args[:date]) : tz.now.beginning_of_day
    hours = (ENV['HOURS'].presence || 48).to_i
    ia_marks = Api::V1::Accounts::Crm::AppointmentsController::IA_MARKS
    apply = ENV['DRY'] == '0'

    scope = account.tasks.where(task_type: 'consulta', booking_kind: nil, archived_at: nil)
                   .where(created_at: day.all_day)
                   .where.not(due_at: nil)
                   .where("title NOT LIKE '⚠️%'")
                   .order(:created_at)
    rows = scope.reject { |t| t.description.to_s.match?(ia_marks) }
                .select { |t| t.due_at - t.created_at <= hours.hours }

    puts "#{apply ? 'APLICANDO' : 'DRY-RUN'} — conta #{account.id}, dia #{day.strftime('%d/%m/%Y')}, janela #{hours} h: #{rows.size} consulta(s)"
    rows.each do |t|
      puts "  ##{t.id.to_s.ljust(6)} #{t.title.to_s.first(32).ljust(32)} criada #{t.created_at.in_time_zone(tz).strftime('%d/%m %H:%M')}  " \
           "consulta #{t.due_at.in_time_zone(tz).strftime('%d/%m %H:%M')}  por #{t.creator&.name}"
      t.update!(booking_kind: 'registro') if apply
    end
    puts apply ? 'Feito: agora aparecem como "Lançada" e ficam fora de "Consultas agendadas".' : 'Nada alterado (DRY=0 para aplicar).'
  end
end
