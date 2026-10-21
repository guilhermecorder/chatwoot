# 🔁 ITEM 348 (16/10): UMA conversa por paciente em cada caixa ("Manter numa
# conversa só" ligado na caixa). Antes, quando a equipe resolvia e o paciente
# escrevia de novo, nascia uma conversa NOVA — e com ela a pausa dos
# Atendentes de IA voltava ao zero. Com a conversa única, a MESMA conversa
# reabre; sem este reset, a pausa de quem assumiu da última vez ficaria
# valendo para sempre e a IA nunca mais responderia esse paciente nessa caixa.
#
# Regra: o PACIENTE reabriu uma conversa resolvida → as pausas dos Atendentes
# de IA (WhatsApp e Instagram) voltam ao zero, igual a uma conversa nova.
# Reabrir pela tela (equipe) NÃO zera: quem reabre à mão está assumindo.
# Etiquetas ficam como estão: att_encerrado já sobe ao CONTATO e vale para
# todas as conversas dele — mesmo comportamento de antes.
module Crm::ReopenReset
  module_function

  PAUSE_KEYS = [Crm::ResponderAgentJob::STATE_KEY, 'cevico_atendente_ia'].freeze

  # chamado pelo Message#reopen_conversation logo depois de reabrir, ANTES do
  # aviso de "mensagem criada" sair para os robôs (a IA já encontra a pausa zerada)
  def after_patient_reopen!(conversation)
    return unless (conversation.additional_attributes || {}).keys.intersect?(PAUSE_KEYS)

    was_paused = false
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      was_paused = paused?(attrs)
      attrs.except(*PAUSE_KEYS)
    end
    note!(conversation) if was_paused
  rescue StandardError => e
    # nunca derruba a mensagem do paciente
    Rails.logger.error "[Crm::ReopenReset] conversa #{conversation&.id}: #{e.message}"
  end

  def paused?(attrs)
    PAUSE_KEYS.any? { |key| attrs.dig(key, 'paused') }
  end

  def note!(conversation)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :activity, private: true,
      content: '🔁 O paciente voltou a escrever e a conversa reabriu: o Atendente IA, que estava pausado, volta a responder aqui. ' \
               'Para pausar de novo, use a chavinha no topo da conversa.'
    )
  end
end
