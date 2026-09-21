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

  # grava o Roteiro (só as seções personalizadas) + updated_at
  def self.write_script!(account, script)
    settings = CrmSetting.find_or_create_by!(account: account)
    cfg = settings.ai_config || {}
    cfg['script'] = script.slice(*SCRIPT_KEYS).transform_values { |v| v.to_s.strip }.merge('updated_at' => Time.current.iso8601)
    settings.update!(ai_config: cfg)
    cfg['script']
  end

  # grava o prompt PUBLICADO da etapa do agente (o rascunho `draft` fica como está)
  def self.write_stage_prompt!(account, agent_key, prompt)
    settings = CrmSetting.find_or_create_by!(account: account)
    cfg = settings.ai_config || {}
    cfg['agents'] ||= {}
    cfg['agents'][agent_key] = (cfg['agents'][agent_key] || {}).merge('prompt' => prompt.to_s.strip)
    settings.update!(ai_config: cfg)
    cfg['agents'][agent_key]['prompt']
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
