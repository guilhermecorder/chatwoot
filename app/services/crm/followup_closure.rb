# 🧠 FOLLOW-UP INTELIGENTE (13/10): o "em que pé a conversa parou" guardado na
# conversa (additional_attributes.cevico_conversa_leitura), compartilhado por
# todos os robôs:
#   { key, situacao, motivo, fonte, at, reativar_em, reativacao, reativacao_at }
#
# key = id da última fala REAL da clínica (cutucada do robô não conta). Quando
# a equipe/IA fala de novo, a key muda e a conversa é lida outra vez; quando o
# paciente fala, a âncora do silêncio muda e nada é cutucado até a clínica
# responder — aí a key também já é outra.
#
# Atalho sem custo: o Atendente de IA (WhatsApp e Instagram) carimba
# cevico_encerrou na fala de despedida (etapa encerramento / pausar). O robô
# respeita o carimbo mesmo que a leitura diga "aberta".
module Crm::FollowupClosure
  module_function

  ATTR = 'cevico_conversa_leitura'.freeze
  CLOSED = %w[encerrada adiada recusou].freeze
  # recusa clara → etiqueta da convenção da base (perda_* = nenhuma automação
  # ativa reativa: campanhas, régua, NPS, Colheitadeira, ligação, follow-up)
  REFUSAL_LABEL = 'perda_sem_interesse'.freeze

  # [id, carimbo_encerrou] da última fala real da clínica (nil se não houver)
  def last_clinic(conversation)
    conversation.messages
                .where(message_type: :outgoing, private: false)
                .where("messages.additional_attributes ->> 'cevico_followup_bot_id' IS NULL")
                .where("messages.additional_attributes ->> 'cevico_followup_reativacao' IS NULL")
                .reorder(id: :desc)
                .pick(:id, Arel.sql("messages.additional_attributes ->> 'cevico_encerrou'"))
  end

  def stored(conversation)
    conversation.additional_attributes&.dig(ATTR) || {}
  end

  # leitura que vale para o silêncio ATUAL (mesma key), ou nil
  def current(conversation, clinic_id)
    data = stored(conversation)
    data.presence && data['key'].to_i == clinic_id.to_i ? data : nil
  end

  def save!(conversation, data)
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      attrs.merge(ATTR => (attrs[ATTR] || {}).merge(data.stringify_keys))
    end
  end

  # recusa: etiqueta no CONTATO (vale para todas as conversas) + nota visível à equipe
  def apply_refusal!(conversation, motivo)
    contact = conversation.contact
    return if contact.nil? || contact.label_list.include?(REFUSAL_LABEL)

    conversation.account.labels.find_or_create_by!(title: REFUSAL_LABEL) do |label|
      label.description = 'Paciente recusou (leitura do follow-up) — nenhuma automação ativa reativa'
      label.color = '#B91C1C'
      label.show_on_sidebar = false
    end
    contact.add_labels([REFUSAL_LABEL])
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
      content: "🧠 Leitura do follow-up: paciente recusou (#{motivo.to_s.truncate(100)}). Etiqueta #{REFUSAL_LABEL} " \
               'aplicada — robôs, campanhas e réguas não mandam mais nada. Foi engano? Remova a etiqueta.'
    )
  rescue StandardError => e
    Rails.logger.warn("[CEVICO followup] recusa sem etiqueta (conversa #{conversation.id}): #{e.message}")
  end
end
