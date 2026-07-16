# Os 3 médicos da casa, com tolerância a grafia: o campo doctor das tasks é
# texto livre (a IA de agendamento preenche "Roberta Negri", "Dra Roberta
# Negri"...). Aqui cada variação resolve para o nome oficial, e os filtros
# por médico enxergam todas as variações de uma vez.
module Crm::DoctorNames
  OFFICIAL = {
    'Dr. Gustavo Bittar' => 'gustavo|bittar',
    'Dr. Henrique Gemelli' => 'henrique|gemelli',
    'Dra. Roberta Negri' => 'roberta|negri'
  }.freeze

  # "dra roberta negri" → "Dra. Roberta Negri"; nome de fora → nil
  def self.canonical(raw)
    OFFICIAL.find { |_name, pattern| raw.to_s.match?(/#{pattern}/i) }&.first
  end

  # scope de tasks filtrado pelas variações de grafia do médico
  def self.filter(scope, name)
    pattern = OFFICIAL[name] || Regexp.escape(name.to_s)
    scope.where('tasks.doctor ~* ?', pattern)
  end
end
