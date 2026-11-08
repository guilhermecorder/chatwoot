# 💬 TEXTO ESPAÇADO NO WHATSAPP (08/11/2026, pedido do Guilherme — o mesmo jeito da ótica):
# toda frase que termina em ponto, interrogação ou exclamação ganha uma linha em branco
# antes da próxima, como ele escreve:
#
#   "Recebi, obrigado! Vou montar o seu orçamento. Te mando segunda de manhã."
#   → "Recebi, obrigado!\n\nVou montar o seu orçamento.\n\nTe mando segunda de manhã."
#
# Não quebra número ("R$ 1.250", "10.5"), reticência no meio da frase, nem "Dr."/"Sra.".
# Liga por conta: ai_config['texto_espacado'] == true (LIFE liga pelo roteiro v3);
# sem a chave, nada muda (a CEVICO segue como está).
module Crm::TextSpacing
  module_function

  SENTENCE_END = /(?<!\bDr|\bDra|\bSr|\bSra|\bSrta|\bAv)([.!?…]["”')]?)[ \t]+(?=["“(]?[[:upper:]0-9])/

  def space(text)
    return text if text.blank?

    text.to_s.gsub(SENTENCE_END, "\\1\n\n").gsub(/\n{3,}/, "\n\n").strip
  end

  def enabled?(account)
    CrmSetting.find_by(account: account)&.ai_config&.dig('texto_espacado') == true
  end

  def for_account(account, text)
    enabled?(account) ? space(text) : text
  end
end
