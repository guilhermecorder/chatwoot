# 🧪 item 383 (03/11/2026): SEGMENTAÇÃO DA BASE + TESTES DE MENSAGEM.
# Guilherme: "pegar as 8 mil pessoas da coluna e mandar para todas no mesmo
# dia não é o nosso estilo — quero um ambiente em que eu seleciono a base,
# isolo o que já foi testado, testo 5 mensagens com 100 pessoas cada, vejo a
# taxa de cada uma e depois escalo a vencedora de mil em mil, de 150 em 150
# por hora, ou 10 a cada 5 minutos".
#
# crm_segments = um SEGMENTO: um pedaço nomeado e congelado da base (lote de
# teste com até 5 mensagens, ou lote de escala com a vencedora), com a regra
# de origem (source), as mensagens (variants), o ritmo (pace) e os números.
# crm_segment_members = as pessoas do segmento, uma linha por pessoa, com a
# mensagem sorteada e o que aconteceu (reservada → enviada). Quem está num
# segmento nunca entra em outro: é o que isola o que já foi testado.
class CreateCrmSegments < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :crm_segments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :creator, foreign_key: { to_table: :users }
      t.references :parent, foreign_key: { to_table: :crm_segments } # escala nascida de um teste
      t.string :name, null: false
      t.string :kind, null: false, default: 'teste' # teste | escala
      t.string :status, null: false, default: 'reservado' # reservado | enviando | pausado | concluido
      t.jsonb :source, null: false, default: {} # colunas, regras de exclusão, tamanho, ordem, semente
      t.jsonb :variants, null: false, default: [] # [{ key, label, template_params, message_preview }]
      t.jsonb :pace, null: false, default: {} # por hora, de quanto em quanto, janela, teto do dia, caixa
      t.jsonb :stats, null: false, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :last_tick_at
      t.timestamps
    end
    add_index :crm_segments, %i[account_id status]

    create_table :crm_segment_members do |t|
      t.references :segment, null: false, foreign_key: { to_table: :crm_segments }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :variant_key, null: false, default: 'A'
      t.string :status, null: false, default: 'reservado' # reservado | enviado | falhou | pulado
      t.string :frente
      t.bigint :inbox_id
      t.references :campaign, foreign_key: { to_table: :crm_campaigns }
      t.references :conversation, foreign_key: true
      t.datetime :sent_at
      t.timestamps
    end
    add_index :crm_segment_members, %i[segment_id contact_id], unique: true
    # uma pessoa em UM segmento só (isola o testado e impede duas reservas ao mesmo tempo)
    add_index :crm_segment_members, :contact_id, unique: true
    add_index :crm_segment_members, %i[segment_id status]
  end
end
