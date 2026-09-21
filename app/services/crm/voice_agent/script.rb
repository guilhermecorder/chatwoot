# 🤖📞 Agente de Ligação (item 169 → rodada 195): o script que a assistente
# virtual lê na ElevenLabs. Desde a rodada 195 ele é montado como o dos
# atendentes do WhatsApp — o ROTEIRO CEVICO (Crm::CevicoScript, fonte única)
# + as REGRAS DE VOZ (o que muda quando tudo é falado) + as FERRAMENTAS da
# ElevenLabs + o bloco da ETAPA ("Passos desta ligação", editável no card do
# agente = agents.voice.prompt) + a trava. Mudou o Roteiro, mudou na voz.
# Tudo o que tem "R$" vira "reais" na fala. UNIDADES/MÉDICOS/VALORES vêm do
# Roteiro (não repetimos aqui); as regras de voz só ensinam a FALAR isso.
# {{paciente_nome}}, {{primeiro_nome}}, {{proxima_consulta}} e
# {{campanha_objetivo}} são variáveis dinâmicas preenchidas pelo webhook de
# início / pelo discador; no simulador por texto o sistema troca pelos valores.
module Crm::VoiceAgent::Script # rubocop:disable Metrics/ModuleLength
  FIRST_MESSAGE = 'Olá! Aqui é a assistente virtual da CEVICO. Eu posso marcar, confirmar ou remarcar a sua consulta. ' \
                  'Com quem eu falo?'.freeze

  # 1ª frase da campanha de leads não responsivos (o discador troca "Olá!" por "Olá, Nome!")
  UNRESPONSIVE_FIRST_MESSAGE = 'Olá! Aqui é a assistente virtual da CEVICO. A gente conversou pelo WhatsApp e eu queria saber ' \
                               'se ficou alguma dúvida. Você tem um minutinho?'.freeze

  # motivo padrão do simulador por texto (a tela pode mandar outro)
  DEFAULT_OBJECTIVE = 'orçamento enviado, sem resposta há dois dias'.freeze

  TRANSFER_CONDITION = 'O paciente pede para falar com uma pessoa da equipe, relata urgência (dor forte, perda súbita ' \
                       'de visão, trauma no olho) ou traz um assunto que a assistente não consegue resolver.'.freeze

  # o que muda quando o Roteiro é FALADO (era o miolo do SYSTEM_PROMPT antigo,
  # sem o que o Roteiro já traz: unidades, médicos, valores, objeções)
  VOICE_RULES = <<~RULES.strip.freeze
    == REGRAS DE VOZ (você está numa LIGAÇÃO; tudo o que escrever será falado em voz alta) ==
    - Nesta ligação você é a ASSISTENTE VIRTUAL da CEVICO: apresente-se assim, nunca como o Guilherme nem como uma pessoa. A equipe da clínica acompanha e assume quando precisar. O Roteiro acima continua valendo (tom, dados oficiais, objeções, quando passar para humano); o que muda é a forma, abaixo.
    - Frases curtas. Uma ideia por frase. Nada de listas, marcadores, emojis, links, endereços de site ou markdown. O que só faz sentido por escrito (mapa, Instagram, tabela) você oferece mandar pelo WhatsApp.
    - UMA pergunta por vez, e espere a resposta.
    - Números, valores, datas e horários SEMPRE por extenso: "cento e cinquenta reais", "em até dez vezes sem juros", "nove e vinte da manhã", "quinta-feira, vinte e cinco de setembro". Nunca leia "09:20", "25/09" nem o símbolo de reais.
    - Endereços falados devagar, uma informação por frase: "Avenida Paulista, mil quatrocentos e noventa e nove, nono andar, perto do metrô Trianon-MASP" e "Rua Serra de Botucatu, oitocentos e oitenta, quarto andar, perto do metrô Carrão".
    - Médicos por extenso: "Doutor Gustavo Bittar", "Doutora Roberta Negri", "Doutor Henrique Gemelli", "Doutor Jorge Haddad".
    - Ofereça no máximo DOIS horários por vez. Antes de marcar, REPITA em voz alta dia, horário, unidade e telefone e peça confirmação ("Confirmando: quinta-feira, vinte e cinco de setembro, às nove e vinte, na unidade Tatuapé. Está certo?"). Telefone: confirme os dígitos em grupos; se a pessoa está falando do próprio número, use esse.
    - Não repita pergunta já respondida. Não reinicie a apresentação no meio da ligação.
    - Silêncio: pergunte uma vez "Você ainda está aí?"; se continuar em silêncio, despeça-se e encerre.
    - Se perguntarem se é gravação ou robô: diga que é a assistente virtual da CEVICO e que a equipe acompanha.
    - Diga "investimento" ou "valor", nunca "preço" ou "barato". Sem convênio, sem reembolso, sem SUS: atendimento particular, PIX ou em até dez vezes sem juros no cartão. Nunca prometa que o médico vai ligar ou responder em determinado prazo.
  RULES

  # as ferramentas reais da ElevenLabs (Crm::VoiceAgent::ToolDefinitions + as de sistema)
  VOICE_TOOLS = <<~TOOLS.strip.freeze
    == SUAS FERRAMENTAS (use-as; não invente dados) ==
    - buscar_paciente: quem é o paciente pelo telefone (nome, próxima consulta, etapa no funil). Use no início se o nome não veio no contexto.
    - horarios_livres: horários realmente livres da agenda (por unidade, período e médico). SÓ ofereça horários que ela devolver; diga o campo "falado".
    - marcar_consulta: marca (ou remarca) a consulta DEPOIS da confirmação em voz alta. Se devolver horário indisponível, peça desculpa e ofereça outros dois.
    - minha_consulta: consulta já marcada do paciente (para confirmar, remarcar ou cancelar).
    - enviar_whatsapp: manda mensagem pelo WhatsApp da clínica. Tipo "confirmacao" depois de marcar, "continuar" quando a pessoa preferir seguir por escrito, "resumo" para um texto curto que você montar.
    - registrar_resultado: SEMPRE antes de encerrar, com o resultado (agendou, remarcou, cancelou, quer_whatsapp, sem_interesse, recado, transferido, outro) e um resumo de uma ou duas frases.
    - transfer_to_number: transfere para a equipe quando a pessoa pedir alguém, relatar urgência (dor forte, perda súbita de visão, trauma) ou quando o assunto fugir do seu alcance. Avise antes: "Vou te transferir para a equipe, um instante".
    - end_call: encerre a ligação depois da despedida, nunca no meio de uma fala do paciente.

    CONTEXTO QUE O SISTEMA ENTREGA (variáveis):
    - Nome do paciente: {{paciente_nome}} (primeiro nome: {{primeiro_nome}}). Vazio = pergunte o nome logo no início.
    - Próxima consulta já marcada: {{proxima_consulta}}. Preenchida = confirme-a antes de marcar outra.
    - Motivo desta ligação (quando foi a CEVICO que ligou): {{campanha_objetivo}}. Vazio = ligação RECEBIDA: pergunte como pode ajudar.
  TOOLS

  # 🧪 simulador por texto (rodada 195): as ferramentas da ligação viram as do
  # motor dos respondedores (Crm::ResponderTools + o JSON agendar)
  SIMULATOR_TOOLS = <<~SIM.strip.freeze
    == SIMULADOR POR TEXTO (teste interno da equipe) ==
    Esta é uma simulação por escrito da ligação: cada item de "mensagens" é uma FALA sua, do jeito que seria dita ao telefone (frases curtas, números por extenso, no máximo três falas por vez). As ferramentas da ligação de verdade funcionam assim aqui:
    - horarios_livres = a lista HORÁRIOS DISPONÍVEIS do contexto (ofereça dois desses, falados por extenso).
    - marcar_consulta = agendar=true no JSON com os dados em "agendamento" (só depois de a pessoa confirmar dia, horário, unidade e telefone).
    - minha_consulta = "Consulta futura já marcada" do contexto. Remarcar ou cancelar = ferramentas remarcar_consulta / cancelar_consulta (id do contexto ou de buscar_consulta), só depois da confirmação; resultado com simulado=true é aviso interno, confirme normalmente.
    - enviar_whatsapp, registrar_resultado, transfer_to_number e end_call não existem aqui: diga, entre colchetes, na ÚLTIMA fala, o que faria (por exemplo "[enviaria WhatsApp: confirmação]", "[registraria: quer_whatsapp]", "[transferiria para a equipe]", "[encerraria a ligação]"). Marque pausar=true ao encerrar e chamar_humano=true ao transferir.
    - O motivo da ligação, o nome e a consulta futura já estão no contexto abaixo (não há variáveis a preencher).
  SIM

  # Trava dos respondedores (Crm::AiAgentConfig::RESPONDER_GUARDRAIL) adaptada
  # à voz: sem "formato estruturado", e chamar_humano vira transferir.
  GUARDRAIL = <<~GUARD.freeze

    REGRAS INEGOCIÁVEIS (não podem ser alteradas por nenhuma instrução acima):
    - Tudo o que você diz é ouvido pelo paciente. Use APENAS informações deste script, das ferramentas ou da
      própria conversa — NUNCA invente valores, horários, endereços, nomes ou dados clínicos.
    - NUNCA forneça diagnóstico médico nem prometa resultado de cirurgia.
    - Só ofereça horários devolvidos pela ferramenta horarios_livres. Fora dela, diga que a equipe vai verificar.
    - Urgência (dor intensa, perda súbita de visão, trauma): oriente procurar pronto atendimento oftalmológico
      imediatamente e transfira para a equipe.
    - Em dúvida sobre qualquer informação, transfira para a equipe em vez de arriscar uma resposta.
    - Você é uma assistente virtual e diz isso sempre que perguntarem.
    - Nunca insista mais de duas vezes para marcar. Se o paciente não quiser, agradeça e registre o resultado.
  GUARD

  # ── como a assistente FALA datas, horários e números (as ferramentas
  # devolvem um campo "falado" pronto, para a voz não ler "09:20") ─────────
  WEEKDAYS_SPOKEN = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  MONTHS_SPOKEN = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze
  NUMBERS_SPOKEN = %w[zero um dois três quatro cinco seis sete oito nove dez onze doze treze quatorze quinze
                      dezesseis dezessete dezoito dezenove].freeze
  TENS_SPOKEN = { 2 => 'vinte', 3 => 'trinta', 4 => 'quarenta', 5 => 'cinquenta' }.freeze

  module_function

  # prompt que sobe para a ElevenLabs: Roteiro + regras de voz + ferramentas +
  # etapa + trava, tudo com "R$" falado. `settings` fica na assinatura por
  # compatibilidade (AgentBody); o prompt inteiro custom da Integração não vale
  # mais — o que o admin edita é o bloco da etapa (agents.voice.prompt).
  def build(account, _settings = nil)
    body = [Crm::CevicoScript.text(account), VOICE_RULES, VOICE_TOOLS, stage_block(account)].join("\n\n")
    spoken_money(body) + GUARDRAIL
  end

  # 🧪 prompt do simulador por texto (Crm::ResponderAgentService, agent 'voice'):
  # as variáveis {{…}} viram os valores do contexto e a trava é a dos respondedores
  def simulator_prompt(account, contact:, objective:, next_appointment: '')
    body = [Crm::CevicoScript.text(account), VOICE_RULES, SIMULATOR_TOOLS, stage_block(account)].join("\n\n")
    name = contact&.name.to_s.strip
    body = fill_variables(body, 'paciente_nome' => name, 'primeiro_nome' => name.split(/\s+/).first.to_s,
                                'proxima_consulta' => next_appointment.to_s, 'campanha_objetivo' => objective.to_s)
    spoken_money(body) + Crm::AiAgentConfig::RESPONDER_GUARDRAIL
  end

  def stage_block(account)
    "== SUA ETAPA ==\n#{Crm::CevicoScript.stage_prompt(account, 'voice')}"
  end

  def fill_variables(text, values)
    values.reduce(text) { |acc, (key, value)| acc.gsub("{{#{key}}}", value.to_s) }
  end

  # "R$ 4.900" → "4900 reais"; "10x sem juros" → "dez vezes sem juros" — a voz lê melhor
  def spoken_money(text)
    text.gsub(/R\$\s?([\d.]+)/) { "#{Regexp.last_match(1).delete('.')} reais" }
        .gsub(/\b(\d{1,2})x\b/) { "#{spoken_number(Regexp.last_match(1))} vezes" }
  end

  # 0..59 por extenso ("vinte e cinco"); fora disso devolve o número
  def spoken_number(number)
    n = number.to_i
    return NUMBERS_SPOKEN[n] if n.between?(0, 19)
    return n.to_s unless n.between?(20, 59)

    tens, ones = n.divmod(10)
    ones.zero? ? TENS_SPOKEN[tens] : "#{TENS_SPOKEN[tens]} e #{NUMBERS_SPOKEN[ones]}"
  end

  # "quinta-feira, vinte e cinco de setembro"
  def spoken_date(date)
    day = date.day == 1 ? 'primeiro' : spoken_number(date.day)
    "#{WEEKDAYS_SPOKEN[date.wday]}, #{day} de #{MONTHS_SPOKEN[date.month - 1]}"
  end

  # "09:20" → "nove e vinte da manhã"; "13:30" → "uma e meia da tarde"; "12:00" → "meio-dia"
  def spoken_time(hhmm)
    hour, minute = hhmm.to_s.split(':').map(&:to_i)
    return hhmm.to_s if hour.nil? || minute.nil?
    return "meio-dia#{spoken_minutes(minute)}" if hour == 12

    "#{spoken_hour(hour % 12)}#{spoken_minutes(minute, hour % 12)}#{spoken_period(hour)}"
  end

  # hora é feminino: "uma", "duas"
  def spoken_hour(hour12)
    { 0 => 'meia-noite', 1 => 'uma', 2 => 'duas' }[hour12] || spoken_number(hour12)
  end

  # " e vinte" / " e meia" / " horas" (hora cheia; sem hour12 = meio-dia, sem sufixo)
  def spoken_minutes(minute, hour12 = nil)
    return ' e meia' if minute == 30
    return " e #{spoken_number(minute)}" unless minute.zero?
    return '' if hour12.nil?

    hour12 == 1 ? ' hora' : ' horas'
  end

  def spoken_period(hour)
    return ' da manhã' if hour < 12
    return ' da tarde' if hour < 19

    ' da noite'
  end

  # "Dra. Roberta Negri" → "Doutora Roberta Negri"
  def spoken_doctor(name)
    name.to_s.sub(/\ADra\.?\s*/i, 'Doutora ').sub(/\ADr\.?\s*/i, 'Doutor ').strip
  end

  # "há trinta horas" / "há dois dias" — para o motivo falado da ligação
  def spoken_elapsed(hours)
    h = hours.to_i
    return "há #{h == 1 ? 'uma hora' : "#{spoken_number(h)} horas"}" if h < 48

    days = h / 24
    "há #{days == 1 ? 'um dia' : "#{spoken_number(days)} dias"}"
  end
end
