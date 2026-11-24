# 🔁 ATENDIMENTO SEM BURACO (23/11/2026): prazos da pausa do Atendente IA do
# WhatsApp. Antes, toda pausa valia PARA SEMPRE (só 👍, a chavinha ou o
# paciente reabrindo a conversa religavam) e o paciente que continuava
# escrevendo ficava sem resposta. Agora duas pausas têm prazo:
#
#   humano_assumiu  vale N min a partir da ÚLTIMA mensagem da equipe
#                   (responder_resume_after_human_minutes, padrão 2);
#   chamou_humano   a IA chamou a equipe, o paciente escreveu DEPOIS disso e
#                   ninguém respondeu em N min desde essa mensagem
#                   (responder_resume_after_handoff_minutes, padrão 10).
#
# 0 = nunca religa sozinha (o comportamento antigo). NÃO vencem: a chavinha
# (botao), o teto diário e tudo o que envolve URGÊNCIA clínica (pausa com a
# marca 'urgente' e a pausa de quem assumiu uma urgência, marca 'sem_prazo').
#
# Duas camadas usam esta peça:
#   preguiçosa  quem pergunta "está pausada?" (CrmListener, ResponderAgentJob,
#               resgate) trata a pausa vencida como não pausada;
#   ativa       o Crm::ResponderResumeJob, agendado ao pausar/renovar, limpa a
#               pausa na hora certa e devolve a conversa ao agente.
#
# As chaves ficam no ai_config da conta (CRM → update_ai aceita e devolve em
# `responder_settings`). SETTINGS também guarda os limites do resgate.
module Crm::ResponderPause # rubocop:disable Metrics/ModuleLength
  module_function

  # chave do ai_config → [padrão, mínimo, máximo]
  SETTINGS = {
    'responder_resume_after_human_minutes' => [2, 0, 1440],
    'responder_resume_after_handoff_minutes' => [10, 0, 1440],
    'responder_rescue_max_hours' => [23, 1, 23], # dentro das 24 h do WhatsApp
    'responder_rescue_per_round' => [15, 1, 40]
  }.freeze
  HUMAN = 'humano_assumiu'.freeze
  HANDOFF = 'chamou_humano'.freeze
  # a IA voltou sem a equipe ter respondido ao pedido dela: fica esta marca no
  # estado (sem 'paused') e o contexto do modelo ganha um aviso. Some quando
  # alguém da equipe responde (a pausa nova sobrescreve) ou depois de 24 h.
  PENDING_KEY = 'handoff_pending'.freeze
  PENDING_TTL = 24.hours
  RESUME_SLACK = 5.seconds

  def ai_config(conversation)
    CrmSetting.find_by(account_id: conversation.account_id)&.ai_config || {}
  end

  # valor da chave (inteiro dentro dos limites); em branco ou ilegível = padrão
  def setting(cfg, key)
    default, min, max = SETTINGS.fetch(key)
    value = Integer((cfg || {})[key].to_s.strip, 10, exception: false)
    value.nil? ? default : value.clamp(min, max)
  end

  def state_of(conversation)
    state = (conversation.additional_attributes || {})[Crm::ResponderAgentJob::STATE_KEY]
    state.is_a?(Hash) ? state : {}
  end

  # a pausa gravada JÁ VENCEU? :human | :handoff | nil. Só leitura.
  def due(conversation, state = state_of(conversation), cfg = nil, now: Time.current) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil unless state['paused']
    return nil if state['urgente'] || state['sem_prazo']

    at = parse_time(state['at'])
    return nil if at.nil?

    case state['reason']
    when HUMAN
      minutes = setting(cfg || ai_config(conversation), 'responder_resume_after_human_minutes')
      :human if minutes.positive? && at <= now - minutes.minutes
    when HANDOFF
      minutes = setting(cfg || ai_config(conversation), 'responder_resume_after_handoff_minutes')
      return nil unless minutes.positive?

      wrote_at = patient_wrote_after(conversation, state, at)
      :handoff if wrote_at && wrote_at <= now - minutes.minutes
    end
  end

  # pausada DE VERDADE agora? (pausa vencida não conta). Só leitura: quem usa
  # é o resgate e a pesquisa de satisfação, que não devem escrever nada.
  def active?(conversation, cfg = nil)
    state = state_of(conversation)
    state['paused'] ? due(conversation, state, cfg).nil? : false
  end

  # camada preguiçosa: confere e, se a pausa venceu, limpa NA HORA (com nota
  # para a equipe). Devolve o estado que vale agora.
  def refresh!(conversation, cfg = nil)
    state = state_of(conversation)
    return state unless state['paused']

    cfg ||= ai_config(conversation)
    kind = due(conversation, state, cfg)
    kind ? resume!(conversation, state, kind, cfg) : state
  end

  # camada ativa: confere de novo quando o prazo acabar
  def schedule_resume(conversation, cfg, key)
    minutes = setting(cfg, key)
    return unless minutes.positive?

    Crm::ResponderResumeJob.set(wait: minutes.minutes + RESUME_SLACK).perform_later(conversation.id)
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderPause] religar não agendado (conversa #{conversation.id}): #{e.message}"
  end

  # paciente escreveu com a IA calada por ter chamado a equipe: agenda a volta
  def schedule_handoff_resume(conversation, state, cfg)
    return unless state['paused'] && state['reason'] == HANDOFF && !state['urgente']

    schedule_resume(conversation, cfg, 'responder_resume_after_handoff_minutes')
  end

  # a IA voltou a responder SEM a equipe ter atendido o pedido dela?
  def handoff_pending?(conversation, now: Time.current)
    pending = state_of(conversation)[PENDING_KEY]
    return false unless pending.is_a?(Hash)

    at = parse_time(pending['at'])
    at.present? && at > now - PENDING_TTL
  end

  # limpa a pausa vencida. Só mexe se o estado ainda é o MESMO que foi lido
  # (se alguém da equipe escreveu no meio, o 'at' mudou e nada acontece).
  def resume!(conversation, seen, kind, cfg)
    cleared = false
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      cleared = same_pause?(attrs[Crm::ResponderAgentJob::STATE_KEY], seen)
      next attrs unless cleared

      value = kind == :handoff ? { PENDING_KEY => { 'at' => seen['at'], 'resumed_at' => Time.current.iso8601 } } : {}
      attrs.merge(Crm::ResponderAgentJob::STATE_KEY => value)
    end
    note!(conversation, kind, cfg) if cleared
    state_of(conversation)
  end

  def same_pause?(current, seen)
    current.is_a?(Hash) && current['paused'] == true && current['reason'] == seen['reason'] && current['at'] == seen['at']
  end

  def note!(conversation, kind, cfg)
    content =
      if kind == :handoff
        minutes = setting(cfg, 'responder_resume_after_handoff_minutes')
        '▶️ Atendente IA do WhatsApp voltou a responder sozinho: o paciente escreveu depois do pedido de atendimento humano ' \
          "e ninguém da equipe respondeu em #{minutes} min. A tarefa continua aberta no Meu Painel."
      else
        minutes = setting(cfg, 'responder_resume_after_human_minutes')
        "▶️ Atendente IA do WhatsApp religado sozinho: #{minutes} min sem mensagem da equipe. " \
          'Para deixar desligado nesta conversa, use a chavinha no topo.'
      end
    conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                  message_type: :activity, private: true, content: content)
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderPause] nota de religar (conversa #{conversation.id}): #{e.message}"
  end

  # quando o paciente escreveu pela 1ª vez DEPOIS de a IA chamar a equipe.
  # A pausa nova guarda a mensagem que a IA respondeu ('msg'); a antiga só tem a hora.
  def patient_wrote_after(conversation, state, paused_at)
    scope = conversation.messages.where(message_type: :incoming, private: false)
    scope = state['msg'].to_i.positive? ? scope.where('id > ?', state['msg'].to_i) : scope.where('created_at > ?', paused_at)
    scope.minimum(:created_at)
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
