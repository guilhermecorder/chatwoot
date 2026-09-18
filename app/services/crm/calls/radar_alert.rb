# Ligação perdida vira AVISO NO RADAR do Meu Painel (item 167, rodada 3):
# entra na mesma lista de avisos do Radar de Oportunidades (ai_config
# opportunity_state.alerts) com kind 'missed_call', para o popup da
# atendente e o bloco do Radar tratarem igual a uma oportunidade quente.
# O aviso some sozinho quando alguém RETORNOU: mandou mensagem na conversa
# ou falou com o paciente numa ligação depois da perdida — ou após 24 h.
class Crm::Calls::RadarAlert
  KIND = 'missed_call'.freeze
  TTL = 24.hours
  MAX_ALERTS = 30
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  REASONS = {
    'outside_hours' => 'ligou fora do horário de atendimento',
    'rejected' => 'a ligação foi recusada',
    'failed' => 'a ligação falhou'
  }.freeze

  def self.push(call)
    new(call).push
  rescue StandardError => e
    Rails.logger.warn("[CEVICO calls] aviso do Radar não gravado: #{e.message}")
    nil
  end

  # o aviso continua valendo? (usado pelo radar_ping e pela limpeza do Radar)
  def self.still_open?(account, alert)
    created = Time.zone.parse(alert['created_at'].to_s)
    return false if created.nil? || created < TTL.ago

    call = Crm::Call.find_by(account_id: account.id, id: alert['call_id'])
    return false if call.nil? || returned?(call)

    true
  rescue ArgumentError
    false
  end

  # alguém já retornou? mensagem da clínica na conversa depois da perdida,
  # ou uma ligação atendida com o paciente depois dela
  def self.returned?(call)
    since = call.ended_at || call.started_at || call.created_at
    if call.conversation
      replied = call.conversation.messages.reorder(nil)
                    .where(message_type: :outgoing, private: false, sender_type: 'User')
                    .exists?(['created_at > ?', since])
      return true if replied
    end
    return false if call.contact_id.blank?

    Crm::Call.where(account_id: call.account_id, contact_id: call.contact_id).answered
             .where.not(id: call.id).exists?(['started_at > ?', since])
  end

  def initialize(call)
    @call = call
  end

  def push
    settings = CrmSetting.find_or_create_by!(account: @call.account)
    cfg = settings.ai_config || {}
    state = cfg['opportunity_state'] || {}
    alerts = Array(state['alerts']).reject { |a| a['kind'] == KIND && a['call_id'] == @call.id }
    alerts << build
    state['alerts'] = alerts.last(MAX_ALERTS)
    cfg['opportunity_state'] = state
    settings.update!(ai_config: cfg)
    alerts.last
  end

  private

  def build
    contact = @call.contact
    {
      'kind' => KIND, 'call_id' => @call.id,
      'conversation_id' => @call.conversation&.display_id,
      'contact_id' => @call.contact_id,
      'contact_name' => contact&.name.presence || @call.display_name.presence || 'Paciente',
      'phone' => contact&.phone_number || "+#{@call.wa_id}",
      'stage_name' => 'Ligação perdida',
      'motivo' => motivo, 'acao' => acao,
      'user_id' => nil, 'user_name' => nil,
      'created_at' => Time.current.iso8601
    }
  end

  def motivo
    at = (@call.started_at || Time.current).in_time_zone(TZ).strftime('%H:%M')
    reason = REASONS[@call.end_reason.to_s] || 'ninguém atendeu'
    "📵 Ligou às #{at} e #{reason}."
  end

  def acao
    'Vale retornar logo: abra a conversa e use o botão Ligar (ou mande uma mensagem). ' \
      'Quem liga costuma estar pronto para decidir — o retorno rápido evita perder o agendamento.'
  end
end
