# 🔧 FERRAMENTAS DOS RESPONDEDORES (rodada 192): o que o Atendente pode FAZER
# além de falar — buscar uma consulta na Agenda (a própria ou a de um
# familiar), remarcar, cancelar e confirmar presença. Entram na chamada da IA
# como `tools` (tool use): a IA pede, este serviço executa e devolve o
# resultado em JSON no `tool_result`; a IA lê e só então escreve ao paciente.
#
# Regras de segurança (valem para todas as ferramentas):
# - a consulta tem que ser DESTA conta, de hoje 00:00 (fuso SP) em diante,
#   não cancelada e não concluída — fora disso é "não encontrada";
# - telefone de TERCEIRO nunca sai inteiro (só os 4 finais);
# - 🔒 auditoria 10/10 (achados #99/#442): consulta de OUTRA pessoa (não é
#   do contato nem do telefone deste WhatsApp) só aparece inteira, e só é
#   remarcada/cancelada/confirmada, com PROVA FORTE: telefone completo (com
#   DDD) cadastrado na consulta + nome completo, ditados por quem conversa.
#   Sem a prova, buscar não lista a consulta (só avisa quantas ficaram
#   ocultas, sem id, nome ou telefone) e as outras ferramentas não executam:
#   abrem tarefa para a equipe e devolvem ok=false;
# - em SOMBRA nenhuma ferramenta escreve: só valida e responde `simulado`.
# `acoes` acumula o que foi feito, para a nota de sombra e os balões da tela
# (montado aqui, nunca pelo modelo).
class Crm::ResponderTools # rubocop:disable Metrics/ClassLength
  TZ = Crm::AgendaSlots::TZ
  MAX_RESULTS = 5
  LOCK_TTL = 30.seconds
  # prova forte de consulta de outra pessoa: telefone com DDD (10+ dígitos)
  PROOF_MIN_DIGITS = 10
  PROOF_FIELDS = {
    telefone: { type: 'string', description: 'Só para consulta de OUTRA pessoa: telefone COMPLETO com DDD cadastrado na ' \
                                             'consulta, ditado por quem conversa' },
    nome_completo: { type: 'string', description: 'Só para consulta de OUTRA pessoa: nome completo do paciente da consulta, ' \
                                                  'ditado por quem conversa' }
  }.freeze
  # nome com menos letras do que isso não procura consulta de terceiro ("a", "Ma")
  NAME_MIN_LETTERS = 3
  HIDDEN_NOTICE = 'Há consulta de OUTRA pessoa (terceiros_ocultos) que NÃO aparece na lista: os dados ficam ocultos até ' \
                  'o paciente ditar o nome completo e o telefone COMPLETO (com DDD) cadastrado nela. Peça os dois e busque ' \
                  'de novo com nome + telefone. Se continuar oculta, não mexa nessa consulta: diga que vai passar para a ' \
                  'equipe e marque chamar_humano.'.freeze
  SHORT_NAME_NOTICE = 'Nome curto demais para procurar a consulta de outra pessoa: peça o nome completo do paciente.'.freeze
  PROOF_HINT = 'Só dá para mexer nessa consulta com o telefone COMPLETO (com DDD) cadastrado nela e o nome completo, ' \
               'ditados por quem conversa (campos telefone e nome_completo).'.freeze
  THIRD_PARTY_TEXTS = {
    opened: 'Esta consulta é de OUTRA pessoa (não é deste WhatsApp) e NADA foi alterado. A equipe já recebeu uma tarefa ' \
            'para conferir com o titular. Diga ao paciente que a equipe vai cuidar disso (ou que o titular pode chamar ' \
            'pelo WhatsApp dele) e marque chamar_humano.',
    failed: 'Esta consulta é de OUTRA pessoa (não é deste WhatsApp) e NADA foi alterado. Não foi possível avisar a equipe ' \
            'automaticamente: diga ao paciente que vai verificar e marque chamar_humano.',
    shadow: 'Esta consulta é de OUTRA pessoa (não é deste WhatsApp) e NADA foi alterado. Em sombra a recusa vale igual ' \
            '(a tarefa para a equipe não é aberta de verdade): diga ao paciente que vai passar para a equipe e marque ' \
            'chamar_humano.'
  }.freeze
  NAMES = %w[buscar_consulta remarcar_consulta cancelar_consulta confirmar_presenca horarios_do_dia].freeze
  TASK_TOOL_NAME = 'abrir_tarefa'.freeze
  # 🏷️ 06/11/2026 (LIFE): o atendente marca a ETAPA do lead com uma etiqueta
  # no contato; a "Automação da coluna" (gatilho: ao receber etiqueta → move o
  # cartão) faz o resto. As etapas vêm da conta (ai_config['crm_etapas']:
  # [{ 'etiqueta' => 'conta_recebida', 'quando' => 'mandou a conta de luz' }]);
  # sem lista configurada, a ferramenta nem aparece para a IA.
  STAGE_TOOL_NAME = 'marcar_etapa'.freeze
  STAGE_MAX = 12
  # 🖼️ 08/11/2026 (LIFE, pedido do Fernando): imagem pronta da empresa num ponto
  # do roteiro (1ª: os 4 telhados numerados na sondagem). Imagens da conta em
  # ai_config['imagens_roteiro'] (Crm::ScriptImages); sem lista, não aparece.
  IMAGE_TOOL_NAME = 'enviar_imagem'.freeze
  # 📝 11/11 (LIFE): ficha do cliente — o atendente anota o que o cliente conta (Crm::ClientSummary)
  SUMMARY_TOOL_NAME = 'anotar_cliente'.freeze
  # 🔊 09/11/2026 (LIFE, pedido do Guilherme): áudio pronto da empresa num ponto do
  # roteiro (1º: o Fernando apresentando a Life para quem vai receber o orçamento).
  # Mesma lista ai_config['imagens_roteiro'], arquivos .ogg/.opus/.mp3/.m4a.
  AUDIO_TOOL_NAME = 'enviar_audio'.freeze
  # 📨 12/11 (LIFE): manda o orçamento gerado (PDF + pergunta de fechamento; o resumo fica para o follow-up) quando o cliente
  # responde ao modelo "orçamento pronto" (Crm::KitQuote::Delivery). Só aparece se há orçamento por enviar.
  QUOTE_TOOL_NAME = 'enviar_orcamento'.freeze
  # ⚡ 12/11 (LIFE): gera o orçamento sozinho e manda em ~30 s (Crm::KitQuoteAutoJob). Só com a chave
  # ai_config['agents'][<atendente>]['orcamento_automatico'] = true e a ficha com a conta e o telhado.
  AUTO_QUOTE_TOOL_NAME = 'gerar_orcamento'.freeze
  FAKE_TASK_WORDS = [
    'placeholder', 'ignorar', 'ignore', 'nenhum', 'nenhuma', 'cancelado', 'cancelada', 'não usar', 'nao usar',
    'não aplic', 'nao aplic', 'não necess', 'nao necess', 'desnecess', 'sem necessidade', 'not needed',
    'nevermind', 'never mind', 'nunca mind', 'n/a', 'teste', 'test', 'dummy', 'xxx'
  ].freeze
  FAKE_TASK_RE = /\A\W*(#{FAKE_TASK_WORDS.map { |w| Regexp.escape(w) }.join('|')})/i
  ALL_NAMES = (NAMES + [TASK_TOOL_NAME, STAGE_TOOL_NAME, IMAGE_TOOL_NAME, AUDIO_TOOL_NAME, SUMMARY_TOOL_NAME,
                        QUOTE_TOOL_NAME, AUTO_QUOTE_TOOL_NAME]).freeze
  AGENT_NAMES = { 'atendente_agendamento' => 'Atendente de Agendamento', 'atendente_pos' => 'Atendente Pós-agendamento',
                  'atendente_pos_op' => 'Atendente de Pós-operatório', 'voice' => 'Agente de Ligação' }.freeze
  # 🩺 item 251: o Atendente de Pós-operatório abre tarefa para a equipe.
  # 🙋 auditoria 10/2026 (#458): os três atendentes do WhatsApp abrem tarefa —
  # urgência clínica ou pedido fora do roteiro num paciente novo também
  # precisa de alguém da equipe avisado, não só de uma nota na conversa.
  TASK_TOOL_KEYS = %w[atendente_agendamento atendente_pos atendente_pos_op].freeze
  WEEKDAYS_SHORT = %w[dom seg ter qua qui sex sáb].freeze

  attr_reader :acoes

  # simulation (08/11): é o "Testar agente" — a imagem do roteiro entra de
  # verdade na conversa de teste (caixa interna sem canal, nada sai dela)
  def initialize(conversation:, agent_key:, live:, simulation: false)
    @conversation = conversation
    @account = conversation.account
    @contact = conversation.contact
    @agent_key = agent_key.to_s
    @live = live == true
    @simulation = simulation == true
    @acoes = []
  end

  # definições para a API (input_schema em JSON Schema)
  def definitions # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
    list = base_definitions
    list << task_definition if TASK_TOOL_KEYS.include?(@agent_key)
    list << stage_definition if TASK_TOOL_KEYS.include?(@agent_key) && crm_etapas.any?
    list << image_definition if TASK_TOOL_KEYS.include?(@agent_key) && script_images.any?
    list << audio_definition if TASK_TOOL_KEYS.include?(@agent_key) && script_audios.any?
    list << quote_definition if TASK_TOOL_KEYS.include?(@agent_key) && pending_quote
    list << auto_quote_definition if auto_quote_available?
    list + summary_definitions
  end

  # 📝 ficha do cliente: só para os atendentes e só quando a conta escolheu os campos
  def summary_definitions
    TASK_TOOL_KEYS.include?(@agent_key) && summary_fields.any? ? [summary_definition] : []
  end

  # campos da ficha do cliente desta conta (vazio = recurso desligado)
  def summary_fields
    @summary_fields ||= Crm::ClientSummary.fields(@account)
  end

  def summary_definition # rubocop:disable Metrics/MethodLength
    guia = summary_fields.map { |f| "#{f['chave']} = #{f['rotulo']}#{" (#{f['quando']})" if f['quando'].present?}" }.join('; ')
    ja = summary_known
    {
      name: SUMMARY_TOOL_NAME,
      description: 'Anota na FICHA DO CLIENTE o que ele acabou de contar (a equipe lê no cartão e na página dele). ' \
                   "Use na hora em que o cliente informar um destes dados, bem curto e com as palavras dele: #{guia}. " \
                   'Só anote o que o cliente DISSE, nunca suposição. Não repita o que já está anotado; se ele corrigir, ' \
                   "anote o valor novo. Não conte ao cliente que anotou.#{" Já anotado: #{ja}." if ja.present?}",
      input_schema: {
        type: 'object',
        properties: {
          dados: {
            type: 'array', minItems: 1, description: 'Um item por informação nova',
            items: {
              type: 'object',
              properties: {
                campo: { type: 'string', enum: summary_fields.pluck('chave'), description: 'Qual dado da ficha' },
                valor: { type: 'string',
                         description: 'O que o cliente disse, em poucas palavras (ex.: "R$ 300 por mês", "vai pôr 2 ar-condicionados")' }
              },
              required: %w[campo valor], additionalProperties: false
            }
          }
        },
        required: %w[dados],
        additionalProperties: false
      }
    }
  end

  # mídias do roteiro desta conta (só as que têm arquivo de verdade)
  def script_medias
    @script_medias ||= Crm::ScriptImages.for(@account)
  end

  def script_images
    @script_images ||= script_medias.select { |m| m['tipo'] == 'imagem' }
  end

  def script_audios
    @script_audios ||= script_medias.select { |m| m['tipo'] == 'audio' }
  end

  def audio_definition
    guia = script_audios.map do |a|
      legenda = a['legenda'].present? ? " (antes dele vai o balão: \"#{a['legenda']}\")" : ''
      "#{a['chave']} = #{a['quando']}#{legenda}"
    end.join('; ')
    {
      name: AUDIO_TOOL_NAME,
      description: 'Envia ao cliente um ÁUDIO PRONTO, gravado pela própria equipe da empresa, no momento do roteiro ' \
                   "descrito para ele, uma vez por conversa: #{guia}. O áudio sai ANTES dos seus balões, já com a frase " \
                   'de apresentação dele. Não repita nos balões o que o áudio diz: siga a conversa.',
      input_schema: {
        type: 'object',
        properties: {
          audio: { type: 'string', enum: script_audios.pluck('chave'), description: 'Qual áudio enviar' },
          reenviar: { type: 'boolean', description: 'true SÓ quando o cliente disser que o áudio não chegou ou não abriu' }
        },
        required: %w[audio],
        additionalProperties: false
      }
    }
  end

  def image_definition
    guia = script_images.map do |i|
      legenda = i['legenda'].present? ? " (vai com a legenda: \"#{i['legenda']}\")" : ''
      prova = i['faz_pergunta'] ? '' : ' [é prova: a legenda não pergunta nada; siga a conversa no balão]'
      "#{i['chave']} = #{i['quando']}#{legenda}#{prova}"
    end.join('; ')
    {
      name: IMAGE_TOOL_NAME,
      description: 'Envia ao cliente uma IMAGEM PRONTA da empresa, no momento do roteiro descrito para ela, uma vez por ' \
                   "conversa: #{guia}. A imagem sai ANTES dos seus balões. Se ela tem legenda, a pergunta já vai na " \
                   'legenda: não repita a pergunta nos balões (menos nas marcadas como prova).',
      input_schema: {
        type: 'object',
        properties: {
          imagem: { type: 'string', enum: script_images.pluck('chave'), description: 'Qual imagem enviar' },
          reenviar: { type: 'boolean', description: 'true SÓ quando o cliente disser que a imagem não chegou ou não abriu' }
        },
        required: %w[imagem],
        additionalProperties: false
      }
    }
  end

  # etapas configuradas na conta (etiqueta + quando usar), já normalizadas
  def crm_etapas
    @crm_etapas ||= Array(CrmSetting.find_by(account: @account)&.ai_config&.dig('crm_etapas')).first(STAGE_MAX).filter_map do |e|
      e = e.to_h.transform_keys(&:to_s)
      tag = e['etiqueta'].to_s.strip.downcase.gsub(/[^a-z0-9_-]/, '_').squeeze('_')[0, 40]
      next if tag.blank?

      { 'etiqueta' => tag, 'quando' => e['quando'].to_s.strip[0, 200] }
    end
  end

  def stage_definition
    guia = crm_etapas.map { |e| "#{e['etiqueta']} = #{e['quando']}" }.join('; ')
    {
      name: STAGE_TOOL_NAME,
      description: 'Marca a ETAPA em que o lead está (vira etiqueta no contato e o cartão anda sozinho no CRM). ' \
                   "Use assim que a conversa chegar ao momento descrito, uma vez por etapa: #{guia}. " \
                   'Não conte ao cliente que marcou.',
      input_schema: {
        type: 'object',
        properties: {
          etapa: { type: 'string', enum: crm_etapas.pluck('etiqueta'), description: 'A etapa que acabou de acontecer' }
        },
        required: %w[etapa],
        additionalProperties: false
      }
    }
  end

  # 🩺 item 251: tarefa para a pessoa responsável (Meu Painel) — dúvida do caso,
  # sintoma de alerta, documento, pedido de humano
  def task_definition # rubocop:disable Metrics/MethodLength
    {
      name: 'abrir_tarefa',
      description: 'Abre uma TAREFA para a pessoa da equipe responsável (aparece no Meu Painel dela) quando a dúvida não ' \
                   'está nas orientações oficiais, envolve o caso clínico, documento/receita/atestado, ou é um sintoma de ' \
                   'alerta. Devolve ok=true e o id. Se já houver tarefa aberta deste paciente, ela é complementada.',
      input_schema: {
        type: 'object',
        properties: {
          motivo: { type: 'string', description: 'Motivo em UMA frase curta (ex.: "dor forte no olho direito há 2h")' },
          detalhes: { type: 'string', description: 'O que o paciente relatou, com as palavras dele, e o que você respondeu' },
          urgencia: { type: 'string', enum: %w[alta normal],
                      description: 'alta = sintoma/alerta (tarefa urgente + aviso no painel da equipe, que vê no próximo ' \
                                   'horário de atendimento); normal = dúvida/documento' },
          quando: { type: 'string', description: 'Só para RETORNO COM DATA (ex.: "daqui a 3, 4 dias eu te chamo"): o DIA em que a ' \
                                                 'equipe deve agir, YYYY-MM-DD. Vira tarefa separada com contagem no painel ' \
                                                 'do responsável e aviso no dia. Sem retorno combinado, não informe.' },
          hora: { type: 'string', description: 'Hora do retorno com data, HH:MM (padrão 09:00)' }
        },
        required: %w[motivo urgencia],
        additionalProperties: false
      }
    }
  end

  def base_definitions # rubocop:disable Metrics/MethodLength
    [
      {
        name: 'buscar_consulta',
        description: 'Busca consultas marcadas na Agenda da clínica (de hoje em diante). Sem filtro devolve as do próprio ' \
                     'paciente desta conversa. Com nome e/ou dia encontra também a consulta de OUTRA pessoa (mãe, filho, ' \
                     'esposa). Devolve id, paciente, dia, hora, unidade, médico e os 4 últimos dígitos do telefone. ' \
                     'Consulta de outra pessoa só aparece quando o telefone informado (com DDD) é o cadastrado nela; ' \
                     'sem isso ela NÃO entra na lista: vem só a contagem terceiros_ocultos e o aviso.',
        input_schema: {
          type: 'object',
          properties: {
            nome: { type: 'string', description: 'Nome (ou parte do nome) do paciente da consulta' },
            telefone: { type: 'string', description: 'Telefone com DDD, quando o paciente informar' },
            dia: { type: 'string', description: 'Dia da consulta no formato YYYY-MM-DD' }
          },
          additionalProperties: false
        }
      },
      {
        name: 'remarcar_consulta',
        description: 'Move uma consulta existente para outro dia/hora/unidade. Use SÓ depois de o paciente dizer SIM a um horário ' \
                     'específico que você propôs ("Fica bom pra você [dia] às [hora]?"). Pergunta ou contraproposta dele ("tem 16h?", ' \
                     '"final do dia?") NÃO é confirmação: responda e pergunte de novo. Devolve ok=true quando remarcou; ok=false com ' \
                     'motivo quando a vaga não está livre (ofereça outra) ou quando o paciente ainda não confirmou. ' \
                     'Consulta de OUTRA pessoa exige telefone e nome_completo ditados por quem conversa.',
        input_schema: {
          type: 'object',
          properties: {
            id: { type: 'integer', description: 'id da consulta (de buscar_consulta ou do contexto)' },
            dia: { type: 'string', description: 'Novo dia, YYYY-MM-DD' },
            hora: { type: 'string', description: 'Nova hora, HH:MM' },
            unidade: { type: 'string', enum: Crm::AgendaSlots.unit_keys(@account) }
          }.merge(PROOF_FIELDS),
          required: %w[id dia hora unidade],
          additionalProperties: false
        }
      },
      {
        name: 'cancelar_consulta',
        description: 'Cancela uma consulta (sem novo horário). Use SÓ depois de o paciente manter o cancelamento. ' \
                     'Consulta de OUTRA pessoa exige telefone e nome_completo ditados por quem conversa.',
        input_schema: {
          type: 'object',
          properties: {
            id: { type: 'integer', description: 'id da consulta' },
            motivo: { type: 'string', description: 'Motivo dito pelo paciente, em poucas palavras' }
          }.merge(PROOF_FIELDS),
          required: %w[id],
          additionalProperties: false
        }
      },
      {
        name: 'confirmar_presenca',
        description: 'Registra que o paciente confirmou que vai à consulta ("confirmo", "estarei lá"). ' \
                     'Consulta de OUTRA pessoa exige telefone e nome_completo ditados por quem conversa.',
        input_schema: {
          type: 'object',
          properties: { id: { type: 'integer', description: 'id da consulta' } }.merge(PROOF_FIELDS),
          required: %w[id],
          additionalProperties: false
        }
      },
      {
        # item 200: agendamento futuro liberado — qualquer dia até 4 meses
        name: 'horarios_do_dia',
        description: 'Vagas LIVRES reais de UM dia específico (qualquer data futura até 4 meses), para quando o paciente ' \
                     'pede um dia que não aparece em HORÁRIOS DISPONÍVEIS ("dia 07/10", "daqui a um mês"). Devolve os ' \
                     'horários livres por unidade e médico. Lista vazia = não há consulta nesse dia (dia sem atendimento) ' \
                     'ou está lotado: ofereça o dia de atendimento mais próximo.',
        input_schema: {
          type: 'object',
          properties: {
            dia: { type: 'string', description: 'Dia pedido, YYYY-MM-DD' },
            unidade: { type: 'string', enum: Crm::AgendaSlots.unit_keys(@account), description: 'Só desta unidade (opcional)' }
          },
          required: %w[dia],
          additionalProperties: false
        }
      }
    ]
  end

  # executa a ferramenta pedida pela IA; devolve o Hash que vai como JSON no tool_result
  def call(name, input) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/MethodLength
    args = (input || {}).to_h.transform_keys(&:to_s)
    case name.to_s
    when 'buscar_consulta' then buscar(args)
    when 'remarcar_consulta' then remarcar(args)
    when 'cancelar_consulta' then cancelar(args)
    when 'confirmar_presenca' then confirmar(args)
    when 'horarios_do_dia' then horarios_do_dia(args)
    when 'abrir_tarefa' then abrir_tarefa(args)
    when 'marcar_etapa' then marcar_etapa(args)
    when SUMMARY_TOOL_NAME then anotar_cliente(args)
    when IMAGE_TOOL_NAME then enviar_imagem(args)
    when AUDIO_TOOL_NAME then enviar_audio(args)
    when QUOTE_TOOL_NAME then enviar_orcamento
    when AUTO_QUOTE_TOOL_NAME then gerar_orcamento
    else
      { ok: false, motivo: "Ferramenta desconhecida: #{name}" }
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::ResponderTools##{name}] #{e.class}: #{e.message}"
    log_acao(name.to_s, false, "erro: #{e.message.truncate(80)}")
    { ok: false, motivo: 'Falha interna ao executar a ferramenta; diga que vai verificar com a equipe.' }
  end

  # consultas que as ferramentas enxergam: desta conta, futuras, ativas
  def scope
    @account.tasks.where(task_type: 'consulta', canceled_at: nil)
            .where.not(status: 'done')
            .where('due_at >= ?', TZ.now.beginning_of_day)
  end

  # o Postgres tem a extensão unaccent? (uma vez por processo)
  def self.unaccent?
    return @unaccent unless @unaccent.nil?

    @unaccent = ActiveRecord::Base.connection.extension_enabled?('unaccent')
  rescue StandardError
    @unaccent = false
  end

  private

  # ── buscar ──────────────────────────────────────────────────────────────
  def buscar(args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    name = args['nome'].to_s.strip
    digits = args['telefone'].to_s.gsub(/\D/, '')
    day = parse_date(args['dia'])

    found = own_appointments
    found |= by_phone(digits, day) if digits.length >= 8
    found |= by_name(name, day) if name_searchable?(name)
    found = found.uniq(&:id).sort_by(&:due_at)
    # 🔒 #99/#442: consulta de outra pessoa só entra na lista com o telefone
    # (com DDD) casando; as outras viram só uma contagem, sem id/nome/telefone
    visible, hidden = found.partition { |t| visible?(t, digits) }
    total = visible.size
    avisos = []
    avisos << SHORT_NAME_NOTICE if name.present? && !name_searchable?(name)
    if total > MAX_RESULTS
      visible = visible.first(MAX_RESULTS)
      avisos << if day
                  'Há mais consultas do que as listadas; peça o nome completo do paciente e busque de novo.'
                else
                  'Muitas consultas com esse nome; pergunte o DIA da consulta e busque de novo com nome + dia.'
                end
    end
    avisos << HIDDEN_NOTICE if hidden.any?
    log_acao('buscar_consulta', true, resumo_busca(visible, total, hidden))
    result = { consultas: visible.map { |t| serialize(t) }, total: total }
    result[:terceiros_ocultos] = hidden.size if hidden.any?
    result[:aviso] = avisos.join(' ') if avisos.any?
    result
  end

  # nome com 3+ letras (sem contar espaços/pontuação) serve para procurar terceiros
  def name_searchable?(name)
    I18n.transliterate(name.to_s).scan(/[a-z0-9]/i).size >= NAME_MIN_LETTERS
  end

  # a consulta pode aparecer inteira? própria, ou o telefone informado (com
  # DDD, mesma régua da prova forte) casa com o dela
  def visible?(task, digits)
    own?(task) || (digits.length >= PROOF_MIN_DIGITS && Crm::AppointmentRecorder.same_phone_line?(digits, task.phone))
  end

  # sempre entram: as do próprio contato (contact_id) e as do telefone deste WhatsApp
  def own_appointments
    list = @contact ? scope.where(contact_id: @contact.id).to_a : []
    own_digits = @contact&.phone_number.to_s.gsub(/\D/, '')
    list |= by_phone(own_digits, nil) if own_digits.length >= 8
    list
  end

  def by_phone(digits, day)
    rel = scope.where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
    rel = rel.where(due_at: day_range(day)) if day
    rel.select { |t| Crm::AppointmentRecorder.same_phone_line?(digits, t.phone) }
  end

  # por nome: ILIKE sem acento (unaccent do Postgres quando existe; senão
  # normaliza em Ruby sobre as futuras) — "Maisa" acha "Maísa"
  def by_name(name, day)
    rel = scope
    rel = rel.where(due_at: day_range(day)) if day
    if self.class.unaccent?
      rel.where('unaccent(title) ILIKE unaccent(?)', "%#{ActiveRecord::Base.sanitize_sql_like(name)}%").order(:due_at).limit(50).to_a
    else
      needle = I18n.transliterate(name).downcase
      rel.order(:due_at).limit(2000).select { |t| I18n.transliterate(t.title.to_s).downcase.include?(needle) }
    end
  end

  def resumo_busca(visible, total, hidden)
    hidden_text = hidden.any? ? " + #{hidden.size} de outra pessoa oculta#{'s' if hidden.size > 1} (telefone não casou)" : ''
    return "buscou consulta: nenhuma encontrada#{hidden_text}" if total.zero?

    first = visible.first
    at = first.due_at.in_time_zone(TZ)
    day = at.to_date == TZ.now.to_date ? 'hoje' : "#{WEEKDAYS_SHORT[at.wday]} #{at.strftime('%d/%m')}"
    "buscou consulta: #{total} encontrada#{'s' if total > 1} (#{patient_name(first)}, #{day} #{at.strftime('%H:%M')})#{hidden_text}"
  end

  # ── remarcar ────────────────────────────────────────────────────────────
  # última fala do paciente termina em pergunta? (texto; áudio transcrito também conta)
  def patient_asked_question?
    last = @conversation.messages.where(message_type: :incoming).reorder(created_at: :desc).first
    return false if last.blank?

    text = [last.content.to_s, *last.attachments.map { |a| a.meta&.[]('transcribed_text').to_s }].join(' ').strip
    text.include?('?')
  end

  def remarcar(args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    task = find_task(args['id'])
    return not_found('remarcar_consulta') unless task
    return third_party('remarcar_consulta', task, args, 'remarcar a consulta') unless allowed?(task, args)

    date = parse_date(args['dia'])
    time = args['hora'].to_s.strip
    unit = args['unidade'].to_s.strip
    units = Crm::AgendaSlots.unit_keys(@account)
    if date.nil? || !time.match?(/\A\d{2}:\d{2}\z/) || units.exclude?(unit)
      return refuse('remarcar_consulta', "Informe dia (YYYY-MM-DD), hora (HH:MM) e unidade (#{units.join(' ou ')}) de um horário da lista.")
    end

    label = "#{WEEKDAYS_SHORT[date.wday]} #{date.strftime('%d/%m')} #{time} · #{unit_label(unit)}"
    # 23/09 (teste real #16309): o agente remarcou para 15:00 quando o paciente
    # perguntou "Tem as 16h?? Ou final de dia?". Pergunta nunca é confirmação:
    # a última fala do paciente com "?" trava a ferramenta até ele dizer sim.
    if patient_asked_question?
      return refuse('remarcar_consulta', 'O paciente fez uma PERGUNTA, não confirmou este horário. Responda o que ele perguntou ' \
                                         "e pergunte \"Fica bom pra você #{label}?\". Só remarque depois do sim dele.")
    end

    # item 307: retorno e pós-operatório são remarcados nas faixas DELES
    modality = Crm::AgendaSlots.slot_modality(task)
    unless @live
      free = Crm::AgendaSlots.slot_available?(@account, date: date, time: time, unit: unit, modality: modality)
      log_acao('remarcar_consulta', free, "remarcaria #{patient_name(task)} p/ #{label} (simulado#{free ? '' : ', vaga ocupada'})")
      mensagem = free ? 'Em sombra nada foi alterado; a vaga está livre.' : 'Em sombra nada foi alterado; a vaga NÃO está livre — ofereça outra.'
      return { simulado: true, ok: free, mensagem: mensagem }
    end

    with_slot_lock(date, time, unit) do
      next refuse('remarcar_consulta', 'Essa vaga não está mais livre. Ofereça outra de HORÁRIOS DISPONÍVEIS.') unless
        Crm::AgendaSlots.slot_available?(@account, date: date, time: time, unit: unit, modality: modality)

      starts_at = TZ.parse("#{date} #{time}")
      doctor = Crm::AgendaSlots.doctor_at(@account, date, time, unit, modality: modality) # item 311
      task.update!(
        due_at: starts_at, unit: unit, doctor: doctor.presence || task.doctor,
        rescheduled_count: task.rescheduled_count + 1, status: :todo, canceled_at: nil,
        description: append_note(task.description, "Remarcada pelo #{agent_name} via WhatsApp (conversa ##{@conversation.display_id}) em #{stamp}")
      )
      Crm::AgentAlert.push(account: @account, kind: 'agente_remarcou', task: task, conversation: @conversation, agent_key: @agent_key)
      effects = side_effects(task, :rescheduled)
      activity_note!("🔁 #{agent_name} remarcou: #{patient_name(task)} — #{label}. #{agenda_link(starts_at)} #{effects}".strip)
      log_acao('remarcar_consulta', true, "remarcou #{patient_name(task)} p/ #{label}")
      { ok: true, consulta: serialize(task.reload) }
    end
  end

  # ── cancelar ────────────────────────────────────────────────────────────
  def cancelar(args) # rubocop:disable Metrics/AbcSize
    task = find_task(args['id'])
    return not_found('cancelar_consulta') unless task
    return third_party('cancelar_consulta', task, args, 'cancelar a consulta') unless allowed?(task, args)

    motivo = args['motivo'].to_s.strip.truncate(200)
    unless @live
      log_acao('cancelar_consulta', true, "cancelaria a consulta de #{patient_name(task)} (simulado)")
      return { simulado: true, ok: true, mensagem: 'Em sombra nada foi alterado; a consulta seria cancelada.' }
    end

    note = "Cancelada pelo #{agent_name} via WhatsApp (conversa ##{@conversation.display_id}) em #{stamp}"
    note += " — motivo: #{motivo}" if motivo.present?
    task.update!(canceled_at: Time.current, description: append_note(task.description, note))
    Crm::AgentAlert.push(account: @account, kind: 'agente_cancelou', task: task, conversation: @conversation, agent_key: @agent_key)
    effects = side_effects(task, :canceled)
    activity_note!("🚫 #{agent_name} cancelou a consulta de #{patient_name(task)} (#{when_label(task)})" \
                   "#{" — motivo: #{motivo}" if motivo.present?} #{effects}".strip)
    log_acao('cancelar_consulta', true, "cancelou a consulta de #{patient_name(task)}")
    { ok: true, consulta: serialize(task) }
  end

  # ── confirmar presença ──────────────────────────────────────────────────
  def confirmar(args)
    task = find_task(args['id'])
    return not_found('confirmar_presenca') unless task
    return third_party('confirmar_presenca', task, args, 'confirmar presença na consulta') unless allowed?(task, args)

    unless @live
      log_acao('confirmar_presenca', true, "confirmaria presença de #{patient_name(task)} (simulado)")
      return { simulado: true, ok: true, mensagem: 'Em sombra nada foi alterado; a presença seria registrada.' }
    end

    task.update!(description: append_note(task.description, "Presença confirmada pelo paciente (WhatsApp, #{agent_name}) em #{stamp}"))
    log_acao('confirmar_presenca', true, "presença confirmada: #{patient_name(task)} (#{when_label(task)})")
    { ok: true, consulta: serialize(task) }
  end

  # ── 🩺 tarefa para a equipe (item 251) ──────────────────────────────────
  def abrir_tarefa(args) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return refuse('abrir_tarefa', 'Esta ferramenta não está disponível para este agente.') unless TASK_TOOL_KEYS.include?(@agent_key)

    motivo = args['motivo'].to_s.strip.first(120)
    return refuse('abrir_tarefa', 'Informe o motivo em uma frase.') if motivo.blank?

    # 08/11 (bancada LIFE): com a imagem do roteiro a IA às vezes "chama por chamar"
    # (motivo "placeholder", "ignorar"…) — isso viraria tarefa-lixo no Meu Painel
    urgencia = args['urgencia'].to_s == 'alta' ? 'alta' : 'normal'
    # urgência nunca é barrada (na clínica "dor" é motivo de verdade)
    return refuse('abrir_tarefa', 'Sem motivo real: NÃO abra tarefa. Só responda ao cliente.') if fake_motivo?(motivo, urgencia)

    due_at, erro = task_due_at(args)
    return refuse('abrir_tarefa', erro) if erro

    quando_txt = due_at ? " para #{WEEKDAYS_SHORT[due_at.wday]} #{due_at.strftime('%d/%m %H:%M')}" : ''
    unless @live
      log_acao('abrir_tarefa', true, "abriria tarefa (#{urgencia})#{quando_txt}: #{motivo} (simulado)")
      return { simulado: true, ok: true, prazo: due_at&.iso8601, mensagem: 'Em sombra nada foi criado; a tarefa seria aberta para a equipe.' }
    end

    outcome = Crm::HandoffTask.open!(account: @account, contact: @contact, conversation: @conversation, agent_key: @agent_key,
                                     motivo: motivo, detalhes: args['detalhes'], urgencia: urgencia, due_at: due_at)
    task = outcome[:task]
    verb = outcome[:created] ? 'abriu' : 'complementou'
    log_acao('abrir_tarefa', true, "#{verb} tarefa ##{task.id} (#{urgencia})#{quando_txt} p/ #{task.assignee&.name || 'equipe'}: #{motivo}")
    { ok: true, id: task.id, criada: outcome[:created], responsavel: task.assignee&.name, urgencia: urgencia, prazo: task.due_at&.iso8601 }
  end

  def fake_motivo?(motivo, urgencia)
    texto = motivo.tr('_', ' ')
    urgencia != 'alta' && (texto.match?(FAKE_TASK_RE) || texto.scan(/\p{L}/).size < 4)
  end

  # ⏰ prazo da tarefa de retorno: dia (YYYY-MM-DD, de hoje até 60 dias) + hora (HH:MM, padrão 09:00).
  # Devolve [due_at, nil] ou [nil, erro]; sem 'quando' = [nil, nil] (tarefa para hoje, como sempre)
  RETURN_MAX_DAYS = 60
  def task_due_at(args)
    return [nil, nil] if args['quando'].blank?

    date = parse_date(args['quando'])
    return [nil, 'quando deve ser uma data YYYY-MM-DD.'] if date.nil?

    hora = args['hora'].to_s.strip.presence || '09:00'
    return [nil, 'hora deve ser HH:MM.'] unless hora.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/)

    at = TZ.parse("#{date} #{hora}")
    return [nil, 'A data do retorno já passou: use hoje ou um dia futuro.'] if at < TZ.now.beginning_of_day
    return [nil, "Retorno no máximo em #{RETURN_MAX_DAYS} dias."] if at > RETURN_MAX_DAYS.days.from_now

    [at, nil]
  end

  # 🏷️ etiqueta da etapa no CONTATO → CrmAutomationTriggerService (após gravar)
  # dispara "ao receber etiqueta" na coluna atual de cada cartão dele
  def marcar_etapa(args)
    return refuse(STAGE_TOOL_NAME, 'Esta ferramenta não está disponível para este agente.') unless TASK_TOOL_KEYS.include?(@agent_key)

    etapa = args['etapa'].to_s.strip.downcase
    return refuse(STAGE_TOOL_NAME, 'Etapa fora da lista desta conta.') unless crm_etapas.pluck('etiqueta').include?(etapa)
    return refuse(STAGE_TOOL_NAME, 'Conversa sem contato.') if @contact.nil?

    if @contact.label_list.map(&:downcase).include?(etapa)
      log_acao(STAGE_TOOL_NAME, true, "etapa #{etapa} já estava marcada")
      return { ok: true, ja_marcada: true }
    end
    unless @live
      log_acao(STAGE_TOOL_NAME, true, "marcaria a etapa #{etapa} (simulado)")
      return { simulado: true, ok: true, mensagem: 'Em sombra nada foi marcado; a etiqueta seria posta no contato.' }
    end

    @account.labels.find_or_create_by!(title: etapa)
    @contact.add_labels([etapa])
    activity_note!("🏷️ #{agent_name} marcou a etapa: #{etapa}")
    log_acao(STAGE_TOOL_NAME, true, "marcou a etapa #{etapa}")
    { ok: true, etapa: etapa }
  end

  # o que já está na ficha deste cliente, para a IA não anotar de novo
  def summary_known
    return '' if @contact.nil?

    Crm::ClientSummary.lines(@contact, fields: summary_fields).map { |l| "#{l[:label]}: #{l[:value]}" }.join('; ')
  end

  # { 'conta' => 'R$ 300', … } só com campos desta conta e valor preenchido
  def summary_values(dados, labels)
    Array(dados).each_with_object({}) do |item, out|
      row = item.to_h.transform_keys(&:to_s)
      key = row['campo'].to_s
      value = row['valor'].to_s.squish
      out[key] = value if labels.key?(key) && value.present?
    end
  end

  # por que a anotação não pode ser feita (nil = pode)
  def summary_problem(values)
    return 'Esta ferramenta não está disponível para este agente.' unless TASK_TOOL_KEYS.include?(@agent_key)
    return 'Conversa sem contato.' if @contact.nil?

    'Nenhum dado da lista desta conta.' if values.empty?
  end

  # 📝 ficha do cliente: grava o que ele contou (Crm::ClientSummary) e põe a etiqueta do campo
  def anotar_cliente(args)
    labels = summary_fields.to_h { |f| [f['chave'], f['rotulo']] }
    values = summary_values(args['dados'], labels)
    problem = summary_problem(values)
    return refuse(SUMMARY_TOOL_NAME, problem) if problem

    resumo = values.map { |key, value| "#{labels[key]}: #{value}" }.join(' · ')
    unless @live
      log_acao(SUMMARY_TOOL_NAME, true, "anotaria na ficha: #{resumo} (simulado)")
      return { simulado: true, ok: true, mensagem: 'Em sombra nada foi gravado; a ficha do cliente receberia estes dados.' }
    end

    changed = Crm::ClientSummary.write!(@contact, values, by: "#{agent_name} (IA)")
    activity_note!("📝 #{agent_name} anotou na ficha do cliente: #{resumo}") if changed.any?
    log_acao(SUMMARY_TOOL_NAME, true, "anotou na ficha: #{resumo}")
    { ok: true, anotado: changed }
  end

  # 📨 orçamento gerado e ainda não enviado a este cliente (o mais novo)
  def pending_quote
    return @pending_quote if defined?(@pending_quote)

    @pending_quote = @contact && Crm::Quote.ativos.where(account: @account, contact: @contact, sent_at: nil).recent.first
  end

  def quote_definition
    {
      name: QUOTE_TOOL_NAME,
      description: "Envia ao cliente o ORÇAMENTO JÁ PRONTO (#{Crm::KitQuote::CardUpdate.new(pending_quote).summary_text}): o PDF da proposta " \
                   'e a pergunta de fechamento ("É interessante para você fazer esse investimento agora?"). ' \
                   'Use quando o cliente pedir o orçamento ou responder à mensagem "seu orçamento está pronto" (ex.: "pode mandar"). ' \
                   'Uma vez por orçamento.',
      input_schema: { type: 'object', properties: {}, additionalProperties: false }
    }
  end

  def enviar_orcamento
    return refuse(QUOTE_TOOL_NAME, 'Esta ferramenta não está disponível para este agente.') unless TASK_TOOL_KEYS.include?(@agent_key)
    return refuse(QUOTE_TOOL_NAME, 'Não há orçamento pronto por enviar: diga que o Fernando te manda assim que ficar pronto.') if pending_quote.nil?

    test_conversation = @simulation && Crm::AgentSimulator.simulated?(@conversation)
    unless @live
      log_acao(QUOTE_TOOL_NAME, true, "enviaria o orçamento ##{pending_quote.id} (simulado)")
      return { simulado: true, ok: true, mensagem: 'Em sombra nada foi enviado; ao vivo o PDF e a pergunta de fechamento iriam agora.' }
    end
    return refuse(QUOTE_TOOL_NAME, 'Conversa de teste: o orçamento não é enviado aqui.') if test_conversation

    Crm::KitQuote::Delivery.new(pending_quote, agent_key: @agent_key).deliver!
    log_acao(QUOTE_TOOL_NAME, true, "enviou o orçamento ##{pending_quote.id}")
    { ok: true, enviado: true,
      aviso: 'O orçamento JÁ FOI ENVIADO: PDF da proposta e a pergunta de fechamento "É interessante para você ' \
             'fazer esse investimento agora?". NÃO repita a pergunta nem mande outro balão agora: espere a resposta do cliente.' }
  end

  # 🖼️ imagem pronta do roteiro → mensagem com anexo na conversa (Crm::ScriptImages).
  # Ao vivo: vai ao cliente. Testar agente: entra na conversa de teste (sem canal).
  # Sombra numa conversa real: nada é enviado, só registrado.
  def enviar_imagem(args)
    enviar_midia(IMAGE_TOOL_NAME, 'imagem', script_images, args['imagem'], args)
  end

  # 🔊 09/11: áudio pronto (ex.: o Fernando apresentando a Life) — mesmo caminho da imagem
  def enviar_audio(args)
    enviar_midia(AUDIO_TOOL_NAME, 'áudio', script_audios, args['audio'], args)
  end

  def enviar_midia(tool, nome, lista, chave_bruta, args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    plural = nome == 'áudio' ? 'áudios' : 'imagens'
    art = nome == 'áudio' ? 'o' : 'a'
    return refuse(tool, 'Esta ferramenta não está disponível para este agente.') unless TASK_TOOL_KEYS.include?(@agent_key)

    chave = chave_bruta.to_s.strip.downcase
    image = lista.find { |i| i['chave'] == chave }
    return refuse(tool, "#{nome.capitalize} fora da lista desta conta: siga só em texto.") if image.nil?

    sent = Crm::ScriptImages.sent_count(@conversation, chave)
    if sent.positive? && args['reenviar'] != true
      log_acao(tool, true, "#{nome} #{chave} já tinha ido nesta conversa")
      return { ok: true, ja_enviada: true,
               aviso: "Est#{nome == 'áudio' ? 'e áudio' : 'a imagem'} JÁ FOI enviad#{nome == 'áudio' ? 'o' : 'a'} antes nesta conversa. " \
                      'Só reenvie (reenviar=true) se o cliente disser que não chegou; senão, siga em texto.' }
    end
    if sent >= Crm::ScriptImages::MAX_SENDS
      return refuse(tool, "#{nome.capitalize} já foi reenviad#{art}. Siga em texto e, se o cliente não recebe " \
                          "#{plural}, abra tarefa normal (\"cliente não recebe #{plural}\").")
    end

    test_conversation = @simulation && Crm::AgentSimulator.simulated?(@conversation)
    unless @live || test_conversation
      log_acao(tool, true, "enviaria #{art} #{nome} #{chave} (simulado)")
      return { simulado: true, ok: true, legenda_enviada: image['legenda'].presence,
               mensagem: "Em sombra nada foi enviado; ao vivo #{art} #{nome} iria ao cliente agora. Siga como se tivesse chegado." }
    end

    message = Crm::ScriptImages.send!(@conversation, image, @agent_key)
    log_acao(tool, true, "enviou #{art} #{nome} #{chave}#{' (conversa de teste)' if test_conversation}")
    { ok: true, enviada: true, mensagem_id: message.id, legenda_enviada: image['legenda'].presence,
      aviso: if nome == 'áudio'
               'O áudio JÁ FOI ENVIADO (com a frase de apresentação antes dele). Não repita o que ele diz: ' \
                 'siga a conversa no balão, como o roteiro manda para este momento.'
             elsif !image['faz_pergunta']
               'A imagem JÁ FOI ENVIADA com a legenda acima (é prova, não pergunta nada). Não repita o que ela diz: ' \
                 'siga a conversa no balão, como o roteiro manda para este momento.'
             elsif image['legenda'].present?
               'A imagem JÁ FOI ENVIADA com a legenda acima, que já faz a pergunta. NÃO repita a pergunta: no máximo um ' \
                 'balão curto comentando a resposta anterior do cliente, sem nova pergunta.'
             else
               'A imagem JÁ FOI ENVIADA. Faça a pergunta dela em um balão curto.'
             end }
  end

  # ── vagas de um dia específico (item 200: agendamento futuro liberado) ──
  # Só lê a Agenda: vale igual em sombra e ao vivo.
  def horarios_do_dia(args)
    date = parse_date(args['dia'])
    return refuse('horarios_do_dia', 'Informe o dia no formato YYYY-MM-DD.') if date.nil?

    # item 307: quem tem retorno/pós-operatório marcado vê as vagas das faixas desse tipo
    booked = Crm::AppointmentRecorder.future_appointment(@account, @contact&.phone_number, nil, @contact)
    modality = Crm::AgendaSlots.slot_modality(booked)
    slots = Crm::AgendaSlots.free_slots_on(@account, date, unit: args['unidade'].to_s.strip.presence, per_window: 8, modality: modality)
    log_acao('horarios_do_dia', true, "vagas de #{WEEKDAYS_SHORT[date.wday]} #{date.strftime('%d/%m')}: #{slots_count_text(slots)}")
    result = { dia: date.to_s, dia_semana: Crm::AgendaSlots::WEEKDAYS[date.wday], vagas: group_slots(slots) }
    result[:aviso] = 'Nenhuma vaga nesse dia (sem atendimento, fechado ou lotado). Ofereça o dia de atendimento mais próximo.' if slots.empty?
    result
  end

  def group_slots(slots)
    slots.group_by { |s| [s[:unit], s[:doctor]] }.map do |(unit, doctor), list|
      { unidade: unit_label(unit), unidade_chave: unit, medico: doctor, horarios: list.map { |s| s[:time] } }
    end
  end

  def slots_count_text(slots)
    return 'nenhuma' if slots.empty?

    "#{slots.size} livre#{'s' if slots.size > 1}"
  end

  # etiqueta + card (item 200); devolve o texto curto para a nota
  def side_effects(task, outcome)
    effects = Crm::BookingSideEffects.apply(account: @account, contact: task.contact || @contact, conversation: @conversation, outcome: outcome)
    Crm::BookingSideEffects.summary(effects)
  end

  # ── apoio ───────────────────────────────────────────────────────────────
  # só consultas do escopo (conta + futura + ativa): id de fora = não existe
  def find_task(id)
    return nil unless id.to_i.positive?

    scope.find_by(id: id.to_i)
  end

  def not_found(tool)
    refuse(tool, 'Consulta não encontrada (confira o id com buscar_consulta).')
  end

  # ── 🔒 dono da consulta (auditoria 10/10, achados #99/#442) ─────────────
  # Remarcar/cancelar/confirmar só na consulta do PRÓPRIO contato (own?) ou
  # com prova forte: telefone completo (com DDD) cadastrado na consulta + nome
  # completo, os dois ditados por quem conversa. A regra vale igual em sombra.
  def allowed?(task, args)
    own?(task) || strong_proof?(task, args)
  end

  def strong_proof?(task, args)
    digits = args['telefone'].to_s.gsub(/\D/, '')
    return false if digits.length < PROOF_MIN_DIGITS
    return false unless Crm::AppointmentRecorder.same_phone_line?(digits, task.phone)

    name_matches?(args['nome_completo'], task)
  end

  # nome completo ditado (2+ palavras de verdade, com o primeiro nome) tem que
  # bater com o nome da consulta — mesma régua do reagendamento pela IA
  def name_matches?(given, task)
    Crm::AppointmentRecorder.same_patient_name?(given, patient_name(task))
  end

  # consulta de outra pessoa sem prova: nada é executado; ao vivo abre tarefa
  # para a equipe conferir com o titular; a IA recebe ok=false com a orientação
  # certa para o que aconteceu (tarefa aberta, falhou ou sombra). Sem o campo
  # `simulado`: a recusa vale igual em sombra, não é "faça de conta que fez".
  def third_party(tool, task, args, verb)
    motivo = "Pediu para #{verb} de outra pessoa (#{patient_name(task)}, #{when_label(task)})"
    opened = @live && open_handoff!(motivo, args)
    status = if opened
               :opened
             elsif @live
               :failed
             else
               :shadow
             end
    resumo = { opened: 'tarefa aberta para a equipe', failed: 'tarefa para a equipe NÃO foi aberta (falha)',
               shadow: 'abriria tarefa para a equipe (simulado)' }[status]
    log_acao(tool, false, "#{motivo}: não executado, #{resumo}", 'outra_pessoa' => true, 'tarefa_aberta' => opened)
    { ok: false, outra_pessoa: true, motivo: "#{THIRD_PARTY_TEXTS[status]} #{PROOF_HINT}" }
  end

  # true quando a tarefa foi aberta (ou complementada); false quando falhou
  def open_handoff!(motivo, args)
    Crm::HandoffTask.open!(account: @account, contact: @contact, conversation: @conversation, agent_key: @agent_key,
                           motivo: motivo, detalhes: handoff_details(args), urgencia: 'normal')
    true
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderTools] tarefa de outra pessoa: #{e.message}"
    false
  end

  def handoff_details(args)
    who = @contact&.name.presence || 'sem nome'
    phone = @contact&.phone_number.presence || 'desconhecido'
    lines = ["Quem conversa: #{who} · telefone deste WhatsApp: #{phone}"]
    lines << "Telefone ditado: #{args['telefone']}" if args['telefone'].present?
    lines << "Nome ditado: #{args['nome_completo']}" if args['nome_completo'].present?
    lines << 'A IA não executou: conferir com o titular da consulta antes de mexer.'
    lines.join("\n")
  end

  # ── ⚡ orçamento automático ──
  def auto_quote_available?
    TASK_TOOL_KEYS.include?(@agent_key) && auto_quote_enabled? && pending_quote.nil? && !Crm::KitQuoteAutoJob.running?(@conversation)
  end

  def auto_quote_enabled?
    CrmSetting.find_by(account: @account)&.ai_config&.dig('agents', @agent_key, 'orcamento_automatico') == true
  end

  def auto_quote_definition
    {
      name: AUTO_QUOTE_TOOL_NAME,
      description: 'Gera o ORÇAMENTO OFICIAL deste cliente agora e envia sozinho em uns 30 segundos (PDF + pergunta de fechamento). ' \
                   'Use quando a ficha já tem o valor da conta de luz e o tipo de telhado (anote antes com anotar_cliente) e o ' \
                   'cliente já respondeu se vai aumentar o consumo (anote em consumo_futuro o que e quantos: ex. ' \
                   '"2 ar-condicionados de 12 mil", "carro elétrico", "piscina aquecida"; o sistema soma na conta sozinho). ' \
                   'Na mesma resposta diga só, curto: "Já estou gerando o seu orçamento aqui, consultando os valores ' \
                   'atualizados. Em alguns segundos te mando, ok?" e não abra tarefa de orçamento. Uma vez por cliente.',
      input_schema: { type: 'object', properties: {}, additionalProperties: false }
    }
  end

  def gerar_orcamento # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return refuse(AUTO_QUOTE_TOOL_NAME, 'Esta ferramenta não está disponível agora.') unless auto_quote_available?

    missing = Crm::KitQuote::AutoBuild.missing(@contact)
    return refuse(AUTO_QUOTE_TOOL_NAME, "Ainda não dá para gerar: #{missing}. Pergunte isso ao cliente (uma pergunta só).") if missing

    increase = Crm::KitQuote::ClientData.new(@contact).call['aumento']
    if increase && Crm::KitQuote::Increase.parse(increase)[:desconhecido]
      opened = @live && open_handoff_quote!("Orçamento: aumento de consumo previsto · #{increase} · gerar contando com o aumento")
      log_acao(AUTO_QUOTE_TOOL_NAME, true, "aumento fora da tabela (#{increase}): orçamento fica com a equipe#{' (simulado)' unless @live}",
               'tarefa_aberta' => opened)
      return { ok: true, automatico: false,
               mensagem: 'Com aumento de consumo o orçamento é montado pela equipe. Diga que vai montar contando com o que ' \
                         'ele comentou e que em alguns minutos manda aqui, combinado? Não prometa horário.' }
    end

    unless @live
      log_acao(AUTO_QUOTE_TOOL_NAME, true, 'geraria e enviaria o orçamento automático (simulado)')
      return { simulado: true, ok: true, mensagem: 'Em sombra nada é gerado; ao vivo o orçamento sairia em ~30 s.' }
    end
    if @simulation && Crm::AgentSimulator.simulated?(@conversation)
      return refuse(AUTO_QUOTE_TOOL_NAME, 'Conversa de teste: o orçamento automático não roda aqui.')
    end

    Crm::KitQuoteAutoJob.enqueue!(@conversation, @agent_key)
    activity_note!('⚡ Orçamento automático pedido pelo atendente: gerando (cotação + PDF) e envia sozinho em ~30 s.')
    log_acao(AUTO_QUOTE_TOOL_NAME, true, 'orçamento automático em geração')
    { ok: true, gerando: true,
      aviso: 'O orçamento JÁ ESTÁ SENDO GERADO e vai sozinho em ~30 s com a pergunta de fechamento. Agora diga só que já está ' \
             'gerando e que em alguns segundos manda. Não mande valor, não faça outra pergunta e não abra tarefa de orçamento.' }
  end

  def open_handoff_quote!(motivo)
    Crm::HandoffTask.open!(account: @account, contact: @contact, conversation: @conversation, agent_key: @agent_key,
                           motivo: motivo, urgencia: 'alta')
    true
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderTools] tarefa do orçamento: #{e.message}"
    false
  end

  def refuse(tool, motivo)
    log_acao(tool, false, motivo.truncate(80))
    { ok: false, motivo: motivo }
  end

  # mesma trava da reserva do job (conta+dia+hora+unidade), 30 s
  def with_slot_lock(date, time, unit)
    lock = Redis::LockManager.new
    key = "CRM_SLOT_LOCK::#{@account.id}::#{date}::#{time}::#{unit}"
    return refuse('remarcar_consulta', 'Outra pessoa está pegando essa vaga agora; tente de novo em instantes.') unless lock.lock(key, LOCK_TTL)

    begin
      yield
    ensure
      lock.unlock(key)
    end
  end

  def serialize(task)
    at = task.due_at.in_time_zone(TZ)
    {
      id: task.id, paciente: patient_name(task),
      dia: at.strftime('%Y-%m-%d'), hora: at.strftime('%H:%M'), dia_semana: Crm::AgendaSlots::WEEKDAYS[at.wday],
      unidade: unit_label(task.unit), medico: task.doctor.presence || 'a definir',
      procedimento: task.procedure.presence || 'consulta de avaliação',
      telefone_final: task.phone.to_s.gsub(/\D/, '').last(4).presence,
      status: status_label(task), do_proprio_contato: own?(task)
    }
  end

  def status_label(task)
    return 'cancelada' if task.canceled_at.present?
    return 'presença confirmada' if task.description.to_s.include?('Presença confirmada')

    task.status == 'doing' ? 'em atendimento' : 'agendada'
  end

  def own?(task)
    return true if @contact && task.contact_id == @contact.id

    own_digits = @contact&.phone_number.to_s.gsub(/\D/, '')
    own_digits.length >= 8 && Crm::AppointmentRecorder.same_phone_line?(own_digits, task.phone)
  end

  def patient_name(task)
    task.title.to_s.sub(/\AConsulta:\s*/i, '').strip.presence || 'Paciente'
  end

  def unit_label(unit)
    Crm::AgendaSlots.unit_label(@account, unit) || 'unidade a definir'
  end

  def when_label(task)
    at = task.due_at.in_time_zone(TZ)
    "#{WEEKDAYS_SHORT[at.wday]} #{at.strftime('%d/%m %H:%M')} · #{unit_label(task.unit)}"
  end

  def agent_name
    AGENT_NAMES[@agent_key] || @agent_key
  end

  def stamp
    TZ.now.strftime('%d/%m %H:%M')
  end

  def parse_date(value)
    return nil if value.blank?

    Date.strptime(value.to_s.strip, '%Y-%m-%d')
  rescue ArgumentError, TypeError
    nil
  end

  def day_range(day)
    TZ.parse(day.to_s).all_day
  end

  def append_note(description, note)
    [description.presence, note].compact.join("\n\n")
  end

  def agenda_link(starts_at)
    "[📆 Ver na agenda](/app/accounts/#{@account.id}/agenda?date=#{starts_at.strftime('%Y-%m-%d')})"
  end

  # rastro na conversa para a equipe (nota interna, nunca chega ao paciente)
  def activity_note!(content)
    @conversation.messages.create!(
      account_id: @account.id, inbox_id: @conversation.inbox_id,
      message_type: :activity, private: true, content: content
    )
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderTools] nota: #{e.message}"
  end

  # extra: marcas a mais para o job (ex.: 'outra_pessoa' => true, 'tarefa_aberta' => true)
  def log_acao(ferramenta, success, resumo, extra = {})
    @acoes << { 'ferramenta' => ferramenta, 'ok' => success == true, 'resumo' => resumo.to_s }.merge(extra)
  end
end
