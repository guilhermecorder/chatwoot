# 🧪 item 383: SEGMENTAÇÃO DA BASE + TESTES DE MENSAGEM (menu Segmentação).
# Leitura para o time; criar, iniciar, pausar, mandar leva e escalar = quem
# edita campanhas (nó crm.campanhas).
class Api::V1::Accounts::Crm::SegmentsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  before_action -> { require_access('crm.campanhas', :edit) }, only: %i[create update destroy start pause tick_now escalar]
  before_action :segment, only: %i[show update destroy start pause tick_now results members escalar]

  def index
    render json: { segments: segments_scope.order(id: :desc).limit(100).map { |s| Crm::SegmentResults.summary(s) } }
  end

  # a base inteira (colunas da casa), as caixas com os modelos aprovados e os padrões
  def base
    render json: {
      stages: Crm::SegmentBuilder.base_overview(Current.account),
      inboxes: inboxes_json,
      defaults: { source: Crm::SegmentBuilder.normalize_source({}), pace: Crm::SegmentSender.normalize_pace({}) },
      steps: Crm::SegmentSender::STEPS, max_variants: Crm::Segment::MAX_VARIANTS
    }
  end

  # a peneira, regra a regra, sem reservar nada
  def preview
    render json: Crm::SegmentBuilder.preview(Current.account, Crm::SegmentBuilder.normalize_source(params[:source]&.to_unsafe_h))
  end

  def show
    render json: Crm::SegmentResults.summary(@segment).merge(results: Crm::SegmentResults.for(@segment))
  end

  def create
    kind = Crm::Segment::KINDS.include?(params[:kind].to_s) ? params[:kind].to_s : 'teste'
    seg = Crm::SegmentBuilder.reserve!(
      Current.account, name: params[:name], kind: kind, source: params[:source]&.to_unsafe_h,
                       variants: params[:variants]&.map(&:to_unsafe_h), pace: params[:pace]&.to_unsafe_h, user: Current.user
    )
    render json: Crm::SegmentResults.summary(seg)
  rescue ArgumentError => e
    render_could_not_create_error(e.message)
  end

  # nome e ritmo sempre; mensagens só enquanto ninguém recebeu
  def update # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    @segment.name = params[:name].to_s.strip if params[:name].present?
    @segment.pace = Crm::SegmentSender.normalize_pace(params[:pace]&.to_unsafe_h) if params[:pace].present?
    if params[:variants].present?
      return render_could_not_create_error('Este segmento já mandou mensagem: as mensagens não mudam mais') unless @segment.editable_variants?

      vars = Crm::SegmentBuilder.normalize_variants(params[:variants].map(&:to_unsafe_h))
      return render_could_not_create_error('Mantenha o mesmo número de mensagens (A, B, C…)') if vars.size != Array(@segment.variants).size

      @segment.variants = vars
    end
    @segment.save!
    render json: Crm::SegmentResults.summary(@segment)
  end

  def destroy
    Crm::SegmentBuilder.release!(@segment)
    head :ok
  rescue ArgumentError => e
    render_could_not_create_error(e.message)
  end

  def start
    return render_could_not_create_error('Este segmento já terminou') if @segment.done?

    @segment.update!(status: 'enviando', started_at: @segment.started_at || Time.current)
    render json: Crm::SegmentResults.summary(@segment)
  end

  def pause
    return render_could_not_create_error('O segmento não está enviando') unless @segment.sending?

    @segment.update!(status: 'pausado')
    render json: Crm::SegmentResults.summary(@segment)
  end

  # manda a próxima leva agora (ignora janela e relógio; teto do dia vale)
  def tick_now
    unless @segment.sending? || @segment.status == 'pausado'
      return render_could_not_create_error('Inicie (ou pause) o segmento antes de mandar uma leva')
    end

    limit = params[:limit].present? ? params[:limit].to_i.clamp(1, 5000) : nil
    # a leva sai pelo robô (fora da requisição: 150 pessoas × 0,2 s passam do tempo do servidor);
    # a trava dentro de tick! garante que robô e botão nunca mandam a mesma leva
    Crm::SegmentDripJob.perform_later(@segment.id, force: true, limit: limit)
    render json: Crm::SegmentResults.summary(@segment).merge(queued: limit || Crm::SegmentSender.step_size(Crm::SegmentSender.pace(@segment)))
  end

  def results
    render json: Crm::SegmentResults.for(@segment)
  end

  # as pessoas do segmento (até 500 por página), com filtro por mensagem e situação
  def members # rubocop:disable Metrics/AbcSize
    scope = @segment.members.includes(:contact).order(:id)
    scope = scope.where(variant_key: params[:variant]) if params[:variant].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    page = params.fetch(:page, 1).to_i.clamp(1, 1000)
    rows = scope.offset((page - 1) * 500).limit(500)
    render json: { total: scope.count, page: page, rows: rows.map { |m| member_json(m) } }
  end

  # 🏆 escala a vencedora: um lote novo (escala) com a mesma peneira, UMA mensagem
  def escalar # rubocop:disable Metrics/AbcSize
    variant = @segment.variant(params[:variant])
    return render_could_not_create_error('Escolha a mensagem vencedora') if variant.nil?

    source = @segment.source.merge('size' => params[:size].to_i, 'seed' => '')
    seg = Crm::SegmentBuilder.reserve!(
      Current.account, name: params[:name].presence || "Escala · #{@segment.name} · #{variant['label']}", kind: 'escala',
                       source: source, variants: [variant], pace: params[:pace].present? ? params[:pace].to_unsafe_h : @segment.pace,
                       user: Current.user, parent: @segment
    )
    render json: Crm::SegmentResults.summary(seg)
  rescue ArgumentError => e
    render_could_not_create_error(e.message)
  end

  def dashboard
    render json: Crm::SegmentResults.dashboard(Current.account)
  end

  private

  def segments_scope
    Crm::Segment.where(account_id: Current.account.id)
  end

  def segment
    @segment = segments_scope.find(params[:id])
  end

  def inboxes_json
    Crm::ReactivationPlan.whatsapp_inboxes(Current.account).map do |i|
      { id: i.id, name: i.name,
        templates: Array(i.channel.try(:message_templates)).select { |t| t['status'].to_s.downcase == 'approved' }
                                                           .map { |t| t.slice('name', 'language', 'category', 'namespace', 'components') } }
    end
  end

  def member_json(row)
    { id: row.id, contact_id: row.contact_id, name: row.contact&.name.presence || 'Sem nome', phone: row.contact&.phone_number,
      variant: row.variant_key, status: row.status, frente: row.frente, inbox_id: row.inbox_id, sent_at: row.sent_at&.iso8601,
      conversation_id: row.conversation_id }
  end
end
