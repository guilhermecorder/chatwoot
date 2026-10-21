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
#      Remarcou e o card já está na coluna de agendamento ou além (Realizada,
#      Cirurgia…) → fica onde está (auditoria 10/2026, #197). Exceção: quem
#      está em "Consulta Confirmada" volta QUIETO para o agendamento (sem
#      reenviar o "consulta marcada") — a nova data ainda não foi confirmada.
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
  # tipo da passagem no histórico de colunas quando o card anda por remarcação
  # (contrato com o KpiBag/BookingRate: quem conta agendamento ignora este tipo)
  RESCHEDULED_EVENT = 'rescheduled'.freeze

  class << self
    # configuração vigente (padrões preenchidos) — a tela lê daqui
    def config(account) # rubocop:disable Metrics/CyclomaticComplexity
      cfg = (CrmSetting.find_by(account: account)&.agenda_config || {})['booking'] || {}
      labels = DEFAULT_LABELS.merge((cfg['labels'] || {}).to_h.transform_keys(&:to_s).compact_blank)
      {
        'labels_enabled' => cfg['labels_enabled'] != false,
        'labels' => labels,
        'stage_id' => cfg['stage_id'].presence&.to_i,
        'cancel_stage_id' => cfg['cancel_stage_id'].presence&.to_i,
        'budget_stage_id' => cfg['budget_stage_id'].presence&.to_i # 💰 item 236
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

    def move_card(account, contact, outcome, preferred_stage_id) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      return nil if contact.blank?

      # 🩹 21/10: a próxima consulta é de pós-op → o card fica em "Consulta Pós Op" (Crm::PosOpReflector)
      return nil if outcome != :canceled && Crm::PosOpReflector.next_is_pos_op?(account, contact)

      target_id = outcome == :canceled ? config(account)['cancel_stage_id'] : booking_stage_id(account, preferred_stage_id)
      return nil if target_id.blank?

      stage = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).find_by(id: target_id)
      return nil if stage.blank?

      card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
      if card.blank?
        # paciente novo, sem card ainda: nasce direto na coluna certa
        # (primeira chegada à coluna, mesmo vindo de remarcação = conta como
        # agendamento — 'entered' — senão esse paciente nunca seria contado)
        Crm::Contact.create!(contact_id: contact.id, pipeline_id: stage.pipeline_id, stage_id: stage.id)
        CrmAutomationTriggerService.new(crm_contact: Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id),
                                        new_stage: stage, event_type: 'card_entered').call
        return stage.name
      end
      return nil if card.stage_id == stage.id

      # 🔁 auditoria 10/2026 (#197): remarcar NÃO puxa o card para trás — quem já
      # está além da coluna (Realizada, Cirurgia…) fica onde está (antes voltava
      # para "Agendamento de Consulta" e recebia de novo o "consulta marcada").
      # "Consulta Confirmada" volta, mas quieta (back_from_confirmed!)
      if outcome == :rescheduled && Crm::ConfirmationReflector.ahead?(account, card, stage)
        return nil unless Crm::ConfirmationReflector.confirmed_stage?(card.stage)

        return back_from_confirmed!(account, card, stage)
      end

      previous = card.stage
      rebooking = outcome == :rescheduled && booked_before?(account, card, stage, previous)
      card.update!(stage_id: stage.id)
      mark_reschedule_entry!(card, stage) if rebooking
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, previous_stage: previous, event_type: 'card_entered').call
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: previous, previous_stage: previous, event_type: 'card_left').call if previous
      stage.name
    end

    # remarcou estando em "Consulta Confirmada": a Task já apagou o "sim"
    # (era para a data antiga), então o card volta para o agendamento — sem
    # card_entered/card_left (não reenvia o "consulta marcada") e sem contar
    # como agendamento novo. Quando o paciente confirmar a nova data, o
    # Crm::ConfirmationReflector leva o card de volta para Confirmada.
    # (decisão provisória da auditoria 10/2026 — opção B; confirmar com o Guilherme)
    def back_from_confirmed!(account, card, stage)
      rebooking = booked_before?(account, card, stage, card.stage)
      card.update!(stage_id: stage.id)
      mark_reschedule_entry!(card, stage) if rebooking
      stage.name
    end

    # o card JÁ TINHA sido agendado antes? (passou pela coluna de agendamento,
    # ou vem de "Consulta Confirmada" / "Não foi à consulta"). Só aí a nova
    # passagem é remarcação; a primeira chegada à coluna conta como agendamento.
    # Chamar ANTES de mover o card.
    def booked_before?(account, card, stage, previous)
      return true if card.stage_logs.exists?(stage_id: stage.id)
      return false if previous.nil?

      missed = (CrmSetting.find_by(account: account)&.agenda_config || {}).dig('attendance_stages', 'missed_stage_id').to_i
      previous.id == missed || Crm::ConfirmationReflector.confirmed_stage?(previous)
    end

    # o card andou por causa de uma REMARCAÇÃO de quem já tinha agendado: a
    # passagem fica no histórico com o tipo próprio 'rescheduled' — a taxa de
    # agendamento e "agendamentos criados" só contam 'entered', então
    # remarcação não vira agendamento novo (mesmo desenho do 'bulk' do item 309)
    def mark_reschedule_entry!(card, stage)
      card.stage_logs.where(stage_id: stage.id, left_at: nil, event_type: 'entered')
          .order(:id).last&.update_columns(event_type: RESCHEDULED_EVENT) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
