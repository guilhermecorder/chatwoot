# Chamado pelo CrmContactsController quando um card muda de coluna
# ou quando uma etiqueta é adicionada/removida
class CrmAutomationTriggerService
  # Aceita crm_contact (Crm::Contact) ou contact (Contact legado)
  # label: etiqueta específica (para eventos label_added/label_removed)
  def initialize(crm_contact: nil, contact: nil, new_stage:, previous_stage: nil, event_type: 'card_entered', label: nil)
    @crm_contact    = crm_contact
    @contact        = crm_contact&.contact || contact
    @new_stage      = new_stage
    @previous_stage = previous_stage
    @event_type     = event_type
    @label          = label
  end

  def call
    return unless @contact

    automations = @new_stage.automations.where(active: true, trigger_type: trigger_type_for_event)

    # Filtra por label_filter se a automação especificou uma etiqueta específica
    if @label.present?
      automations = automations.select do |a|
        filter = a.action_config&.dig('label_filter')
        filter.blank? || filter.strip.downcase == @label.strip.downcase
      end
    end

    automations.each do |automation|
      schedule_at = automation.delay_minutes.to_i > 0 ? automation.delay_minutes.minutes.from_now : Time.current

      if schedule_at <= Time.current
        CrmAutomationFireJob.perform_later(
          automation.id,
          @contact.id,
          extra_payload
        )
      else
        CrmAutomationFireJob.set(wait_until: schedule_at).perform_later(
          automation.id,
          @contact.id,
          extra_payload
        )
      end
    end
  end

  private

  def trigger_type_for_event
    case @event_type
    when 'card_entered' then 'card_entered'
    when 'card_left'    then 'card_left'
    when 'label_added'  then 'label_added'
    when 'label_removed' then 'label_removed'
    end
  end

  def extra_payload
    payload = {
      event_type:     @event_type,
      previous_stage: @previous_stage ? { id: @previous_stage.id, name: @previous_stage.name } : {}
    }
    payload[:label] = @label if @label.present?
    payload
  end
end
