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
      temas: Crm::CopyBankGenerator::TEMAS.keys,
      formatos: Crm::CopyBankGenerator::FORMATOS.keys
    }
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
    draft.update!(draft_params)
    render json: draft_json(draft)
  end

  def destroy_draft
    Current.account.cevico_copy_drafts.find(params[:id]).destroy!
    head :no_content
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

  def generator
    Crm::CopyBankGenerator.new(Current.account, tema: params[:tema], formato: params[:formato], notas: params[:notas])
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
      autor: draft.creator&.available_name
    }
  end
end
