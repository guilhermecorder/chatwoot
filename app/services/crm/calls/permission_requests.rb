# Limites da Calling API da Meta para o PEDIDO DE PERMISSÃO (conformidade
# 20/09): 1 pedido por 24 h e 2 por 7 dias para o mesmo paciente — travados
# aqui, antes de bater na Meta/ElevenLabs. O histórico fica no contato
# (`additional_attributes.cevico_call_permission_requests`, últimos 10).
module Crm::Calls::PermissionRequests
  module_function

  KEY = 'cevico_call_permission_requests'.freeze
  LIMITS = [[24.hours, 1, 'já pedimos permissão a este paciente nas últimas 24 h'],
            [7.days, 2, 'já pedimos permissão a este paciente 2 vezes nos últimos 7 dias']].freeze

  # texto do bloqueio, ou nil quando pode pedir
  def limit_error(contact)
    stamps = recent(contact)
    LIMITS.each do |window, max, text|
      return "Limite da Meta: #{text}." if stamps.count { |t| t > window.ago } >= max
    end
    nil
  end

  # item 333: grava pelo Cevico::AttributeMerge (trava da linha) — o update!
  # cru apagava marcas de lembrete/pausa gravadas no mesmo instante (julho)
  def remember!(contact)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      stamps = (parse_stamps(attrs[KEY]).select { |t| t > 7.days.ago } + [Time.current]).map(&:iso8601).last(10)
      attrs.merge(KEY => stamps)
    end
  end

  def recent(contact)
    parse_stamps((contact.additional_attributes || {})[KEY])
  end

  def parse_stamps(list)
    Array(list).filter_map do |value|
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
