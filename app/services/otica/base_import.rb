# 👓 IMPORTAÇÃO DA BASE DE CLIENTES DO SAVWIN (03/11/2026).
#
# Lê a exportação do SavWin (CSV; cabeçalho sem distinção de caixa/acento;
# separador ; ou ,) com uma linha por cliente OU uma linha por venda (aí fica
# a venda mais recente de cada telefone) e, para cada cliente:
#   1. normaliza o celular (+55 DDD 9XXXX-XXXX; fixo e número inválido ficam
#      de fora, no relatório);
#   2. cria ou atualiza o Contact pelo telefone, com os atributos
#      personalizados ultima_compra, valor_ultima_compra, tipo_lente,
#      vendedora, nascimento, origem_base e segmento_base;
#   3. aplica a etiqueta do segmento (regras de campanhas/reativacao-base/PLANO.md):
#        base_s0  menos de 6 meses da última compra (só a Jornada fala com ele)
#        base_s2  6 a 12 meses                        → segundo óculos
#        base_s1  12 a 36 meses                       → renovar
#        base_s3  multifocal há 18 a 36 meses         → lente digital (vale sobre o s1)
#        base_s4  aniversário nos próximos 7 dias     → etiqueta extra, qualquer segmento
#        base_fora mais de 36 meses ou sem data       → sem card
#   4. cria o card no funil "Pós-venda e relacionamento" na coluna do segmento
#      (achada pelo NOME, como Otica::CrmBridge), com stage_moved_at = data da
#      última compra; card que já está numa coluna "viva" (conversa, comprou de
#      novo…) não é mexido.
# Idempotente: rodar de novo não duplica contato, etiqueta nem card. Com
# dry: true só monta o relatório. Nenhuma automação do CRM dispara aqui (o
# card nasce direto, sem o gatilho de "entrou na coluna"): a Jornada e a
# Reativação em lotes são quem fala com o cliente, com aprovação.
require 'csv'

