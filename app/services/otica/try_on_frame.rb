require 'mini_magick'

# 🖼️ MOLDURA DA PROVA VIRTUAL (22/11/2026, ideia do Guilherme no banho):
# em vez de um cartão antes/depois por armação, a cliente recebe UMA imagem com moldura:
#   topo  → a fotinho dela num círculo + "FORMATO DO ROSTO / Oval" + "Modelos ideais: retangular ou quadrada"
#   meio  → as 2 opções lado a lado (ela usando cada armação), numeradas 1 e 2
#   embaixo de cada foto → o nome da armação e o formato (nas faixas, a faixa e o valor)
#   rodapé → a marca da loja
# Fundo preto, texto branco, verde só nos detalhes (número e formatos ideais). 1080×1350 (4:5).
# A imagem do servidor não tem fonte instalada: a Roboto Bold vai junto em vendor/fonts.
class Otica::TryOnFrame
  WIDTH = 1080
  HEIGHT = 1350
  BG = '#0F0F12'.freeze
  WHITE = '#FFFFFF'.freeze
  GRAY = '#9C9CA6'.freeze
  GREEN = '#4CD787'.freeze
  FONT = Rails.root.join('vendor/fonts/Roboto-Bold.ttf').to_s.freeze

  # selfie: { bytes:, mime: } (a foto dela, sem óculos)
  # options: [{ image: { bytes:, mime: }, title: 'Bulget BG8040M', subtitle: 'Retangular' }] (1 ou 2)
  # face_label: 'oval' · ideais: ['retangular', 'quadrada'] · logo: bytes PNG ou nil
  def self.compose(selfie:, options:, face_label:, ideais:, logo: nil)
    new(selfie, options, face_label, ideais, logo).compose
  end

  def initialize(selfie, options, face_label, ideais, logo)
    @selfie = selfie
    @options = options.first(2)
    @face = face_label.to_s
    @ideais = Array(ideais).compact_blank.first(2)
    @logo = logo
    @temp = []
  end

  def compose
    raise ArgumentError, 'sem opção' if @options.empty?

    canvas = temp('png')
    magick { |m| m << '-size' << "#{WIDTH}x#{HEIGHT}" << "xc:#{BG}" << canvas }
    canvas = header(canvas)
    canvas = @options.size == 2 ? two_up(canvas) : one_up(canvas)
    canvas = footer(canvas) if @logo
    out = temp('jpg')
    magick { |m| m << canvas << '-strip' << '-quality' << '90' << out }
    { bytes: File.binread(out), mime: 'image/jpeg' }
  ensure
    @temp.each { |f| f.close! rescue nil } # rubocop:disable Style/RescueModifier
  end

  private

  # ── topo: fotinho redonda + formato do rosto + modelos ideais ───────────────
  def header(canvas)
    thumb = circle(@selfie, 140)
    canvas = place(canvas, thumb, 56, 52)
    canvas = place(canvas, text('FORMATO DO ROSTO', 24, GRAY), 226, 64)
    canvas = place(canvas, text(@face.capitalize, 64, WHITE), 222, 96)
    return canvas if @ideais.empty?

    label = text(@ideais.size == 1 ? 'Modelo ideal pra você: ' : 'Modelos ideais pra você: ', 30, GRAY)
    lw = MiniMagick::Image.open(label).width
    value = text(@ideais.map(&:capitalize).join(' ou '), 30, GREEN, max: WIDTH - 56 - 56 - lw - 9)
    canvas = place(canvas, label, 56, 222)
    place(canvas, value, 56 + lw + 9, 222) # o label come o espaço do fim
  end

  # ── 2 opções lado a lado ────────────────────────────────────────────────────
  PHOTO_TOP = 290
  def two_up(canvas)
    w = 516
    h = 740
    @options.each_with_index do |opt, i|
      x = 16 + (i * (w + 16))
      canvas = place(canvas, rounded(opt[:image], w, h, 26), x, PHOTO_TOP)
      canvas = place(canvas, badge(i + 1), x + 18, PHOTO_TOP + 18)
      canvas = place(canvas, text(opt[:title], 34, WHITE, width: w, gravity: 'center'), x, PHOTO_TOP + h + 26)
      canvas = place(canvas, text(opt[:subtitle], 28, GRAY, width: w, gravity: 'center'), x, PHOTO_TOP + h + 74)
    end
    canvas
  end

  # ── 1 opção só (quando só saiu uma) ─────────────────────────────────────────
  def one_up(canvas)
    w = 600
    h = 800
    x = (WIDTH - w) / 2
    opt = @options.first
    canvas = place(canvas, rounded(opt[:image], w, h, 26), x, PHOTO_TOP)
    canvas = place(canvas, text(opt[:title], 36, WHITE, width: WIDTH, gravity: 'center'), 0, PHOTO_TOP + h + 22)
    place(canvas, text(opt[:subtitle], 28, GRAY, width: WIDTH, gravity: 'center'), 0, PHOTO_TOP + h + 70)
  end

  # ── rodapé: a marca da loja em branco (os óculos verdes da marca ficam verdes) ──
  def footer(canvas)
    logo = temp('png')
    magick do |m|
      m << write(bytes: @logo, mime: 'image/png') << '-trim' << '+repage' << '-resize' << '300x84'
      m << '-channel' << 'RGB' << '-fx' << '(u.g>0.75&&u.r<0.3)?u:1' << '+channel' << logo
    end
    lw, lh = MiniMagick::Image.open(logo).dimensions
    place(canvas, logo, (WIDTH - lw) / 2, HEIGHT - 40 - lh)
  end

  # ── peças ───────────────────────────────────────────────────────────────────
  # texto numa linha; width = caixa fixa (centraliza); max = corta com reticências até caber
  def text(value, size, color, width: nil, gravity: 'west', max: nil) # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize
    limit = max || width
    value = value.to_s.squish
    value = fit(value, size, limit) if limit
    out = temp('png')
    if value.empty? # sem formato cadastrado, por ex.: peça transparente em vez de quebrar a imagem
      magick { |m| m << '-size' << '1x1' << 'xc:none' << out }
      return out
    end
    value = "\\#{value}" if value.start_with?('@') # "@arquivo" faria o ImageMagick ler um arquivo
    magick do |m|
      m << '-background' << 'none' << '-font' << FONT << '-pointsize' << size.to_s << '-fill' << color
      m << "label:#{value.gsub('%', '%%')}"
      # caixa fixa DEPOIS do texto (com -size antes, o label estica a fonte até encher a largura)
      m << '-gravity' << gravity << '-extent' << "#{width}x" if width
      m << out
    end
    out
  end

  # corta o texto até a largura caber (Roboto Bold ≈ 0,56 da altura por letra)
  def fit(value, size, limit)
    chars = (limit / (size * 0.56)).floor
    value.size > chars ? "#{value[0, [chars - 1, 1].max].rstrip}…" : value
  end

  def rounded(img, w, h, r) # rubocop:disable Naming/MethodParameterName, Metrics/AbcSize
    photo = temp('png')
    magick { |m| m << write(img) << '-auto-orient' << '-resize' << "#{w}x#{h}^" << '-gravity' << 'center' << '-extent' << "#{w}x#{h}" << photo }
    mask = temp('png')
    magick do |m|
      m << '-size' << "#{w}x#{h}" << 'xc:black' << '-fill' << 'white' << '-draw' << "roundrectangle 0,0,#{w - 1},#{h - 1},#{r},#{r}" << mask
    end
    out = temp('png')
    magick { |m| m << photo << mask << '-alpha' << 'off' << '-compose' << 'CopyOpacity' << '-composite' << out }
    out
  end

  def circle(img, d) # rubocop:disable Naming/MethodParameterName, Metrics/AbcSize
    photo = temp('png')
    # o rosto costuma estar no terço de cima da selfie: recorta o quadrado puxado pra cima
    magick { |m| m << write(img) << '-auto-orient' << '-resize' << "#{d}x#{d}^" << '-gravity' << 'north' << '-extent' << "#{d}x#{d}" << photo }
    out = temp('png')
    magick do |m|
      m << photo << '(' << '-size' << "#{d}x#{d}" << 'xc:black' << '-fill' << 'white' << '-draw' << "circle #{d / 2},#{d / 2} #{d / 2},1" << ')'
      m << '-alpha' << 'off' << '-compose' << 'CopyOpacity' << '-composite'
      m << '-fill' << 'none' << '-stroke' << 'rgba(255,255,255,0.85)' << '-strokewidth' << '3' << '-draw' << "circle #{d / 2},#{d / 2} #{d / 2},3" << out
    end
    out
  end

  def badge(number)
    d = 58
    out = temp('png')
    magick do |m|
      m << '-size' << "#{d}x#{d}" << 'xc:none' << '-fill' << GREEN << '-draw' << "circle #{d / 2},#{d / 2} #{d / 2},1"
      m << '-font' << FONT << '-pointsize' << '32' << '-fill' << BG << '-gravity' << 'center' << '-annotate' << '+0+1' << number.to_s << out
    end
    out
  end

  def place(canvas, piece, x, y) # rubocop:disable Naming/MethodParameterName
    out = temp('png')
    magick { |m| m << canvas << piece << '-gravity' << 'northwest' << '-geometry' << "+#{x}+#{y}" << '-compose' << 'Over' << '-composite' << out }
    out
  end

  def magick(&)
    MiniMagick::Tool::Magick.new(&)
  end

  def write(img)
    path = temp(ext_of(img[:mime]))
    File.binwrite(path, img[:bytes])
    path
  end

  def temp(ext)
    f = Tempfile.new(['moldura', ".#{ext}"], binmode: true)
    @temp << f
    f.path
  end

  def ext_of(mime)
    return 'png' if mime.to_s.include?('png')
    return 'webp' if mime.to_s.include?('webp')

    'jpg'
  end
end
