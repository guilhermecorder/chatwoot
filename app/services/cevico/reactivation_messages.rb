# 📣 Reativação de fim de ano (item 380, 03/11): as mensagens PRONTAS moram
# em config/cevico/reativacao_fim_de_ano.yml (o ORIGINAL). O que o Guilherme
# edita na tela (Marketing → Campanhas → Reativação) fica POR CIMA, em
# agenda_config['reactivation_messages'] = { id => { texto, titulo, em, por } },
# e "Restaurar original" apaga a edição daquele id.
#
# payload(account) devolve o YAML já com as edições aplicadas, os públicos em
# ordem de prioridade e, por público, a coluna do funil da casa que bate em
# coluna_regex com a contagem de cards de hoje.
module Cevico::ReactivationMessages # rubocop:disable Metrics/ModuleLength
  module_function

  PATH = Rails.root.join('config/cevico/reativacao_fim_de_ano.yml')
  # 👓 03/11: cada ramo tem o seu arquivo; a ótica reativa a base do SavWin
  PATHS = { 'otica' => Rails.root.join('config/otica/reativacao_base.yml') }.freeze
  SETTING_KEY = 'reactivation_messages'.freeze
  TEXT_MAX = 1500
  TITLE_MAX = 120

  # lê o YAML uma vez por mudança do arquivo (mtime): em development a edição
  # do arquivo aparece na hora; em produção o arquivo não muda sem deploy
  # o arquivo do ramo da empresa (clínica = o original; ótica = a base do SavWin)
  def path_for(account)
    return PATH if account.nil?

    PATHS[Cevico::Company.for(account).segment] || PATH
  end

  def load(path = PATH)
    @cache ||= {}
    mtime = File.mtime(path)
    entry = @cache[path.to_s]
    return entry[:data] if entry && entry[:mtime] == mtime

    data = YAML.safe_load_file(path, aliases: false) || {}
    @cache[path.to_s] = { mtime: mtime, data: data }
    data
  end

  def publicos(account = nil)
    Array(load(path_for(account))['publicos']).sort_by { |p| p['prioridade'].to_i }
  end

  # { id => { 'publico' => key, 'frente' => key, 'titulo' => …, 'texto' => … } }
  def messages_index(account = nil)
    publicos(account).each_with_object({}) do |publico, index|
      (publico['mensagens'] || {}).each do |frente, list|
        Array(list).each do |msg|
          index[msg['id'].to_s] = msg.merge('publico' => publico['key'], 'frente' => frente)
        end
      end
    end
  end

  def find_message(id, account = nil)
    messages_index(account)[id.to_s]
  end

  def edits_for(account)
    config = CrmSetting.find_by(account_id: account.id)&.agenda_config || {}
    config[SETTING_KEY].is_a?(Hash) ? config[SETTING_KEY] : {}
  end

  def payload(account)
    edits = edits_for(account)
    names = editor_names(account, edits)
    data = load(path_for(account))
    stages = house_stages(account, data.dig('campanha', 'funil_regex'))
    list = publicos(account).map { |publico| publico_payload(publico, edits, names, stages) }
    all = list.flat_map { |p| p[:mensagens].values.flatten }
    { campanha: data['campanha'] || {}, frentes: Array(data['frentes']), publicos: list,
      totais: { publicos: list.size, mensagens: all.size, editadas: all.count { |m| m[:editado] } } }
  end

  # uma mensagem só, já com a edição aplicada (resposta do salvar/restaurar)
  def message_payload(account, id)
    original = find_message(id, account)
    return nil unless original

    edits = edits_for(account)
    message_json(original, edits[id.to_s], editor_names(account, edits))
  end

  def save!(crm_settings, id:, texto:, titulo:, user:)
    entry = { 'texto' => texto, 'em' => Time.current.iso8601, 'por' => user&.id }
    entry['titulo'] = titulo if titulo.present?
    Cevico::SettingMerge.merge!(crm_settings, :agenda_config) do |fresh|
      fresh[SETTING_KEY] = {} unless fresh[SETTING_KEY].is_a?(Hash)
      fresh[SETTING_KEY][id.to_s] = entry
      fresh
    end
  end

  def reset!(crm_settings, id:)
    Cevico::SettingMerge.merge!(crm_settings, :agenda_config) do |fresh|
      fresh[SETTING_KEY].delete(id.to_s) if fresh[SETTING_KEY].is_a?(Hash)
      fresh
    end
  end

  def publico_payload(publico, edits, names, stages)
    mensagens = (publico['mensagens'] || {}).transform_values do |list|
      Array(list).map { |msg| message_json(msg, edits[msg['id'].to_s], names) }
    end
    publico.except('mensagens').symbolize_keys.merge(
      mensagens: mensagens,
      funil: stage_count(publico['coluna_regex'], stages)
    )
  end

  def message_json(msg, edit, names)
    edit = {} unless edit.is_a?(Hash) && edit['texto'].present?
    original = msg['texto'].to_s.strip
    { id: msg['id'], titulo: edit['titulo'].presence || msg['titulo'], titulo_original: msg['titulo'],
      texto: edit['texto'] || original, original: original,
      editado: edit.any?, editado_em: edit['em'], editado_por: names[edit['por'].to_i] }
  end

  # colunas do funil da casa (o primeiro por position, nunca o do Oftalmofácil;
  # o arquivo do ramo pode apontar outro funil pelo nome em campanha.funil_regex)
  def house_stages(account, funil_regex = nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    partner_id = Crm::PartnerGuard.partner_pipeline_id(account)
    pipelines = Crm::Pipeline.where(account_id: account.id).order(:position, :id)
    pipelines = pipelines.where.not(id: partner_id) if partner_id
    pipeline = funil_regex.present? ? pipelines.to_a.find { |p| p.name.to_s.match?(Regexp.new(funil_regex, Regexp::IGNORECASE)) } : nil
    pipeline ||= pipelines.first
    return [] unless pipeline

    stages = pipeline.stages.to_a
    counts = Crm::Contact.where(stage_id: stages.map(&:id)).group(:stage_id).count
    stages.map { |s| { id: s.id, name: s.name, cards: counts[s.id].to_i } }
  end

  def stage_count(regex, stages)
    return nil if regex.blank?

    matcher = Regexp.new(regex, Regexp::IGNORECASE)
    stage = stages.find { |s| s[:name].to_s.match?(matcher) }
    stage ? { stage_id: stage[:id], stage_name: stage[:name], cards: stage[:cards] } : nil
  rescue RegexpError
    nil
  end

  def editor_names(account, edits)
    ids = edits.values.filter_map { |e| e.is_a?(Hash) ? e['por'].to_i : nil }.select(&:positive?).uniq
    return {} if ids.empty?

    account.users.where(id: ids).pluck(:id, :name).to_h
  end
end
