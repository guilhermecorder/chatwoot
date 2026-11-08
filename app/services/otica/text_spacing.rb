# 💬 TEXTO ESPAÇADO NO WHATSAPP DA ÓTICA (08/11/2026, pedido do Guilherme): toda frase
# que termina em ponto, interrogação ou exclamação ganha uma linha em branco antes da
# próxima, como ele escreve:
#
#   "Recebi sua foto! Já estou montando. Em alguns segundos te mando."
#   → "Recebi sua foto!\n\nJá estou montando.\n\nEm alguns segundos te mando."
#
# Não quebra número ("R$ 1.250"), reticência no meio de frase, nem "Dr."/"Sra.".
# Vale só no ramo ótica (a CEVICO segue como está).
module Otica::TextSpacing
  module_function

  SENTENCE_END = /(?<!\bDr|\bDra|\bSr|\bSra|\bSrta)([.!?…]["”')]?)[ \t]+(?=["“(]?[[:upper:]0-9])/

  def space(text)
    return text if text.blank?

    text.to_s.gsub(SENTENCE_END, "\\1\n\n").gsub(/\n{3,}/, "\n\n").strip
  end

  # aplica só quando a conta é do ramo ótica
  def for_account(account, text)
    Otica::VirtualTryOn.otica?(account) ? space(text) : text
  end
end
