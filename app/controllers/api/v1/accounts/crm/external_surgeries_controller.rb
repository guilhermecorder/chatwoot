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
    ahead = ahead_of_target_count(matched_ids, stage)

    render json: {
      total_lines: lines.size,
      matched: result[:matched].size,
      matched_sample: result[:matched].first(5).map { |m| m[:name] }.compact,
      ambiguous: result[:ambiguous].first(20),
      ambiguous_count: result[:ambiguous].size,
      unmatched: result[:unmatched].first(50),
      unmatched_count: result[:unmatched].size,
      already_in_target: already_in_target,
      ahead_of_target: ahead,
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

  # ── 📄 PLANILHA DE FECHAMENTO (item 132) ────────────────────────────────
  # POST preview_sheet (multipart) — lê o .xlsx inteiro (uma aba por mês),
  # casa por NOME com os contatos e devolve o retrato + um token: as linhas
  # ficam guardadas 2h no cache para o apply não precisar do arquivo de novo.
  def preview_sheet
    file = params[:file]
    return render_could_not_create_error('Envie o arquivo .xlsx da planilha') if file.blank?

    stage = resolve_stage(params[:target_stage_id])
    return render_could_not_create_error('Escolha a coluna de destino') if stage.blank?

    parsed = Crm::ClosingSheetReader.new(file.tempfile.path).parse
    return render_could_not_create_error('Não achei abas com Paciente + valor nessa planilha') if parsed[:rows].empty?

    token = SecureRandom.hex(8)
    Rails.cache.write(sheet_cache_key(token), parsed[:rows], expires_in: 2.hours)

    match = match_rows_by_name(parsed[:rows])
    matched_ids = match[:matched].map { |m| m[:contact_id] }.uniq
    already = matched_ids.any? ? Crm::Contact.where(pipeline_id: stage.pipeline_id, stage_id: stage.id, contact_id: matched_ids).count : 0
    ahead = ahead_of_target_count(matched_ids, stage)

    render json: {
      token: token,
      sheets: parsed[:sheets],
      skipped: parsed[:skipped],
      total_rows: parsed[:rows].size,
      total_value: parsed[:rows].sum { |r| r[:value] }.round(2),
      months: months_summary(parsed[:rows]),
      matched: match[:matched].size,
      matched_by_phone: match[:matched].count { |m| m[:via] == :phone },
      has_phone_column: parsed[:rows].any? { |r| r[:phone].present? },
      matched_sample: match[:matched].first(5).map { |m| m[:row][:name] },
      ambiguous: match[:ambiguous].first(20).map { |m| m[:row][:name] },
      ambiguous_count: match[:ambiguous].size,
      unmatched: match[:unmatched].first(30).map { |r| r[:name] },
      unmatched_count: match[:unmatched].size,
      already_in_target: already,
      ahead_of_target: ahead,
      target_stage: { id: stage.id, name: stage.name }
    }
  end

  # 🤖 POST ai_match_sheet — item 154: a IA compara os nomes que NÃO casaram
  # com candidatos do banco (mesma pessoa escrita diferente). Só sugere:
  # nada é gravado aqui; os pares de confiança ALTA entram no apply quando
  # o admin marcar "usar os achados da IA".
  def ai_match_sheet
    rows = Rails.cache.read(sheet_cache_key(params[:token].to_s))
    return render_could_not_create_error('A prévia expirou — envie a planilha de novo') if rows.blank?

    match = match_rows_by_name(rows)
    result = Crm::SheetNameMatchService.new(account: Current.account, rows: match[:unmatched]).call
    return render_could_not_create_error(result[:error]) if result[:error]

    # guarda no MESMO cache da prévia: o apply relê daqui (nunca do navegador)
    Rails.cache.write("#{sheet_cache_key(params[:token].to_s)}:ai", result[:matches], expires_in: 2.hours)

    alta = result[:matches].select { |m| m[:confidence] == 'alta' }
    media = result[:matches].select { |m| m[:confidence] == 'media' }
    render json: {
      found_high: alta.size,
      found_medium: media.size,
      still_unmatched: match[:unmatched].size - alta.size,
      pairs_high: alta.first(30).map { |m| { sheet: m[:name], system: m[:contact_name] } },
      pairs_medium: media.first(15).map { |m| { sheet: m[:name], system: m[:contact_name] } }
    }
  end

  # POST apply_sheet — recasa no servidor a partir do cache (nunca confia em
  # ids do navegador) e dispara o job com DATA REAL + procedimento por linha.
  # create_missing: cria contato (sem telefone) para as linhas não casadas —
  # o histórico entra inteiro e os dashboards passam a contar a realidade.
  # use_ai_matches: os pares de confiança ALTA achados pela IA (do cache,
  # derivados no servidor) também entram como casados.
  def apply_sheet
    rows = Rails.cache.read(sheet_cache_key(params[:token].to_s))
    return render_could_not_create_error('A prévia expirou — envie a planilha de novo') if rows.blank?

    stage = resolve_stage(params[:target_stage_id])
    return render_could_not_create_error('Escolha a coluna de destino') if stage.blank?

    match = match_rows_by_name(rows)
    entries = match[:matched].map do |m|
      [m[:contact_id], m[:row][:value], m[:row][:date], m[:row][:procedure]]
    end
    unmatched = match[:unmatched]

    if params[:use_ai_matches] == true
      ai = Array(Rails.cache.read("#{sheet_cache_key(params[:token].to_s)}:ai"))
      ai_by_name = ai.select { |m| m[:confidence] == 'alta' }.to_h { |m| [normalize_name(m[:name]), m[:contact_id]] }
      if ai_by_name.any?
        ai_rows, unmatched = unmatched.partition { |r| ai_by_name.key?(normalize_name(r[:name])) }
        entries += ai_rows.map { |r| [ai_by_name[normalize_name(r[:name])], r[:value], r[:date], r[:procedure]] }
      end
    end

    create_rows = params[:create_missing] == true ? unmatched.first(2000) : []
    return render_could_not_create_error('Nenhuma linha casou — ative "criar pacientes não encontrados" para importar o histórico') if entries.empty? && create_rows.empty?

    Crm::ExternalSurgeryJob.perform_later(
      Current.account.id,
      entries,
      stage.id,
      params[:label].to_s,
      {
        'set_value' => params[:set_value] != false,
        'overwrite_value' => params[:overwrite_value] == true,
        'create_rows' => create_rows.map { |r| r.slice(:name, :phone, :value, :date, :procedure).transform_keys(&:to_s) }
      }
    )
    render json: { enqueued: true, matched: entries.size, to_create: create_rows.size }
  end

  # ── ↩️ DESFAZER (item 133) ──────────────────────────────────────────────
  # GET import_status — recibo da última importação (para mostrar o botão)
  def import_status
    receipt = (crm_settings&.agenda_config || {})['surgery_import_undo']
    return render json: { undoable: false } if receipt.blank?

    render json: {
      undoable: true,
      id: receipt['id'],
      at: receipt['at'],
      stage_name: receipt['stage_name'],
      entries: Array(receipt['entries']).size,
      created_contacts: Array(receipt['entries']).count { |e| e['created_contact_id'].present? }
    }
  end

  # POST undo_last — desfaz a última importação (job em segundo plano)
  def undo_last
    receipt = (crm_settings&.agenda_config || {})['surgery_import_undo']
    return render_could_not_create_error('Não há importação para desfazer') if receipt.blank?
    return render_could_not_create_error('Recibo não confere — recarregue a tela') if receipt['id'] != params[:id].to_s

    Crm::ExternalSurgeryUndoJob.perform_later(Current.account.id, receipt['id'])
    render json: { enqueued: true, entries: Array(receipt['entries']).size }
  end

  private

  # 🛡️ quantos casados estão numa coluna DEPOIS do alvo (ex.: Pós
  # Operatório) — o job preserva esses; a prévia avisa (rodada 137)
  def ahead_of_target_count(matched_ids, stage)
    return 0 if matched_ids.blank?

    Crm::Contact.joins(:stage)
                .where(pipeline_id: stage.pipeline_id, contact_id: matched_ids)
                .where('crm_stages.position > ?', stage.position)
                .count
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: Current.account)
  end

  def sheet_cache_key(token)
    "cevico/closing_sheet/#{Current.account.id}/#{token}"
  end

  # casa TELEFONE primeiro (pedido 01/09 — único, resolve homônimos), nome
  # normalizado como reserva pra linha sem telefone. Planilha sem a coluna
  # Telefone se comporta exatamente como antes (só nome).
  def match_rows_by_name(rows)
    name_index = Hash.new { |h, k| h[k] = [] }
    phone_index = Hash.new { |h, k| h[k] = [] }
    Current.account.contacts.pluck(:id, :name, :phone_number).each do |id, name, phone|
      key = normalize_name(name)
      name_index[key] << id if key.present?
      digits = phone.to_s.gsub(/\D/, '')
      phone_index[digits.last(8)] << [id, digits] if digits.length >= 8
    end

    matched = []
    ambiguous = []
    unmatched = []
    rows.each do |row|
      phone_ids = phone_match_ids(phone_index, row[:phone])
      ids = phone_ids || name_index[normalize_name(row[:name])]
      if ids.size == 1
        matched << { contact_id: ids.first, row: row, via: phone_ids ? :phone : :name }
      elsif ids.size > 1
        ambiguous << { contact_ids: ids, row: row }
      else
        unmatched << row
      end
    end
    { matched: matched, ambiguous: ambiguous, unmatched: unmatched }
  end

  # candidatos pelo fim do número + confirmação de linha (mesmo critério do
  # resto do CEVICO — dois DDDs com o mesmo final de 8 não casam).
  # nil = linha sem telefone utilizável → cai no casamento por nome.
  def phone_match_ids(phone_index, phone_digits)
    digits = phone_digits.to_s
    return nil if digits.length < 8

    ids = phone_index[digits.last(8)]
          .select { |(_id, contact_digits)| Crm::AppointmentRecorder.same_phone_line?(digits, contact_digits) }
          .map(&:first).uniq
    ids.presence
  end

  def normalize_name(name)
    name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
        .gsub(/[^a-z\s]/, ' ').squeeze(' ').strip
  end

  def months_summary(rows)
    rows.group_by { |r| r[:date]&.slice(0, 7) || r[:sheet] }
        .map { |month, list| { month: month, count: list.size, value: list.sum { |r| r[:value] }.round(2) } }
        .sort_by { |m| m[:month].to_s }
  end

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
