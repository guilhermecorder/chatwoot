require 'mini_magick'

# 📖 23/11/2026 (Guilherme: "se a gente não tem, a gente não pode pôr isso ali no menu… não podemos frustrá-la"):
# a prancha do CATÁLOGO DE ESTILOS é montada NA HORA, só com os estilos que a loja tem hoje com foto e saldo
# para aquele público (Otica::CatalogoEstilos.available). As peças (topo, um quadro por código, rodapé) saem de
# OTICA/nucleo-criativo/catalogo-estilos/montar.py → public/otica/catalogo/pecas/.
# Grade de 2 colunas; com número ímpar, o último quadro fica no meio. Altura = o que couber.
class Otica::CatalogoPrancha
  DIR = Rails.public_path.join('otica/catalogo/pecas')
  WIDTH = 1080
  TOP = 250
  FOOTER = 110
  GAP = 8
  TILE_W = 528
  TILE_H = 380

  def self.compose(publico, codes)
    new(publico, codes).compose
  end

  def self.installed?(publico, codes)
    [DIR.join("topo-#{publico}.jpg"), DIR.join('rodape.jpg'), *codes.map { |c| DIR.join("#{c}.jpg") }].all? { |p| File.exist?(p) }
  end

  def initialize(publico, codes)
    @publico = publico
    @codes = codes
  end

  # devolve o caminho de um JPG temporário com a prancha pronta
  def compose
    rows = (@codes.size + 1) / 2
    height = TOP + GAP + (rows * (TILE_H + GAP)) + FOOTER
    out = Tempfile.create(['catalogo-', '.jpg']).path
    MiniMagick::Tool::Magick.new do |m|
      m.size("#{WIDTH}x#{height}")
      m << 'xc:black'
      place(m, DIR.join("topo-#{@publico}.jpg"), 0, 0)
      @codes.each_with_index do |code, i|
        x, y = slot(i)
        place(m, DIR.join("#{code}.jpg"), x, y)
      end
      place(m, DIR.join('rodape.jpg'), 0, height - FOOTER)
      m.quality(88)
      m << out
    end
    out
  end

  private

  def slot(index)
    row = index / 2
    y = TOP + GAP + (row * (TILE_H + GAP))
    last_alone = @codes.size.odd? && index == @codes.size - 1
    x = last_alone ? (WIDTH - TILE_W) / 2 : GAP + ((index % 2) * (TILE_W + GAP))
    [x, y]
  end

  def place(magick, path, x, y) # rubocop:disable Naming/MethodParameterName
    magick << path.to_s
    magick.geometry("+#{x}+#{y}")
    magick.composite
  end
end
