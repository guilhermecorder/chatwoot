# 02/11: LEAD QUE A PÁGINA MANDA ANTES DO WHATSAPP (página Pré-análise):
# nome + telefone + respostas do quiz chegam por POST /p/:slug/lead. O
# paciente nasce no sistema mesmo que a pessoa nunca aperte "enviar" no
# WhatsApp — é o "lead de verdade" pedido pelo Guilherme.
#
# Mesmas regras do formulário público (auditoria, achados #118/#119):
#   · telefone de cadastro EXISTENTE → o cadastro NÃO muda (nem o nome);
#   · telefone DESCONHECIDO → paciente novo SEM card (fora dos indicadores de
#     etapa; o card nasce quando ele escreve no WhatsApp) + tarefa "chamar no
#     WhatsApp" para a equipe enxergar; teto diário por conta;
#   · a resposta é IGUAL para qualquer telefone (LGPD): ninguém descobre pela
#     página se um número é paciente da clínica.
#
# O Protocolo nasce AQUI (CevicoPageRef) e volta para a página pôr na mensagem
# do WhatsApp — o clique depois não pede outro nem conta duas vezes. O contato
# recebe o carimbo page_ads na hora (primeiro toque vence), por isso já aparece
# como lead em Resultados de tráfego e na Biblioteca; as respostas ficam em
# additional_attributes['pre_analise'].
class Cevico::PageLead
  DAILY_CAP = ENV.fetch('CEVICO_PAGE_LEAD_DAILY_CAP', '300').to_i
  MAX_ANSWERS = 12
  MAX_VALUE = 80
  ATTR = 'pre_analise'.freeze
  PENDING_KEY = 'cevico_page_lead_pending'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def initialize(page:, params:, request:)
    @page = page
    @account = page.account
    @params = params
    @request = request
    @new_contact = false
  end

  def call
    name, digits = identity
    return { ok: false, error: 'identity' } if name.nil?

    answers = sanitized_answers
    contact = find_contact(digits) || create_contact(name, digits)
    ref = mint_ref
    register!(contact, ref, answers, name)
    count_click!(ref)
    { ok: true, token: ref&.token, line: ref && "Protocolo: #{ref.token}" }.compact
  rescue StandardError => e
    Rails.logger.error "[Cevico::PageLead] #{@page.slug}: #{e.class}: #{e.message}"
    { ok: false }
  end

  private

  # nome com 2+ letras e telefone com DDD (10 a 13 dígitos); senão [nil, nil]
  def identity
    name = @params[:nome].to_s.strip[0, 120]
    digits = @params[:telefone].to_s.gsub(/\D/, '')
    return [nil, nil] if name.length < 2 || digits.length < 10 || digits.length > 13

    [name, digits]
  end

  # carimbo + respostas no contato e, se ele é novo, a tarefa para a equipe
  def register!(contact, ref, answers, name)
    return if contact.nil?

    stamp!(contact, ref, answers, name)
    open_task!(contact, answers) if @new_contact
  end

  # respostas do quiz: só texto curto, poucas chaves (nada de JSON gigante)
  def sanitized_answers
    raw = @params[:respostas]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return {} unless raw.is_a?(Hash)

    raw.first(MAX_ANSWERS).to_h { |k, v| [k.to_s[0, 40], v.to_s.strip[0, MAX_VALUE]] }.compact_blank
  end

  # origem da visita: o que o script da página guardou (utm/gclid/ref_host),
  # senão o referer do POST
  def origin_params
    raw = @params[:origem]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : {}
  end

  def find_contact(digits)
    @account.contacts
            .where.not(phone_number: [nil, ''])
            .where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
            .order(:id)
            .find { |c| Crm::AppointmentRecorder.same_phone_line?(digits, c.phone_number) }
  end

  # paciente novo SEM card; passou do teto do dia → não cria (resposta igual)
  def create_contact(name, digits)
    return nil unless allowed_today?

    e164 = digits.start_with?('55') && digits.length >= 12 ? "+#{digits}" : "+55#{digits}"
    contact = Crm::Stamp.with(via: 'paciente') { @account.contacts.create!(name: name, phone_number: e164) }
    @new_contact = true
    contact
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    find_contact(digits) # corrida (dois envios) ou outra máscara do mesmo número
  end

  def allowed_today?
    key = "cevico:page_lead_cap:#{@account.id}:#{Time.current.in_time_zone(TZ).to_date.iso8601}"
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 1.day.to_i) if count == 1
    count <= DAILY_CAP
  rescue StandardError
    true
  end

  def mint_ref
    data = Cevico::TrafficSource.snapshot(origin_params, page: @page, cookies: @request.cookies, referer: @request.referer)
    data['source'] = Cevico::TrafficSource.classify(origin_params, referer: @request.referer, account: @page.account)[:source] if origin_params.blank?
    CevicoPageRef.mint!(page: @page, source_data: data.merge('via' => 'pagina_lead'))
  end

  # carimbo de origem (primeiro toque vence) + respostas do quiz + marca de
  # pendente quando o paciente é novo — num merge atômico, sem apagar o resto
  def stamp!(contact, ref, answers, name)
    now = Time.current.iso8601
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      merged = attrs.merge(ATTR => { 'respostas' => answers, 'nome_informado' => name, 'pagina' => @page.slug, 'em' => now })
      merged = merged.merge(PENDING_KEY => { 'page_id' => @page.id, 'at' => now }) if @new_contact
      merged['page_ads'].present? || ref.nil? ? merged : merged.merge('page_ads' => attribution(ref, now))
    end
    ref&.update(contact_id: contact.id) if ref&.contact_id.nil?
  end

  def attribution(ref, now)
    ref.source_data.merge('token' => ref.token, 'clicked_at' => ref.created_at.iso8601, 'captured_at' => now, 'via' => 'pagina_lead')
  end

  def open_task!(contact, answers)
    resumo = answers.map { |k, v| "#{k}: #{v}" }.join(' · ')
    Crm::HandoffTask.open!(
      account: @account, contact: contact, conversation: nil, agent_key: 'Página',
      motivo: "Lead da página «#{@page.title}» — chamar no WhatsApp",
      detalhes: 'A pessoa deixou nome e WhatsApp na página e ainda não escreveu para a clínica. ' \
                "Respostas da pré-análise: #{resumo.presence || 'sem respostas'}. " \
                'Chame no WhatsApp com a pré-análise completa e o investimento; confirme o número antes de agendar.'
    )
  rescue StandardError => e
    Rails.logger.warn "[Cevico::PageLead] tarefa (paciente #{contact&.id}): #{e.message}"
    nil
  end

  # conta como clique no convite (o botão do WhatsApp depois NÃO conta de novo)
  def count_click!(ref)
    source = ref&.source_data&.dig('source') || 'direto'
    CevicoPageTraffic.bump!(page: @page, kind: 'cta', source: source, campaign: ref&.source_data&.dig('campaign').to_s)
    @page.track_hit!('cta')
  rescue StandardError => e
    Rails.logger.warn "[Cevico::PageLead] contagem: #{e.message}"
  end
end
