class Crm::MessageAutomationRunJob < ApplicationJob
  queue_as :low

  THROTTLE_SECONDS = 0.2
  # o cron reenfileira esta régua a cada 5 min; TTL generoso p/ a rodada não
  # ser considerada "morta" enquanto ainda processa uma base grande
  LOCK_TTL = 1.hour

  def perform(automation_id)
    automation = Crm::MessageAutomation.find_by(id: automation_id)
    return if automation.blank? || !automation.active?

    # TRAVA: sem ela, uma rodada que passa dos 5 min do cron era sobreposta pela
    # seguinte com a MESMA lista de elegíveis → paciente recebia a régua 2×.
    lock_manager = Redis::LockManager.new
    lock_key = "CRM_MESSAGE_AUTOMATION_LOCK::#{automation.id}"
    return unless lock_manager.lock(lock_key, LOCK_TTL)

    begin
      run_automation(automation)
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  private

  def run_automation(automation)
    stats = automation.stats.presence || {}
    stats['sent'] ||= 0
    stats['failed'] ||= 0

    automation.eligible_contacts.find_each do |contact|
      process_contact(automation, contact, stats)
      sleep THROTTLE_SECONDS
    end

    automation.update!(stats: stats.merge('last_run_at' => Time.current.iso8601))
  end

  def process_contact(automation, contact, stats)
    # marca ANTES de enviar: se a rodada estourar o TTL do lock e outra começar,
    # o contato já saiu da lista de elegíveis (eligible_contacts exclui quem tem
    # o marcador) — garante envio único. Falhou o envio? tira a marca de volta,
    # pra não deixar o paciente sem receber.
    marker = automation.marker_label
    automation.account.labels.find_or_create_by!(title: marker)
    contact.label_list.add(marker)
    contact.save!

    conversation = Crm::SendTemplateService.new(source: automation, contact: contact).perform
    if conversation.nil? # sem telefone / template inválido: não foi envio
      unmark(contact, marker)
      return
    end

    stats['sent'] += 1
  rescue StandardError => e
    Rails.logger.error "[Crm::MessageAutomationRunJob] automation #{automation.id} contact #{contact.id}: #{e.message}"
    unmark(contact, automation.marker_label)
    stats['failed'] += 1
  end

  # devolve o contato à fila de elegíveis quando o envio não aconteceu
  def unmark(contact, marker)
    contact.label_list.remove(marker)
    contact.save!
  rescue StandardError => e
    Rails.logger.error "[Crm::MessageAutomationRunJob] rollback do marcador falhou contact #{contact.id}: #{e.message}"
  end
end
