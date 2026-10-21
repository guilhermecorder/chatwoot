# 🧩 item 344 (13/10 noite) — FUNIL DO OFTALMOFÁCIL ACERTADO. Pedido do
# Guilherme: "retorno vindo do oftalmofácil é consulta de retorno… veja quais
# colunas precisam haver no CRM para que fique tudo acertado… pode construir
# inclusive uma pré-definição". Três consertos, sempre com prévia:
#   1. PRÉ-DEFINIÇÃO: as colunas da jornada no funil do parceiro
#      (Crm::PartnerFunnel::STAGES) — as que faltam nascem e o funil fica na
#      ordem da jornada (colunas fora dela vão para o fim, com os cards).
#   2. RETORNO ≠ CIRURGIA: agendamentos do hub que nasceram como cirurgia mas
#      são retorno/consulta/exame/pós-op viram consulta (mesma regra do sync).
#   4. COLUNAS POR TIPO (Exame, Consulta, Lente Rígida, Intravítrea): os cards
#      vão para a ETAPA da jornada lida da Agenda — o tipo agora é etiqueta +
#      filtro no card (Crm::AppointmentKind). As colunas vazias ele apaga à mão.
#   3. CARD NA COLUNA ERRADA: paciente do parceiro que está em "Cirurgia
#      Agendada/Realizada" só por causa de CONSULTA do hub volta para a coluna
#      de consulta certa; as entradas erradas em coluna de cirurgia viram
#      'bulk' (deixam de contar como cirurgia nos indicadores).
#   DRY=1 (padrão) só mostra · DRY=0 aplica (fazer BACKUP antes)
#   bundle exec rake cevico:of_colunas ACCOUNT_ID=1 DRY=1
namespace :cevico do # rubocop:disable Metrics/BlockLength
  desc 'Funil do Oftalmofácil: pré-definição das colunas + retorno vira consulta + cards em cirurgia por engano (DRY=1 mostra, DRY=0 aplica)'
  task of_colunas: :environment do # rubocop:disable Metrics/BlockLength
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    dry = ENV.fetch('DRY', '1') != '0'
    funnel = Crm::PartnerFunnel.pipeline(account)
    abort "conta #{account.id}: o ambiente Oftalmofácil ainda não tem funil (CRM → Ambientes do CRM → Oftalmofácil → Editar)." unless funnel

    puts "conta #{account.id} · funil «#{funnel.name}» · #{dry ? 'PRÉVIA (nada gravado)' : 'APLICANDO'}"

    # ── 1 · colunas ────────────────────────────────────────────────────
    preview = Crm::PartnerFunnel.preset_preview(account)
    puts "\n1) COLUNAS (pré-definição da jornada; ao aplicar, o funil fica nesta ordem e as outras vão para o fim)"
    preview[:columns].each do |col|
      renamed = col[:exists] && col[:current_name] != col[:name] ? " (já existe: «#{col[:current_name]}»)" : ''
      puts "   #{col[:exists] ? '✓' : '+'} #{col[:name]}#{renamed}"
    end
    puts "   outras colunas que ficam como estão: #{preview[:extras].join(', ')}" if preview[:extras].any?
    Crm::PartnerFunnel.apply_preset!(account) unless dry

    # ── 2 · agendamentos do hub: retorno/consulta que nasceram cirurgia ──
    hub = Crm::OftalmofacilSurgery.where(account_id: account.id).index_by(&:item_token)
    wrong_tasks = account.tasks.where(task_type: 'cirurgia').where(external_ref: hub.keys).filter_map do |task|
      kind = Crm::OftalmofacilSyncService.kind_for(hub[task.external_ref])
      [task, kind] if kind[:task_type] == 'consulta'
    end
    puts "\n2) AGENDAMENTOS DO HUB que estavam como CIRURGIA mas são consulta: #{wrong_tasks.size}"
    wrong_tasks.first(40).each do |task, kind|
      puts "   ##{task.id} · #{task.due_at&.in_time_zone('America/Sao_Paulo')&.strftime('%d/%m/%y %H:%M')} · #{task.title} → #{kind[:prefix]}"
    end
    unless dry
      wrong_tasks.each do |task, kind|
        title = task.title.to_s.sub(/\ACirurgia:/, "#{kind[:prefix]}:")
        # update_columns de propósito: só o tipo muda (sem lembrete, remarcação nem carimbo novos)
        task.update_columns(task_type: kind[:task_type], modality: kind[:modality], title: title, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # ── 3 · cards do parceiro em coluna de cirurgia só por causa de consulta ──
    surgery_roles = %i[surgery realized]
    surgical_contacts = hub.values.select { |s| Crm::OftalmofacilSyncService.kind_for(s)[:task_type] == 'cirurgia' }
                           .filter_map(&:contact_id).to_set
    latest = hub.values.select(&:contact_id).group_by(&:contact_id).transform_values { |list| list.max_by { |s| s.surgery_date || Date.new(1900) } }
    moves = funnel.crm_contacts.includes(:stage, :contact).filter_map do |card|
      next unless surgery_roles.include?(Crm::PartnerFunnel.role_of(card.stage&.name))
      next if surgical_contacts.include?(card.contact_id)

      item = latest[card.contact_id]
      next if item.nil? # sem item do hub: não foi o sync que pôs aí — fica

      key = case item.status_kind
            when 'ausente' then :missed
            when 'realizada' then Crm::OftalmofacilSyncService.kind_for(item)[:modality] == 'pos_op' ? :postop : :consulted
            else :booked
            end
      [card, key]
    end
    puts "\n3) CARDS em coluna de CIRURGIA só por causa de consulta do hub: #{moves.size}"
    moves.first(40).each do |card, key|
      puts "   card #{card.id} · #{card.contact&.name} · #{card.stage&.name} → #{Crm::PartnerFunnel::STAGES[key][:name]}"
    end
    unless dry
      moved = 0
      moves.each do |card, key|
        target = Crm::PartnerFunnel.stage!(account, key)
        next if target.nil?

        ActiveRecord::Base.transaction do
          # as entradas em coluna de cirurgia deste card deixam de contar como cirurgia
          card.stage_logs.where(stage_id: funnel.stages.select { |s| surgery_roles.include?(Crm::PartnerFunnel.role_of(s.name)) }.map(&:id))
              .update_all(event_type: Crm::StageLogBulk::BULK, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          card.update_columns(stage_id: target.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        end
        moved += 1
      end
      Crm::PartnerGuard.forget!(account)
      Crm::EnvironmentMigration.clear_kpi_caches!(account)
      puts "   APLICADO: #{moved} card(s) na coluna de consulta certa."
    end

    # ── 4 · cards nas colunas por TIPO → etapa da jornada ──────────────
    # (decisão 13/10: "Etapas + tipo no cartão" — o tipo virou etiqueta e
    # filtro no CRM; a coluna passa a dizer a ETAPA, lida da Agenda)
    funnel.reload
    type_columns = funnel.stages.order(:position).reject { |st| Crm::PartnerFunnel.role_of(st.name) }
    in_type = funnel.crm_contacts.where(stage_id: type_columns.map(&:id)).includes(:stage, :contact).to_a
    now = Time.current
    plan = in_type.map do |card|
      tasks = account.tasks.where(contact_id: card.contact_id, task_type: %w[consulta cirurgia], archived_at: nil).where.not(due_at: nil).to_a
      live = tasks.reject(&:canceled_at)
      task = live.select { |t| t.due_at >= now.beginning_of_day }.min_by(&:due_at) || live.max_by(&:due_at)
      key = if task.nil?
              tasks.any? ? :canceled : :new
            elsif task.task_type == 'cirurgia'
              # futura ou faltou = ainda agendada; passada = realizada
              task.due_at >= now.beginning_of_day || task.attendance == 'missed' ? :surgery : :realized
            elsif task.due_at >= now.beginning_of_day
              task.confirmed_at ? :confirmed : :booked
            elsif task.attendance == 'missed'
              :missed
            elsif task.modality == 'retorno'
              :retorno
            elsif task.modality == 'pos_op'
              :postop
            else
              :consulted
            end
      [card, key, task]
    end
    puts "\n4) CARDS NAS COLUNAS POR TIPO (#{type_columns.map(&:name).join(', ').presence || 'nenhuma'}) → etapa da jornada: #{plan.size}"
    plan.first(60).each do |card, key, task|
      quando = task ? " (agendamento #{task.due_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%y')})" : ''
      puts "   card #{card.id} · #{card.contact&.name} · #{card.stage&.name} → #{Crm::PartnerFunnel::STAGES[key][:name]}#{quando}"
    end
    unless dry
      plan.each do |card, key, _task|
        target = Crm::PartnerFunnel.stage!(account, key)
        # update_columns de propósito: arrumação de coluna, não é "entrada" nova
        # (não dispara automação nem conta como agendamento de hoje)
        card.update_columns(stage_id: target.id, updated_at: Time.current) if target # rubocop:disable Rails/SkipsModelValidations
      end
      empty = type_columns.select { |st| st.reload.crm_contacts.none? }
      puts "   APLICADO: #{plan.size} card(s) na etapa da jornada."
      puts "   colunas por tipo que ficaram VAZIAS (pode apagar no CRM, se quiser): #{empty.map(&:name).join(', ')}" if empty.any?
      Crm::PartnerGuard.forget!(account)
      Crm::EnvironmentMigration.clear_kpi_caches!(account)
    end

    puts dry ? "\nPRÉVIA — nada gravado. Para aplicar: DRY=0 (fazer o BACKUP antes)." : "\nPRONTO."
  end
end
