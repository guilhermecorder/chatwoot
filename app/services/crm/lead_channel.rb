# 🧭 COMO O PACIENTE CHEGOU — informado pela equipe (item 362, 21/10/2026).
#
# Diagnóstico do item 361: dos 196 pacientes operados em 90 dias, 179 não tinham
# carimbo automático nenhum (clique no anúncio da Meta ou utm da página) — 153
# foram criados pela própria equipe na Agenda. Quem atende sabe como a pessoa
# chegou ("vi no Google", "liguei", "minha irmã operou aí"); isso vira um
# carimbo no contato, `additional_attributes['canal_origem']`, com quem informou
# e quando. Regra de PRIMEIRO TOQUE, igual aos carimbos automáticos: gravado uma
# vez, não sobrescreve. O carimbo automático (meta_ads / page_ads) continua
# valendo mais quando existe — este é o "informado pela equipe".
#
# Cada chave diz para qual CANAL do CAC ela conta (Crm::AcquisitionChannel):
# google · meta · organico.
module Crm::LeadChannel
  module_function

  KEYS = {
    'google_anuncio' => { label: 'Google · anúncio', channel: 'google' },
    'google_busca' => { label: 'Google · busca ou site', channel: 'organico' },
    'meta_anuncio' => { label: 'Instagram / Facebook · anúncio', channel: 'meta' },
    'instagram_perfil' => { label: 'Instagram · perfil ou bio', channel: 'organico' },
    'whatsapp_direto' => { label: 'WhatsApp direto', channel: 'organico' },
    'ligacao' => { label: 'Ligação', channel: 'organico' },
    'indicacao' => { label: 'Indicação de paciente', channel: 'organico' },
    'parceiro' => { label: 'Médico ou parceiro', channel: 'organico' },
    'balcao' => { label: 'Passou na clínica', channel: 'organico' },
    'outro' => { label: 'Outro', channel: 'organico' }
  }.freeze
  ATTR = 'canal_origem'.freeze

  def valid?(key)
    KEYS.key?(key.to_s)
  end

  def label_for(key)
    KEYS.dig(key.to_s, :label)
  end

  def channel_for(key)
    KEYS.dig(key.to_s, :channel)
  end

  # chaves que contam para um canal do CAC ('meta' | 'google' | 'organico')
  def keys_for(channel)
    KEYS.select { |_, v| v[:channel] == channel }.keys
  end

  # grava no contato (primeiro toque: só se ainda não tem). Devolve true se gravou.
  def stamp!(contact, key, user: nil, at: Time.current)
    return false if contact.blank? || !valid?(key)

    attrs = contact.additional_attributes.to_h
    return false if attrs[ATTR].is_a?(Hash) && attrs[ATTR]['key'].present?

    contact.update!(additional_attributes: attrs.merge(ATTR => { 'key' => key.to_s, 'por' => user&.name, 'em' => at.iso8601 }))
    true
  end

  # o que a equipe informou (hash) ou nil
  def team_stamp(contact)
    stamp = contact&.additional_attributes&.dig(ATTR)
    stamp.is_a?(Hash) && stamp['key'].present? ? stamp : nil
  end

  # a chave para MOSTRAR no formulário: o carimbo automático (que vale mais)
  # traduzido para uma chave, senão o informado pela equipe. { key:, auto: }
  def key_of(contact) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    attrs = contact&.additional_attributes.to_h
    meta = attrs['meta_ads']
    page = attrs['page_ads']
    return { key: 'meta_anuncio', auto: true } if meta.is_a?(Hash) && (meta['source_id'].present? || meta['ctwa_clid'].present?)

    if page.is_a?(Hash) && page['source'].present?
      return { key: 'google_anuncio', auto: true } if page['source'] == 'google_ads'
      return { key: 'meta_anuncio', auto: true } if page['source'] == 'meta_ads'
      return { key: 'google_busca', auto: true } if page['source'] == 'google_organico'
    end
    team = team_stamp(contact)
    team ? { key: team['key'], auto: false } : nil
  end
end
