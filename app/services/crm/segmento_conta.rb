# Segmento COM os ajustes da conta (Configurações → Personalização):
# o admin edita profissionais, unidades, listas e metas direto na tela,
# gravados em crm_settings.agenda_config['segment']. Sem ajuste salvo,
# vale o pacote do segmento (config/segmentos/<id>.yml) — que no preset
# clínica é exatamente o comportamento de sempre.
#
# Ordem de resolução em TODO lugar: conta > segmento > chumbado.
module Crm::SegmentoConta
  module_function

  def overrides(account)
    return {} if account.nil?

    CrmSetting.find_by(account: account)&.agenda_config&.dig('segment') || {}
  end

  # ── Profissionais ───────────────────────────────────────────
  def profissionais(account)
    lista = Array(overrides(account)['professionals'])
    lista.any? { |p| p['nome'].present? } ? lista : Segmento.profissionais
  end

  # { 'Dr. Gustavo Bittar' => 'gustavo|bittar', ... } — com os ajustes da conta
  def profissionais_grafias(account)
    profissionais(account).each_with_object({}) do |p, map|
      next if p['nome'].blank?

      map[p['nome']] = p['grafias'].presence || Regexp.escape(p['nome'])
    end
  end

  # ── Unidades ────────────────────────────────────────────────
  def unidades(account)
    lista = Array(overrides(account)['units'])
    lista.any? { |u| u['key'].present? } ? lista : Segmento.unidades
  end

  def unidade_keys(account)
    unidades(account).filter_map { |u| u['key'].presence }
  end

  def unit_labels(account)
    unidades(account).each_with_object({}) do |u, map|
      map[u['key']] = u['nome'].presence || u['key'] if u['key'].present?
    end
  end

  def unit_label(account, key)
    unit_labels(account)[key.to_s] || key.to_s
  end

  # ── Metas ───────────────────────────────────────────────────
  def meta(account, chave, padrao)
    v = overrides(account).dig('metas', chave.to_s).to_i
    v.positive? ? v : (Segmento.config.dig('metas', chave.to_s).to_i.positive? ? Segmento.config.dig('metas', chave.to_s).to_i : padrao)
  end
end
