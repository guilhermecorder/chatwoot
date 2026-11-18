# 🪝 item 397 (18/11/2026): BANCO DE GANCHOS — o ambiente de geração de
# criativos no padrão GANCHO → HISTÓRIA → OFERTA (hook, story, offer).
# Guilherme: "subir os 1.000 ganchos como templates, escolher o tipo de
# gancho e ele já ir gerando; escrever o corpo, escolher o call to action,
# inserir ganchos contextualizados ao longo da copy; e ir aumentando a base".
#
# cevico_copy_blocks = as PEÇAS do banco, uma linha por peça:
#   kind 'gancho' (abertura), 'historia' (corpo/estrutura), 'oferta' (CTA)
#   e 'regancho' (frase de reconexão no meio da copy). Os ganchos do PDF
#   "1,000 Viral Hooks" guardam o original em inglês e o link do vídeo de
#   referência no Instagram.
# cevico_copy_drafts = as CRIAÇÕES montadas (qual gancho/história/oferta
#   entrou, o texto final) — base para depois cruzar com o resultado.
class CreateCevicoCopyBank < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    create_table :cevico_copy_blocks do |t|
      t.references :account, null: false, foreign_key: true
      t.string :kind, null: false, default: 'gancho' # gancho | historia | oferta | regancho
      t.string :categoria # gancho: educativo, comparacao…; historia: estrutura; oferta: tipo
      t.text :texto, null: false # versão em português, com [lacunas]
      t.text :original # texto original (inglês, no caso do PDF)
      t.text :exemplo # o modelo já preenchido para a CEVICO
      t.string :referencia # link do vídeo de referência
      t.string :saude, null: false, default: 'pronto' # pronto | adaptar | evitar (regras do CFM)
      t.jsonb :lacunas, null: false, default: []
      t.string :fonte, null: false, default: 'manual' # pbl-1000 | cevico | manual
      t.boolean :favorito, null: false, default: false
      t.integer :usos, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.references :creator, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :cevico_copy_blocks, %i[account_id kind categoria]

    create_table :cevico_copy_drafts do |t|
      t.references :account, null: false, foreign_key: true
      t.references :creator, foreign_key: { to_table: :users }
      t.string :titulo, null: false
      t.string :tema # refrativa | catarata | …
      t.string :formato # reels | carrossel | anuncio | post
      t.string :status, null: false, default: 'rascunho' # rascunho | aprovado | publicado
      t.jsonb :partes, null: false, default: {} # { gancho:{block_id,texto}, historia:{…}, oferta:{…}, reganchos:[…] }
      t.text :texto_final
      t.timestamps
    end
    add_index :cevico_copy_drafts, %i[account_id created_at]
  end
end
