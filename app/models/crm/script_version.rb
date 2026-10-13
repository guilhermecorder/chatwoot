# 🕘 Uma FOTO do Roteiro CEVICO (ou do prompt da etapa de um agente) tirada
# ANTES de cada mudança (rodada 191): editar na tela, aplicar uma orientação,
# voltar para uma versão. Assim o admin nunca perde um texto que funcionava.
#
# kind 'script' → content = ai_config['script'] inteiro (só as seções
#   personalizadas; seção ausente = texto padrão do Crm::CevicoScript)
# kind 'stage'  → content = { 'prompt' => ai_config.agents[agent_key].prompt }
#   (o campo cru; vazio = padrão STAGE_PROMPTS)
# == Schema Information
#
# Table name: crm_script_versions
#
#  id            :bigint           not null, primary key
#  agent_key     :string
#  content       :jsonb            not null
#  kind          :string           default("script"), not null
#  note          :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#  guidance_id   :bigint
#
# Indexes
#
#  index_crm_script_versions_on_account_id                 (account_id)
#  index_crm_script_versions_on_account_id_and_created_at  (account_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::ScriptVersion < ApplicationRecord
  self.table_name = 'crm_script_versions'

  KINDS = %w[script stage].freeze
  SCRIPT_KEYS = Crm::CevicoScript::SECTIONS.pluck('key').freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :guidance, class_name: 'Crm::AgentGuidance', optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :agent_key, presence: true, if: -> { kind == 'stage' }

  scope :recent, -> { order(created_at: :desc) }

  # Guarda o conteúdo ATUAL antes de mudar. Se a última foto do mesmo alvo
  # já é idêntica, não cria outra (o hub salva a cada clique — evita ruído).
  def self.snapshot!(account, kind:, note:, by:, agent_key: nil, guidance: nil) # rubocop:disable Metrics/ParameterLists
    content = current_content(account, kind, agent_key)
    last = where(account: account, kind: kind, agent_key: agent_key).recent.first
    return last if last && last.content == content

    create!(account: account, kind: kind, agent_key: agent_key, content: content,
            note: note.to_s.strip.first(200), created_by: by, guidance: guidance)
  end

  def self.current_content(account, kind, agent_key)
    cfg = CrmSetting.find_by(account: account)&.ai_config || {}
    if kind == 'stage'
      { 'prompt' => cfg.dig('agents', agent_key, 'prompt').to_s }
    else
      (cfg['script'] || {}).slice(*SCRIPT_KEYS).transform_values(&:to_s)
    end
  end

  # ── escrita no lugar certo (usada pelas orientações e pelo "voltar") ──

  # grava o Roteiro (só as seções personalizadas) + updated_at.
  # 🔒 Rodada 4 da auditoria (#102): sob a trava da linha, relendo a config
  # fresca (Cevico::SettingMerge) — "voltar para esta" nunca apaga o que outro
  # escritor acabou de gravar no ai_config
  def self.write_script!(account, script)
    saved = Cevico::SettingMerge.merge!(account, :ai_config) do |cfg|
      cfg['script'] = script.slice(*SCRIPT_KEYS).transform_values { |v| v.to_s.strip }.merge('updated_at' => Time.current.iso8601)
      cfg
    end
    saved['script']
  end

  # grava o prompt PUBLICADO da etapa do agente (o rascunho `draft` fica como está)
  def self.write_stage_prompt!(account, agent_key, prompt)
    key = agent_key.to_s
    saved = Cevico::SettingMerge.merge!(account, :ai_config) do |cfg|
      cfg['agents'] ||= {}
      cfg['agents'][key] = (cfg['agents'][key] || {}).merge('prompt' => prompt.to_s.strip)
      cfg
    end
    saved.dig('agents', key, 'prompt')
  end

  # Orientação aplicada: acrescenta UMA linha no fim da seção do Roteiro, lendo
  # o Roteiro FRESCO dentro da trava (Rodada 4). Assim, se outro admin salvou o
  # Roteiro no hub nesse meio-tempo, a edição dele fica e a linha entra por cima.
  # Seção vazia (= padrão) parte do texto padrão. Devolve a seção gravada.
  def self.append_script_line!(account, section, line)
    key = section.to_s
    saved = Cevico::SettingMerge.merge!(account, :ai_config) do |cfg|
      script = (cfg['script'] || {}).slice(*SCRIPT_KEYS).transform_values { |v| v.to_s.strip }
      base = script[key].presence || Crm::CevicoScript.default_text(key, 'v1', account: account).to_s.strip
      cfg['script'] = script.merge(key => "#{base}\n#{line}".strip, 'updated_at' => Time.current.iso8601)
      cfg
    end
    saved.dig('script', key)
  end

  # mesma ideia para o prompt PUBLICADO da etapa do agente (o rascunho fica como está)
  def self.append_stage_line!(account, agent_key, line)
    key = agent_key.to_s
    saved = Cevico::SettingMerge.merge!(account, :ai_config) do |cfg|
      base = cfg.dig('agents', key, 'prompt').to_s.strip.presence ||
             Crm::CevicoScript.default_stage_prompt(key, 'v1', account: account).to_s.strip
      cfg['agents'] ||= {}
      cfg['agents'][key] = (cfg['agents'][key] || {}).merge('prompt' => "#{base}\n#{line}".strip)
      cfg
    end
    saved.dig('agents', key, 'prompt')
  end

  # "Voltar para esta": foto do estado atual e o conteúdo desta versão de volta
  def restore!(by:)
    self.class.snapshot!(account, kind: kind, agent_key: agent_key, note: "antes de voltar para a versão ##{id}", by: by)
    if kind == 'stage'
      self.class.write_stage_prompt!(account, agent_key, content['prompt'])
    else
      self.class.write_script!(account, content)
    end
  end

  def size
    content.values.sum { |v| v.to_s.length }
  end

  def to_payload
    {
      id: id, kind: kind, agent_key: agent_key, note: note, size: size, guidance_id: guidance_id,
      author: created_by ? { id: created_by.id, name: created_by.name } : nil,
      created_at: created_at.iso8601
    }
  end
end
