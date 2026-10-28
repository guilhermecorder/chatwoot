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

  # 🎨 Personalização (28/10): imagens que a conta pode trocar na tela
  IMAGE_KINDS = %w[logo logo_dark icon hero].freeze
  # pares padrão do dicionário global: palavra da clínica → chave do vocabulário
  DICTIONARY_SEEDS = [
    %w[paciente paciente], %w[pacientes paciente_plural], %w[consulta consulta], %w[consultas consulta_plural],
    %w[cirurgia cirurgia], %w[cirurgias cirurgia_plural], %w[médico medico], %w[médicos medico_plural],
    %w[clínica empresa]
  ].freeze

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

  # ── frases prontas (conta > segmento > clínica) ────────────────────────
  # Rótulos compostos onde gênero/concordância mudam ("Consultas marcadas
  # hoje"). As chaves são as do `frases:` dos segmentos + as que as telas
  # registram em helper/frases/*.js. Vazio = vale o segmento da instalação.
  def phrases
    (raw['phrases'] || {}).to_h.transform_keys(&:to_s).compact_blank
  end

  def phrase(key, default = nil)
    phrases[key.to_s].presence || Segmento.frase(key, default)
  end

  # padrões que a tela mostra ao lado de cada frase: clínica (o texto de
  # sempre) coberto pelo segmento da instalação
  def phrase_defaults
    base = (Segmento.load_yml(Segmento::FALLBACK_ID) || {})['frases'] || {}
    base.merge(Segmento.config['frases'] || {})
  end

  # ── nomes dos ambientes (menu + título das telas) ──────────────────────
  def labels
    (raw['labels'] || {}).to_h.transform_keys(&:to_s).compact_blank
  end

  def label(key, default = nil)
    labels[key.to_s].presence || default || key.to_s
  end

  # ── dicionário global (troca de palavras nas telas não adaptadas) ──────
  # { 'enabled' => true/false/nil, 'pairs' => [{ 'de' => 'consulta', 'para' => 'vistoria' }] }
  # Sem decisão explícita: ligado fora da clínica, desligado na clínica.
  def dictionary_raw = (raw['dictionary'] || {}).to_h.transform_keys(&:to_s)

  def dictionary_enabled?
    v = dictionary_raw['enabled']
    return ActiveModel::Type::Boolean.new.cast(v) == true unless v.nil?

    !clinic?
  end

  # pares padrão: só as palavras que o vocabulário da conta realmente troca
  def dictionary_defaults
    DICTIONARY_SEEDS.filter_map do |from, token|
      to = vocabulary[token].to_s
      next if to.blank? || to.casecmp?(from)

      { 'de' => from, 'para' => to }
    end
  end

  def dictionary_pairs
    own = Array(dictionary_raw['pairs']).filter_map do |p|
      p = p.to_h.transform_keys(&:to_s)
      next if p['de'].to_s.strip.blank? || p['para'].to_s.strip.blank?

      { 'de' => p['de'].to_s.strip, 'para' => p['para'].to_s.strip }
    end
    own.any? ? own : dictionary_defaults
  end

  def dictionary
    { 'enabled' => dictionary_enabled?, 'pairs' => dictionary_pairs, 'defaults' => dictionary_defaults,
      'explicit' => !dictionary_raw['enabled'].nil? }
  end

  # ── identidade visual (nome do sistema, paleta, marca d'água) ──────────
  # { 'system_name' => 'Sistema LIFE', 'palette' => 'tangerine', 'watermark' => false, 'accent' => '#D2990B' }
  def visual
    v = (raw['visual'] || {}).to_h.transform_keys(&:to_s)
    { 'system_name' => v['system_name'].to_s.strip, 'palette' => v['palette'].to_s.strip,
      'watermark' => v['watermark'].nil? ? true : ActiveModel::Type::Boolean.new.cast(v['watermark']) == true,
      'accent' => v['accent'].to_s.strip }
  end

  # URLs das imagens anexadas à conta (nil = usa a da instalação / o olho)
  def images
    settings = account && CrmSetting.find_by(account: account)
    IMAGE_KINDS.index_with do |kind|
      att = settings&.public_send("brand_#{kind}")
      att&.attached? ? Rails.application.routes.url_helpers.rails_blob_path(att, only_path: true) : nil
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
      tracking: tracking.slice('meta_pixel_id', 'ga4_measurement_id'),
      # 🎨 Personalização (28/10)
      phrases: phrases,
      phrase_defaults: phrase_defaults,
      labels: labels,
      dictionary: dictionary,
      visual: visual,
      images: images
    }
  end

  # ── gravação (admin) ───────────────────────────────────────────────────
  def self.save!(account, attrs) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    attrs = attrs.to_h.transform_keys(&:to_s)
    # Rodada 4 (achado #383): `current` é só o que veio em attrs; no fim o
    # merge_key! junta com o que já está gravado, sob a trava da linha
    current = {}

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

    # 🎨 Personalização (28/10): frases, nomes dos ambientes, dicionário, visual
    if attrs.key?('phrases')
      current['phrases'] = attrs['phrases'].to_h.transform_keys(&:to_s).first(400).to_h
                                           .select { |k, _| k.match?(/\A[\w.:-]{1,80}\z/) }
                                           .transform_values { |v| v.to_s.strip[0, 300] }
                                           .compact_blank
    end
    if attrs.key?('labels')
      current['labels'] = attrs['labels'].to_h.transform_keys(&:to_s).first(200).to_h
                                         .select { |k, _| k.match?(/\A[\w .:&()>\/-]{1,80}\z/) }
                                         .transform_values { |v| v.to_s.strip[0, 60] }
                                         .compact_blank
    end
    if attrs.key?('dictionary')
      d = attrs['dictionary'].to_h.transform_keys(&:to_s)
      dict = {}
      dict['enabled'] = ActiveModel::Type::Boolean.new.cast(d['enabled']) == true unless d['enabled'].nil? || d['enabled'].to_s == ''
      if d.key?('pairs')
        dict['pairs'] = Array(d['pairs']).first(100).filter_map do |p|
          p = p.to_h.transform_keys(&:to_s)
          from = p['de'].to_s.strip[0, 40]
          to = p['para'].to_s.strip[0, 40]
          next if from.blank? || to.blank? || from.casecmp?(to)

          { 'de' => from, 'para' => to }
        end
      end
      current['dictionary'] = dict
    end
    if attrs.key?('visual')
      v = attrs['visual'].to_h.transform_keys(&:to_s)
      current['visual'] = {
        'system_name' => v['system_name'].to_s.strip[0, 40],
        'palette' => v['palette'].to_s.strip[0, 30],
        'watermark' => v['watermark'].nil? ? true : ActiveModel::Type::Boolean.new.cast(v['watermark']) == true,
        'accent' => v['accent'].to_s.strip[0, 9]
      }
    end

    Cevico::SettingMerge.merge_key!(account, :agenda_config, KEY) { |saved| saved.to_h.merge(current) }
    new(account)
  end

  # 🎨 imagem da identidade visual: anexa (file) ou remove (remove: true)
  def self.save_image!(account, kind, file: nil, remove: false)
    raise ArgumentError, 'imagem desconhecida' unless IMAGE_KINDS.include?(kind.to_s)

    settings = CrmSetting.find_or_create_by!(account: account)
    att = settings.public_send("brand_#{kind}")
    if remove
      att.purge_later if att.attached?
    elsif file
      raise ArgumentError, 'só imagens (PNG, JPG, SVG, WEBP)' unless file.content_type.to_s.start_with?('image/')
      raise ArgumentError, 'imagem muito grande (máx. 5 MB)' if file.size.to_i > 5.megabytes

      att.attach(file)
    end
    new(account)
  end
end
