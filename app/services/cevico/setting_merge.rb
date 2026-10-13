# Gravador travado ÚNICO do crm_settings (agenda_config / ai_config).
#
# O crm_settings é uma linha só por conta onde dezenas de escritores guardam
# estado (radar, atendentes de IA, lembretes, NPS, cursor do Oftalmofácil,
# janelas da agenda…). O padrão "lê → altera → update!" SEM trava faz o último
# a gravar apagar a chave que o outro acabou de escrever, porque update! grava
# a coluna jsonb INTEIRA (achado #318 da auditoria de 07/10 — mesmo buraco que
# o AttributeMerge fechou em julho para additional_attributes).
#
# merge! serializa os escritores com a trava da linha (SELECT ... FOR UPDATE),
# relê a coluna FRESCA dentro da trava, aplica o bloco e grava. Regra da casa:
# a partir da Rodada 4 esta é a ÚNICA forma permitida de gravar agenda_config
# e ai_config (o spec-lint setting_merge_lint_spec.rb vigia os ofensores).
#
# Uso:
#   Cevico::SettingMerge.merge!(account, :agenda_config) { |cfg| cfg['x'] = 1; cfg }
#   Cevico::SettingMerge.merge_key!(settings, :ai_config, 'radar') { |h| h.merge('at' => t) }
#
# REGRA DO BLOCO (para quem converte os pontos antigos): termine o bloco
# SEMPRE com `cfg` (o hash completo). O bloco OU mexe na cópia que recebeu
# (`cfg['x'] = …`, `cfg.delete('y')`) OU devolve um hash novo (`cfg.merge(…)`)
# — não os dois. Se mexeu na cópia, o que vale é a cópia, seja qual for a
# última linha: assim `cfg['oftalmofacil'] = { … }` ou `cfg.delete('x')` no fim
# do bloco NUNCA grava o pedaço devolvido como se fosse a coluna inteira.
#
# Aceita Account ou CrmSetting. Se a linha ainda não existe, cria. Se o
# CrmSetting recebido estiver "sujo" (hash mutado em memória antes de chamar),
# a trava roda num registro limpo e a foto velha NÃO é gravada; a coluna do
# registro recebido é atualizada com o que foi salvo. Nos controllers, passe o
# CrmSetting que você tem na mão (`crm_settings`), não `Current.account`: só
# assim a resposta montada logo depois sai com a foto nova.
module Cevico::SettingMerge
  module_function

  # colunas jsonb do crm_settings que podem ser gravadas por aqui
  COLUMNS = %w[agenda_config ai_config google_ads_config meta_ads_config sheets_config column_presets agent_permissions].freeze
  # destas, as que guardam LISTA (default []) em vez de hash (default {})
  LIST_COLUMNS = %w[column_presets].freeze

  # Grava a coluna inteira sob trava. O bloco recebe uma cópia FRESCA da coluna
  # (hash, ou lista no column_presets) e devolve o valor completo a gravar —
  # ver REGRA DO BLOCO no topo. Devolve o que foi gravado (chaves em texto,
  # como o banco devolve).
  def merge!(account_or_settings, column)
    column = column.to_s
    raise ArgumentError, "Cevico::SettingMerge: coluna não permitida (#{column})" unless COLUMNS.include?(column)

    row = fresh_row(account_or_settings)
    saved = nil
    row.with_lock do # with_lock já recarrega a linha (reload com FOR UPDATE)
      base = row[column] || (LIST_COLUMNS.include?(column) ? [] : {}) # foto do banco; o bloco não encosta nela
      current = base.deep_dup
      result = yield(current)
      saved = stringify(choose(base, current, result))
      row.update!(column => saved)
    end
    sync_caller(account_or_settings, row, column, saved)
    saved
  end

  # Mexe numa chave só (ex.: 'oftalmofacil' dentro de agenda_config), sob a mesma
  # trava, sem tocar nas irmãs. O bloco recebe uma cópia do valor atual (hash
  # vazio se não existe) e devolve o novo valor; vale a mesma REGRA DO BLOCO:
  # se mexeu na cópia (hash ou lista), grava a cópia; se não mexeu, grava o que
  # devolveu. Devolve o valor gravado na chave.
  def merge_key!(account_or_settings, column, key)
    raise ArgumentError, "Cevico::SettingMerge: #{column} guarda lista, não tem chave — use merge!" if LIST_COLUMNS.include?(column.to_s)

    key = key.to_s
    value = nil
    merge!(account_or_settings, column) do |cfg|
      base = cfg[key].nil? ? {} : cfg[key]
      current = base.deep_dup
      result = yield(current)
      value = choose(base, current, result)
      cfg.merge(key => value)
    end
    value
  end

  # Decide o que gravar: a cópia que o bloco recebeu ou o que o bloco devolveu.
  # - valor simples (texto, número, nil): vale o que o bloco devolveu;
  # - devolveu a própria cópia, ou mexeu nela (ficou diferente da foto): vale a cópia;
  # - não mexeu e devolveu hash/lista NOVO do mesmo tipo (ex. cfg.merge): vale o devolvido;
  # - não mexeu e devolveu outra coisa (nil, um pedaço de dentro da cópia…): vale a cópia.
  def choose(base, current, result)
    return result unless current.is_a?(Hash) || current.is_a?(Array)
    return current if result.equal?(current) || current != base
    return result if result.is_a?(current.class) && !inside?(current, result)

    current
  end

  # o objeto devolvido é um pedaço de dentro da cópia? (ex. `cfg['x'] = { … }`
  # devolve o sub-hash que acabou de entrar na cópia)
  def inside?(container, obj)
    values = container.is_a?(Hash) ? container.values : container
    values.any? { |v| v.equal?(obj) || ((v.is_a?(Hash) || v.is_a?(Array)) && inside?(v, obj)) }
  end

  # chaves em texto, como o jsonb devolve — senão quem lê `cfg['nova']` na mesma
  # requisição recebe nil (gravou `nova: 1` com símbolo)
  def stringify(value)
    case value
    when Hash then value.deep_stringify_keys
    when Array then value.map { |v| v.is_a?(Hash) ? v.deep_stringify_keys : v }
    else value
    end
  end

  # registro limpo para travar: Account → linha da conta (cria se faltar);
  # CrmSetting sujo (lock! recusa registro com mudanças) → cópia nova pelo id
  def fresh_row(account_or_settings)
    case account_or_settings
    when CrmSetting
      s = account_or_settings
      return find_or_create_row(s.account_id) unless s.persisted?

      s.has_changes_to_save? ? CrmSetting.find(s.id) : s
    when Account
      find_or_create_row(account_or_settings.id)
    else
      raise ArgumentError, "Cevico::SettingMerge: esperava Account ou CrmSetting, veio #{account_or_settings.class}"
    end
  end

  def find_or_create_row(account_id)
    CrmSetting.find_or_create_by!(account_id: account_id)
  rescue ActiveRecord::RecordNotUnique
    CrmSetting.find_by!(account_id: account_id) # duas criações ao mesmo tempo: a outra ganhou
  end

  # o registro que o chamador tem na mão passa a refletir a coluna gravada, sem
  # mexer nas outras mudanças pendentes dele e sem marcar a coluna como suja
  def sync_caller(account_or_settings, row, column, saved)
    return unless account_or_settings.is_a?(CrmSetting) && !account_or_settings.equal?(row)

    account_or_settings[column] = saved
    account_or_settings.clear_attribute_changes([column])
  end

  # ajudantes internos: a API fixa é só merge! e merge_key!
  private_class_method :choose, :inside?, :stringify, :fresh_row, :find_or_create_row, :sync_caller
end
