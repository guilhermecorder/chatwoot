# Preenche a Agenda com o HISTÓRICO REAL: varre conversas que têm mensagem de
# confirmação de agendamento (ex. o bot do N8N manda "Consulta confirmada: …")
# e roda o Agente de Agendamento em cada uma, criando/reagendando as consultas
# na Agenda do sistema — "duplica" a agenda do Google sem mexer no N8N.
#
# Este fluxo NÃO fala com nenhum paciente: só lê conversas e escreve na Agenda.
class Crm::AgendaBackfillJob < ApplicationJob
  queue_as :low

  CONFIRMATION_TERMS = ['consulta confirmada', 'consulta agendada', 'agendamento confirmado'].freeze
  MAX_LIMIT = 300

  def perform(account_id, options = {})
    account = Account.find_by(id: account_id)
    return if account.blank?

    since = options['since_days'].to_i.positive? ? options['since_days'].to_i.days.ago : 90.days.ago
    limit = options['limit'].to_i.positive? ? [options['limit'].to_i, MAX_LIMIT].min : 100

    conversation_ids = matching_conversation_ids(account, since, limit)
    stats = Hash.new(0)

    account.conversations.where(id: conversation_ids).includes(:contact).each do |conversation|
      result = Crm::AppointmentExtractionService.new(conversation: conversation).call

      if result[:error]
        stats[:errors] += 1
        # sem chave/agente desligado = não adianta continuar varrendo
        break if result[:error].include?('pausado') || result[:error].include?('não configurada')

        next
      end

      outcome = Crm::AppointmentRecorder.record(
        account: account, result: result,
        contact: conversation.contact, conversation: conversation
      )
      stats[outcome] += 1

      sleep 0.3 # respiro entre chamadas de IA
    rescue StandardError => e
      stats[:errors] += 1
      Rails.logger.error "[Crm::AgendaBackfill] conversa #{conversation.id}: #{e.message}"
    end

    save_last_run(account, conversation_ids.size, stats)
    Rails.logger.info "[Crm::AgendaBackfill] #{conversation_ids.size} conversas → #{stats.inspect}"
  end

  private

  # conversas com mensagem ENVIADA de confirmação no período (mais recentes primeiro)
  def matching_conversation_ids(account, since, limit)
    clauses = CONFIRMATION_TERMS.map { 'unaccent(messages.content) ILIKE unaccent(?)' }.join(' OR ')
    values  = CONFIRMATION_TERMS.map { |t| "%#{t}%" }

    Message.reorder(nil)
           .where(account_id: account.id, message_type: :outgoing)
           .where('messages.created_at >= ?', since)
           .where(clauses, *values)
           .order(created_at: :desc)
           .limit(limit * 5)
           .pluck(:conversation_id)
           .compact.uniq.first(limit)
  end

  # resultado da última varredura fica visível no card do agente
  def save_last_run(account, scanned, stats)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    cfg = settings.agenda_config || {}
    cfg['backfill_last_run'] = {
      'at' => Time.current.iso8601,
      'scanned' => scanned,
      'created' => stats[:created],
      'rescheduled' => stats[:rescheduled],
      'already' => stats[:already],
      'skipped' => stats[:skipped],
      'errors' => stats[:errors]
    }
    settings.update!(agenda_config: cfg)
  rescue StandardError => e
    Rails.logger.warn "[Crm::AgendaBackfill] falhou ao salvar last_run: #{e.message}"
  end
end
