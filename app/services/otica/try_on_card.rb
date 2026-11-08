require 'mini_magick'

# 🪞 CARTÃO DA PROVA VIRTUAL (08/11/2026, pedido do Guilherme): a foto gerada ocupa
# a imagem inteira, sem moldura, e a marca da loja (logo verde) fica POR CIMA, num
# selo de vidro fosco estilo "Liquid Glass" (o fundo desfocado aparece através,
# cantos arredondados, borda e brilho finos). Com 2 fotos (de frente e de 3/4) elas
# ficam lado a lado, separadas por um fio branco. Sem texto: a legenda vai na
# mensagem e a imagem do servidor não tem fontes. O selo é uma pílula embaixo,
# centralizada e pequena (≈ 1/5 da largura), para não atrapalhar a foto.
#
# Tamanhos: 1 foto = 1080×1440 (3:4, igual à geração); 2 fotos = 1080×720.
# Composição com o ImageMagick da imagem (MiniMagick), tudo em arquivos temporários.
class Otica::TryOnCard
  WIDTH = 1080
  GAP = 4
  GLASS = { width_ratio: 0.21, height_ratio: 0.40, bottom_ratio: 0.035, logo_w: 0.62, logo_h: 0.56, blur: 16 }.freeze
  # 08/11 (Guilherme: "o contraste do logo não ficou bom"): o vidro ganha um tom forte por trás do logo.
  # branco = vidro forçado pro branco + logo verde original · verde = vidro no verde da marca + logo em branco
  TONES = {
    'branco' => { fill: 'white', veil: '80%', sat: 100, logo_white: false },
    'verde' => { fill: '#1E7A4C', veil: '78%', sat: 100, logo_white: true }
  }.freeze
  DEFAULT_TONE = 'branco'.freeze

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
    base = glass_badge(base) if @logo
    out = temp('jpg')
    magick { |m| m << base << '-strip' << '-quality' << '90' << out }
    { bytes: File.binread(out), mime: 'image/jpeg' }
  ensure
    @temp.each { |f| f.close! rescue nil } # rubocop:disable Style/RescueModifier
  end

  private

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
    half = (WIDTH - GAP) / 2
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

  # o selo de vidro (pílula) com o logo verde, embaixo e centralizado, pequeno pra não atrapalhar a foto.
  # Receita do "Liquid Glass" claro aprovado nos vídeos (ESTUDIO CRIATIVO/ferramentas/video/otica/beyonce5.html):
  # véu branco · desfoque 16px + brilho 1,12 · borda em degradê diagonal (forte nas pontas,
  # some no meio) · brilho no terço de cima · sombra 0 12px 32px. O véu é forte (ver TONES) para o logo ter contraste
  # em qualquer roupa; o desfoque da foto ainda aparece através, por isso continua "vidro".
  def glass_badge(base) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    w, h = MiniMagick::Image.open(base).dimensions
    bw = (w * GLASS[:width_ratio]).round
    bh = (bw * GLASS[:height_ratio]).round
    x = (w - bw) / 2
    y = h - bh - (w * GLASS[:bottom_ratio]).round
    r = bh / 2
    rr = "roundrectangle 0,0,#{bw - 1},#{bh - 1},#{r},#{r}"
    pill = temp('png')
    magick { |m| m << '-size' << "#{bw}x#{bh}" << 'xc:none' << '-fill' << 'white' << '-draw' << rr << pill }
    # borda: anel de 2,5px com alfa em degradê diagonal (0,95 nas pontas → 0,04 no meio)
    ring = temp('png')
    mask = temp('png')
    magick do |m|
      m << '-size' << "#{bw}x#{bh}" << 'xc:black' << '-fill' << 'none' << '-stroke' << 'white' << '-strokewidth' << '2.5' << '-draw' << rr
      m << '-fx' << 'u*(0.04+0.91*pow(abs((i/w+j/h)/2-0.5)*2,1.3))' << '-alpha' << 'off' << mask
    end
    magick { |m| m << '-size' << "#{bw}x#{bh}" << 'xc:white' << mask << '-alpha' << 'off' << '-compose' << 'CopyOpacity' << '-composite' << ring }
    glass = temp('png')
    magick do |m|
      m << base << '-crop' << "#{bw}x#{bh}+#{x}+#{y}" << '+repage' << '-alpha' << 'set'
      m << '-blur' << "0x#{GLASS[:blur]}" << '-modulate' << "108,#{@tone[:sat]}" << '-fill' << @tone[:fill] << '-colorize' << @tone[:veil]
      # brilho no terço de cima
      m << '(' << '-size' << "#{bw}x#{(bh * 0.45).round}" << 'gradient:rgba(255,255,255,0.38)-rgba(255,255,255,0)' << ')'
      m << '-gravity' << 'north' << '-compose' << 'Over' << '-composite'
      m << ring << '-compose' << 'Over' << '-composite'
      # o logo: verde original no vidro branco; branco no vidro verde
      logo_box = "#{(bw * GLASS[:logo_w]).round}x#{(bh * GLASS[:logo_h]).round}"
      m << '(' << write(bytes: @logo, mime: 'image/png') << '-trim' << '+repage' << '-resize' << logo_box
      m << '-fill' << 'white' << '-colorize' << '100%' if @tone[:logo_white]
      m << ')'
      m << '-gravity' << 'center' << '-compose' << 'Over' << '-composite'
      m << pill << '-gravity' << 'northwest' << '-compose' << 'DstIn' << '-composite' << glass
    end
    out = temp('png')
    magick do |m|
      m << base
      m << '(' << '-size' << "#{w}x#{h}" << 'xc:none' << '-fill' << 'rgba(0,0,0,0.38)' \
        << '-draw' << "roundrectangle #{x + 8},#{y + 14},#{x + bw - 8},#{y + bh + 4},#{r},#{r}" << '-blur' << '0x14' << ')'
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
