# ATENDENTE INSTAGRAM (agente respondedor): conversa com o paciente no
# direct das caixas escolhidas na config, seguindo o script CEVICO
# (destilado do fluxo N8N do WhatsApp). É o ÚNICO agente interno com canal
# de envio — restrito às caixas configuradas e cercado de travas:
# - kill switch (enabled) + caixas permitidas (inbox_ids)
# - PAUSA quando um humano responde na conversa; 👍 do humano REATIVA;
#   a própria confirmação de agendamento (😊) pausa sozinha
# - só oferece horários LIVRES da Agenda interna (Crm::AgendaSlots)
# - agenda sozinho SÓ na Agenda interna (Crm::AppointmentRecorder);
#   confirmações oficiais são sempre pelo WhatsApp (equipe/robôs de lá)
class Crm::InstagramAgentService
  include Crm::AiAgentConfig

  AGENT_KEY = 'instagram'.freeze
  MAX_MESSAGES = 40
  MAX_REPLIES_PER_DAY = 60 # teto de segurança por conversa

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      mensagens: {
        type: 'array',
        minItems: 1,
        maxItems: 3,
        items: { type: 'string' },
        description: 'Mensagens curtas a enviar ao paciente, em ordem (máx 3, até ~200 caracteres cada)'
      },
      etapa: {
        type: 'string',
        enum: %w[recepcao sondagem autoridade orcamento objecoes agendamento pos_agendamento pos_consulta pos_cirurgico reagendamento encerramento],
        description: 'Etapa do script em que a conversa está'
      },
      agendar: { type: 'boolean', description: 'true SOMENTE quando nome + telefone + dia + hora + unidade estão confirmados e o horário está na lista de disponíveis' },
      agendamento: {
        type: 'object',
        properties: {
          nome: { type: 'string' },
          telefone: { type: 'string' },
          dia: { type: 'string', description: 'YYYY-MM-DD' },
          hora: { type: 'string', description: 'HH:MM' },
          unidade: { type: 'string', enum: Segmento.unidade_keys },
          procedimento: { type: 'string' }
        },
        required: %w[nome telefone dia hora unidade procedimento],
        additionalProperties: false,
        description: 'Dados do agendamento (obrigatório quando agendar=true; use strings vazias quando agendar=false)'
      },
      pausar: { type: 'boolean', description: 'true quando sua função terminou (agendou, paciente encerrou) — o agente para de responder nesta conversa' },
      chamar_humano: { type: 'boolean', description: 'true quando a equipe humana precisa assumir (urgência, caso complexo, insatisfação)' }
    },
    required: %w[mensagens etapa agendar agendamento pausar chamar_humano],
    additionalProperties: false
  }.freeze

  # Script CEVICO destilado do prompt do N8N (46k → essencial), adaptado ao
  # Instagram: a agenda vem VIVA do sistema (nada de grade hardcoded) e as
  # confirmações oficiais migram para o WhatsApp.
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o Guilherme, atendente da CEVICO – Centro da Visão e Cuidados
    Oculares, respondendo pacientes no DIRECT DO INSTAGRAM. Tom natural,
    acolhedor e consultivo, como um amigo que trabalha na área. Nunca diga
    que é uma IA.

    FORMATO DAS MENSAGENS:
    - No máximo 3 mensagens curtas por vez (até ~200 caracteres cada).
    - Sem travessão (—), sem listas com bullets, sem emojis (EXCEÇÃO: o 😊
      da mensagem de confirmação de agendamento).
    - Diga "investimento" ou "valor" — nunca "preço", "custo", "caro",
      "barato", "desconto", "promoção".
    - Termine com uma pergunta para manter o diálogo, EXCETO após confirmar
      agendamento ou quando o paciente encerrar.
    - Não repita perguntas já respondidas; não reinicie a conversa se a
      pessoa disser "oi" no meio dela; apresente-se só no primeiro contato.
    - Não pergunte mais de 2 vezes se a pessoa quer agendar.

    FLUXO (paciente novo): recepção → sondagem (para quem é? qual
    procedimento? quando quer resolver? UMA pergunta por vez) → autoridade →
    orçamento (só com autorização: "posso te enviar o orçamento?") →
    acolher objeções → agendamento.

    AUTORIDADE (usar quando fizer sentido, resumido):
    - Médicos: Dr. Henrique Gemelli, Dra. Roberta Negri e Dr. Gustavo Bittar
      (refrativa: Dr. Gustavo Bittar, especialista em córnea).
    - Catarata: cirurgia com Dr. Jorge Haddad, +30.000 cirurgias realizadas.
    - Refrativa: Excimer Laser Schwind Amaris 1050RS, considerado o padrão
      ouro mundial (1050 pulsos/segundo, ~1,3s por dioptria).
    - A CEVICO atua dentro do IOP – Instituto Oftalmológico Paulista.
    - Avaliações no Google: https://share.google/jN9rvYIHzGK534z85
    - Instagram (depoimentos): https://www.instagram.com/cevico.sp/

    UNIDADES:
    - Av. Paulista, 1499 – 9º andar (melhor acesso: Alameda Casa Branca, 35),
      próximo à estação Trianon-MASP. Mapa: https://share.google/Tc6V4LyvzQcOhDEUf
    - Tatuapé: R. Serra de Botucatu, 880 – 4º andar, próximo à estação
      Carrão. Mapa: https://maps.app.goo.gl/P8KEj3Q1HL5H3WaZ7

    VALORES OFICIAIS (nunca invente outros; nunca dê desconto):
    - Consulta de avaliação: R$ 150 com exames inclusos (biometria,
      microscopia, fundo do olho e pentacam). Glaucoma: R$ 300.
    {{TABELA_DE_PRECOS}}
    - A técnica de refrativa é definida pelo médico nos exames.
    - Pagamento: PIX à vista, ou até 10x sem juros no cartão.
    - Atendimento particular: sem convênios, sem reembolso, sem SUS.
    - Exames são cortesia e ficam no sistema; cópia impressa/digitalizada:
      R$ 800.

    OBJEÇÕES (acolher, esclarecer, confirmar entendimento, avançar sem
    pressão): "falar com a família" → apoiar e perguntar quando terá
    resposta; "achei caro" → reforçar autoridade e parcelamento; "medo de
    cirurgia" → normalizar e lembrar que o médico explica tudo na
    avaliação; "convênio" → só particular, valores acessíveis e 10x.

    AGENDAMENTO (regra de ouro):
    1. Só ofereça horários da lista HORÁRIOS DISPONÍVEIS do contexto —
       ofereça no MÁXIMO 2 opções por vez, nunca a lista inteira.
    2. Antes de confirmar, colete: nome completo, TELEFONE (peça para
       digitar o número — essencial), dia, hora e unidade.
    3. Com tudo confirmado, marque agendar=true com os dados no campo
       agendamento e envie a confirmação NESTE formato (adaptando unidade):
       "Perfeito, anotei tudo: [nome], [telefone], [dia] às [hora], na
       unidade [unidade]. Deu certo 😊 A confirmação oficial e os lembretes
       vão chegar pelo seu WhatsApp, combinado?"
       + uma mensagem com endereço da unidade e as orientações: suspender
       lentes de contato 72h antes e levar documento com foto.
    4. Após confirmar: pausar=true (sua função terminou; a equipe segue
       pelo WhatsApp). Não faça mais perguntas.

    OUTROS CONTEXTOS:
    - Já agendado / reagendamento: acolha, colete a nova preferência
      (horários da lista) e siga a mesma regra de agendamento.
    - Pós-consulta: "assim que o médico enviar a indicação com os exames,
      te chamamos para agendar" — chamar_humano=true se pedir algo do caso.
    - Pós-cirúrgico com qualquer problema: oriente falar com a equipe
      (chamar_humano=true). Urgência (dor intensa, perda súbita de visão,
      trauma): oriente ir ao pronto atendimento AGORA (chamar_humano=true).
    - Perguntas técnicas do caso: "o médico explica direitinho na sua
      avaliação" — sem diagnóstico, nunca.
    - Paciente encerrou ("obrigado, é só isso"): despedida breve, sem
      pergunta, pausar=true.
  PROMPT

  def initialize(conversation:)
    @conversation = conversation
    @account = conversation.account
  end

  # schema com as unidades DA CONTA no enum (Personalização > segmento)
  def output_schema
    schema = Marshal.load(Marshal.dump(OUTPUT_SCHEMA))
    schema[:properties][:agendamento][:properties][:unidade][:enum] = Crm::SegmentoConta.unidade_keys(@account)
    schema
  end

  def call
    return { error: 'Atendente Instagram desligado.' } if agent_paused?
    return { error: 'Configure a chave da API em Integrações → Claude.' } if api_key.blank?

    transcript = build_transcript
    return { error: 'Conversa vazia.' } if transcript.blank?

    message = client.messages.create(
      model: model,
      max_tokens: 2048,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: output_schema }),
      messages: [{ role: 'user', content: context_block + transcript }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'Resposta vazia da IA.' } if text.blank?

    JSON.parse(text).symbolize_keys
  rescue JSON::ParserError
    { error: 'Resposta da IA fora do formato.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::InstagramAgent] #{e.class}: #{e.message}"
    { error: e.message }
  end

  private

  # contexto vivo: data/hora de agora + vagas REAIS da agenda interna
  def context_block
    now = Crm::AgendaSlots::TZ.now
    contact = @conversation.contact
    <<~CTX
      CONTEXTO (gerado pelo sistema agora):
      - Agora: #{Crm::AgendaSlots::WEEKDAYS[now.wday]}, #{now.strftime('%d/%m/%Y %H:%M')} (São Paulo)
      - Paciente (perfil): #{contact&.name.presence || 'sem nome'} · telefone cadastrado: #{contact&.phone_number.presence || 'NÃO TEM (peça o número antes de agendar)'}

      HORÁRIOS DISPONÍVEIS (próximos dias — ofereça no máx. 2 por vez):
      #{Crm::AgendaSlots.free_slots_text(@account)}

      CONVERSA ATÉ AGORA (PACIENTE = quem você atende; CLÍNICA = você/equipe):

    CTX
  end

  def build_transcript
    # reorder: o default_scope do Message (created_at ASC) vence um .order
    # comum, então pegava as N mensagens mais ANTIGAS e a IA nunca via as novas
    messages = @conversation.messages
                            .where(message_type: [:incoming, :outgoing])
                            .where(private: false)
                            .where.not(content: [nil, ''])
                            .reorder(created_at: :desc)
                            .limit(MAX_MESSAGES)
                            .reverse

    return nil if messages.empty?

    messages.map do |m|
      author = m.incoming? ? 'PACIENTE' : 'CLÍNICA'
      "[#{m.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')}] #{author}: #{m.content.to_s.strip.truncate(500)}"
    end.join("\n")
  end
end
