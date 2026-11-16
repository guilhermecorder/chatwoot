# 🧹 SEM DIMINUTIVO E SEM FRASE PASSIVA (LIFE, 16/11/2026 · Guilherme: "tire sempre todas as palavras do diminutivo. Eu
# odeio ficar falando no diminutivo" + tom firme, nada de "se ficou dúvida…").
# O roteiro (v23) já proíbe, mas no dia em que entrou a IA ainda escreveu "vou confirmar certinho" e "qualquer dúvida que
# surgir é só me chamar aqui". Esta é a trava final: limpa o texto ANTES de ir para o cliente.
#
#   Crm::PlainWords.clean("Vou confirmar certinho com o Anderson. Qualquer dúvida é só me chamar!")
#   → "Vou confirmar com o Anderson."
#   Crm::PlainWords.clean("Qualquer dúvida que surgir é só me chamar aqui.") → "" (o balão inteiro sai)
#
# Liga por conta: ai_config['sem_diminutivo'] == true (a LIFE liga no console); sem a chave, nada muda (CEVICO igual).
module Crm::PlainWords
  module_function

  # diminutivo → palavra normal (a forma com "s" vem junto)
  SWAPS = {
    'rapidinho' => 'rápido', 'rapidinha' => 'rápida', 'minutinho' => 'minuto', 'tempinho' => 'tempo',
    'instantinho' => 'instante', 'pouquinho' => 'pouco', 'pouquinha' => 'pouca', 'agorinha' => 'agora', 'cedinho' => 'cedo',
    'pertinho' => 'perto', 'coisinha' => 'coisa', 'perguntinha' => 'pergunta', 'fotinha' => 'foto', 'continha' => 'conta'
  }.freeze
  SWAP_RE = /\b(#{SWAPS.keys.join('|')})(s?)\b/i
  # "certinho"/"direitinho" só enfeitam: "tudo certinho" vira "tudo certo"; no resto, a palavra sai
  CERTO_RE = /\b(tudo|está|esta|tá|ta|fica|ficou|deu|dá|da)\s+(certinh|direitinh)([oa])(s?)\b/i
  ENFEITE_RE = /[ \t]*,?[ \t]*\b(?:certinh|direitinh)[oa]s?\b/i
  # frase passiva de despedida: a frase inteira sai
  PASSIVA_RE = /
    (?:qualquer\s+(?:dúvida|duvida|coisa)[^.!?…]*\b(?:cham\w*|fal\w*|avis\w*|aqui|disposição)\b|
       se\s+(?:ficou|ficar|tiver|surgir)\s+(?:alguma\s+)?(?:dúvida|duvida)|
       fico\s+no\s+aguardo|fico\s+à\s+disposição|estou\s+à\s+disposição|estou\s+por\s+aqui|sigo\s+à\s+disposição)
  /xi
  SENTENCE = /[^.!?…\n]*[.!?…]+["”')]?|[^.!?…\n]+$/

  def enabled?(account)
    CrmSetting.find_by(account: account)&.ai_config&.dig('sem_diminutivo') == true
  end

  def clean(text)
    return text if text.blank?

    out = text.to_s.gsub(CERTO_RE) { "#{Regexp.last_match(1)} cert#{Regexp.last_match(3)}#{Regexp.last_match(4)}" }
    out = out.gsub(ENFEITE_RE, '')
    out = out.gsub(SWAP_RE) { keep_case(Regexp.last_match(1), SWAPS[Regexp.last_match(1).downcase]) + Regexp.last_match(2) }
    drop_passive(out)
  end

  # tira só a frase passiva; o resto do balão fica (com as linhas em branco do jeito que estavam)
  def drop_passive(text)
    text.split(/(\n+)/).map do |part|
      next part if part.start_with?("\n")

      part.scan(SENTENCE).grep_v(PASSIVA_RE).join.strip
    end.join.gsub(/\n{3,}/, "\n\n").strip
  end

  def keep_case(original, word)
    original[0] == original[0].upcase ? word.capitalize : word
  end
end
