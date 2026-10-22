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
#   1. manual        valores lançados no card da Agenda (tasks.charges, com quem lançou)
#   2. observacao    "Valor: 250" escrito por uma PESSOA na observação
#   3. procedimento  "R$ 350" escrito no TIPO DE CONSULTA (task.procedure,
#                    ex.: "CONSULTA | JÁ PAC | R$350") — item 340
#   4. o PRÉ-CONFIGURADO do tipo (agenda_config.appointment_prices):
#        particular  consulta particular → o valor do MÉDICO
#        exames      cada exame citado no agendamento → soma
#        especiais   avaliação com ESPECIALISTA, pelo problema escrito no
#                    agendamento (glaucoma/retina R$ 300, ceratocone R$ 350 —
#                    os valores do Roteiro; 19/10, Vaneide: "agendou com
#                    especialista em retina, só que o valor não subiu")
#        avaliacao / retorno / pos_op / teleconsulta → o valor do tipo
#   5. observacao    outro "R$ 250" solto na observação (sem "Valor:")
#   6. padrao        o "valor padrão" do lembrete (como já era) ou 150,00
#
# 💰 item 340 (13/10): a confirmação do Alessandro saiu "R$ 150" com a Agenda
# mostrando R$ 350. Duas causas: (a) o valor escrito no tipo de consulta era
# ignorado; (b) até a auditoria (eb435dd) a IA gravava "Valor da consulta:
# R$ 150" FIXO na observação — inclusive no bloco "Reagendada pela IA:" que
# entra embaixo da observação da equipe. O que a IA escreveu nesses blocos
# antigos NÃO conta como valor (human_notes); a rake cevico:limpar_valor_ia
# tira essa linha das consultas futuras.
#
# Um valor pode ser número ("150,00") ou texto ("sem custo"). Sem nada salvo
# na pré-configuração, retorno e pós-operatório saem "sem custo" (palavra
# dele: "não tem custo") e a avaliação segue o valor padrão do lembrete.
module Crm::AppointmentPrice # rubocop:disable Metrics/ModuleLength
  module_function

  KEY = 'appointment_prices'.freeze
  TYPES = %w[avaliacao retorno pos_op teleconsulta].freeze
  FREE = 'sem custo'.freeze
  # 🩺 19/10: avaliação com especialista — o problema escrito no agendamento
  # ("avaliação retina", "glaucoma") puxa o valor do especialista. Padrão = os
  # valores do Roteiro (Crm::CevicoScript); o admin ajusta em Agenda → Valores.
  SPECIALS = [{ 'name' => 'glaucoma', 'price' => '300,00' }, { 'name' => 'retina', 'price' => '300,00' },
              { 'name' => 'ceratocone', 'price' => '350,00' }].freeze
  DEFAULTS = { 'avaliacao' => '', 'retorno' => FREE, 'pos_op' => FREE, 'teleconsulta' => '', 'particular' => {}, 'exames' => [],
               'especiais' => SPECIALS }.freeze
  FALLBACK = '150,00'.freeze
  MAX_EXAMS = 60
  MAX_CHARGES = 8
  # "Valor: 250,00" ou "R$ 250" na observação da consulta
  VALUE_PATTERN = /valor\s*:\s*(?:R\$\s*)?([\d.]+(?:,\d{1,2})?)/i
  REAL_PATTERN = /R\$\s*([\d.]+(?:,\d{1,2})?)/i
  NOTE_PATTERNS = [VALUE_PATTERN, REAL_PATTERN].freeze
  # 🤖 item 340: blocos que a IA escrevia na observação (formato até eb435dd):
  #   consulta nova  "Valor da consulta: R$ 150\n<notas>\nConversa #12 — agendado pela IA"
  #   remarcação     "<observação da equipe>\n\nReagendada pela IA:\nValor da consulta: R$ 150\n…"
  AI_VALUE_LINE = /\A\s*Valor da consulta:\s*(?:R\$\s*)?[\d.]+(?:,\d{1,2})?\s*\z/i
  # sem carimbo (backfill sem conversa) só vale como da IA o valor FIXO que ela gravava
  AI_FIXED_VALUE_LINE = /\A\s*Valor da consulta:\s*R\$\s*150(?:,00)?\s*\z/i
  AI_STAMP_LINE = /agendado pela IA\s*\z/i
  AI_RESCHEDULE_LINE = /\A\s*Reagendada pela IA:/i
  PARAGRAPH_BREAK = /(\n[ \t]*\n)/
  BREAK_ONLY = /\A\n[ \t]*\n\z/

  def config(account)
    saved = (CrmSetting.find_by(account_id: account.id)&.agenda_config || {})[KEY]
    DEFAULTS.merge(saved.is_a?(Hash) ? saved : {})
  end

  # o que a tela manda → o que fica gravado
  def sanitize(raw) # rubocop:disable Metrics/AbcSize
    raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    out = TYPES.index_with { |type| tidy(raw[type]) }
    out['particular'] = (raw['particular'] || {}).to_h.to_h { |doctor, value| [doctor.to_s.strip[0, 80], tidy(value)] }
                                                 .reject { |doctor, value| doctor.blank? || value.blank? }
    out['exames'] = named_prices(raw['exames'])
    # tela antiga (sem o bloco) não apaga os especiais padrão; lista vazia enviada = nenhum
    out['especiais'] = raw.key?('especiais') ? named_prices(raw['especiais']) : SPECIALS
    out
  end

  # [{ name, price }] da tela → gravado (sem nome sai)
  def named_prices(list)
    Array(list).first(MAX_EXAMS).filter_map do |row|
      row = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
      name = row['name'].to_s.strip[0, 60]
      name.present? ? { 'name' => name, 'price' => tidy(row['price']) } : nil
    end
  end

  # { text:, source:, label:, by: } — o valor que vale para este agendamento
  def resolve(cfg, task, fallback: nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    manual = manual_total(task)
    return manual if manual

    notes = human_notes(task.description)
    explicit = match_money(notes, VALUE_PATTERN)
    return { text: explicit, source: 'observacao', label: 'escrito na observação' } if explicit

    written = from_procedure(task.procedure)
    return { text: written, source: 'procedimento', label: 'escrito no tipo de consulta' } if written

    consulta = task.task_type == 'consulta'
    found = consulta ? preset(cfg, task) : nil
    return found if found

    loose = match_money(notes, REAL_PATTERN)
    return { text: loose, source: 'observacao', label: 'escrito na observação' } if loose
    return nil unless consulta

    { text: fallback.presence || FALLBACK, source: 'padrao', label: 'valor padrão' }
  end

  # o pré-configurado do tipo (nil = não tem)
  def preset(cfg, task) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil unless task.task_type == 'consulta'

    if task.particular
      value = pick((cfg['particular'] || {}), task.doctor)
      return { text: value, source: 'particular', label: "particular · #{task.doctor}" } if value.present?
    end
    return exam_total(cfg, task.procedure) if task.modality == 'exames'

    special = special_price(cfg, task)
    return special if special

    type = TYPES.include?(task.modality) ? task.modality : 'avaliacao'
    value = cfg[type].to_s
    value.present? ? { text: value, source: 'preset', label: "pré-configurado · #{type.tr('_', ' ')}" } : nil
  end

  # 🩺 avaliação com especialista: o problema do agendamento cita um dos
  # "especiais" (glaucoma, retina, ceratocone…) → o valor dele. Só na
  # avaliação (retorno e pós-op seguem sem custo).
  def special_price(cfg, task)
    return nil unless ['', 'avaliacao'].include?(task.modality.to_s)

    wanted = fold(task.procedure)
    return nil if wanted.blank?

    hit = Array(cfg['especiais']).find { |row| row['price'].present? && wanted.include?(fold(row['name'])) }
    hit && { text: hit['price'], source: 'preset', label: "pré-configurado · avaliação de #{hit['name']}" }
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

  # valor escrito por uma PESSOA na observação (os blocos antigos da IA não contam)
  def from_notes(text)
    notes = human_notes(text)
    NOTE_PATTERNS.lazy.filter_map { |pattern| match_money(notes, pattern) }.first
  end

  # "CONSULTA | JÁ PAC | R$350" → "350,00" (item 340)
  def from_procedure(text)
    NOTE_PATTERNS.lazy.filter_map { |pattern| match_money(text, pattern) }.first
  end

  def match_money(text, pattern)
    raw = text.to_s.match(pattern)&.[](1)
    raw.present? ? tidy(raw) : nil
  end

  # ── 🤖 item 340: o que a IA escreveu nos blocos antigos ────────────────
  # a observação sem as linhas escritas pela IA (é daqui que o valor é lido)
  def human_notes(text)
    tagged_lines(text).reject { |_line, by_ai| by_ai }.map(&:first).join("\n")
  end

  # tem a linha antiga "Valor da consulta: R$ X" escrita pela IA?
  def legacy_ai_value?(text)
    tagged_lines(text).any? { |line, by_ai| by_ai && line.match?(AI_VALUE_LINE) }
  end

  # a mesma observação sem SÓ essa linha (o resto fica como está) — rake cevico:limpar_valor_ia
  def without_legacy_ai_value(text)
    parts = text.to_s.split(PARAGRAPH_BREAK)
    parts.each_with_index.map do |part, index|
      next part if part.match?(BREAK_ONLY)

      paragraph_lines(part, first: index.zero?).reject { |line, by_ai| by_ai && line.match?(AI_VALUE_LINE) }.map(&:first).join("\n")
    end.join
  end

  # [[linha, escrita_pela_ia?], …] parágrafo a parágrafo
  def tagged_lines(text)
    text.to_s.split(PARAGRAPH_BREAK).each_with_index.flat_map do |part, index|
      part.match?(BREAK_ONLY) ? [] : paragraph_lines(part, first: index.zero?)
    end
  end

  # num parágrafo da IA, tudo até o carimbo "— agendado pela IA" foi ela que
  # escreveu (linhas que a equipe juntou depois do carimbo são da equipe); o bloco
  # "Reagendada pela IA:" sem carimbo é dela inteiro; sem carimbo nenhum, só a
  # linha "Valor da consulta: R$ 150" (o valor fixo) que abre a observação é da IA
  def paragraph_lines(paragraph, first:)
    lines = paragraph.split("\n", -1)
    stamp = lines.rindex { |line| line.match?(AI_STAMP_LINE) }
    ai_until = if stamp
                 stamp
               elsif lines.first.to_s.match?(AI_RESCHEDULE_LINE)
                 lines.size - 1
               elsif first && lines.first.to_s.match?(AI_FIXED_VALUE_LINE)
                 0
               else
                 -1
               end
    lines.each_with_index.map { |line, index| [line, index <= ai_until] }
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
