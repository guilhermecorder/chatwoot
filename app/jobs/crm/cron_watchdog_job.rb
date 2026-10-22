# 🚨 VIGIA DOS ROBÔS (auditoria 10/2026, achado #217 — Rodada 6 "Rede de
# segurança"). A cada 10 min confere o sinal de vida que cada robô CEVICO deixa
# (Crm::CronHealth) e, quando um robô PAROU (perdeu os 2 últimos horários) ou
# terminou em ERRO 2× seguidas, avisa o administrador de cada conta por 3 caminhos:
#   1. aviso no Radar do Meu Painel (Crm::AgentAlert, kind 'robo_parado');
#   2. tarefa 🔴 no Meu Painel do administrador (uma aberta por robô);
#   3. e-mail para os administradores (AdministratorNotifications::CevicoAlertMailer).
# Um aviso por problema: enquanto o mesmo problema continua, repete só a cada
# 12 h. Quando o robô volta a rodar, o próprio vigia tira o aviso do Radar
# (não depende do Radar de Oportunidades estar ligado), FECHA a tarefa 🔴
# dele (22/10: as de 16/10 ficaram abertas 6 dias com o robô já rodando) e a
# tela também esconde na leitura o aviso de robô que já voltou.
# O resumo fica em ai_config.cron_health (para tela/console), gravado pelo
# Cevico::SettingMerge. A marca "já avisei" é gravada ANTES de avisar: se o
# aviso falhar, no pior caso perde um aviso — nunca vira rajada.
# Fila HIGH: se a fila dos lembretes empacar, o vigia ainda roda e avisa.
class Crm::CronWatchdogJob < ApplicationJob
  queue_as :high

  STATE_KEY = 'cron_health'.freeze
  REALERT_AFTER = 12.hours
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def perform(now = nil)
    now ||= Time.current
    problems = Crm::CronHealth.problems(now: now)
    snapshot = Crm::CronHealth.snapshot(now: now)
    CrmSetting.find_each do |settings|
      watch_account(settings, problems, snapshot, now)
    rescue StandardError => e
      Rails.logger.error "[CEVICO vigia dos robôs] conta #{settings.account_id}: #{e.message}"
    end
  end

  private

  def watch_account(settings, problems, snapshot, now) # rubocop:disable Metrics/AbcSize
    due = []
    Cevico::SettingMerge.merge_key!(settings, :ai_config, STATE_KEY) do |state|
      incidents = (state['incidents'] || {}).slice(*problems.keys) # o que voltou ao normal sai da lista
      problems.each do |job, problem|
        incident = incidents[job]
        next unless alert_due?(incident, problem, now)

        due << problem
        incidents[job] = { 'kind' => problem[:kind], 'since' => since_for(incident, problem, now), 'alerted_at' => now.iso8601 }
      end
      state['checked_at'] = now.iso8601
      state['jobs'] = snapshot
      state['incidents'] = incidents
      state
    end
    clear_recovered_alerts!(settings, problems)
    close_recovered_tasks!(settings.account, problems, now)
    due.each { |problem| alert!(settings.account, for_account(problem, settings.account_id)) }
  end

  # tira do Radar os avisos de robô que já voltou ao normal
  def clear_recovered_alerts!(settings, problems)
    alerts = Array(settings.ai_config&.dig('opportunity_state', 'alerts'))
    return unless alerts.any? { |a| a['kind'] == Crm::AgentAlert::ROBOT_KIND && !problems.key?(a['job'].to_s) }

    Cevico::SettingMerge.merge_key!(settings, :ai_config, 'opportunity_state') do |state|
      state['alerts'] = Array(state['alerts']).reject { |a| a['kind'] == Crm::AgentAlert::ROBOT_KIND && !problems.key?(a['job'].to_s) }
      state
    end
  end

  # tarefa 🔴 de robô que voltou: fecha, com a linha de quando voltou (só as
  # que o vigia abriu — o título é o dele; robô ainda com problema fica aberto)
  def close_recovered_tasks!(account, problems, now)
    labels = Crm::CronHealth::JOBS.transform_values { |meta| meta[:label] }.merge('sidekiq' => Crm::CronHealth::SIDEKIQ_LABEL)
    titles = labels.except(*problems.keys).values.flat_map { |label| ["🔴 Robô parado: #{label}", "🔴 Robô com erro: #{label}"] }
    line = "#{now.in_time_zone(TZ).strftime('%d/%m %H:%M')} · o robô voltou a rodar — tarefa fechada pelo vigia."
    account.tasks.where(title: titles, status: %i[todo doing]).find_each do |task|
      task.update!(status: :done, description: [task.description.presence, line].compact.join("\n\n"))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO vigia dos robôs] conta #{account.id}: tarefa não fechada (#{e.message})"
  end

  # o último erro vem com "conta N · ": a outra conta não vê o número alheio
  def for_account(problem, account_id)
    message = problem[:message].to_s.gsub(/conta (\d+) · /) { Regexp.last_match(1).to_i == account_id ? '' : 'outra conta · ' }
    problem.merge(message: message)
  end

  # problema novo, mudou de tipo (parado → erro) ou já faz 12 h do último aviso
  def alert_due?(incident, problem, now)
    return true if incident.nil? || incident['kind'] != problem[:kind]

    alerted = Time.zone.parse(incident['alerted_at'].to_s)
    alerted.nil? || alerted <= now - REALERT_AFTER
  rescue ArgumentError
    true
  end

  def since_for(incident, problem, now)
    incident && incident['kind'] == problem[:kind] ? incident['since'] : now.iso8601
  end

  def alert!(account, problem)
    admin = account.administrators.order(:id).first
    return if admin.nil? # sem administrador: o aviso ficaria visível para todos os atendentes

    task = open_task!(account, admin, problem)
    Crm::AgentAlert.push_robot(account: account, problem: problem, user: admin, task: task)
    AdministratorNotifications::CevicoAlertMailer.with(account: account).robo_parado(problem).deliver_later
  rescue StandardError => e
    Rails.logger.error "[CEVICO vigia dos robôs] conta #{account.id} #{problem[:job]}: aviso falhou (#{e.message})"
  end

  # tarefa 🔴 para o administrador — uma ABERTA por robô: aviso repetido só
  # acrescenta a linha nova na descrição
  def open_task!(account, admin, problem)
    return nil if admin.nil?

    title = task_title(problem)
    line = "#{TZ.now.strftime('%d/%m %H:%M')} · #{problem[:message]}"
    existing = account.tasks.where(title: title, status: %i[todo doing]).order(:id).first
    return existing.tap { |t| t.update!(description: [t.description.presence, line].compact.join("\n\n")) } if existing

    account.tasks.create!(
      title: title, description: "#{line}\n\nO que fazer: avisar quem cuida do sistema e, enquanto isso, " \
                                 'conferir à mão o que esse robô faria hoje.',
      priority: :urgent, status: :todo, due_at: TZ.now,
      creator: admin, assignee: admin
    )
  rescue StandardError => e
    Rails.logger.warn "[CEVICO vigia dos robôs] tarefa não aberta: #{e.message}"
    nil
  end

  def task_title(problem)
    "🔴 #{problem[:kind] == 'erro' ? 'Robô com erro' : 'Robô parado'}: #{problem[:label]}"
  end
end
