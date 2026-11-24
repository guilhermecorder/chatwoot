# 🛡️ VIGIA DOS ORÇAMENTOS (LIFE, 24/11/2026 · pedido do Guilherme): "nós precisamos enviar 100% dos orçamentos, a não
# ser que a gente não faça — bateria etc., ou alguma coisa que precisa passar para o Anderson ou para o Mauro". No
# diagnóstico de 24/11, 25 das 88 contas não viraram orçamento enviado; 10 eram falha nossa: orçamento pronto preso no
# "me avisa que eu te mando" (o cliente não respondeu ao modelo), "em alguns minutos te mando" que caiu na equipe e
# ninguém fez, e a IA segurando o orçamento numa pergunta a mais.
#
# De hora em hora, das 8h às 20h (São Paulo), nas contas com o orçamento automático ligado:
#   1. QUEM TEM CONTA + TELHADO NA FICHA E NENHUM ORÇAMENTO nos últimos 10 dias (falou com a gente nos últimos 7) →
#      monta e envia pelo caminho de sempre (Crm::KitQuoteAutoJob), em silêncio se o fornecedor falhar (a tarefa
#      urgente sai igual, mas o cliente não ouve "instabilidade" de novo).
#   2. ORÇAMENTO PRONTO E NÃO ENVIADO, esperando resposta ao "seu orçamento está pronto" há mais de 20 h →
#      com o modelo do PDF aprovado (life_orcamento_pdf), vai o PDF direto; orçamento com mais de 5 dias é refeito
#      antes (preço do dia: os equipamentos acompanham o dólar).
# Fica de fora: quem tem tarefa aberta de caso especial (bateria, híbrido, isolado, usina, ampliação, já tem placas,
# Mauro), está em "Sem Interesse", tem etiqueta de encerramento (nao_perturbe, perda_*) ou a leitura deu "recusou".
# Cada conversa recebe no máximo 2 tentativas por dia.
class Crm::KitQuoteWatchdogJob < ApplicationJob
  queue_as :low

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  HOURS = (8..20)
  AGENT = 'atendente_agendamento'.freeze
  STATE_KEY = 'cevico_orcamento_vigia'.freeze
  MAX_TRIES_PER_DAY = 2
  QUIET_AFTER_LAST_MESSAGE = 2.hours # não atravessa a conversa que está acontecendo (a IA ainda pode estar na sondagem)
  SPECIAL = /bateria|h[ií]brid|isolad|off.?grid|usina|amplia|j[aá] tem placa|mauro/i
  WAITING_HOURS = 20
  REBUILD_AFTER = 5.days

  def perform(now = Time.current)
    return unless HOURS.cover?(now.in_time_zone(TZ).hour)

    CrmSetting.find_each do |settings|
      next unless settings.ai_config&.dig('agents', AGENT, 'orcamento_automatico') == true

      check(settings.account, now)
    rescue StandardError => e
      Rails.logger.error "[Crm::KitQuoteWatchdogJob] conta #{settings.account_id}: #{e.class}: #{e.message}"
    end
  end

  # o que faria nesta conta (sem fazer): [[:montar | :enviar_pdf | :refazer, conversation, motivo], …]
  def self.plan(account, now = Time.current)
    new.send(:actions, account, now)
  end

  private

  def check(account, now)
    actions(account, now).each do |action, conversation, motivo|
      count_try!(conversation, now)
      case action
      when :montar, :refazer
        Crm::KitQuoteAutoJob.enqueue!(conversation, AGENT, origem: 'vigia')
        note!(conversation, "🛡️ Vigia dos orçamentos: #{motivo}. Montando e enviando o orçamento agora.")
      when :enviar_pdf
        result = Crm::KitQuote::Delivery.new(pending_quote(conversation.contact)).call
        note!(conversation, "🛡️ Vigia dos orçamentos: #{motivo}. Resultado: #{result}.")
      end
    rescue StandardError => e
      Rails.logger.error "[Crm::KitQuoteWatchdogJob] conversa #{conversation.id}: #{e.class}: #{e.message}"
    end
  end

  def actions(account, now)
    candidates(account, now).filter_map do |conversation|
      contact = conversation.contact
      next if blocked?(conversation, now)

      quote = pending_quote(contact)
      if quote
        waiting_action(conversation, quote, now)
      elsif Crm::KitQuote::AutoBuild.missing(contact).nil? && !recent_quote?(contact, now)
        [:montar, conversation, 'conta e telhado na ficha e nenhum orçamento enviado']
      end
    end
  end

  # conversas de WhatsApp em que o cliente falou nos últimos 7 dias (a mais recente de cada contato)
  def candidates(account, now)
    ids = Message.where(account_id: account.id, message_type: :incoming, private: false)
                 .where(created_at: (now - 7.days)..now).reorder(nil).distinct.pluck(:conversation_id)
    Conversation.where(id: ids).joins(:inbox).where(inboxes: { channel_type: 'Channel::Whatsapp' })
                .includes(:contact).order(last_activity_at: :desc).to_a
                .select(&:contact).uniq(&:contact_id)
  end

  def waiting_action(conversation, quote, now)
    asked = Time.zone.parse(quote.payload.to_h[Crm::KitQuote::Delivery::WAITING_KEY].to_s)
    return nil if asked.nil? || asked > now - WAITING_HOURS.hours
    return [:refazer, conversation, stale_reason(quote)] if quote.created_at < now - REBUILD_AFTER

    delivery = Crm::KitQuote::Delivery.new(quote)
    return nil unless conversation.can_reply? || delivery.send(:pdf_template_approved?)

    [:enviar_pdf, conversation, "orçamento ##{quote.id} preso no \"me avisa que eu te mando\" há mais de #{WAITING_HOURS} h"]
  end

  def stale_reason(quote)
    "orçamento ##{quote.id} de #{quote.created_at.in_time_zone(TZ).strftime('%d/%m')} preso no \"me avisa que eu te mando\" " \
      'e com mais de 5 dias (refeito com o preço de hoje)'
  end

  def blocked?(conversation, now)
    return true if conversation.messages.where(created_at: (now - QUIET_AFTER_LAST_MESSAGE)..now).exists?(private: false)
    return true if Crm::KitQuoteAutoJob.running?(conversation)
    return true if tries_today(conversation, now) >= MAX_TRIES_PER_DAY
    return true if special_case?(conversation.contact)
    return true if stop_label?(conversation)
    return true if Crm::FollowupClosure.stored(conversation)['situacao'] == 'recusou'

    no_interest_stage?(conversation.contact)
  end

  def pending_quote(contact)
    Crm::Quote.ativos.where(contact_id: contact.id, sent_at: nil).recent.first
  end

  def recent_quote?(contact, now)
    Crm::Quote.ativos.where(contact_id: contact.id).exists?(['created_at > ?', now - 10.days])
  end

  def special_case?(contact)
    contact.account.tasks.where(contact_id: contact.id).where.not(status: :done).pluck(:title, :description)
           .any? { |title, desc| "#{title} #{desc}".match?(SPECIAL) }
  end

  def stop_label?(conversation)
    labels = (conversation.label_list + conversation.contact.label_list).map(&:downcase)
    labels.include?('nao_perturbe') || labels.any? { |l| l.start_with?('perda_') }
  end

  def no_interest_stage?(contact)
    Crm::Contact.where(contact_id: contact.id).includes(:stage).any? do |card|
      I18n.transliterate(card.stage&.name.to_s).downcase.include?('sem interesse')
    end
  end

  def tries_today(conversation, now)
    state = (conversation.additional_attributes || {})[STATE_KEY].to_h
    state['dia'] == now.in_time_zone(TZ).to_date.iso8601 ? state['tentativas'].to_i : 0
  end

  def count_try!(conversation, now)
    day = now.in_time_zone(TZ).to_date.iso8601
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      old = attrs[STATE_KEY].to_h
      attrs.merge(STATE_KEY => { 'dia' => day, 'tentativas' => (old['dia'] == day ? old['tentativas'].to_i : 0) + 1,
                                 'em' => now.iso8601 })
    end
  end

  def note!(conversation, text)
    conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
                                  private: true, content: text)
  end
end
