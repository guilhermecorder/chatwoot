# 💰 UM SÓ jeito de ler dinheiro escrito à mão ou vindo de planilha
# (Rodada 5 da auditoria, achado #192).
#
# Antes cada caminho tinha a sua conta: o leitor do .xlsx de fechamento
# fazia Float('5.000') = 5.0 (R$ 5,00 em vez de R$ 5.000,00 — receita 1000×
# menor), enquanto a planilha do Google e a colagem de telefones já tinham
# sido consertadas cada uma do seu jeito. Agora os três chamam este aqui.
#
# Regra (padrão brasileiro):
#   - vírgula = centavos ("3900,5" → 3900.5; "5.000,00" → 5000.0);
#   - sem vírgula, ponto só é MILHAR quando vem em grupos de 3 dígitos
#     ("5.000" → 5000; "12.500" → 12500; "1.234.567" → 1234567);
#   - fora disso o ponto é decimal (número cru do Excel: "24187.8");
#   - aceita "R$", espaços (inclusive o espaço "duro" do Excel) e números
#     de verdade (3900, 3900.5);
#   - texto que não é dinheiro ("à combinar", "1,2,3") → nil. Melhor ficar
#     sem valor do que gravar um valor errado;
#   - centavos têm 1 ou 2 dígitos: "5,000" (milhar no jeito americano) → nil,
#     em vez de virar R$ 5,00.
# O modo loose (planilha do Google) é tolerante de propósito: junta os
# dígitos de TODO o texto, então textos com várias partes ("2x 2.500,00")
# podem dar valor errado. Para célula com anotação depois do número, use
# parse_with_note, que recusa quando sobra outro número no texto.
module Cevico::Money
  module_function

  MILHAR = /\A[1-9]\d{0,2}(?:\.\d{3})+\z/
  INTEIRO = /\A(?:\d+|[1-9]\d{0,2}(?:\.\d{3})+)\z/

  # Devolve Float com 2 casas, ou nil quando não dá para ler com segurança.
  # loose: true joga fora qualquer letra/símbolo antes (planilha do Google,
  # que sempre foi tolerante: "R$ 5.000,00 à vista" → 5000.0).
  def parse(raw, loose: false)
    return nil if raw.nil?
    return raw.to_f.round(2) if raw.is_a?(Numeric)

    # espaços saem ANTES do "R$", para "R $ 5.000" e "$ 5.000" também valerem
    text = raw.to_s.gsub(/[[:space:]]/, '').sub(/\A(-?)r?\$/i, '\\1').sub(/r?\$\z/i, '')
    text = text.gsub(/[^\d,.-]/, '') if loose
    negative = text.start_with?('-')
    text = text.delete_prefix('-')
    return nil unless text.match?(/\A\d[\d.,]*\z/)

    number = to_number(text)
    return nil if number.nil?

    (negative ? -number : number).round(2)
  end

  # Célula com ANOTAÇÃO depois do número ("5.000,00 (pago)", "R$ 3.900 à
  # vista"): lê só o número do começo. Se sobrar OUTRO número no resto
  # ("2x 2.500,00", "1.500 - 2.000"), não dá para saber qual é o valor → nil.
  NOTA = /\A[[:space:]]*(-?[[:space:]]*(?:r[[:space:]]*)?\$?[[:space:]]*-?\d[\d.,]*)(.*)\z/im

  def parse_with_note(raw)
    return parse(raw) unless raw.is_a?(String)

    match = raw.match(NOTA)
    return nil if match.nil? || match[2].match?(/\d/)

    parse(match[1])
  end

  def to_number(text)
    if text.include?(',')
      with_comma(text)
    elsif text.match?(MILHAR)
      text.delete('.').to_f
    elsif text.match?(/\A\d+(?:\.\d+)?\z/)
      text.to_f
    end
  end

  # "3.900,50" / "3900,5": uma vírgula só, centavos com 1 ou 2 dígitos e,
  # antes dela, número inteiro com ou sem pontos de milhar
  def with_comma(text)
    inteiro, centavos, sobra = text.split(',', -1)
    return nil if sobra || !centavos.to_s.match?(/\A\d{1,2}\z/) || !inteiro.match?(INTEIRO)

    "#{inteiro.delete('.')}.#{centavos}".to_f
  end
end
