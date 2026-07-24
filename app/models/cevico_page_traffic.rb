# Agregado de tráfego das Páginas: uma linha por página/dia/origem/campanha
# (visitas e cliques no convite). Não guarda visita a visita — soma no
# balde certo via UPSERT atômico, aguenta 100+ páginas com ads sem crescer
# fora de controle.
# == Schema Information
#
# Table name: cevico_page_traffic
#
#  id             :bigint           not null, primary key
#  campaign       :string           default(""), not null
#  cta_clicks     :integer          default(0), not null
#  date           :date             not null
#  source         :string           default("direto"), not null
#  views          :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  cevico_page_id :bigint           not null
#
# Indexes
#
#  index_cevico_page_traffic_on_account_id_and_date  (account_id,date)
#  index_page_traffic_unique_bucket                  (cevico_page_id,date,source,campaign) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (cevico_page_id => cevico_pages.id)
#
class CevicoPageTraffic < ApplicationRecord
  self.table_name = 'cevico_page_traffic'

  belongs_to :account
  belongs_to :cevico_page

  KINDS = { 'view' => 'views', 'cta' => 'cta_clicks' }.freeze

  # soma 1 no balde (página, hoje, origem, campanha) — atômico via
  # ON CONFLICT do índice único; nunca corre atrás de race condition
  def self.bump!(page:, kind:, source:, campaign: '')
    column = KINDS[kind.to_s]
    return if column.blank?

    now = Time.current
    connection.execute(sanitize_sql_array([<<~SQL.squish, page.account_id, page.id, Date.current, source.to_s, campaign.to_s, now, now]))
      INSERT INTO cevico_page_traffic
        (account_id, cevico_page_id, date, source, campaign, #{column}, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, 1, ?, ?)
      ON CONFLICT (cevico_page_id, date, source, campaign)
      DO UPDATE SET #{column} = cevico_page_traffic.#{column} + 1, updated_at = EXCLUDED.updated_at
    SQL
  rescue StandardError => e
    Rails.logger.error "[CevicoPageTraffic] bump falhou: #{e.message}"
  end
end
