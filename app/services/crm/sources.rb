# 🏷️ item 322: QUEM É A FONTE de um funil, de uma caixa, de um agendamento.
# Um lugar só para essa pergunta — o carimbo (Crm::Stamp), o preenchimento do
# passado (Crm::SourceBackfill) e a tela Fontes de pacientes leem daqui.
#
# O mapa (funil → fonte, caixa → fonte) fica 10 minutos em cache porque é
# consultado a cada card que nasce; muda quando alguém salva uma fonte ou o
# card do OftalmoFácil (forget!).
module Crm::Sources
  module_function

  CACHE_TTL = 10.minutes
  DEFAULTS = {
    Crm::Source::OWN_KEY => { name: 'CEVICO', kind: 'own', color: '#152C61', position: 0 },
    Crm::Source::PARTNER_KEY => { name: 'Oftalmofácil', kind: 'partner', color: '#0D9488', position: 1 }
  }.freeze

  # a fonte da casa — nasce sozinha na primeira vez em que alguém pergunta
  def own(account)
    ensure!(account, Crm::Source::OWN_KEY)
  end

  # a fonte do hub de parceiros (Oftalmofácil)
  def partner(account)
    ensure!(account, Crm::Source::PARTNER_KEY)
  end

  def ensure!(account, key)
    Crm::Source.find_by(account_id: account.id, key: key) ||
      Crm::Source.create!(DEFAULTS.fetch(key).merge(account_id: account.id, key: key))
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    Crm::Source.find_by!(account_id: account.id, key: key)
  end

  # todas as fontes da conta (a da casa sempre existe; a do Oftalmofácil
  # aparece quando o hub está configurado)
  def list(account)
    own(account)
    partner(account) if partner_configured?(account)
    Crm::Source.where(account_id: account.id).ordered.to_a
  end

  def partner_configured?(account)
    Crm::PartnerGuard.partner_pipeline_id(account).present? || Crm::PartnerGuard.partner_inbox_ids(account).any? ||
      Crm::PartnerGuard.own_provider_name(account).present?
  end

  # o funil principal da casa: o de entrada dos leads (CrmListener) e o dos
  # indicadores (KpiBagService). Nenhuma fonte parceira pode ficar com ele.
  def main_pipeline_ids(account)
    [account.crm_pipelines.order(:position).first&.id, account.crm_pipelines.order(:id).first&.id].compact.uniq
  end

  def own_id(account)
    map(account)['own']
  end

  def partner_id(account)
    map(account)['keys'][Crm::Source::PARTNER_KEY] || partner(account).id
  end

  def id_for_key(account, key)
    map(account)['keys'][key.to_s]
  end

  # funil que nenhuma fonte pegou = da casa
  def id_for_pipeline(account, pipeline_id)
    map(account)['pipelines'][pipeline_id.to_s] || own_id(account)
  end

  def id_for_inbox(account, inbox_id)
    map(account)['inboxes'][inbox_id.to_s] || own_id(account)
  end

  def map(account)
    Rails.cache.fetch(cache_key(account), expires_in: CACHE_TTL) { build_map(account) }
  end

  def build_map(account) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    sources = list(account)
    out = { 'own' => sources.find(&:own?)&.id, 'keys' => {}, 'pipelines' => {}, 'inboxes' => {} }
    sources.each do |source|
      out['keys'][source.key] = source.id
      next if source.own?

      source.pipeline_ids.each { |id| out['pipelines'][id.to_s] ||= source.id }
      source.inbox_ids.each { |id| out['inboxes'][id.to_s] ||= source.id }
    end
    out
  end

  def forget!(account)
    Rails.cache.delete(cache_key(account)) if account.present?
  end

  def cache_key(account)
    "cevico:sources:map:#{account.id}"
  end
end
