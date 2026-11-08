require 'mini_magick'

# 🪞 CARTÃO DA PROVA VIRTUAL (08/11/2026, pedido do Guilherme: "o mais simples possível"):
# ANTES e DEPOIS da mesma foto, lado a lado e sem nada escrito: à esquerda a foto da cliente
# como ela mandou, à direita a mesma foto com a armação (a única diferença é o óculos), fio
# branco no meio. Por cima, só a marca da loja numa pílula de vidro "Liquid Glass" embaixo,
# centralizada e pequena (≈ 1/5 da largura), que vira marca quando ela compartilhar.
#
# Tamanhos: 1 foto = 1080×1440 (3:4, igual à geração); 2 fotos = 1080×720.
# Composição com o ImageMagick da imagem (MiniMagick), tudo em arquivos temporários.
class Otica::TryOnCard
  WIDTH = 1080
  GAP = 4
  GLASS = { width_ratio: 0.21, height_ratio: 0.40, bottom_ratio: 0.035, logo_w: 0.62, logo_h: 0.56, blur: 16 }.freeze
  # 08/11 (Guilherme: "o contraste do logo não ficou bom"): o vidro ganha um tom forte por trás do conteúdo.
  # branco = vidro forçado pro branco + logo verde e texto escuro · verde = vidro no verde da marca + logo e texto brancos
  # vidro = o "Liquid Glass" escuro dos vídeos (ESTUDIO CRIATIVO/ferramentas/video/otica/beyonce5.html, classe .lg):
  # fumê translúcido rgba(20,20,24,.34) sobre desfoque 22px com saturação 185%, brilho .2 no alto, conteúdo branco
  # (o logo vira a versão branca com os óculos verdes). Padrão desde 08/11 ("esta transparente, glass como no vídeo").
  TONES = {
    'vidro' => { fill: '#141418', veil: '40%', sat: 185, content_white: true, sheen: 0.2, blur: 22 },
    'branco' => { fill: 'white', veil: '80%', sat: 100, content_white: false, sheen: 0.38, blur: 16 },
    'verde' => { fill: '#1E7A4C', veil: '78%', sat: 100, content_white: true, sheen: 0.38, blur: 16 }
  }.freeze
  DEFAULT_TONE = 'vidro'.freeze

  # images: [{ bytes:, mime: }] (1 ou 2); logo: bytes PNG ou nil. Devolve { bytes:, mime: 'image/jpeg' }
  def self.compose(images:, logo: nil, tom: DEFAULT_TONE)
    new(images, logo, tom).compose
  end

  def initialize(images, logo, tom = DEFAULT_TONE)
    @images = images.first(2)
    @logo = logo
    @tone = TONES[tom.to_s] || TONES[DEFAULT_TONE]
    @temp = []
  end

  def compose
    raise ArgumentError, 'sem imagem' if @images.empty?

    base = @images.size == 2 ? pair : single
    base = logo_badge(base) if @logo
    out = temp('jpg')
    magick { |m| m << base << '-strip' << '-quality' << '90' << out }
    { bytes: File.binread(out), mime: 'image/jpeg' }
  ensure
    @temp.each { |f| f.close! rescue nil } # rubocop:disable Style/RescueModifier
  end

  private

  def half
    (WIDTH - GAP) / 2
  end

  # uma foto: 1080×1440, preenchendo tudo
  def single
    out = temp('png')
    magick do |m|
      m << write(@images[0]) << '-auto-orient' << '-resize' << "#{WIDTH}x1440^" << '-gravity' << 'center' << '-extent' << "#{WIDTH}x1440" << out
    end
    out
  end

  # duas fotos: lado a lado (1080×720), fio branco no meio
  def pair # rubocop:disable Metrics/AbcSize
    out = temp('png')
    magick do |m|
      m << '-size' << "#{WIDTH}x720" << 'xc:white'
      @images.each_with_index do |img, i|
        m << '(' << write(img) << '-auto-orient' << '-resize' << "#{half}x720^" << '-gravity' << 'center' << '-extent' << "#{half}x720" << ')'
        m << '-gravity' << 'northwest' << '-geometry' << "+#{i * (half + GAP)}+0" << '-composite'
      end
      m << out
    end
    out
  end

  # a marca da loja numa pílula embaixo, centralizada
  def logo_badge(base)
    w, h = MiniMagick::Image.open(base).dimensions
    bw = (w * GLASS[:width_ratio]).round
    bh = (bw * GLASS[:height_ratio]).round
    glass_at(base, x: (w - bw) / 2, y: h - bh - (w * GLASS[:bottom_ratio]).round, w: bw, h: bh,
                   content: write(bytes: @logo, mime: 'image/png'), logo: true,
                   box: "#{(bw * GLASS[:logo_w]).round}x#{(bh * GLASS[:logo_h]).round}")
  end

  # Pílula de vidro na receita do "Liquid Glass" claro aprovado nos vídeos
  # (ESTUDIO CRIATIVO/ferramentas/video/otica/beyonce5.html): o pedaço da foto desfocado com véu
  # (ver TONES) · brilho no terço de cima · borda em degradê diagonal (forte nas pontas, some no
  # meio) · sombra suave · logo centralizado. Devolve o caminho da nova base.
  def glass_at(base, x:, y:, w:, h:, content:, box:, logo: false) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists, Naming/MethodParameterName
    bw, bh = MiniMagick::Image.open(base).dimensions
    r = h / 2
    rr = "roundrectangle 0,0,#{w - 1},#{h - 1},#{r},#{r}"
    pill = temp('png')
    magick { |m| m << '-size' << "#{w}x#{h}" << 'xc:none' << '-fill' << 'white' << '-draw' << rr << pill }
    mask = temp('png')
    magick do |m|
      m << '-size' << "#{w}x#{h}" << 'xc:black' << '-fill' << 'none' << '-stroke' << 'white' << '-strokewidth' << '2.5' << '-draw' << rr
      m << '-fx' << 'u*(0.04+0.91*pow(abs((i/w+j/h)/2-0.5)*2,1.3))' << '-alpha' << 'off' << mask
    end
    ring = temp('png')
    magick { |m| m << '-size' << "#{w}x#{h}" << 'xc:white' << mask << '-alpha' << 'off' << '-compose' << 'CopyOpacity' << '-composite' << ring }
    glass = temp('png')
    magick do |m|
      m << base << '-crop' << "#{w}x#{h}+#{x}+#{y}" << '+repage' << '-alpha' << 'set'
      m << '-blur' << "0x#{@tone[:blur]}" << '-modulate' << "104,#{@tone[:sat]}" << '-fill' << @tone[:fill] << '-colorize' << @tone[:veil]
      m << '(' << '-size' << "#{w}x#{(h * 0.45).round}" << "gradient:rgba(255,255,255,#{@tone[:sheen]})-rgba(255,255,255,0)" << ')'
      m << '-gravity' << 'north' << '-compose' << 'Over' << '-composite'
      m << ring << '-compose' << 'Over' << '-composite'
      m << '(' << content << '-trim' << '+repage' << '-resize' << box
      # conteúdo branco no vidro escuro/verde; no logo, os óculos verde-claros da marca ficam verdes
      if @tone[:content_white]
        m << '-channel' << 'RGB' << '-fx' << (logo ? '(u.g>0.75&&u.r<0.3)?u:1' : '1') << '+channel'
      end
      m << ')'
      m << '-gravity' << 'center' << '-compose' << 'Over' << '-composite'
      m << pill << '-gravity' << 'northwest' << '-compose' << 'DstIn' << '-composite' << glass
    end
    out = temp('png')
    magick do |m|
      m << base
      m << '(' << '-size' << "#{bw}x#{bh}" << 'xc:none' << '-fill' << 'rgba(0,0,0,0.30)' \
        << '-draw' << "roundrectangle #{x + 6},#{y + 10},#{x + w - 6},#{y + h + 3},#{r},#{r}" << '-blur' << '0x10' << ')'
      m << '-gravity' << 'northwest' << '-compose' << 'Over' << '-composite'
      m << glass << '-geometry' << "+#{x}+#{y}" << '-compose' << 'Over' << '-composite' << out
    end
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
    f = Tempfile.new(['prova', ".#{ext}"], binmode: true)
    @temp << f
    f.path
  end

  def ext_of(mime)
    return 'png' if mime.to_s.include?('png')
    return 'webp' if mime.to_s.include?('webp')

    'jpg'
  end
end
