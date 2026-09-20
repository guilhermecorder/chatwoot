# Um anúncio da conta da Meta com o seu criativo (gancho = title, corpo = body,
# CTA = cta_type, miniatura, formato). Item 172 — Central de Criativos.
# == Schema Information
#
# Table name: cevico_ad_creatives
#
#  id               :bigint           not null, primary key
#  ad_name          :string
#  adset_name       :string
#  campaign_name    :string
#  creative         :jsonb            not null
#  effective_status :string
#  format           :string           default("other"), not null
#  synced_at        :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  ad_id            :string           not null
#  adset_id         :string
#  campaign_id      :string
#
# Indexes
#
#  index_cevico_ad_creatives_on_account_id                  (account_id)
#  index_cevico_ad_creatives_on_account_id_and_ad_id        (account_id,ad_id) UNIQUE
#  index_cevico_ad_creatives_on_account_id_and_campaign_id  (account_id,campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::AdCreative < ApplicationRecord
  include Rails.application.routes.url_helpers

  self.table_name = 'cevico_ad_creatives'
  # miniatura guardada no NOSSO armazenamento (a URL da Meta expira e o
  # anúncio pode ser apagado lá) — Crm::AdCreativeMediaJob preenche
  has_one_attached :thumbnail

  FORMATS = %w[video image carousel dynamic other].freeze
  FORMAT_LABELS = {
    'video' => 'Vídeo', 'image' => 'Imagem', 'carousel' => 'Carrossel',
    'dynamic' => 'Dinâmico', 'other' => 'Outro'
  }.freeze

  belongs_to :account

  validates :ad_id, presence: true, uniqueness: { scope: :account_id }
  validates :format, inclusion: { in: FORMATS }

  scope :for_campaign, ->(campaign_id) { campaign_id.present? ? where(campaign_id: campaign_id) : all }

  def video?
    format == 'video'
  end

  def dynamic?
    format == 'dynamic'
  end

  # 🎬 v2.1 (item 181): o gancho/corpo/CTA de um VÍDEO vêm da transcrição
  # (o que o vídeo fala); o texto do anúncio fica como reserva. `text_source`
  # diz de onde veio ('video' | 'ad').
  def transcript
    (creative['transcript'] || {}).to_h
  end

  def transcript_done?
    transcript['status'] == 'done' && transcript['text'].present?
  end

  def text_source
    transcript_done? ? 'video' : 'ad'
  end

  def hook
    (transcript_done? && transcript['hook'].presence) || ad_hook
  end

  def body
    (transcript_done? && transcript['body'].presence) || ad_body
  end

  # CTA continua sendo o botão da Meta (é o que o paciente clica); o pedido
  # falado no vídeo fica em `video_cta`
  def cta
    creative['cta_type'].presence
  end

  def video_cta
    transcript_done? ? transcript['cta'].presence : nil
  end

  # marca "na fila" antes de enfileirar o job (a tela mostra o estado)
  def queue_transcript!
    update!(creative: creative.merge('transcript' => transcript.merge('status' => 'queued', 'error' => nil)))
  end

  def ad_hook
    creative['title'].presence
  end

  def ad_body
    creative['body'].presence
  end

  def format_label
    FORMAT_LABELS[format] || format
  end

  def insights
    Crm::AdInsight.where(account_id: account_id, ad_id: ad_id)
  end

  def thumbnail_stored?
    thumbnail.attached?
  end

  # a nossa cópia quando existe; senão a URL da Meta
  def thumbnail_src
    return url_for(thumbnail) if thumbnail_stored?

    creative['thumbnail_url']
  rescue StandardError
    creative['thumbnail_url']
  end

  def meta_thumbnail_url
    creative['thumbnail_url'].presence || creative['image_url'].presence
  end
end
