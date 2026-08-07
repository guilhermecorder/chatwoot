class Api::V1::Accounts::Crm::ExternalSurgeriesController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  # cirurgias feitas fora do sistema = área concedível (padrão: só admin)
  before_action -> { require_capability(:data_tools) }

  MAX_LINES = 3000

  # POST preview — casa a lista colada com os contatos (por telefone) e mostra
  # o retrato: quantos casaram, ambíguos, não encontrados e já na coluna.
  def preview
    lines, stage, error = load_request
    return render_could_not_create_error(error) if error

    result = match_contacts(lines)
    matched_ids = result[:matched].map { |m| m[:contact_id] }
    already_in_target = if matched_ids.any?
                          Crm::Contact.where(pipeline_id: stage.pipeline_id, stage_id: stage.id,
                                             contact_id: matched_ids).count
                        else
                          0
                        end

    render json: {
      total_lines: lines.size,
      matched: result[:matched].size,
      matched_sample: result[:matched].first(5).map { |m| m[:name] }.compact,
      ambiguous: result[:ambiguous].first(20),
      ambiguous_count: result[:ambiguous].size,
      unmatched: result[:unmatched].first(50),
      unmatched_count: result[:unmatched].size,
      already_in_target: already_in_target,
      target_stage: { id: stage.id, name: stage.name }
    }
  end

  # POST apply — refaz o casamento no servidor (nunca confia em ids do
  # navegador) e dispara o job em segundo plano
  def apply
    lines, stage, error = load_request
    return render_could_not_create_error(error) if error

    matched_pairs = match_contacts(lines)[:matched].map { |m| [m[:contact_id], m[:value]] }
    return render_could_not_create_error('Nenhum telefone da lista casou com um contato do sistema') if matched_pairs.empty?

    Crm::ExternalSurgeryJob.perform_later(
      Current.account.id,
      matched_pairs,
      stage.id,
      params[:label].to_s,
      {
        'set_value' => params[:set_value] != false,
        'overwrite_value' => params[:overwrite_value] == true
      }
    )
    render json: { enqueued: true, matched: matched_pairs.size }
  end

  private

  # valida lista + coluna-alvo (mesmas regras na prévia e no aplicar)
  def load_request
    lines = parse_lines(params[:list])
    return [nil, nil, 'Cole a lista de telefones (um por linha)'] if lines.empty?
    if lines.size > MAX_LINES
      return [nil, nil, "A lista tem #{lines.size} linhas — o máximo é #{MAX_LINES} por vez. Divida em partes menores."]
    end

    stage = resolve_stage(params[:target_stage_id])
    return [nil, nil, 'Escolha a coluna de destino'] if stage.blank?

    [lines, stage, nil]
  end

  def resolve_stage(stage_id)
    return nil if stage_id.blank?

    Crm::Stage.joins(:pipeline)
              .where(crm_pipelines: { account_id: Current.account.id })
              .find_by(id: stage_id)
  end

  # Linhas aceitas: "telefone", "telefone;valor" ou "telefone;valor;data"
  # (separador ; ou tab — colar do Excel funciona). Telefone vira só dígitos;
  # linha vazia ou sem nenhum dígito é ignorada.
  def parse_lines(raw)
    raw.to_s.split(/\r?\n/).filter_map do |line|
      parts = line.split(/[;\t]/).map(&:strip)
      phone_raw = parts[0].to_s
      digits = phone_raw.gsub(/\D/, '')
      next if digits.blank?

      { phone: digits, raw: phone_raw, value: parse_value(parts[1]), date: parts[2].presence }
    end
  end

  # Valor em formato brasileiro ou simples: "3900", "3900,00", "3.900,00",
  # "3.900" (milhar), "R$ 3.900". Inválido ou zero = sem valor.
  def parse_value(raw)
    text = raw.to_s.gsub(/r\$/i, '').gsub(/\s/, '')
    return nil if text.blank?

    text = if text.include?(',')
             text.delete('.').tr(',', '.')
           elsif text.match?(/\A\d{1,3}(\.\d{3})+\z/) # "3.900" sem vírgula = milhar BR
             text.delete('.')
           else
             text
           end
    value = Float(text)
    value.positive? ? value.round(2) : nil
  rescue ArgumentError, TypeError
    nil
  end

  # Casa por SUFIXO de 9 e 8 dígitos — cobre telefone BR com/sem o 55 do país
  # e com/sem o nono dígito. 2+ contatos com o mesmo sufixo = ambíguo (não
  # aplica; aparece na prévia para o admin resolver).
  def match_contacts(lines)
    index8, index9 = build_phone_indexes
    matched = []
    ambiguous = []
    unmatched = []
    seen = {}

    lines.each do |line|
      digits = line[:phone]
      if digits.length < 8
        unmatched << line[:raw]
        next
      end

      candidates = digits.length >= 9 ? index9[digits[-9..]] || [] : []
      candidates = index8[digits[-8..]] || [] if candidates.empty?
      candidates = candidates.uniq { |c| c[0] }

      if candidates.empty?
        unmatched << line[:raw]
      elsif candidates.size == 1
        id, name = candidates.first
        next if seen[id] # linha repetida do mesmo paciente: vale a primeira

        seen[id] = true
        matched << { contact_id: id, name: name, value: line[:value] }
      else
        ambiguous << { phone: line[:raw], names: candidates.map { |c| c[1] }.compact.first(5) }
      end
    end

    { matched: matched, ambiguous: ambiguous, unmatched: unmatched }
  end

  def build_phone_indexes
    index8 = {}
    index9 = {}
    Current.account.contacts.where.not(phone_number: [nil, '']).pluck(:id, :name, :phone_number).each do |id, name, phone|
      digits = phone.to_s.gsub(/\D/, '')
      next if digits.length < 8

      (index8[digits[-8..]] ||= []) << [id, name]
      (index9[digits[-9..]] ||= []) << [id, name] if digits.length >= 9
    end
    [index8, index9]
  end
end
