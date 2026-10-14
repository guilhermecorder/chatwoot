# 🏷️ FONTES DE PACIENTES (item 322, só admin): o cadastro das fontes (cada uma
# com o seu ambiente: funis e caixas), o retrato do carimbo e o botão que
# carimba o passado (prévia antes de gravar).
# 🧭 item 341 (13/10, "Ambientes do CRM"): a tela passa a ser a VERDADE ÚNICA de
# qual número (caixa) e qual funil ficam em qual ambiente — inclusive o do
# Oftalmofácil (antes só no card de Integrações; salvar aqui atualiza o card
# também). Caixa ou funil que já é de outro ambiente → 422 com o motivo.
class Api::V1::Accounts::Crm::SourcesController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action :set_source, only: [:update]

  def index
    render json: Crm::SourceOverview.new(Current.account).call
  end

  # POST /crm/sources — fonte nova (sempre parceira; a da casa é uma só)
  def create
    source = Crm::Source.new(account: Current.account, kind: 'partner', key: unique_key(params[:name]),
                             position: Crm::Source.where(account_id: Current.account.id).maximum(:position).to_i + 1)
    save_and_render(source)
  end

  def update
    save_and_render(@source)
  end

  # POST /crm/sources/backfill — { apply: false } mostra o que seria carimbado;
  # { apply: true } grava. Só toca em registro sem carimbo.
  def backfill
    apply = ActiveModel::Type::Boolean.new.cast(params[:apply]) == true
    result = apply ? Crm::SourceBackfill.run!(Current.account) : Crm::SourceBackfill.preview(Current.account)
    render json: { applied: apply, result: result, pending: Crm::SourceBackfill.pending(Current.account) }
  end

  # 🧩 item 344 (PRÉ-DEFINIÇÃO): as colunas da jornada no funil do
  # Oftalmofácil — GET mostra o que existe e o que falta; POST cria as que
  # faltam e põe o funil na ordem da jornada (nada é apagado nem renomeado;
  # colunas fora da jornada vão para o fim)
  def funnel_preset
    render json: { preset: Crm::PartnerFunnel.preset_preview(Current.account) }
  end

  def apply_funnel_preset
    return render json: { error: 'O ambiente Oftalmofácil ainda não tem funil — escolha o funil em Editar.' }, status: :unprocessable_entity \
      unless Crm::PartnerFunnel.pipeline(Current.account)

    Crm::PartnerFunnel.apply_preset!(Current.account)
    render json: { preset: Crm::PartnerFunnel.preset_preview(Current.account) }
  end

  private

  def set_source
    @source = Crm::Source.find_by!(account_id: Current.account.id, id: params[:id])
  end

  def save_and_render(source) # rubocop:disable Metrics/AbcSize
    source.name = params[:name].to_s.strip if params.key?(:name)
    source.color = params[:color].to_s[/\A#\h{6}\z/] if params.key?(:color)
    problem = assign_environment(source)
    return render json: { error: problem }, status: :unprocessable_entity if problem
    return render json: { error: source.errors.full_messages.to_sentence }, status: :unprocessable_entity unless source.save

    sync_legacy_card!(source)
    # o funil mudou de dono → cards e entradas dele acompanham
    Crm::SourceBackfill.restamp_funnels!(Current.account)
    Crm::PartnerGuard.forget!(Current.account)
    # 🧩 item 344: as colunas que faltam nascem pelo botão da pré-definição (ou
    # sob demanda, quando um card precisa delas) — salvar não cria 11 colunas sozinho
    render json: Crm::SourceOverview.new(Current.account).call
  end

  # funis e caixas da fonte. A da casa não escolhe (fica com o resto). 🧭 item
  # 341: a do Oftalmofácil também escolhe aqui. Devolve o motivo quando a
  # caixa/funil já é de outro ambiente (nil = tudo certo).
  def assign_environment(source) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if source.own?

    taken = Crm::Source.where(account_id: Current.account.id).where.not(id: source.id).reject(&:own?)
    if params.key?(:pipeline_ids)
      wanted = Array(params[:pipeline_ids]).map(&:to_i).uniq & Current.account.crm_pipelines.pluck(:id)
      # o funil principal da casa (o de entrada dos leads e dos indicadores) nunca muda de dono
      main = wanted & Crm::Sources.main_pipeline_ids(Current.account)
      return 'O funil principal da CEVICO não pode sair do ambiente da casa.' if main.any?

      clash = clash_message(taken, wanted, :pipeline_ids, 'O funil', Current.account.crm_pipelines)
      return clash if clash

      source.config = source.config.merge('pipeline_ids' => wanted)
    end
    return nil unless params.key?(:inbox_ids)

    wanted = Array(params[:inbox_ids]).map(&:to_i).uniq & Current.account.inboxes.pluck(:id)
    clash = clash_message(taken, wanted, :inbox_ids, 'O número/caixa', Current.account.inboxes)
    return clash if clash

    source.config = source.config.merge('inbox_ids' => wanted)
    nil
  end

  # cada caixa e cada funil pertencem a UM ambiente só
  def clash_message(taken, wanted, method, label, scope)
    taken.each do |other|
      ids = wanted & other.public_send(method)
      next if ids.empty?

      return "#{label} «#{scope.where(id: ids).pluck(:name).to_sentence}» já está no ambiente «#{other.name}». Tire de lá primeiro."
    end
    nil
  end

  # 🧭 item 341: o card do OftalmoFácil em Integrações (que a sincronização e a
  # cerca ainda leem) passa a refletir o que foi escolhido aqui
  def sync_legacy_card!(source) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return unless source.legacy_partner? && (params.key?(:pipeline_ids) || params.key?(:inbox_ids))

    setting = CrmSetting.find_or_create_by!(account_id: Current.account.id)
    agenda = (setting.agenda_config || {}).deep_dup
    of = agenda['oftalmofacil'] || {}
    of['partner_inbox_ids'] = Array(source.config['inbox_ids']).map(&:to_i) if params.key?(:inbox_ids)
    if params.key?(:pipeline_ids)
      ids = Array(source.config['pipeline_ids']).map(&:to_i)
      # o funil do hub continua o mesmo se ficou marcado
      keep = ids.include?(of['partner_pipeline_id'].to_i) ? of['partner_pipeline_id'].to_i : ids.first
      keep ? of['partner_pipeline_id'] = keep : of.delete('partner_pipeline_id')
    end
    agenda['oftalmofacil'] = of
    setting.update!(agenda_config: agenda)
  end

  def unique_key(name)
    base = name.to_s.parameterize(separator: '_')[0, 30].presence || 'fonte'
    key = base
    n = 1
    key = "#{base}_#{n += 1}" while Crm::Source.exists?(account_id: Current.account.id, key: key)
    key
  end
end
