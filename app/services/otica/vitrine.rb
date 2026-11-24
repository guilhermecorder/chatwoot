# 🏆 VITRINE DOS MAIS VENDIDOS (24/11/2026, pedido do Guilherme: "ele está usando só armações feias, pesadas,
# que não vendem… pegar os modelos mais vendidos, tanto masculino quanto feminino… a gente não deve mais acessar
# 100% do nosso banco").
#
# Como funciona:
# - QUEM ENTRA na prova é a chavinha "Na prova virtual" do produto (try_on). Desde 24/11 ela fica ligada SÓ nas
#   armações das grifes campeãs de venda; as outras continuam no estoque, fora da prova e do catálogo de estilos.
#   Nada aqui busca fora da vitrine: sem opção boa nela, a prova manda a mais próxima ou convida pra loja.
# - A ORDEM dentro da vitrine leva em conta o quanto cada grife vende (este módulo): entre armações que combinam
#   igual com o rosto, a de grife que mais vende vem primeiro (Charmy e Roma na frente).
#
# Fonte: SavWin → Relatórios de Vendas → Curva ABC por produto, loja 0001, 24/11/2025 a 24/11/2026; armações de
# grau (linhas ACETATO e METAL) = 527 peças. Cada modelo vende pouco (no máximo 7 no ano, 1 por cor), por isso o
# campeão é a GRIFE. Refazer todo mês (OTICA/docs/VITRINE-MAIS-VENDIDOS-2026-11-24.md).
module Otica::Vitrine
  module_function

  # peças vendidas em 12 meses, por grife (as 8 primeiras = 91% das armações vendidas)
  GRIFES = {
    'CHARMY' => 214, 'ROMA' => 88, 'MX' => 55, 'JEAN MARCELL' => 32,
    'MAF' => 30, 'SUBLIME' => 27, 'ATITUDE' => 18, 'DETROIT' => 14
  }.freeze
  ATUALIZADO_EM = '24/11/2026'.freeze
  # bônus máximo na pontuação do visagismo (a grife nº 1), pela RAIZ das vendas: Charmy 0,6 · Roma 0,38 · MX 0,30 ·
  # Jean Marcell 0,23 · MAF 0,22 · Sublime 0,21 · Atitude 0,17 · Detroit 0,15. É um empurrão, não uma trava: o
  # degrau entre duas posições de formato é 0,3 e o sorteio por conversa vai até 0,29, então o formato do rosto
  # continua mandando e cada cliente ainda vê opções diferentes (nada de a mesma Charmy pra todo mundo).
  MAX_BONUS = 0.6

  # "Jean Marcell" / "jean marcell " → "JEAN MARCELL"
  def grife_of(product)
    product.brand.to_s.strip.upcase.squeeze(' ')
  end

  def campea?(product)
    GRIFES.key?(grife_of(product))
  end

  def vendidas(product)
    GRIFES[grife_of(product)].to_i
  end

  # 0 (grife fora do ranking) a MAX_BONUS (a que mais vende)
  def bonus(product)
    top = GRIFES.values.max.to_f
    return 0.0 if top <= 0

    (MAX_BONUS * Math.sqrt(vendidas(product) / top)).round(3)
  end
end
