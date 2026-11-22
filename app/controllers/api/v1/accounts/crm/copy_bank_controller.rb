# 🪝 item 397: BANCO DE GANCHOS — peças (ganchos, histórias, ofertas,
# reganchos), criações montadas e a IA que preenche/escreve.
# Acesso: nó 'marketing.criativos' (ver Cevico::AccessCatalog).
class Api::V1::Accounts::Crm::CopyBankController < Api::V1::Accounts::BaseController
  GERAR_QTD = 8

  # tudo de uma vez: o banco cabe inteiro na tela (≈1.050 peças, ~600 KB)
  def index
    Crm::CopyBankSeeder.ensure!(Current.account)
    blocks = Current.account.cevico_copy_blocks.order(:kind, :position, :id)
    render json: {
      blocks: blocks.map { |b| block_json(b) },
      categorias: CevicoCopyBlock::GANCHO_CATEGORIAS,
      empresa: empresa_json,
      formatos: Crm::CopyBankGenerator::FORMATOS.keys
    }
  end

  # 🧾 formulários com respostas + a leitura para a copy já salva (se houver)
  def forms
    counts = Crm::FormResponse.where(account_id: Current.account.id).where.not(completed_at: nil).group(:crm_form_id).count
    list = Crm::Form.where(account: Current.account).order(updated_at: :desc).map do |f|
      { id: f.id, name: f.name, respostas: counts[f.id] || 0, brief: f.ai_insight.is_a?(Hash) ? f.ai_insight['copy'] : nil }
    end
    render json: { forms: list }
  end

  # 🧾 "Puxar o que importa": lê as respostas e salva em ai_insight['copy']
  def form_brief
    form = Crm::Form.where(account: Current.account).find(params[:id])
    result = Crm::FormCopyBriefService.new(form: form).call
    return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error]

    form.update!(ai_insight: (form.ai_insight.is_a?(Hash) ? form.ai_insight : {}).merge('copy' => result))
    render json: { brief: result }
  end

  def create_block
    block = Current.account.cevico_copy_blocks.create!(
      block_params.merge(fonte: 'manual', creator: Current.user,
                         position: (Current.account.cevico_copy_blocks.maximum(:position) || 0) + 1)
    )
    render json: block_json(block), status: :created
  end

  def update_block
    block = Current.account.cevico_copy_blocks.find(params[:id])
    block.update!(block_params)
    render json: block_json(block)
  end

  def destroy_block
    Current.account.cevico_copy_blocks.find(params[:id]).destroy!
    head :no_content
  end

  # contador de uso (o que o time mais escolhe sobe no "mais usados")
  def use_block
    block = Current.account.cevico_copy_blocks.find(params[:id])
    block.increment!(:usos) # rubocop:disable Rails/SkipsModelValidations
    render json: { id: block.id, usos: block.usos }
  end

  def drafts
    list = Current.account.cevico_copy_drafts.order(created_at: :desc).limit(200)
    render json: { drafts: list.map { |d| draft_json(d) } }
  end

  def create_draft
    draft = Current.account.cevico_copy_drafts.create!(draft_params.merge(creator: Current.user))
    render json: draft_json(draft), status: :created
  end

  def update_draft
    draft = Current.account.cevico_copy_drafts.find(params[:id])
    draft.update!(keep_ad_links(draft, draft_params.to_h))
    render json: draft_json(draft)
  end

  def destroy_draft
    Current.account.cevico_copy_drafts.find(params[:id]).destroy!
    head :no_content
  end

  # 🏆 ranking real: uso das peças + resultado dos anúncios ligados às criações
  def ranking
    render json: Crm::CopyBankRanking.new(Current.account).call
  end

  # anúncios da conta (Central de Criativos) para ligar a uma criação
  def ads
    scope = Crm::AdCreative.where(account_id: Current.account.id)
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
      scope = scope.where('ad_name ILIKE :q OR campaign_name ILIKE :q', q: q)
    end
    list = scope.order(Arel.sql('synced_at DESC NULLS LAST')).limit(40)
    render json: { ads: list.map { |a| { ad_id: a.ad_id, nome: a.ad_name, campanha: a.campaign_name, status: a.effective_status } } }
  end

  # liga (ou desliga) anúncios a uma criação — guarda só em partes['ad_ids']
  def link_ads
    draft = Current.account.cevico_copy_drafts.find(params[:id])
    ids = Array(params[:ad_ids]).map(&:to_s).compact_blank.uniq.first(30)
    known = Crm::AdCreative.where(account_id: Current.account.id, ad_id: ids).pluck(:ad_id)
    draft.update!(partes: (draft.partes.is_a?(Hash) ? draft.partes : {}).merge('ad_ids' => ids & known))
    render json: draft_json(draft)
  end

  # IA: escolhido o tipo de gancho, preenche modelos sorteados (ou os marcados)
  def generate_hooks
    modelos = hook_models
    result = generator.ganchos(modelos.map { |m| { id: m.id, texto: m.texto } })
    return render json: result, status: :unprocessable_entity if result[:error] || result['error']

    by_id = modelos.index_by(&:id)
    ganchos = Array(result['ganchos']).filter_map do |g|
      m = by_id[g['modelo_id'].to_i]
      m && { modelo: block_json(m), texto: g['texto'].to_s }
    end
    render json: { ganchos: ganchos }
  end

  # IA: escreve a copy inteira (gancho → história → oferta, com reganchos)
  def generate_copy
    result = generator.copy(
      gancho: params[:gancho].to_s, historia_modelo: params[:historia_modelo].to_s,
      historia: params[:historia].to_s, oferta: params[:oferta].to_s,
      reganchos: Array(params[:reganchos])
    )
    return render json: result, status: :unprocessable_entity if result[:error] || result['error']

    render json: result
  end

  private

  # salvar o texto de novo não pode desligar os anúncios já ligados à criação
  def keep_ad_links(draft, attrs)
    linked = draft.partes.is_a?(Hash) ? draft.partes['ad_ids'] : nil
    return attrs if linked.blank? || !attrs['partes'].is_a?(Hash) || attrs['partes'].key?('ad_ids')

    attrs.merge('partes' => attrs['partes'].merge('ad_ids' => linked))
  end

  def ranking_service
    @ranking_service ||= Crm::CopyBankRanking.new(Current.account)
  end

  def generator
    Crm::CopyBankGenerator.new(Current.account, tema: params[:tema], tema_livre: params[:tema_livre], formato: params[:formato],
                                                notas: params[:notas], contexto: params[:contexto])
  end

  def empresa_json
    company = Cevico::Company.for(Current.account)
    { nome: company.name, clinica: company.clinic?, ramo: company.segment_label,
      temas: company.clinic? ? Crm::CopyBankGenerator::TEMAS.keys : [] }
  end

  def hook_models
    scope = Current.account.cevico_copy_blocks.where(kind: 'gancho').where.not(saude: 'evitar')
    ids = Array(params[:ids]).map(&:to_i).first(GERAR_QTD)
    return scope.where(id: ids).to_a if ids.any?

    scope = scope.where(categoria: params[:categoria]) if params[:categoria].present?
    scope.order(Arel.sql('RANDOM()')).limit(GERAR_QTD).to_a
  end

  def block_params
    # envelope: a rota tem defaults { format: 'json' } (mesma lição do content_items)
    params.require(:block).permit(:kind, :categoria, :texto, :original, :exemplo, :referencia, :saude, :favorito)
  end

  def draft_params
    params.require(:draft).permit(:titulo, :tema, :formato, :status, :texto_final, partes: {})
  end

  def block_json(block)
    {
      id: block.id, kind: block.kind, categoria: block.categoria, texto: block.texto, original: block.original,
      exemplo: block.exemplo, referencia: block.referencia, saude: block.saude, lacunas: block.lacunas,
      fonte: block.fonte, favorito: block.favorito, usos: block.usos
    }
  end

  def draft_json(draft)
    {
      id: draft.id, titulo: draft.titulo, tema: draft.tema, formato: draft.formato, status: draft.status,
      partes: draft.partes, texto_final: draft.texto_final, created_at: draft.created_at,
      autor: draft.creator&.available_name, codigo: Crm::CopyBankRanking.code_for(draft),
      anuncios: ranking_service.ads_for(draft)
    }
  end
end
