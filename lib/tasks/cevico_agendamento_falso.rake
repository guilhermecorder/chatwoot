# 🧹 item 345 (14/10): limpa o "agendamento falso" da automação sem filtro de
# etiqueta (Crm::FalseBookingCleanup explica a regra).
#
#   bundle exec rake cevico:agendamento_falso ACCOUNT_ID=1 AUTOMACAO=2 DESDE=2026-10-13 DRY=1
#   (confere a lista) → BACKUP → mesma linha com DRY=0
namespace :cevico do # rubocop:disable Metrics/BlockLength
  desc 'Agendamento falso (automação de etiqueta sem filtro): tira dos indicadores e devolve o card (DRY=1 só lista)'
  task agendamento_falso: :environment do # rubocop:disable Metrics/BlockLength
    abort('❌ informe a conta: ACCOUNT_ID=1') if ENV['ACCOUNT_ID'].blank?
    abort('❌ informe a automação: AUTOMACAO=2') if ENV['AUTOMACAO'].blank?

    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    tz = ActiveSupport::TimeZone['America/Sao_Paulo']
    since = tz.parse(ENV.fetch('DESDE', '2026-10-13'))
    dry = ENV.fetch('DRY', '1') != '0'
    automation = Crm::Automation.joins(stage: :pipeline).where(crm_pipelines: { account_id: account.id }).find(ENV.fetch('AUTOMACAO'))
    target = Crm::FalseBookingCleanup.target_stage(automation)
    abort("❌ a automação ##{automation.id} não move card para uma coluna que exista") if target.nil?

    rows = Crm::FalseBookingCleanup.plan(automation, since)
    falsas = rows.reject(&:real?)
    puts "automação ##{automation.id} '#{automation.name}': #{automation.stage.name} → #{target.name} · desde #{since.strftime('%d/%m %H:%M')}"
    puts "#{rows.size} entrada(s) causadas por ela · #{rows.size - falsas.size} com consulta de verdade (ficam) · #{falsas.size} FALSAS"
    puts
    rows.each do |row|
      quando = row.log.entered_at.in_time_zone(tz).strftime('%d/%m %H:%M')
      nome = row.card.contact&.name.to_s.first(28).ljust(28)
      decisao = if row.real?
                  "MANTER (consulta marcada #{row.consult.created_at.in_time_zone(tz).strftime('%d/%m %H:%M')})"
                elsif row.back
                  "TIRAR do indicador + VOLTAR para #{automation.stage.name}"
                else
                  'TIRAR do indicador (o card já andou depois — fica onde está)'
                end
      puts "  #{quando}  #{nome}  #{decisao}"
    end

    conversoes = Crm::FalseBookingCleanup.conversions_for(rows)
    if conversoes.any?
      puts
      puts "⚠️ #{conversoes.size} conversão(ões) enviadas junto com entradas falsas " \
           '(o sistema não consegue desfazer — Google Ads/Meta, à mão se quiser):'
      conversoes.group_by(&:first).each do |auto, list|
        puts "  ##{auto.id} '#{auto.name}': #{list.size}"
        list.each { |_, log, row| puts "     #{log.created_at.in_time_zone(tz).strftime('%d/%m %H:%M:%S')}  #{row.card.contact&.name}" }
      end
    end

    puts
    if dry
      puts "DRY: nada mudou. Voltariam #{falsas.count(&:back)} card(s). Para aplicar: BACKUP e depois DRY=0"
    else
      result = Crm::FalseBookingCleanup.apply!(automation, rows)
      puts "APLICADO: #{result[:marked]} entrada(s) fora dos indicadores · #{result[:moved]} card(s) de volta para #{automation.stage.name}"
    end
  end
end
