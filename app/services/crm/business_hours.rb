# Horário comercial da clínica para métricas de atendimento (pedido 22/07):
# seg–sex, 08h–17h em São Paulo, fora feriados nacionais. O que cai fora
# (noite, madrugada, fim de semana, feriado) é "fora do horário" — medido à
# parte, sem meta, porque não há atendente presente para responder.
module Crm
  module BusinessHours
    module_function

    TZ_NAME = 'America/Sao_Paulo'.freeze
    OPEN_HOUR = 8
    CLOSE_HOUR = 17 # exclusivo: 16h59 é comercial, 17h00 já não é

    # feriados nacionais do ano: fixos + os que dependem da Páscoa
    def national_holidays(year)
      easter = easter_date(year)
      [
        Date.new(year, 1, 1),   # Confraternização Universal
        Date.new(year, 4, 21),  # Tiradentes
        Date.new(year, 5, 1),   # Dia do Trabalho
        Date.new(year, 9, 7),   # Independência
        Date.new(year, 10, 12), # Nossa Senhora Aparecida
        Date.new(year, 11, 2),  # Finados
        Date.new(year, 11, 15), # Proclamação da República
        Date.new(year, 11, 20), # Consciência Negra
        Date.new(year, 12, 25), # Natal
        easter - 48,            # Carnaval (segunda)
        easter - 47,            # Carnaval (terça)
        easter - 2,             # Sexta-feira Santa
        easter + 60             # Corpus Christi
      ]
    end

    # algoritmo de Meeus/Jones/Butcher (domingo de Páscoa, calendário gregoriano)
    def easter_date(year) # rubocop:disable Metrics/AbcSize
      a = year % 19
      b, c = year.divmod(100)
      d, e = b.divmod(4)
      f = (b + 8) / 25
      g = (b - f + 1) / 3
      h = ((19 * a) + b - d - g + 15) % 30
      i, k = c.divmod(4)
      l = (32 + (2 * e) + (2 * i) - h - k) % 7
      m = (a + (11 * h) + (22 * l)) / 451
      month = (h + l - (7 * m) + 114) / 31
      day = ((h + l - (7 * m) + 114) % 31) + 1
      Date.new(year, month, day)
    end

    # condição SQL "este timestamp caiu no horário comercial" para uma coluna
    # UTC do banco; from/to delimitam quais anos precisam de lista de feriado
    def sql_condition(column, from, to)
      local = "((#{column}) AT TIME ZONE 'UTC') AT TIME ZONE '#{TZ_NAME}'"
      years = (from.year..to.year)
      holidays = years.flat_map { |y| national_holidays(y) }
                      .map { |d| "'#{d.iso8601}'" }.join(', ')
      "EXTRACT(DOW FROM #{local}) BETWEEN 1 AND 5 " \
        "AND EXTRACT(HOUR FROM #{local}) >= #{OPEN_HOUR} " \
        "AND EXTRACT(HOUR FROM #{local}) < #{CLOSE_HOUR} " \
        "AND (#{local})::date NOT IN (#{holidays})"
    end
  end
end
