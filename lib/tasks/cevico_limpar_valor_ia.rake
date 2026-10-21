# 💰 item 340 (13/10): até a auditoria (commit eb435dd) a IA gravava na
# observação da consulta a linha "Valor da consulta: R$ 150" (valor FIXO),
# também no bloco "Reagendada pela IA:" que entra embaixo da observação da
# equipe. A confirmação lia esse "R$ 150" e o Alessandro recebeu R$ 150 com a
# Agenda mostrando R$ 350. O leitor do valor já ignora essas linhas
# (Crm::AppointmentPrice.human_notes); esta tarefa TIRA só essa linha das
# consultas FUTURAS, mantendo todo o resto da observação.
#   DRY=1 (padrão) só lista; DRY=0 aplica
#   bundle exec rake cevico:limpar_valor_ia ACCOUNT_ID=1 DRY=1
namespace :cevico do
  desc 'Consultas futuras: tira a linha antiga "Valor da consulta: R$ X" que a IA gravava na observação (DRY=1 só lista)'
  task limpar_valor_ia: :environment do
    abort('❌ informe a conta: ACCOUNT_ID=1') if ENV['ACCOUNT_ID'].blank?

    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    dry = ENV.fetch('DRY', '1') != '0'
    tz = ActiveSupport::TimeZone['America/Sao_Paulo']
    tasks = account.tasks.where(task_type: 'consulta').where('due_at >= ?', Time.current)
                   .where('description ILIKE ?', '%Valor da consulta%').order(:due_at)
    hits = tasks.select { |task| Crm::AppointmentPrice.legacy_ai_value?(task.description) }

    puts "conta #{account.id} · #{hits.size} consulta(s) futura(s) com a linha antiga da IA na observação"
    hits.each do |task|
      after = Crm::AppointmentPrice.without_legacy_ai_value(task.description)
      when_at = task.due_at&.in_time_zone(tz)&.strftime('%d/%m/%Y %H:%M')
      puts "- task #{task.id} · #{task.title} · #{when_at}"
      puts "    ANTES:  #{task.description.to_s.gsub("\n", ' ⏎ ')}"
      puts "    DEPOIS: #{after.gsub("\n", ' ⏎ ')}"
      # só a observação muda (sem callbacks: nada de mover card, sincronizar ou avisar ninguém)
      task.update_column(:description, after) unless dry # rubocop:disable Rails/SkipsModelValidations
    end

    if dry
      puts 'DRY: nada mudou. Para aplicar: DRY=0 (só a linha "Valor da consulta: R$ X" escrita pela IA sai)'
    else
      puts "APLICADO: #{hits.size} observação(ões) limpas."
    end
  end
end
