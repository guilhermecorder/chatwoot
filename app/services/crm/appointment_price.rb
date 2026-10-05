# 💰 VALOR DO AGENDAMENTO (item 324, 05/10). Pedido do Guilherme depois que
# uma paciente particular da Dra. Roberta recebeu a confirmação com o preço
# errado: "precisamos de pré-configuração para avaliação, avaliação particular,
# retorno, pós-operatório 1… os exames, cada um tem o seu valor; as consultas
# particulares, cada uma tem o seu valor também, por médico… as mensagens de
# confirmação devem captar primeiro o valor pré-configurado, mas se houver
# algo adicionado à mão, a mensagem prioriza esse valor (e é importante que
# esteja lá qual agente adicionou)".
#
# De onde sai o valor de UM agendamento, nesta ordem (a primeira que existir):
#   1. manual      valores lançados no card da Agenda (tasks.charges, com quem lançou)
#   2. observacao  "Valor: 250" / "R$ 250" escrito na observação (como já era)
#   3. o PRÉ-CONFIGURADO do tipo (agenda_config.appointment_prices):
#        particular  consulta particular → o valor do MÉDICO
#        exames      cada exame citado no agendamento → soma
#        avaliacao / retorno / pos_op / teleconsulta → o valor do tipo
#   4. padrao      o "valor padrão" do lembrete (como já era) ou 150,00
#
# Um valor pode ser número ("150,00") ou texto ("sem custo"). Sem nada salvo
# na pré-configuração, retorno e pós-operatório saem "sem custo" (palavra
# dele: "não tem custo") e a avaliação segue o valor padrão do lembrete.
module Crm::AppointmentPrice
  module_function

  KEY = 'appointment_prices'.freeze
  TYPES = %w[avaliacao retorno pos_op teleconsulta].freeze
  FREE = 'sem custo'.freeze
  DEFAULTS = { 'avaliacao' => '', 'retorno' => FREE, 'pos_op' => FREE, 'teleconsulta' => '', 'particular' => {}, 'exames' => [] }.freeze
  FALLBACK = '150,00'.freeze
  MAX_EXAMS = 60
  MAX_CHARGES = 8
  # "Valor: 250,00" ou "R$ 250" na observação da consulta
  NOTE_PATTERNS = [/valor\s*:\s*(?:R\$\s*)?([\d.]+(?:,\d{1,2})?)/i, /R\$\s*([\d.]+(?:,\d{1,2})?)/i].freeze

  def config(account)
    saved = (CrmSetting.find_by(account_id: account.id)&.agenda_config || {})[KEY]
    DEFAULTS.merge(saved.is_a?(Hash) ? saved : {})
  end

  # o que a tela manda → o que fica gravado
  def sanitize(raw) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    out = TYPES.index_with { |type| tidy(raw[type]) }
    out['particular'] = (raw['particular'] || {}).to_h.to_h { |doctor, value| [doctor.to_s.strip[0, 80], tidy(value)] }
                                                 .reject { |doctor, value| doctor.blank? || value.blank? }
    out['exames'] = Array(raw['exames']).first(MAX_EXAMS).filter_map do |exam|
      exam = exam.respond_to?(:to_unsafe_h) ? exam.to_unsafe_h : exam.to_h
      name = exam['name'].to_s.strip[0, 60]
      name.present? ? { 'name' => name, 'price' => tidy(exam['price']) } : nil
    end
    out
  end

  # { text:, source:, label:, by: } — o valor que vale para este agendamento
  def resolve(cfg, task, fallback: nil)
    manual = manual_total(task)
    return manual if manual

    noted = from_notes(task.description)
    return { text: noted, source: 'observacao', label: 'escrito na observação' } if noted
    return nil unless task.task_type == 'consulta'

    preset(cfg, task) || { text: fallback.presence || FALLBACK, source: 'padrao', label: 'valor padrão' }
  end

  # o pré-configurado do tipo (nil = não tem)
  def preset(cfg, task) # rubocop:disable Metrics/CyclomaticComplexity
    return nil unless task.task_type == 'consulta'

    if task.particular
      value = pick((cfg['particular'] || {}), task.doctor)
      return { text: value, source: 'particular', label: "particular · #{task.doctor}" } if value.present?
    end
    return exam_total(cfg, task.procedure) if task.modality == 'exames'

    type = TYPES.include?(task.modality) ? task.modality : 'avaliacao'
    value = cfg[type].to_s
    value.present? ? { text: value, source: 'preset', label: "pré-configurado · #{type.tr('_', ' ')}" } : nil
  end

  # soma dos exames da pré-configuração citados no agendamento
  def exam_total(cfg, procedure)
    wanted = fold(procedure)
    hits = Array(cfg['exames']).select { |exam| exam['price'].present? && wanted.include?(fold(exam['name'])) }
    return nil if hits.empty?

    { text: total(hits.pluck('price')), source: 'preset', label: "pré-configurado · #{hits.pluck('name').join(' + ')}" }
  end

  def manual_total(task)
    rows = Array(task.charges).select { |row| row['amount'].present? }
    return nil if rows.empty?

    { text: total(rows.pluck('amount')), source: 'manual', label: 'lançado à mão',
      by: rows.filter_map { |row| row['by_name'].presence }.uniq.join(', ').presence }
  end

  def from_notes(text)
    raw = NOTE_PATTERNS.lazy.filter_map { |pattern| text.to_s.match(pattern)&.[](1) }.first
    raw.present? ? tidy(raw) : nil
  end

  # valores lançados à mão: quem já estava fica como estava; linha nova ou
  # alterada ganha o nome de quem lançou
  def stamp_charges(current, list, user) # rubocop:disable Metrics/CyclomaticComplexity
    Array(list).first(MAX_CHARGES).filter_map do |row|
      row = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
      label = row['label'].to_s.strip[0, 60]
      amount = tidy(row['amount'])
      next if amount.blank?

      Array(current).find { |old| old['label'] == label && old['amount'] == amount } ||
        { 'label' => label, 'amount' => amount, 'by_id' => user&.id, 'by_name' => user&.name, 'at' => Time.current.iso8601 }
    end
  end

  # ── dinheiro ──────────────────────────────────────────────────────────
  # "150" → "150,00" · "R$ 1.250,5" → "1.250,50" · "sem custo" → "sem custo"
  def tidy(value)
    text = value.to_s.strip.sub(/\AR\$\s*/i, '')[0, 30]
    number = to_number(text)
    number ? money(number) : text
  end

  def to_number(text)
    text = text.to_s.strip.sub(/\AR\$\s*/i, '')
    return BigDecimal(text) if text.match?(/\A\d+\.\d{1,2}\z/) # 150.00 (ponto como centavos)
    return nil unless text.match?(/\A\d[\d.]*(,\d{1,2})?\z/)

    BigDecimal(text.delete('.').tr(',', '.'))
  end

  def money(number)
    cents = (number * 100).round.to_i
    whole = (cents / 100).to_s.reverse.scan(/\d{1,3}/).join('.').reverse
    format('%<whole>s,%<cents>02d', whole: whole, cents: cents % 100)
  end

  # vários valores: soma os números; um só em texto ("sem custo") fica como está
  def total(values)
    numbers = values.filter_map { |value| to_number(value) }
    return values.first.to_s if numbers.empty?

    money(numbers.sum)
  end

  def pick(hash, name)
    key = fold(name)
    hash.find { |candidate, _value| fold(candidate) == key }&.last.to_s
  end

  def fold(text)
    I18n.transliterate(text.to_s).downcase.squish
  end
end
