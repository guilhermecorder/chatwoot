# Agente de Agendamento: lê a conversa e extrai os dados da consulta marcada
# (nome, telefone, dia, hora e unidade). Usado pela ação de coluna
# "Agendar consulta (IA)" — quando o card entra em "Consulta agendada", o
# sistema cria o compromisso na Agenda (Tatuapé / Av. Paulista) sozinho.
class Crm::AppointmentExtractionService
  include Crm::AiAgentConfig

  AGENT_KEY = 'scheduler'.freeze
  MAX_MESSAGES = 60
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      encontrado: {
        type: 'boolean',
        description: 'true somente se a conversa confirma dia E hora da consulta'
      },
      nome: { type: 'string', description: 'Nome do paciente como aparece na conversa' },
      telefone: { type: 'string', description: 'Telefone do paciente, se mencionado (senão vazio)' },
      data: { type: 'string', description: 'Data da consulta no formato YYYY-MM-DD (vazio se não confirmada)' },
      hora: { type: 'string', description: 'Hora da consulta no formato HH:MM 24h (vazio se não confirmada)' },
      unidade: {
        type: 'string',
        enum: %w[tatuape paulista nao_identificada],
        description: 'Unidade da clínica combinada na conversa: Tatuapé, Av. Paulista, ou nao_identificada'
      },
      problema: {
        type: 'string',
        description: 'Motivo da consulta em 1-3 palavras: catarata, refrativa, ceratocone, lentes fácicas, exames, pós-operatório, consulta geral... Vazio se não ficar claro.'
      },
      medico: { type: 'string', description: 'Nome do médico combinado na conversa, se mencionado (senão vazio)' },
      observacoes: {
        type: 'string',
        description: 'Observação IMPORTANTE que o paciente falou na conversa e a recepção precisa saber ' \
                     '(convênio, medo, acompanhante, urgência, pedido especial, condição de saúde). 1-2 frases. Vazio se não houver.'
      },
      valor_consulta: {
        type: 'string',
        description: 'Valor da consulta combinado na conversa, ex "R$ 150" ou "R$ 300" (glaucoma). Vazio se não foi mencionado.'
      },
      reagendamento: {
        type: 'boolean',
        description: 'true se esta confirmação é um REAGENDAMENTO (o paciente já tinha consulta e mudou dia/horário)'
      },
      sexo: {
        type: 'string',
        enum: %w[masculino feminino desconhecido],
        description: 'Sexo do PACIENTE da consulta, deduzido do nome ou do contexto ' \
                     '("minha mãe", "meu pai", "ele/ela"). Na dúvida, desconhecido.'
      }
    },
    required: %w[encontrado nome telefone data hora unidade problema medico observacoes valor_consulta reagendamento sexo],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você lê conversas de atendimento da CEVICO (clínica oftalmológica com duas
    unidades: Tatuapé e Av. Paulista) e extrai os dados da CONSULTA AGENDADA
    para registrar na agenda da clínica.

    Regras:
    - Só marque encontrado=true se a conversa CONFIRMA dia e hora (a atendente
      propôs e o paciente aceitou, ou vice-versa). Proposta sem confirmação não vale.
    - Se houver mais de um agendamento, use o MAIS RECENTE confirmado.
    - hora: copie o horário EXATAMENTE como foi confirmado, LITERAL:
      "11h" = 11:00, "11 horas" = 11:00, "11:30"/"11h30"/"onze e meia" = 11:30.
      NUNCA arredonde nem complete minutos que não foram ditos (11:00 e 11:30
      são consultas DIFERENTES — errar isso fura a agenda da clínica). Se a
      conversa citar vários horários (opções oferecidas), vale só o da
      CONFIRMAÇÃO final. Horário não explícito = campo vazio.
    - Datas relativas ("amanhã", "quinta que vem") devem ser convertidas usando a
      data de hoje informada no início da conversa.
    - unidade: identifique pela menção a Tatuapé ou Paulista/Av. Paulista/Bela Vista.
      Na dúvida, nao_identificada.
    - observacoes: registre o que a RECEPÇÃO precisa saber sobre o paciente
      (convênio, medo de cirurgia, acompanhante, urgência, condição de saúde,
      pedido especial). Não repita dia/hora aqui.
    - valor_consulta: se a conversa mencionou o valor da consulta (ex.: R$ 150,
      R$ 300 para glaucoma), registre; senão deixe vazio.
    - reagendamento=true quando a conversa mostra que o paciente JÁ TINHA uma
      consulta e trocou o dia/horário ("preciso remarcar", "mudar o horário").
    - sexo: deduza o sexo do PACIENTE da consulta pelo nome (Maria → feminino,
      João → masculino) ou pelo contexto ("minha mãe", "meu avô", "ela"). Atenção:
      quem conversa pode estar marcando para OUTRA pessoa — o que vale é o
      paciente. Nome ambíguo e sem pistas no texto → desconhecido.
    - Não invente dados: campo não confirmado fica vazio.
  PROMPT

  WEEKDAYS_PT = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze

  def initialize(conversation:)
    @conversation = conversation
    @account = conversation.account
  end

  def call
    return { error: 'IA não configurada. Adicione a chave da API em Integrações → Claude.' } if api_key.blank?
    return { error: 'O Secretário da Agenda está pausado. Reative em Automações → Agentes de IA.' } if agent_paused?

    transcript = build_transcript
    return { error: 'Conversa sem mensagens para analisar.' } if transcript.blank?

    message = client.messages.create(
      model: model,
      max_tokens: 1024,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: transcript }]
    )
    record_usage(message)

    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'A IA não retornou os dados do agendamento.' } if text.blank?

    parsed = JSON.parse(text)
    {
      found: parsed['encontrado'] == true,
      name: parsed['nome'].to_s.strip,
      phone: parsed['telefone'].to_s.strip,
      starts_at: parse_datetime(parsed['data'], parsed['hora']),
      unit: %w[tatuape paulista].include?(parsed['unidade']) ? parsed['unidade'] : nil,
      procedure: parsed['problema'].to_s.strip,
      doctor: parsed['medico'].to_s.strip,
      notes: parsed['observacoes'].to_s.strip,
      price: parsed['valor_consulta'].to_s.strip,
      reschedule: parsed['reagendamento'] == true,
      gender: %w[masculino feminino].include?(parsed['sexo']) ? parsed['sexo'] : nil,
      model: model
    }
  rescue Anthropic::Errors::AuthenticationError
    { error: 'Chave da API inválida. Confira em CRM → Integrações → IA.' }
  rescue Anthropic::Errors::RateLimitError
    { error: 'Limite de uso da IA atingido. Tente novamente em instantes.' }
  rescue StandardError => e
    Rails.logger.error "[Crm::AppointmentExtraction] #{e.class}: #{e.message}"
    { error: 'Erro na extração do agendamento.' }
  end

  private

  # horário salvo no fuso da clínica (São Paulo)
  def parse_datetime(date, time)
    return nil if date.blank? || time.blank?

    TZ.parse("#{date} #{time}")
  rescue StandardError
    nil
  end

  def build_transcript
    messages = @conversation.messages
                            .where(message_type: [:incoming, :outgoing])
                            .where(private: false)
                            .where.not(content: [nil, ''])
                            .order(created_at: :desc)
                            .limit(MAX_MESSAGES)
                            .reverse

    return nil if messages.empty?

    lines = messages.map do |m|
      author = m.incoming? ? 'PACIENTE' : 'CLÍNICA'
      "[#{stamp(m.created_at.in_time_zone(TZ))}] #{author}: #{m.content.to_s.strip.truncate(600)}"
    end

    contact = @conversation.contact
    header = "Hoje é #{stamp(TZ.now)}.\n" \
             "Contato cadastrado: #{contact&.name || 'sem nome'} — telefone #{contact&.phone_number || 'não informado'}.\n" \
             "Extraia os dados da consulta agendada nesta conversa:\n\n"
    header + lines.join("\n")
  end

  def stamp(time)
    "#{time.strftime('%d/%m/%Y')} (#{WEEKDAYS_PT[time.wday]}) #{time.strftime('%H:%M')}"
  end
end
