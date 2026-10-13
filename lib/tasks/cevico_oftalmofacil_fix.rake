# 🏥 Conserto pós-primeira-carga do OftalmoFácil (15/09): os cards que a
# carga colocou em "Cirurgia Agendada" ficaram com a entrada datada no dia da
# carga (723 "Entrou em Cirurgia Agendada" nos 7 dias). Reescreve a data de
# entrada pela data em que a cirurgia foi MARCADA lá (of_created_at).
#
#   bundle exec rails cevico:oftalmofacil_backdate_agendadas ACCOUNT_ID=1        # só mostra (dry-run)
#   bundle exec rails cevico:oftalmofacil_backdate_agendadas ACCOUNT_ID=1 DRY=0  # aplica
namespace :cevico do # rubocop:disable Metrics/BlockLength
  desc 'Retrodata a entrada em Cirurgia Agendada dos cards vindos do OftalmoFácil'
  task oftalmofacil_backdate_agendadas: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    dry = ENV.fetch('DRY', '1') != '0'
    stage = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id })
                      .where('crm_stages.name ILIKE ?', '%cirurgia agendada%').order(:position).first
    abort 'coluna "Cirurgia Agendada" não encontrada' unless stage

    scope = Crm::OftalmofacilSurgery.where(account: account, status_kind: %w[agendada aguardando_pagamento])
                                    .where.not(contact_id: nil).where.not(of_created_at: nil)
    fixed = skipped = 0
    scope.find_each do |surgery|
      card = Crm::Contact.find_by(contact_id: surgery.contact_id, pipeline_id: stage.pipeline_id)
      log = card && Crm::StageLog.where(crm_contact_id: card.id, stage_id: stage.id).order(entered_at: :desc).first
      # só mexe na entrada que a carga criou (datada depois da marcação lá)
      if log.nil? || surgery.of_created_at > Time.current || log.entered_at <= surgery.of_created_at
        skipped += 1
        next
      end

      puts "#{dry ? '[dry] ' : ''}card #{card.id} (#{surgery.patient_name}): #{log.entered_at.to_date} → #{surgery.of_created_at.to_date}"
      unless dry
        log.update_columns(entered_at: surgery.of_created_at) # rubocop:disable Rails/SkipsModelValidations
        card.update_column(:stage_moved_at, surgery.of_created_at) if card.stage_id == stage.id # rubocop:disable Rails/SkipsModelValidations
      end
      fixed += 1
    end
    summary = "#{fixed} entrada(s) retrodatada(s), #{skipped} sem mexer"
    puts dry ? "DRY-RUN — nada gravado. #{summary} (rode com DRY=0 para aplicar)" : summary
  end

  # 🔁 auditoria 10/2026 (#462/#472): a mesma consulta lançada pela recepção na
  # Agenda E vinda do hub nasceu DUAS vezes (duas tasks → dois lembretes pagos no
  # mesmo dia, e o "sim" do paciente confirmava só uma). O sync adota a da equipe
  # e, a cada rodada, une as que nasceram na ordem inversa
  # (Crm::OftalmofacilSyncService#dedupe_tasks!, próximos 14 dias). Este rake é
  # o atalho manual, sem limite de dias: a task da equipe fica (quem criou,
  # observações, hora) e ganha o vínculo com o hub; a cópia do hub vai para a
  # Lixeira com o motivo "duplicada_hub". Resposta do paciente (sim/não) e marcas
  # de lembrete já enviadas passam para a que fica.
  #
  #   bundle exec rails cevico:oftalmofacil_dedupe_tasks ACCOUNT_ID=1          # só mostra (dry-run)
  #   bundle exec rails cevico:oftalmofacil_dedupe_tasks ACCOUNT_ID=1 DRY=0    # aplica
  #   PAST=1 → olha também consultas já passadas (padrão: de hoje em diante)
  desc 'Une a consulta lançada pela recepção com a mesma consulta vinda do Oftalmofácil (uma task, um lembrete)'
  task oftalmofacil_dedupe_tasks: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    dry = ENV.fetch('DRY', '1') != '0'
    tz = ActiveSupport::TimeZone['America/Sao_Paulo']
    service = Crm::OftalmofacilSyncService.new(account: account, silent: true, since: nil)
    abort 'Agenda unificada desligada nesta conta (Integrações → OftalmoFácil → Agenda)' unless service.agenda_enabled?

    # Rodada 4 (achado #172): aplicando (DRY=0), disputa a MESMA trava do
    # Crm::OftalmofacilSyncJob — com o cron no meio, os dois mexeriam no mesmo
    # par de consultas. O dry-run só lê e roda sem trava.
    token = nil
    unless dry
      token = Crm::OftalmofacilSyncJob.acquire_lock(account.id)
      abort Crm::OftalmofacilSyncJob::BUSY_MESSAGE if token.nil?
    end
    begin
      pairs = service.dedupe_tasks!(days: nil, past: ENV['PAST'] == '1', dry: dry)
    ensure
      Crm::OftalmofacilSyncJob.release_lock(account.id, token)
    end
    pairs.each do |twin, hub|
      puts "#{dry ? '[dry] ' : ''}##{twin.id} #{twin.title.to_s.first(32)} (#{twin.due_at.in_time_zone(tz).strftime('%d/%m %H:%M')}, " \
           "por #{twin.creator&.name}) ← adota o hub ##{hub.id} #{twin.external_ref || hub.external_ref}"
    end
    service.result.errors.each { |e| puts "erro: #{e}" }
    summary = "#{pairs.size} consulta(s) duplicada(s) unida(s)"
    puts dry ? "DRY-RUN — nada gravado. #{summary} (rode com DRY=0 para aplicar)" : summary
  end
end