class Otica::BaseImport # rubocop:disable Metrics/ClassLength
  COLUMNS = {
    'nome' => :name, 'cliente' => :name, 'nome_cliente' => :name, 'nome_do_cliente' => :name, 'razao_social' => :name,
    'telefone' => :phone, 'celular' => :phone, 'fone' => :phone, 'whatsapp' => :phone, 'telefone_celular' => :phone,
    'tel' => :phone, 'fone_celular' => :phone, 'telefone_1' => :phone, 'telefone1' => :phone,
    'nascimento' => :birthdate, 'data_nascimento' => :birthdate, 'data_de_nascimento' => :birthdate,
    'aniversario' => :birthdate, 'dt_nascimento' => :birthdate, 'dt_nasc' => :birthdate,
    'ultima_compra' => :last_purchase, 'data_ultima_compra' => :last_purchase, 'data_da_ultima_compra' => :last_purchase,
    'data_venda' => :last_purchase, 'data_da_venda' => :last_purchase, 'dt_venda' => :last_purchase, 'data' => :last_purchase,
    'emissao' => :last_purchase, 'data_emissao' => :last_purchase, 'data_compra' => :last_purchase,
    'valor' => :amount, 'valor_total' => :amount, 'total' => :amount, 'valor_ultima_compra' => :amount,
    'valor_venda' => :amount, 'liquido' => :amount, 'valor_liquido' => :amount, 'total_liquido' => :amount,
    'lente' => :lens, 'tipo_lente' => :lens, 'tipo_de_lente' => :lens, 'lentes' => :lens, 'produto' => :lens,
    'descricao' => :lens, 'grife' => :lens, 'linha' => :lens, 'produtos' => :lens,
    'vendedor' => :seller, 'vendedora' => :seller,
    'email' => :email, 'e_mail' => :email
  }.freeze
  SEGMENTS = {
    's0' => 'Base: compra recente', 's2' => '6 meses', 's1' => '1 ano', 's3' => 'Multifocal'
  }.freeze
  BASE_LABELS = {
    'base_s0' => ['#94A3B8', 'Base SavWin: comprou há menos de 6 meses (só a Jornada)'],
    'base_s1' => ['#D4A017', 'Base SavWin: renovar (última compra há 1 a 3 anos)'],
    'base_s2' => ['#D97706', 'Base SavWin: segundo óculos (última compra há 6 a 12 meses)'],
    'base_s3' => ['#7C3AED', 'Base SavWin: multifocal há mais de 18 meses (lente digital)'],
    'base_s4' => ['#EC4899', 'Base SavWin: aniversário nesta semana'],
    'base_fora' => ['#CBD5E1', 'Base SavWin: fora da campanha (mais de 3 anos ou sem data)']
  }.freeze
  ATTRIBUTES = [
    ['ultima_compra', 'date', 'Última compra'],
    ['valor_ultima_compra', 'currency', 'Valor da última compra'],
    ['tipo_lente', 'text', 'Tipo de lente'],
    ['vendedora', 'text', 'Vendedora'],
    ['nascimento', 'date', 'Data de nascimento'],
    ['origem_base', 'text', 'Origem da base'],
    ['segmento_base', 'text', 'Segmento da base']
  ].freeze
  # colunas "vivas": o card de quem está aqui não é mexido pela importação
  LIVE_STAGE = /em conversa|comprou de novo|pedido em produ|pronto para retirar/i
  MULTIFOCAL = /multifocal|progressiv|bifocal|varilux|hb custom|multi co/i
  MAX_ROWS = 20_000

  attr_reader :report

  def initialize(account, csv_text, dry: false, today: Date.current)
    @account = account
    @csv_text = utf8(csv_text)
    @dry = dry
    @today = today
    @report = Hash.new(0)
    @problems = []
    @by_segment = Hash.new { |h, k| h[k] = 0 }
  end

  def call
    rows = parse
    return self if rows.nil?

    header = rows.shift
    mapping = header_mapping(header)
    unless mapping.value?(:phone)
      @problems << 'Não achei a coluna do telefone/celular. Confira o cabeçalho.'
      return self
    end

    clients = collapse(rows.first(MAX_ROWS), mapping)
    @report[:linhas] = [rows.size, MAX_ROWS].min
    @report[:clientes] = clients.size
    prepare! unless @dry
    clients.each_value { |c| import!(c) }
    self
  end

  def report_lines
    seg = %w[s3 s2 s1 s0 s4 fora].map { |k| "#{k}: #{@by_segment[k]}" }.join(' · ')
    lines = [
      "#{@dry ? 'ENSAIO (nada gravado)' : 'Importação'} — #{@report[:linhas]} linha(s), #{@report[:clientes]} cliente(s) com celular válido.",
      "Segmentos → #{seg}",
      "Sem celular ou número inválido: #{@report[:sem_celular]} · sem data de compra: #{@report[:sem_data]} · " \
      "linhas repetidas (mesmo telefone): #{@report[:repetidas]}",
      "Contatos: #{@report[:contatos_criados]} criado(s), #{@report[:contatos_atualizados]} atualizado(s) · " \
      "cards: #{@report[:cards_criados]} criado(s), #{@report[:cards_movidos]} movido(s), #{@report[:cards_mantidos]} mantido(s) em coluna viva"
    ]
    lines << 'Funil "Pós-venda e relacionamento" ou suas colunas não encontrados: rode cevico:otica:preparar antes.' if @report[:sem_funil].positive?
    lines + @problems.first(30).map { |p| "  ! #{p}" }
  end

  def result
    { report: @report.to_h, segmentos: @by_segment.to_h, problemas: @problems.first(50) }
  end

  private

  # ── leitura ───────────────────────────────────────────────────────────────
  def utf8(text)
    t = text.to_s.dup.force_encoding('UTF-8')
    t = t.encode('UTF-8', 'Windows-1252', invalid: :replace, undef: :replace) unless t.valid_encoding?
    t.delete_prefix("\uFEFF")
  end

  def parse
    first = @csv_text.lines.first.to_s
    sep = first.count(';') >= first.count(',') ? ';' : ','
    CSV.parse(@csv_text, col_sep: sep, liberal_parsing: true)
  rescue CSV::MalformedCSVError => e
    @problems << "Arquivo CSV inválido: #{e.message}"
    nil
  end

  def header_mapping(header)
    header.to_a.each_with_index.to_h do |name, idx|
      key = I18n.transliterate(name.to_s).downcase.strip.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
      [idx, COLUMNS[key]]
    end.compact
  end

  # uma linha por cliente: do mesmo telefone fica a venda mais recente
  def collapse(rows, mapping) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    clients = {}
    rows.each_with_index do |row, i|
      next if row.compact.all?(&:blank?)

      c = { line: i + 2 }
      mapping.each { |idx, field| c[field] = row[idx].to_s.strip if c[field].blank? || field == :lens }
      phone = self.class.normalize_phone(c[:phone])
      if phone.nil?
        @report[:sem_celular] += 1
        @problems << "linha #{c[:line]}: celular inválido (#{c[:phone].presence || 'vazio'})" if @problems.size < 60
        next
      end
      c[:phone] = phone
      c[:last_purchase] = self.class.parse_date(c[:last_purchase])
      c[:birthdate] = self.class.parse_date(c[:birthdate])
      c[:amount] = self.class.parse_amount(c[:amount])
      if (prev = clients[phone])
        @report[:repetidas] += 1
        next if prev[:last_purchase] && c[:last_purchase] && c[:last_purchase] <= prev[:last_purchase]
        next if c[:last_purchase].nil?

        c[:name] = prev[:name] if c[:name].blank?
        c[:birthdate] ||= prev[:birthdate]
      end
      clients[phone] = c
    end
    clients
  end

  # ── regras ───────────────────────────────────────────────────────────────
  def segment_of(row)
    return 'fora' if row[:last_purchase].nil?

    months = months_between(row[:last_purchase], @today)
    return 'fora' if months > 36
    return 's0' if months < 6
    return 's2' if months < 12
    return 's3' if months >= 18 && row[:lens].to_s.match?(MULTIFOCAL)

    's1'
  end

  def birthday_this_week?(date)
    return false if date.nil?

    (0..7).any? do |n|
      d = @today + n
      d.month == date.month && d.day == date.day
    end
  end

  def months_between(from, to)
    m = ((to.year - from.year) * 12) + to.month - from.month
    m -= 1 if to.day < from.day
    m
  end

  # ── gravação ─────────────────────────────────────────────────────────────
  def prepare!
    ATTRIBUTES.each do |key, type, label|
      CustomAttributeDefinition.find_or_create_by!(account_id: @account.id, attribute_model: 'contact_attribute', attribute_key: key) do |d|
        d.attribute_display_name = label
        d.attribute_display_type = type
      end
    end
    BASE_LABELS.each do |title, (color, desc)|
      Label.find_or_create_by!(account_id: @account.id, title: title) do |l|
        l.color = color
        l.description = desc
      end
    end
    @pipeline = Crm::Pipeline.where(account_id: @account.id).order(:position).to_a.find { |p| p.name.to_s.match?(/p[óo]s-venda/i) }
    @stages = @pipeline ? @pipeline.stages.to_a : []
  end

  def import!(row)
    seg = segment_of(row)
    @by_segment[seg] += 1
    birthday = birthday_this_week?(row[:birthdate])
    @by_segment['s4'] += 1 if birthday
    @report[:sem_data] += 1 if row[:last_purchase].nil?
    return if @dry

    contact = upsert_contact!(row, seg)
    labels!(contact, seg, birthday)
    card!(contact, row, seg)
  rescue ActiveRecord::RecordInvalid => e
    @problems << "linha #{row[:line]}: #{e.record.errors.full_messages.join(', ')}"
  end

  def upsert_contact!(row, seg) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contact = @account.contacts.find_by(phone_number: row[:phone])
    attrs = (contact&.custom_attributes || {}).merge(
      'ultima_compra' => row[:last_purchase]&.iso8601, 'valor_ultima_compra' => row[:amount], 'tipo_lente' => row[:lens].presence,
      'vendedora' => row[:seller].presence, 'nascimento' => row[:birthdate]&.iso8601, 'origem_base' => 'savwin', 'segmento_base' => seg
    ).compact
    if contact
      contact.name = row[:name] if row[:name].present? && (contact.name.blank? || contact.name.to_s.match?(/\A[\d\s+()-]+\z/))
      contact.custom_attributes = attrs
      changed = contact.changed?
      contact.save! if changed
      @report[changed ? :contatos_atualizados : :contatos_iguais] += 1
      contact
    else
      @report[:contatos_criados] += 1
      @account.contacts.create!(name: row[:name].presence || row[:phone], phone_number: row[:phone], custom_attributes: attrs)
    end
  end

  def labels!(contact, seg, birthday)
    wanted = ["base_#{seg}"]
    wanted << 'base_s4' if birthday
    current = contact.label_list.to_a
    final = (current - BASE_LABELS.keys) + wanted
    contact.update_labels(final.uniq) if final.sort != current.sort
  end

  def card!(contact, row, seg) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    return if seg == 'fora'

    stage = @stages.find { |s| s.name.to_s.match?(Regexp.new(Regexp.escape(SEGMENTS[seg]), Regexp::IGNORECASE)) }
    if @pipeline.nil? || stage.nil?
      @report[:sem_funil] += 1
      return
    end
    card = Crm::Contact.find_or_initialize_by(contact_id: contact.id, pipeline_id: @pipeline.id)
    if card.new_record?
      card.assign_attributes(stage_id: stage.id, origin: 'savwin', cevico_born_via: 'savwin', value: row[:amount])
      card.save!
      moved_at!(card, row)
      @report[:cards_criados] += 1
    elsif card.stage_id == stage.id
      @report[:cards_iguais] += 1
    elsif card.stage&.name.to_s.match?(LIVE_STAGE)
      @report[:cards_mantidos] += 1
    else
      card.update!(stage_id: stage.id)
      moved_at!(card, row)
      @report[:cards_movidos] += 1
    end
  end

  # o modelo carimba stage_moved_at com "agora" ao criar/mover; na base a data
  # que importa é a da última compra (é por ela que o lote ordena)
  def moved_at!(card, row)
    return if row[:last_purchase].nil?

    card.update_column(:stage_moved_at, row[:last_purchase].in_time_zone) # rubocop:disable Rails/SkipsModelValidations
  end

  # ── utilitários (públicos para os testes) ────────────────────────────────
  class << self
    # "+55 11 95502-0981" / "(11) 95502-0981" / "1195502098" / "011 9550-20981" → "+5511955020981"; fixo/inválido → nil
    def normalize_phone(raw) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      d = raw.to_s.gsub(/\D/, '')
      d = d.sub(/\A0+/, '')
      d = d.delete_prefix('55') if d.size >= 12 && d.start_with?('55')
      return nil unless d.size.between?(10, 11)

      ddd = d[0, 2]
      num = d[2..]
      return nil unless ddd.to_i.between?(11, 99)

      num = "9#{num}" if num.size == 8 && num.match?(/\A[6-9]/)
      return nil unless num.size == 9 && num.start_with?('9')

      "+55#{ddd}#{num}"
    end

    def parse_date(raw)
      s = raw.to_s.strip[%r{\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}}]
      return nil if s.nil?

      fmt = if s.match?(/\A\d{4}/)
              '%Y-%m-%d'
            else
              (s[-4..].match?(/\A\d{4}\z/) ? '%d/%m/%Y' : '%d/%m/%y')
            end
      Date.strptime(s.tr('.-', '//'), fmt.tr('-', '/'))
    rescue ArgumentError
      nil
    end

    def parse_amount(raw)
      s = raw.to_s.gsub(/[^\d,.-]/, '')
      return nil if s.blank?

      s = s.count(',').positive? && (s.count('.').zero? || s.rindex(',') > s.rindex('.')) ? s.delete('.').tr(',', '.') : s.delete(',')
      Float(s).round(2)
    rescue ArgumentError
      nil
    end
  end
end
