# 🎯 QUAL MODELO DE MENSAGEM VAI PARA ESTA CONSULTA (item 327, 05/10). Pedido
# do Guilherme: "vamos precisar de modelos de mensagens específicos para quando
# for RETORNO… e também quero poder personalizar POR MÉDICO".
#
# Um BLOCO de modelos (o do lembrete, ou o de cada caixa em by_inbox) tem:
#   units.paulista / units.tatuape   o modelo PADRÃO de cada unidade
#   template_params                  o modelo padrão "geral"
#   followup                         o modelo padrão do reforço
#   variants: [{ modality, doctor, units, template_params, followup }]
#     MODELOS PERSONALIZADOS: valem só para aquele tipo de atendimento
#     (retorno, pós-operatório, exame…), só para aquele médico, ou os dois.
#
# Ordem de escolha — o mais específico primeiro; dentro de cada conjunto, o
# modelo da UNIDADE da consulta antes do geral:
#   médico + tipo → médico → tipo → padrão
# Conjunto sem modelo para a consulta (nem da unidade, nem geral) passa a vez
# para o seguinte: personalizar o retorno só da Paulista não tira o retorno do
# Tatuapé do modelo padrão.
#
# Entre DUAS caixas (a da conversa do paciente × a padrão do lembrete) ganha
# o modelo mais específico; empate = a caixa da conversa (itens 310/314/323).
module Crm::ReminderModels
  module_function

  MODALITIES = %w[avaliacao retorno pos_op exames teleconsulta].freeze
  MODALITY_LABELS = { 'avaliacao' => 'Avaliação', 'retorno' => 'Retorno', 'pos_op' => 'Pós-operatório', 'exames' => 'Exame',
                      'teleconsulta' => 'Teleconsulta' }.freeze
  MAX_VARIANTS = 16

  # 📍 item 323 (04/10, Guilherme: "consulta sem unidade é na Av. Paulista
  # hoje"): agendamento sem unidade na Agenda vale Av. Paulista — no modelo
  # escolhido e no {{unidade}} da mensagem. PROVISÓRIO, palavra dele: "por
  # enquanto fica como padrão, mas isso pode (e deve) mudar no futuro" — a
  # regra mora só aqui, para trocar num lugar só.
  DEFAULT_UNIT = 'paulista'.freeze

  def unit_key(task)
    task.unit.to_s.strip.presence || DEFAULT_UNIT
  end

  def modality_key(task)
    MODALITIES.include?(task.modality) ? task.modality : 'avaliacao'
  end

  # o bloco tem algum modelo (padrão ou personalizado)?
  def any?(block)
    sets(block).any? { |set| slot(set).present? || units(set).any? }
  end

  # o modelo desta consulta neste bloco: { template_params, message_preview,
  # rank, general, model } — ou nil se o bloco não tem nada que sirva
  def pick(block, task)
    candidates(block, task).each do |set, spec|
      by_unit = units(set)[unit_key(task)]
      return chosen(by_unit, set, spec, unit: true) if by_unit

      general = slot(set)
      return chosen(general, set, spec, unit: false) if general
    end
    nil
  end

  # o modelo do REFORÇO: o personalizado mais específico que tiver, senão o padrão do bloco
  def followup(block, task)
    candidates(block, task).each do |set, spec|
      found = slot(set['followup'])
      return found.merge('model' => (spec.positive? ? label(set) : nil)).compact if found
    end
    nil
  end

  # `mine` é mais específico que `other`? (tipo/médico primeiro, depois unidade × geral)
  def better?(mine, other)
    (Array(mine&.dig('rank')) <=> Array(other&.dig('rank'))).to_i.positive?
  end

  def label(variant)
    [MODALITY_LABELS[variant['modality']], variant['doctor'].presence].compact.join(' · ')
  end

  def specificity(variant)
    (variant['doctor'].present? ? 2 : 0) + (variant['modality'].present? ? 1 : 0)
  end

  # ── por dentro ────────────────────────────────────────────────────────
  def variants(block)
    Array((block || {})['variants']).select { |variant| variant.is_a?(Hash) && specificity(variant).positive? }
  end

  def sets(block)
    variants(block) + [block || {}]
  end

  # [conjunto, especificidade] do mais específico para o padrão (0)
  def candidates(block, task)
    matching = variants(block).select { |variant| match?(variant, task) }
                              .sort_by.with_index { |variant, index| [-specificity(variant), index] }
    matching.map { |variant| [variant, specificity(variant)] } + [[block || {}, 0]]
  end

  def match?(variant, task)
    (variant['modality'].blank? || variant['modality'] == modality_key(task)) &&
      (variant['doctor'].blank? || fold(variant['doctor']) == fold(task.doctor))
  end

  def units(set)
    ((set || {})['units'] || {}).select { |_unit, tpl| slot(tpl).present? }
  end

  def slot(raw)
    return nil unless raw.is_a?(Hash) && raw['template_params'].present?

    { 'template_params' => raw['template_params'], 'message_preview' => raw['message_preview'] }
  end

  def chosen(tpl, set, spec, unit:)
    slot(tpl).merge('rank' => [spec, unit ? 1 : 0], 'general' => (true unless unit),
                    'model' => (spec.positive? ? label(set) : nil)).compact
  end

  def fold(text)
    I18n.transliterate(text.to_s).downcase.squish
  end
end
