# CSV do histórico de chamadas (item 176) — colunas em pt-BR, horário de
# São Paulo, uma linha por ligação; abre direto no Excel/Numbers/Sheets.
require 'csv'

class Crm::Calls::CsvExport
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  HEADERS = ['Data', 'Hora', 'Direção', 'Situação', 'Motivo do fim', 'Paciente', 'Telefone', 'Atendente', 'Quem cuidou',
             'Caixa', 'Espera (s)', 'Conversa (s)', 'Resultado (IA)', 'Retornada em', 'Gravação', 'Conversa #', 'Resumo'].freeze
  DIRECTIONS = { 'inbound' => 'Recebida', 'outbound' => 'Feita pela clínica' }.freeze
  STATUSES = { 'ringing' => 'Tocando', 'accepted' => 'Em chamada', 'completed' => 'Atendida', 'missed' => 'Perdida',
               'rejected' => 'Recusada', 'failed' => 'Falha', 'canceled' => 'Cancelada' }.freeze

  def initialize(calls)
    @calls = calls
  end

  def to_csv
    CSV.generate(col_sep: ';') do |csv|
      csv << HEADERS
      @calls.each { |call| csv << row(call) }
    end
  end

  private

  def row(call)
    when_columns(call) + who_columns(call) + result_columns(call)
  end

  def when_columns(call)
    at = call.started_at&.in_time_zone(TZ)
    [at&.strftime('%d/%m/%Y'), at&.strftime('%H:%M'), DIRECTIONS[call.direction] || call.direction,
     STATUSES[call.status] || call.status, call.end_reason]
  end

  def who_columns(call)
    contact = call.contact
    [contact&.name || call.display_name, contact&.phone_number || call.wa_id, call.user&.available_name,
     handler_label(call), call.inbox&.name]
  end

  def handler_label(call)
    call.ai? ? 'Assistente virtual' : 'Atendente'
  end

  def result_columns(call)
    [call.wait_seconds, call.talk_seconds, call.outcome_label, returned_label(call),
     call.recording.attached? ? 'sim' : '', call.conversation&.display_id, call.summary.to_s.squish.first(300)]
  end

  def returned_label(call)
    at = call.returned_at
    at && Time.zone.parse(at).in_time_zone(TZ).strftime('%d/%m/%Y %H:%M')
  end
end
