# 🔎 Conferência do dia: hub do Oftalmofácil × nossa Agenda (item 249).
#   ACCOUNT_ID=1 DIA=2026-09-28 HUB=1 bundle exec rake cevico:agenda_dia
#   FIX=1 traz para a Agenda o que faltou (só o que é corrigível; nada muda no hub)
# Sem DIA = próximo dia útil. HUB=1 consulta o banco do hub (só leitura).
namespace :cevico do # rubocop:disable Metrics/BlockLength
  desc 'Confere as cirurgias/consultas do hub do Oftalmofácil para um dia contra a nossa Agenda (FIX=1 corrige)'
  task agenda_dia: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    date = ENV['DIA'].present? ? Date.parse(ENV['DIA']) : Crm::OftalmofacilDayCheck.default_date
    check = Crm::OftalmofacilDayCheck.new(account: account, date: date)
    fix = ENV['FIX'] == '1'
    rep = fix ? check.reconcile! : check.report(hub: ENV['HUB'] == '1')

    puts "== Conferência do hub × Agenda — #{rep[:weekday]} #{date.strftime('%d/%m/%Y')} =="
    c = rep[:config]
    puts "Config: sync #{c[:enabled] ? 'ligado' : 'DESLIGADO'} · Agenda unificada #{c[:agenda_enabled] ? 'ligada' : 'DESLIGADA'} · " \
         "janela desde #{c[:agenda_from]} · parceiros #{c[:partners_enabled] ? 'sim' : 'não'} · último sync #{c[:last_run_at] || '—'}"
    puts "Hub consultado: #{rep[:hub][:checked] ? "sim (#{rep[:hub][:total]} itens no dia)" : (rep[:hub][:error] || 'não')}"
    rep[:rows].each do |r|
      flag = '·'
      flag = '✓' if r[:situation] == 'ok'
      flag = '✗' if Crm::OftalmofacilDayCheck::PROBLEMS.include?(r[:situation])
      puts format('%<f>s %<h>-5s %<p>-28s %<c>-22s %<u>-14s %<k>-10s %<s>s',
                  f: flag, h: r[:hour] || '--:--', p: r[:patient].to_s[0, 28], c: r[:clinic].to_s[0, 22],
                  u: r[:unit_label].to_s[0, 14], k: r[:kind], s: [r[:situation_label], r[:reason].presence].compact.join(' — '))
    end
    rep[:strays].each do |t|
      puts "? agendamento ##{t[:task_id]} (#{t[:title]}) está na Agenda neste dia mas o hub marca #{t[:hub_date] || 'outra data'}"
    end
    s = rep[:summary]
    puts "Total #{s['total']} · problemas #{s['problemas']} · corrigíveis pelo reprocessamento #{s['corrigiveis']}"
    if fix
      puts "Reprocessados #{rep[:fixed]} · agendamentos criados #{rep[:tasks_created]} · atualizados #{rep[:tasks_updated]}"
      Array(rep[:errors]).each { |e| puts "  ⚠️ #{e}" }
    else
      puts 'Para corrigir: FIX=1 (ou o botão "Trazer para a Agenda" no ambiente Oftalmofácil).'
    end
  end
end
