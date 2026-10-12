# 🏢 Identidade da empresa (rodada 334): o que o sistema sabe sobre a
# empresa dona da conta — nome, ramo, vocabulário, unidades, assistente.
# Fica em crm_settings.agenda_config['company'] (sem migration).
#
# Sem configuração nenhuma, tudo responde como a CEVICO de hoje (ramo
# clínica, "paciente", "consulta", "médico") — ninguém sente diferença.
# A Sua Ótica nasce com ramo 'otica' e fala "cliente", "atendimento",
# "consultor".
class Cevico::Company
  KEY = 'company'.freeze
  SEGMENTS = %w[clinica otica outro].freeze
  SEGMENT_LABELS = { 'clinica' => 'Clínica', 'otica' => 'Ótica', 'outro' => 'Outro ramo' }.freeze

  # vocabulário padrão por ramo — o admin pode trocar qualquer palavra
  VOCABULARY = {
    'clinica' => { 'paciente' => 'paciente', 'paciente_plural' => 'pacientes', 'consulta' => 'consulta',
                   'consulta_plural' => 'consultas', 'medico' => 'médico', 'medico_plural' => 'médicos',
                   'cirurgia' => 'cirurgia', 'cirurgia_plural' => 'cirurgias', 'empresa' => 'clínica',
                   'unidade' => 'unidade', 'unidade_plural' => 'unidades' },
    'otica' => { 'paciente' => 'cliente', 'paciente_plural' => 'clientes', 'consulta' => 'atendimento',
                 'consulta_plural' => 'atendimentos', 'medico' => 'consultor', 'medico_plural' => 'consultores',
                 'cirurgia' => 'compra', 'cirurgia_plural' => 'compras', 'empresa' => 'ótica',
                 'unidade' => 'loja', 'unidade_plural' => 'lojas' },
    'outro' => { 'paciente' => 'cliente', 'paciente_plural' => 'clientes', 'consulta' => 'atendimento',
                 'consulta_plural' => 'atendimentos', 'medico' => 'consultor', 'medico_plural' => 'consultores',
                 'cirurgia' => 'compra', 'cirurgia_plural' => 'compras', 'empresa' => 'empresa',
                 'unidade' => 'unidade', 'unidade_plural' => 'unidades' }
  }.freeze

  # módulos que só fazem sentido numa clínica (desligados nos outros ramos)
  CLINIC_MODULES = %w[cirurgias medicos oftalmofacil notas_clinicas pos_operatorio].freeze

  attr_reader :account, :raw

  def self.for(account)
    new(account)
  end

  def initialize(account)
    @account = account
    settings = account && CrmSetting.find_by(account: account)
    @raw = ((settings&.agenda_config || {})[KEY] || {}).to_h
  end

  def configured?
    raw.present?
  end

  def name
    raw['name'].to_s.strip.presence || account&.name.to_s.presence || 'CEVICO'
  end

  def segment
    SEGMENTS.include?(raw['segment'].to_s) ? raw['segment'].to_s : 'clinica'
  end

  def clinic?
    segment == 'clinica'
  end

  def segment_label
    SEGMENT_LABELS[segment]
  end

  def tagline = raw['tagline'].to_s.strip
  def about = raw['about'].to_s.strip
  def offers = raw['offers'].to_s.strip
  def tone = raw['tone'].to_s.strip
  def city = raw['city'].to_s.strip.presence || 'São Paulo'

  # ── vocabulário ────────────────────────────────────────────────────────
  def vocabulary
    VOCABULARY[segment].merge((raw['vocabulary'] || {}).to_h.transform_keys(&:to_s).compact_blank)
  end

  def word(token)
    vocabulary[token.to_s] || token.to_s
  end

  # troca {{paciente}}, {{Paciente_plural}}… pelo vocabulário da empresa
  # ({{Token}} com maiúscula inicial sai capitalizado; {{EMPRESA}} = nome)
  def fill(text)
    return text.to_s if text.blank?

    text.to_s.gsub(/\{\{(\w+)\}\}/) do
      token = Regexp.last_match(1)
      case token
      when 'EMPRESA', 'NOME_DA_EMPRESA' then name
      when 'CIDADE' then city
      else
        base = token.downcase
        value = vocabulary[base]
        next "{{#{token}}}" unless value

        token[0] == token[0].upcase ? value.sub(/\A\p{L}/, &:upcase) : value
      end
    end
  end

  # ── unidades (lojas / filiais) ─────────────────────────────────────────
  # [{ 'key' => 'paulista', 'label' => 'Av. Paulista', 'address' => '', 'phone' => '' }]
  def units # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    list = Array(raw['units']).filter_map do |u|
      u = u.to_h.transform_keys(&:to_s)
      key = u['key'].to_s.parameterize(separator: '_')[0, 40]
      next if key.blank?

      { 'key' => key, 'label' => u['label'].to_s.strip.presence || key.humanize,
        'address' => u['address'].to_s.strip, 'phone' => u['phone'].to_s.gsub(/\D/, '')[0, 15] }
    end
    return list if list.any?
    return [] unless clinic?

    # clínica sem lista própria: as unidades que a Agenda já conhece
    Crm::AgendaSlots::UNIT_LABELS.map { |key, label| { 'key' => key, 'label' => label, 'address' => '', 'phone' => '' } }
  end

  def unit_keys = units.pluck('key')
  def unit_label(key) = units.find { |u| u['key'] == key.to_s }&.dig('label') || key.to_s

  # ── assistente virtual ─────────────────────────────────────────────────
  def assistant_name = raw.dig('assistant', 'name').to_s.strip.presence
  def assistant_gender = %w[m f].include?(raw.dig('assistant', 'gender').to_s) ? raw.dig('assistant', 'gender').to_s : 'f'

  # ── módulos ────────────────────────────────────────────────────────────
  # módulo ligado? Clínica = todos ligados (salvo desligado à mão); outros
  # ramos = os clínicos desligados, salvo ligado à mão.
  def module?(key)
    key = key.to_s
    explicit = (raw['modules'] || {}).to_h[key]
    return explicit == true || explicit == 'true' unless explicit.nil?

    clinic? || CLINIC_MODULES.exclude?(key)
  end

  def modules
    (CLINIC_MODULES + %w[agenda campanhas ligacoes marketing financeiro]).uniq.index_with { |k| module?(k) }
  end

  # ── domínio público / hub / rastreio POR EMPRESA ───────────────────────
  # (vazio = vale a configuração global do sistema, como hoje)
  def public_host = Cevico::PublicSite.normalize(raw['public_host'].to_s)
  def hub = (raw['hub'] || {}).to_h
  def tracking = (raw['tracking'] || {}).to_h

  # ── bloco de contexto para os prompts dos agentes de IA ────────────────
  def prompt_context # rubocop:disable Metrics/AbcSize
    lines = ["Empresa: #{name} (#{segment_label.downcase})."]
    lines << "Sobre: #{about}" if about.present?
    lines << "O que oferece: #{offers}" if offers.present?
    lines << "Tom de voz: #{tone}" if tone.present?
    lines << "Unidades: #{units.map { |u| [u['label'], u['address'].presence].compact.join(' — ') }.join('; ')}." if units.any?
    lines << "Chame quem atende de \"#{word(:paciente)}\" e o atendimento de \"#{word(:consulta)}\"." unless clinic?
    lines.join("\n")
  end

  # ── o que vai para a tela ──────────────────────────────────────────────
  def to_h
    {
      configured: configured?,
      name: name,
      segment: segment,
      segment_label: segment_label,
      segments: SEGMENTS.map { |s| { key: s, label: SEGMENT_LABELS[s] } },
      tagline: tagline, about: about, offers: offers, tone: tone, city: city,
      vocabulary: vocabulary,
      vocabulary_defaults: VOCABULARY[segment],
      units: units,
      assistant: { name: assistant_name, gender: assistant_gender },
      modules: modules,
      public_host: public_host,
      hub: hub,
      tracking: tracking.slice('meta_pixel_id', 'ga4_measurement_id')
    }
  end

  # ── gravação (admin) ───────────────────────────────────────────────────
  def self.save!(account, attrs) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    attrs = attrs.to_h.transform_keys(&:to_s)
    settings = CrmSetting.find_or_create_by!(account: account)
    cfg = (settings.agenda_config || {}).dup
    current = (cfg[KEY] || {}).to_h.dup

    current['name'] = attrs['name'].to_s.strip[0, 80] if attrs.key?('name')
    current['segment'] = attrs['segment'].to_s if attrs.key?('segment') && SEGMENTS.include?(attrs['segment'].to_s)
    %w[tagline about offers tone city].each do |field|
      current[field] = attrs[field].to_s.strip[0, 2000] if attrs.key?(field)
    end
    if attrs.key?('vocabulary')
      current['vocabulary'] = attrs['vocabulary'].to_h.transform_keys(&:to_s)
                                                 .select { |k, _| VOCABULARY['clinica'].key?(k) }
                                                 .transform_values { |v| v.to_s.strip[0, 40] }
                                                 .compact_blank
    end
    if attrs.key?('units')
      current['units'] = Array(attrs['units']).first(30).filter_map do |u|
        u = u.to_h.transform_keys(&:to_s)
        key = (u['key'].presence || u['label']).to_s.parameterize(separator: '_')[0, 40]
        next if key.blank?

        { 'key' => key, 'label' => u['label'].to_s.strip[0, 60].presence || key.humanize,
          'address' => u['address'].to_s.strip[0, 200], 'phone' => u['phone'].to_s.gsub(/\D/, '')[0, 15] }
      end
    end
    if attrs.key?('assistant')
      a = attrs['assistant'].to_h.transform_keys(&:to_s)
      current['assistant'] = { 'name' => a['name'].to_s.strip[0, 40], 'gender' => %w[m f].include?(a['gender'].to_s) ? a['gender'].to_s : 'f' }
    end
    if attrs.key?('modules')
      current['modules'] = attrs['modules'].to_h.transform_keys(&:to_s)
                                           .slice(*CLINIC_MODULES)
                                           .transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) == true }
    end
    current['public_host'] = Cevico::PublicSite.normalize(attrs['public_host'].to_s).to_s if attrs.key?('public_host')
    if attrs.key?('hub')
      h = attrs['hub'].to_h.transform_keys(&:to_s)
      current['hub'] = { 'whatsapp' => h['whatsapp'].to_s.gsub(/\D/, '')[0, 15], 'tagline' => h['tagline'].to_s.strip[0, 300],
                         'cta_text' => h['cta_text'].to_s.strip[0, 300] }.compact_blank
    end
    if attrs.key?('tracking')
      t = attrs['tracking'].to_h.transform_keys(&:to_s)
      current['tracking'] = { 'meta_pixel_id' => t['meta_pixel_id'].to_s.gsub(/\D/, '')[0, 30],
                              'ga4_measurement_id' => t['ga4_measurement_id'].to_s.strip[0, 30] }.compact_blank
    end

    cfg[KEY] = current
    settings.update!(agenda_config: cfg)
    new(account)
  end
end
