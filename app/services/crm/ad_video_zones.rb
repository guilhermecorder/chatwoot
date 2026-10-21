# 🎬 ZONAS do vídeo de um anúncio (item 287, rodada 4): Gancho · Corpo · CTA.
#
# De onde vem: quando a transcrição tem trechos com tempo, o gancho termina
# onde termina a fala do gancho e o CTA começa onde começa o pedido falado.
# Sem isso, a divisão é ESTIMADA (e a tela avisa): gancho = 0 a 3 s, CTA = os
# últimos ~15 % do vídeo (mínimo 3 s), corpo = o meio.
# Sem duração conhecida não há segundos: as zonas são dadas pelos marcos
# (até 3 s = gancho, de 75 % ao fim = CTA, o meio = corpo).
#
# Para onde vai: faixas com nome no fundo do gráfico, a zona de cada queda e a
# frase-resumo ("a maior perda acontece no gancho…").
class Crm::AdVideoZones
  NAMES = { 'hook' => 'Gancho', 'body' => 'Corpo', 'cta' => 'CTA' }.freeze
  PHRASES = { 'hook' => 'no gancho', 'body' => 'no corpo', 'cta' => 'no CTA' }.freeze
  HOOK_SECONDS = 3.0
  CTA_SHARE = 0.15
  CTA_MIN = 3.0
  MARK_ZONES = { 'Impressões' => 'hook', '3 s' => 'body', '25%' => 'body', '50%' => 'body', '75%' => 'cta' }.freeze
  ESTIMATED = 'A divisão em gancho, corpo e CTA é estimada: gancho = 3 primeiros segundos, CTA = trecho final do vídeo. ' \
              'Com a transcrição com tempo, ela passa a seguir a fala.'.freeze
  FROM_SPEECH = 'A divisão em gancho, corpo e CTA segue a fala do vídeo (transcrição com tempo).'.freeze
  BY_MARKS = 'Sem a duração do vídeo, as zonas seguem os marcos: até 3 s = gancho, de 75% ao fim = CTA (estimado).'.freeze

  def initialize(duration:, transcript: {}, points: [])
    @duration = duration.to_f.positive? ? duration.to_f : nil
    @transcript = transcript || {}
    @points = points
  end

  def list
    return [] unless @duration

    hook_end, cta_start = bounds
    [zone('hook', 0, hook_end), zone('body', hook_end, cta_start), zone('cta', cta_start, @duration)].select { |z| z[:to] > z[:from] }
  end

  def estimated?
    spoken_bounds.nil?
  end

  def note
    return BY_MARKS unless @duration

    estimated? ? ESTIMATED : FROM_SPEECH
  end

  # zona de uma queda (pelo ponto onde ela começa)
  def for_drop(from, _to)
    key = @duration && from[:t] ? key_at(from[:t]) : (MARK_ZONES[from[:label]] || 'body')
    { zone: key, zone_label: NAMES[key] }
  end

  # "A maior perda acontece no gancho, nos 3 primeiros segundos; depois disso a
  # maior queda é no corpo, entre 8 s e 16 s."
  def summary(drops)
    first = drops.first
    return nil if first.nil?

    rest = drops.drop(1).find { |d| d[:zone] != first[:zone] } || drops[1]
    text = "A maior perda acontece #{PHRASES[first[:zone]]}, #{span(first)}"
    rest ? "#{text}; depois disso a maior queda é #{PHRASES[rest[:zone]]}, #{span(rest)}." : "#{text}."
  end

  private

  def zone(key, from, to)
    { key: key, label: NAMES[key], from: from.round(1), to: to.round(1) }
  end

  def key_at(second)
    hook_end, cta_start = bounds
    return 'hook' if second < hook_end
    return 'cta' if second >= cta_start

    'body'
  end

  def bounds
    @bounds ||= spoken_bounds || [[HOOK_SECONDS, @duration / 2].min, @duration - cta_length]
  end

  # últimos ~15 % do vídeo, no mínimo 3 s (e nunca mais que um terço dele)
  def cta_length
    [@duration * CTA_SHARE, CTA_MIN].max.then { |length| [length, @duration / 3].min }
  end

  # [fim do gancho, começo do CTA] pela fala — nil quando a transcrição não tem tempo
  def spoken_bounds
    return @spoken_bounds if defined?(@spoken_bounds)

    @spoken = nil
    return nil unless @duration && segments.size >= 2

    hook_end = spoken_edge(@transcript['hook'], :last, 'end') || segments.first['end'].to_f
    cta_start = spoken_edge(@transcript['cta'], :first, 'start') || segments.last['start'].to_f
    hook_end = hook_end.clamp(1.0, @duration / 2)
    cta_start = cta_start.clamp(hook_end, @duration)
    @spoken_bounds = [hook_end, cta_start]
  end

  def segments
    @segments ||= Array(@transcript['segments']).select { |s| s.is_a?(Hash) && s['text'].present? }
  end

  # o tempo do trecho cuja fala faz parte do gancho (ou do CTA) da transcrição
  def spoken_edge(text, which, field)
    target = clean(text)
    return nil if target.blank?

    matches = segments.select { |s| clean(s['text']).present? && (target.include?(clean(s['text'])) || clean(s['text']).include?(target)) }
    matches.public_send(which)&.dig(field)&.to_f
  end

  def clean(text)
    text.to_s.downcase.gsub(/[^\p{L}\p{N} ]/, ' ').squish
  end

  def span(drop) # rubocop:disable Metrics/CyclomaticComplexity
    return 'nos 3 primeiros segundos' if drop[:from_label] == 'Impressões' && drop[:to_label] == '3 s'
    return "entre #{drop[:from_label]} e #{drop[:to_label]}" if drop[:from_t].nil? || drop[:to_t].nil?
    return 'no primeiro segundo' if drop[:from_t].zero? && drop[:to_t] <= 1
    return "nos #{seconds(drop[:to_t])} primeiros segundos" if drop[:from_t].zero?

    "entre #{seconds(drop[:from_t])} s e #{seconds(drop[:to_t])} s"
  end

  def seconds(value)
    (value.to_f % 1).zero? ? value.to_i.to_s : value.to_f.round(1).to_s.tr('.', ',')
  end
end
