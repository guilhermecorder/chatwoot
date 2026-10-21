# Paciente respondeu "não vou / remarcar" a uma mensagem da jornada → aviso
# no Radar do Meu Painel (mesma lista dos avisos do Radar de Oportunidades,
# kind 'journey_reply'). Some quando a clínica respondeu depois da resposta
# dele, ou após 24 h. Espelha Crm::Calls::RadarAlert.
class Crm::Journey::RadarAlert
  KIND = 'journey_reply'.freeze
  TTL = 24.hours
  MAX_ALERTS = 30

  def self.push(send, message)
    new(send, message).push
  rescue StandardError => e
    Rails.logger.warn("[CEVICO jornada] aviso do Radar não gravado: #{e.message}")
    nil
  end

  def self.still_open?(account, alert)
    created = Time.zone.parse(alert['created_at'].to_s)
    return false if created.nil? || created < TTL.ago

    send = Crm::JourneySend.find_by(account_id: account.id, id: alert['send_id'])
    return false if send.nil? || send.reply != 'declined'

    !replied_after?(send, account.conversations.find_by(display_id: alert['conversation_id']), created)
  rescue ArgumentError
    false
  end

  # a clínica já respondeu depois do "não vou"?
  def self.replied_after?(send, fallback_conversation, created)
    conversation = send.conversation || fallback_conversation
    return false if conversation.nil?

    conversation.messages.reorder(nil).where(message_type: :outgoing, private: false, sender_type: 'User')
                .exists?(['created_at > ?', send.replied_at || created])
  end

  def initialize(send, message)
    @send = send
    @message = message
  end

  # 🔒 Rodada 4 da auditoria (#81): grava sob a trava da linha relendo a lista
  # fresca (Cevico::SettingMerge) — nunca por cima do que outro escritor gravou
  def push
    alert = build
    Cevico::SettingMerge.merge_key!(@send.account, :ai_config, 'opportunity_state') do |state|
      alerts = Array(state['alerts']).reject { |a| a['kind'] == KIND && a['send_id'] == @send.id }
      alerts << alert
      state['alerts'] = alerts.last(MAX_ALERTS)
      state
    end
    alert
  end

  private

  def build
    contact = @send.contact
    {
      'kind' => KIND, 'send_id' => @send.id,
      'conversation_id' => @message.conversation&.display_id || @send.conversation&.display_id,
      'contact_id' => contact.id, 'contact_name' => contact.name.presence || 'Paciente', 'phone' => contact.phone_number,
      'stage_name' => @send.journey_message.name,
      'motivo' => "⚠️ Respondeu à mensagem “#{@send.journey_message.name}”: “#{@message.content.to_s.truncate(90)}”",
      'acao' => 'Vale ligar ou responder agora para remarcar: quem avisa que não vai ainda quer ser atendido — ' \
                'ofereça duas opções de data e feche na hora.',
      'user_id' => nil, 'user_name' => nil, 'created_at' => Time.current.iso8601
    }
  end
end
