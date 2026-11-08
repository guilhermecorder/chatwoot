# 🪞 LEITURA DO ROSTO (08/11/2026): o que a foto da cliente diz para o
# visagismo. Uma chamada só ao Gemini (a mesma leitura de imagem que já roda
# em toda foto recebida, Crm::MediaReadingService) devolve, além de tipo/
# descrição/texto, um bloco "rosto":
#   pessoas (quantas), frontal (de frente?), formato (oval/redondo/…),
#   usa_oculos (já está de óculos na foto?), adulto (parece adulto?),
#   qualidade (ok|ruim: escura, borrada, muito longe), observacao (1 frase)
# A prova virtual só roda com 1 pessoa, adulta, de frente e qualidade ok —
# fora disso o agente pede outra foto. Nada de diagnóstico, nada de saúde.
module Otica::FaceReading
  module_function

  TIPOS = %w[selfie receita oculos_atual print comprovante documento outro].freeze
  QUALIDADES = %w[ok ruim].freeze

  IMAGE_PROMPT = <<~TXT.freeze
    Você recebe uma imagem enviada por um cliente ao WhatsApp de uma ÓTICA (loja de óculos, português do Brasil).
    1) "tipo": classifique em UMA palavra: selfie | receita | oculos_atual | print | comprovante | documento | outro.
       selfie = foto em que aparece o rosto de uma pessoa (para experimentar armações).
       oculos_atual = foto de um óculos (sem rosto), receita = receita de óculos/grau.
    2) "descricao": em até 2 frases, o que a imagem mostra (sem diagnóstico, sem opinar sobre saúde).
    3) "texto": TODO o texto legível na imagem, copiado literalmente (graus, nomes, datas, valores). Vazio se não houver.
    4) "rosto": SÓ quando tipo = selfie (senão null), um objeto:
       {"pessoas": número de pessoas na foto,
        "frontal": true se o rosto principal está de frente ou quase (até 3/4),
        "formato": formato do rosto principal, UMA palavra: oval | redondo | quadrado | coracao | alongado | diamante | triangular,
        "usa_oculos": true se a pessoa já está de óculos na foto,
        "adulto": true se a pessoa principal aparenta ser adulta,
        "qualidade": "ok" ou "ruim" (ruim = escura, borrada, rosto muito pequeno ou cortado),
        "observacao": 1 frase simples sobre o rosto útil para escolher armação (ex.: "testa larga e queixo fino")}
    Responda SOMENTE com um JSON válido, sem comentários:
    {"tipo": "...", "descricao": "...", "texto": "...", "rosto": null}
  TXT

  # limpa o bloco "rosto" devolvido pelo Gemini (nada fora das listas entra)
  def normalize(raw)
    return nil unless raw.is_a?(Hash)

    formato = raw['formato'].to_s.strip.downcase
    formato = 'coracao' if formato == 'coração'
    {
      'pessoas' => raw['pessoas'].to_i,
      'frontal' => raw['frontal'] == true,
      'formato' => (Otica::Visagismo::FACE_SHAPES.key?(formato) ? formato : 'oval'),
      'usa_oculos' => raw['usa_oculos'] == true,
      'adulto' => raw['adulto'] != false,
      'qualidade' => (QUALIDADES.include?(raw['qualidade'].to_s) ? raw['qualidade'].to_s : 'ok'),
      'observacao' => raw['observacao'].to_s.strip.truncate(160)
    }
  end

  # a foto serve para a prova virtual? devolve [true, nil] ou [false, motivo
  # em palavras simples (para o agente pedir outra foto)]
  def usable(rosto) # rubocop:disable Metrics/CyclomaticComplexity
    return [false, 'a foto não mostra um rosto'] if rosto.blank?
    return [false, 'a foto está escura, borrada ou o rosto está muito pequeno; peça outra, de frente e com luz'] if rosto['qualidade'] == 'ruim'
    return [false, 'a foto tem mais de uma pessoa; peça uma foto só da cliente'] if rosto['pessoas'].to_i > 1
    return [false, 'a foto não mostra um rosto'] if rosto['pessoas'].to_i < 1
    return [false, 'o rosto não está de frente; peça uma foto olhando para a câmera'] unless rosto['frontal']
    return [false, 'a pessoa da foto parece menor de idade; a prova virtual é só para adultos'] unless rosto['adulto']

    [true, nil]
  end

  # linha curta que entra na CONVERSA que o agente lê
  def summary(rosto)
    return '' if rosto.blank?

    parts = ["rosto #{Otica::Visagismo.face_label(rosto['formato'])}"]
    parts << "#{rosto['pessoas']} pessoa(s)" if rosto['pessoas'].to_i != 1
    parts << (rosto['frontal'] ? 'de frente' : 'de lado')
    parts << 'já de óculos' if rosto['usa_oculos']
    parts << 'foto ruim' if rosto['qualidade'] == 'ruim'
    parts << 'parece menor de idade' unless rosto['adulto']
    parts.join(', ')
  end
end
