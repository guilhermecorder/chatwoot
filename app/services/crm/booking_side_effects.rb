# 🏷️ EFEITOS DE UM AGENDAMENTO (item 200, 22/09 — "o agente roda solto e o
# sistema etiqueta o paciente e move o card sozinho").
#
# Sempre que uma consulta é CRIADA, REAGENDADA ou CANCELADA — pelo Secretário
# da Agenda lendo a conversa (robô do N8N ou equipe) ou pelo Atendente interno
# ao vivo — este serviço:
#   1. põe a ETIQUETA do acontecimento no paciente e na conversa
#      (consulta_agendada · consulta_reagendada · consulta_cancelada) e tira a
#      contrária (agendou de novo → sai a "cancelada"; cancelou → saem as outras);
#   2. MOVE O CARD do CRM para a coluna configurada (agendou/remarcou → coluna
#      de agendamento; cancelou → coluna de cancelamento), disparando as
#      automações da coluna nova como se a equipe tivesse arrastado o card.
#
# Configuração em agenda_config['booking'] (tela Agendamentos → Ajustes):
#   { 'labels_enabled' => true,
#     'labels' => { 'created' => 'consulta_agendada', 'rescheduled' => 'consulta_reagendada',
#                   'canceled' => 'consulta_cancelada' },
#     'stage_id' => 12, 'cancel_stage_id' => 15 }
# Sem coluna de agendamento configurada, vale a "Ao agendar, mover o card
# para" do Atendente de Agendamento (after_booking_stage_id). Nada configurado
# = só as etiquetas. Nunca levanta exceção para quem chama: um erro aqui não
# pode desfazer a consulta que acabou de ser gravada.
class Crm::BookingSideEffects
  OUTCOMES = %i[created rescheduled canceled].freeze
  DEFAULT_LABELS = {
    'created' => 'consulta_agendada',
    'rescheduled' => 'consulta_reagendada',
    'canceled' => 'consulta_cancelada'
  }.freeze
  LABEL_COLORS = { 'created' => '#059669', 'rescheduled' => '#D97706', 'canceled' => '#DC2626' }.freeze

  class << self
    # configuração vigente (padrões preenchidos) — a tela lê daqui
    def config(account) # rubocop:disable Metrics/CyclomaticComplexity
      cfg = (CrmSetting.find_by(account: account)&.agenda_config || {})['booking'] || {}
      labels = DEFAULT_LABELS.merge((cfg['labels'] || {}).to_h.transform_keys(&:to_s).compact_blank)
      {
        'labels_enabled' => cfg['labels_enabled'] != false,
        'labels' => labels,
        'stage_id' => cfg['stage_id'].presence&.to_i,
        'cancel_stage_id' => cfg['cancel_stage_id'].presence&.to_i
      }
    end

    # coluna de agendamento efetiva: a da tela ou a do Atendente de Agendamento
    def booking_stage_id(account, fallback = nil)
      config(account)['stage_id'] || fallback.presence&.to_i ||
        CrmSetting.find_by(account: account)&.ai_config&.dig('agents', 'atendente_agendamento', 'after_booking_stage_id').presence&.to_i
    end

    # Devolve { labels: [...aplicadas], stage: 'nome da coluna' | nil } (só o
    # que de fato mudou). stage_id: coluna preferida de quem chama (o card do
    # agente); nil = a da configuração.
    def apply(account:, contact:, conversation:, outcome:, stage_id: nil)
      outcome = outcome.to_sym
      return {} unless OUTCOMES.include?(outcome)

      result = { labels: [], stage: nil }
      result[:labels] = apply_labels(account, contact, conversation, outcome)
      result[:stage] = move_card(account, contact, outcome, stage_id)
      result
    rescue StandardError => e
      Rails.logger.warn("[Crm::BookingSideEffects] #{e.class}: #{e.message}")
      {}
    end

    # texto curto para a nota interna: "🏷️ consulta_agendada · card → Agendamento de Consulta"
    def summary(result)
      parts = []
      parts << "🏷️ #{result[:labels].join(', ')}" if result[:labels].present?
      parts << "card → #{result[:stage]}" if result[:stage].present?
      parts.join(' · ')
    end

    private

    def apply_labels(account, contact, conversation, outcome) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      cfg = config(account)
      return [] unless cfg['labels_enabled']

      wanted = cfg['labels'][outcome.to_s].to_s.strip.downcase
      return [] if wanted.blank?

      others = cfg['labels'].except(outcome.to_s).values.map { |l| l.to_s.strip.downcase }.compact_blank
      ensure_label!(account, wanted, LABEL_COLORS[outcome.to_s])

      changed = []
      if conversation
        current = conversation.label_list.map(&:to_s)
        target = (current - others + [wanted]).uniq
        if target.sort != current.sort
          conversation.update_labels(target)
          changed << wanted
        end
      end
      if contact
        current = contact.label_list.map(&:to_s)
        target = (current - others + [wanted]).uniq
        if target.sort != current.sort
          contact.update!(label_list: target)
          changed << wanted
        end
      end
      changed.uniq
    end

    # a etiqueta precisa existir no cadastro da conta (senão some da tela)
    def ensure_label!(account, title, color)
      return if account.labels.exists?(title: title)

      account.labels.create!(title: title, color: color || '#1f93ff', show_on_sidebar: true)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Crm::BookingSideEffects] etiqueta '#{title}': #{e.message}")
    end

    def move_card(account, contact, outcome, preferred_stage_id) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      return nil if contact.blank?

      target_id = outcome == :canceled ? config(account)['cancel_stage_id'] : booking_stage_id(account, preferred_stage_id)
      return nil if target_id.blank?

      stage = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).find_by(id: target_id)
      return nil if stage.blank?

      card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
      if card.blank?
        # paciente novo, sem card ainda: nasce direto na coluna certa
        Crm::Contact.create!(contact_id: contact.id, pipeline_id: stage.pipeline_id, stage_id: stage.id)
        CrmAutomationTriggerService.new(crm_contact: Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id),
                                        new_stage: stage, event_type: 'card_entered').call
        return stage.name
      end
      return nil if card.stage_id == stage.id

      previous = card.stage
      card.update!(stage_id: stage.id)
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, previous_stage: previous, event_type: 'card_entered').call
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: previous, previous_stage: previous, event_type: 'card_left').call if previous
      stage.name
    end
  end
end
