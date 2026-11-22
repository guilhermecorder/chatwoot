# 🏆 18/11/2026 (Guilherme: "subi criativos na Meta, quero que você saiba de
# quais ganchos são e relacione o resultado do anúncio à modalidade de
# gancho — um ranqueamento real"). Junta três coisas que o sistema já tem:
#   1. o USO de cada peça do banco (cevico_copy_blocks.usos, o botão Usar);
#   2. as CRIAÇÕES salvas (cevico_copy_drafts), que guardam o gancho que entrou;
#   3. os ANÚNCIOS da Meta (Central de Criativos: cevico_ad_creatives + insights).
# A ligação criação → anúncio é feita de dois jeitos, sem migration:
#   • pelo CÓDIGO da criação (CRI-<id>) escrito no nome do anúncio na Meta;
#   • à mão, na aba Criações (partes['ad_ids']).
# Daí sai o resultado por criação, por gancho e por TIPO de gancho.
class Crm::CopyBankRanking
  CODE = /\bCRI-(\d+)\b/i
  SUMS = %w[impressions plays_3s conversations spend link_clicks].freeze
  DRAFTS_MAX = 500
  HOOKS_MAX = 60

  def self.code_for(draft)
    "CRI-#{draft.id}"
  end

  def initialize(account)
    @account = account
  end

  def call
    drafts = @account.cevico_copy_drafts.order(created_at: :desc).limit(DRAFTS_MAX).to_a
    links = ad_links(drafts)
    @totals = insight_totals(links.values.flatten.uniq)
    rows = drafts.map { |d| draft_row(d, links[d.id] || []) }
    { criacoes: rows, tipos: tipo_rows(rows), ganchos: hook_rows(rows), resumo: resumo(rows) }
  end

  # anúncios ligados a UMA criação (para o cartão da aba Criações)
  def ads_for(draft)
    ids = ad_links([draft])[draft.id] || []
    ad_names.slice(*ids).map { |id, nome| { ad_id: id, nome: nome } }
  end

  private

  def ad_names
    @ad_names ||= Crm::AdCreative.where(account_id: @account.id).pluck(:ad_id, :ad_name).to_h
  end

  # { draft_id => [ad_id, …] } — à mão (partes['ad_ids']) + código no nome do anúncio
  def ad_links(drafts)
    by_code = ads_by_code
    drafts.to_h { |d| [d.id, ((manual_ads(d) & ad_names.keys) + by_code[d.id]).uniq] }
  end

  # { id da criação => [ad_id, …] } lido do CRI-<id> no nome de cada anúncio
  def ads_by_code
    ad_names.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(ad_id, name), acc|
      name.to_s.scan(CODE).flatten.each { |n| acc[n.to_i] << ad_id }
    end
  end

  def manual_ads(draft)
    Array(draft.partes.is_a?(Hash) ? draft.partes['ad_ids'] : nil).map(&:to_s)
  end

  # { ad_id => { 'impressions' => n, … } } — soma de todos os dias
  def insight_totals(ad_ids)
    return {} if ad_ids.empty?

    selects = SUMS.map { |k| Arel.sql("COALESCE(SUM((metrics->>'#{k}')::numeric), 0)") }
    Crm::AdInsight.where(account_id: @account.id, ad_id: ad_ids).group(:ad_id).pluck(:ad_id, *selects).to_h do |row|
      [row.first, SUMS.zip(row.drop(1).map(&:to_f)).to_h]
    end
  end

  def metrics_for(ad_ids)
    sums = SUMS.index_with { |k| ad_ids.sum { |id| @totals.dig(id, k).to_f } }
    imp = sums['impressions']
    conv = sums['conversations']
    {
      anuncios: ad_ids.size, impressoes: imp.round, conversas: conv.round, gasto: sums['spend'].round(2),
      gancho_pct: imp.positive? ? (sums['plays_3s'] / imp * 100).round(1) : nil,
      conversas_mil: imp.positive? ? (conv / imp * 1000).round(2) : nil,
      custo_conversa: conv.positive? ? (sums['spend'] / conv).round(2) : nil
    }
  end

  def draft_row(draft, ad_ids)
    gancho = draft.partes.is_a?(Hash) ? (draft.partes['gancho'] || {}) : {}
    {
      id: draft.id, codigo: self.class.code_for(draft), titulo: draft.titulo, status: draft.status,
      tipo: gancho['tipo'].presence, block_id: gancho['block_id'], ad_ids: ad_ids,
      anuncios_lista: ad_ids.map { |id| { ad_id: id, nome: ad_names[id] } }
    }.merge(metrics_for(ad_ids))
  end

  def tipo_rows(rows)
    usos = @account.cevico_copy_blocks.where(kind: 'gancho').group(:categoria).sum(:usos)
    keys = (rows.filter_map { |r| r[:tipo] } + usos.select { |_, n| n.positive? }.keys.compact).uniq
    keys.map do |tipo|
      mine = rows.select { |r| r[:tipo] == tipo }
      { tipo: tipo, usos: usos[tipo].to_i, criacoes: mine.size }.merge(metrics_for(mine.flat_map { |r| r[:ad_ids] }.uniq))
    end
  end

  def hook_rows(rows)
    by_block = rows.select { |r| r[:block_id] }.group_by { |r| r[:block_id].to_i }
    blocks = @account.cevico_copy_blocks.where(kind: 'gancho')
    list = blocks.where('usos > 0').or(blocks.where(id: by_block.keys)).map { |b| hook_row(b, by_block[b.id] || []) }
    list.sort_by { |h| [-(h[:conversas_mil] || -1), -h[:usos]] }.first(HOOKS_MAX)
  end

  def hook_row(block, mine)
    { block_id: block.id, texto: block.texto, tipo: block.categoria, usos: block.usos, favorito: block.favorito, criacoes: mine.size }
      .merge(metrics_for(mine.flat_map { |r| r[:ad_ids] }.uniq))
  end

  def resumo(rows)
    ligadas = rows.select { |r| r[:ad_ids].any? }
    { criacoes: rows.size, ligadas: ligadas.size }.merge(metrics_for(ligadas.flat_map { |r| r[:ad_ids] }.uniq))
  end
end
