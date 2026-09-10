# 📅 LEMBRETES PELO DIA DA CONSULTA (item 156, pacote COMPARECIMENTO):
#   D-1 = véspera, pedindo confirmação por resposta ("responde SIM")
#   D-0 = no dia (ex.: 07h), lembrando que a consulta é hoje
#
# Cron a cada 15 min; cada régua só age na HORA configurada da conta
# (Automações → Robôs → "Lembretes do dia da consulta") e cada consulta
# recebe NO MÁXIMO 1 envio por régua — a marca fica no contato
# (additional_attributes.cevico_appt_reminders[task_id]), então repetir a
# rodada dentro da mesma hora não duplica nada.
#
# O envio é MENSAGEM MODELO (Crm::SendTemplateService, o mesmo das
# Campanhas) — chega mesmo com a janela de 24h fechada. Nos valores das
# variáveis, {{hora}} vira o horário da consulta e {{unidade}} vira a casa
# (Av. Paulista/Tatuapé); {{contact.name}} segue com o Liquid do serviço.
#
# A CONFIRMAÇÃO da D-1 é lida pelo CrmListener (resposta "sim/confirmo"
# de quem tem lembrete enviado) — vira marca confirmed + nota na conversa.
class Crm::AppointmentReminderSendJob < ApplicationJob
  queue_as :scheduled_jobs

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  DEFAULT_HOURS = { 'd1' => 10, 'd0' => 7 }.freeze
  MAX_MARK_ENTRIES = 60 # marcas antigas são podadas (consultas já passaram)

  TemplateSource = Struct.new(:account, :inbox, :sender, :template_params, :message_preview, :name) do
    def account_id = account.id
    def inbox_id = inbox.id
  end

  # now: só os testes passam (congelar o relógio sem gem de viagem no tempo)
  def perform(now = nil)
    now_sp = now ? now.in_time_zone(TZ) : TZ.now
    CrmSetting.find_each do |settings|
      cfg = settings.agenda_config&.dig('appointment_reminders') || {}
      %w[d1 d0].each do |regua|
        run_regua(settings.account, regua, cfg[regua] || {}, now_sp)
      rescue StandardError => e
        Rails.logger.error "[CEVICO lembretes] conta #{settings.account_id} #{regua}: #{e.message}"
      end
    end
  end

  private

  def run_regua(account, regua, rcfg, now_sp) # rubocop:disable Metrics/AbcSize
    return unless rcfg['enabled'] == true
    return unless now_sp.hour == (rcfg['hour'] || DEFAULT_HOURS[regua]).to_i

    inbox = account.inboxes.find_by(id: rcfg['inbox_id'])
    return if inbox.nil? || rcfg['template_params'].blank?

    date = regua == 'd1' ? now_sp.to_date + 1 : now_sp.to_date
    day_start = TZ.local(date.year, date.month, date.day)
    scope = account.tasks.where(task_type: 'consulta', canceled_at: nil, archived_at: nil)
                   .where(due_at: day_start..day_start.end_of_day)
                   .where(attendance: [nil, ''])
                   .where.not(contact_id: nil)
    scope.includes(:contact).find_each do |task|
      send_for(account, inbox, rcfg, regua, task)
    end
  end

  def send_for(account, inbox, rcfg, regua, task) # rubocop:disable Metrics/CyclomaticComplexity
    contact = task.contact
    return if contact.nil? || contact.phone_number.blank?

    marks = (contact.additional_attributes || {}).dig('cevico_appt_reminders', task.id.to_s) || {}
    return if marks[regua].present?

    source = TemplateSource.new(account, inbox, nil,
                                personalized_params(rcfg['template_params'], task),
                                rcfg['message_preview'].presence,
                                "Lembrete de consulta (#{regua.upcase})")
    conversation = Crm::SendTemplateService.new(source: source, contact: contact).perform
    return if conversation.nil?

    mark_sent(contact, task, regua)
  rescue StandardError => e
    Rails.logger.error "[CEVICO lembretes] task #{task.id}: #{e.message}"
  end

  # {{hora}}/{{unidade}} nos VALORES das variáveis viram o dado da consulta
  def personalized_params(template_params, task)
    params = template_params.deep_dup
    hora = task.due_at&.in_time_zone(TZ)&.strftime('%H:%M').to_s
    unidade = Crm::AgendaSlots::UNIT_LABELS[task.unit.to_s] || task.unit.to_s
    body = params.dig('processed_params', 'body')
    body&.transform_values! { |v| v.to_s.gsub('{{hora}}', hora).gsub('{{unidade}}', unidade) }
    params
  end

  def mark_sent(contact, task, regua)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      marks = attrs['cevico_appt_reminders'] || {}
      entry = marks[task.id.to_s] || {}
      entry[regua] = Time.current.iso8601
      marks[task.id.to_s] = entry
      # poda: marcas de consultas antigas não servem pra mais nada
      marks = marks.sort_by { |_id, e| e.values.max.to_s }.last(MAX_MARK_ENTRIES).to_h if marks.size > MAX_MARK_ENTRIES
      attrs.merge('cevico_appt_reminders' => marks)
    end
  end
end
