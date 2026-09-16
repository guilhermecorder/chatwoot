# 🏥 Conserto pós-primeira-carga do OftalmoFácil (15/09): os cards que a
# carga colocou em "Cirurgia Agendada" ficaram com a entrada datada no dia da
# carga (723 "Entrou em Cirurgia Agendada" nos 7 dias). Reescreve a data de
# entrada pela data em que a cirurgia foi MARCADA lá (of_created_at).
#
#   bundle exec rails cevico:oftalmofacil_backdate_agendadas ACCOUNT_ID=1        # só mostra (dry-run)
#   bundle exec rails cevico:oftalmofacil_backdate_agendadas ACCOUNT_ID=1 DRY=0  # aplica
namespace :cevico do
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
end
