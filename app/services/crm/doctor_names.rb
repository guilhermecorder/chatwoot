# Os profissionais da casa, com tolerância a grafia: o campo doctor das
# tasks é texto livre (a IA de agendamento preenche "Roberta Negri", "Dra
# Roberta Negri"...). Cada variação resolve para o nome oficial, e os
# filtros por profissional enxergam todas as variações de uma vez.
#
# A lista vem do SEGMENTO (config/segmentos/<id>.yml → profissionais) —
# no preset clínica são os 3 médicos de sempre; noutros segmentos, a
# equipe que o yml definir.
module Crm::DoctorNames
  # { 'Dr. Gustavo Bittar' => 'gustavo|bittar', ... }
  def self.official
    @official ||= Segmento.profissionais_grafias.freeze
  end

  # "dra roberta negri" → "Dra. Roberta Negri"; nome de fora → nil
  def self.canonical(raw)
    official.find { |_name, pattern| raw.to_s.match?(/#{pattern}/i) }&.first
  end

  # scope de tasks filtrado pelas variações de grafia do profissional
  def self.filter(scope, name)
    pattern = official[name] || Regexp.escape(name.to_s)
    scope.where('tasks.doctor ~* ?', pattern)
  end
end
