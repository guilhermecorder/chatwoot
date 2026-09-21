# ✍️ Uma ORIENTAÇÃO para um atendente de IA (rodada 191): "o paciente disse X,
# o agente respondeu Y, deveria ter respondido Z; regra para o futuro W".
# Nasce da mão do admin (botão Orientar no simulador/tela Sombra) ou do 👎 na
# tela Sombra (source 'sombra'). "Aplicar" escreve o texto formatado no FIM
# da seção escolhida do Roteiro (ou nos passos do agente) e guarda uma foto
# do que havia antes (Crm::ScriptVersion).
# == Schema Information
#
# Table name: crm_agent_guidances
#
#  id              :bigint           not null, primary key
#  agent_key       :string           not null
#  agent_text      :text
#  applied_at      :datetime
#  ideal_reply     :text
#  patient_excerpt :text
#  rule            :text
#  source          :string           default("manual"), not null
#  status          :string           default("pending"), not null
#  target_section  :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  applied_by_id   :bigint
#  conversation_id :integer
#  created_by_id   :bigint
#  message_id      :bigint
#
# Indexes
#
#  index_crm_agent_guidances_on_account_id                 (account_id)
#  index_crm_agent_guidances_on_account_id_and_message_id  (account_id,message_id)
#  index_crm_agent_guidances_on_account_id_and_status      (account_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::AgentGuidance < ApplicationRecord
  self.table_name = 'crm_agent_guidances'

  SOURCES = %w[manual sombra].freeze
  STATUSES = %w[pending applied ignored].freeze
  # seções do Roteiro + 'stage' (os passos do próprio agente)
  SECTIONS = (Crm::CevicoScript::SECTIONS.pluck('key') + ['stage']).freeze
  SECTION_TITLES = Crm::CevicoScript::SECTIONS.to_h { |s| [s['key'], s['title']] }.merge('stage' => 'Passos do agente').freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :applied_by, class_name: 'User', optional: true

  validates :agent_key, inclusion: { in: Crm::AiAgentConfig::RESPONDER_AGENTS }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :target_section, inclusion: { in: SECTIONS }, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }

  # 👎 da tela Sombra vira orientação pendente (1 por nota: não duplica)
  def self.from_shadow_note!(note, by:)
    shadow = (note.additional_attributes || {})['cevico_ia_shadow'] || {}
    return if shadow['agent'].blank?

    guidance = find_or_initialize_by(account: note.account, message_id: note.id)
    guidance.assign_attributes(shadow_attributes(note, shadow, by)) if guidance.new_record?
    guidance.absorb_rating_note(shadow['rating_note'])
    guidance.save!
    guidance
  end

  # a nota do 👎 vira a regra (só enquanto pendente e sem regra escrita à mão)
  def absorb_rating_note(rating_note)
    text = rating_note.to_s.strip
    self.rule = text if text.present? && pending? && rule.blank?
  end

  def self.shadow_attributes(note, shadow, by)
    trigger = note.conversation.messages.find_by(id: shadow['trigger_message_id'])
    { agent_key: shadow['agent'], source: 'sombra', conversation_id: note.conversation.display_id,
      patient_excerpt: trigger&.content.to_s.strip.first(1000),
      agent_text: Array(shadow['mensagens']).join("\n"), created_by: by }
  end
  private_class_method :shadow_attributes

  def pending?
    status == 'pending'
  end

  # a linha que entra no Roteiro
  def formatted_line
    if target_section == 'objections' && patient_excerpt.present?
      excerpt = patient_excerpt.to_s.squish.truncate(140)
      line = "\"#{excerpt}\" → #{ideal_reply.to_s.squish}"
      line += " (regra: #{rule.to_s.squish})" if rule.present?
      line
    else
      "- #{(rule.presence || ideal_reply).to_s.squish}"
    end
  end

  # texto formatado no FIM da seção (foto antes) → status applied.
  # Devolve o texto novo da seção. Levanta ArgumentError com a mensagem
  # para a tela quando falta algo.
  def apply!(by:)
    raise ArgumentError, 'Esta orientação já foi aplicada.' unless pending? || status == 'ignored'
    raise ArgumentError, 'Escolha em qual seção a orientação entra.' unless SECTIONS.include?(target_section)
    raise ArgumentError, 'Escreva como o agente deveria responder ou a regra para o futuro.' if ideal_reply.blank? && rule.blank?

    new_text = nil
    transaction do
      new_text = target_section == 'stage' ? apply_to_stage!(by) : apply_to_script!(by)
      update!(status: 'applied', applied_at: Time.current, applied_by: by)
    end
    new_text
  end

  def to_payload # rubocop:disable Metrics/AbcSize
    {
      id: id, agent_key: agent_key, source: source, status: status,
      conversation_id: conversation_id, message_id: message_id,
      patient_excerpt: patient_excerpt, agent_text: agent_text, ideal_reply: ideal_reply, rule: rule,
      target_section: target_section, target_section_title: SECTION_TITLES[target_section],
      preview_line: (ideal_reply.present? || rule.present? ? formatted_line : nil),
      applied_at: applied_at&.iso8601,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil,
      applied_by: applied_by ? { id: applied_by.id, name: applied_by.name } : nil,
      created_at: created_at.iso8601, updated_at: updated_at.iso8601
    }
  end

  private

  # seção vazia (= padrão) parte do DEFAULT: a partir daqui ela vira personalizada
  def apply_to_script!(by)
    Crm::ScriptVersion.snapshot!(account, kind: 'script', note: "antes de aplicar a orientação ##{id}", by: by, guidance: self)
    script = Crm::ScriptVersion.current_content(account, 'script', nil)
    base = script[target_section].to_s.strip.presence || Crm::CevicoScript::DEFAULT[target_section].to_s
    script[target_section] = "#{base}\n#{formatted_line}"
    Crm::ScriptVersion.write_script!(account, script)
    script[target_section]
  end

  # passos do agente: parte do prompt vigente (personalizado ou padrão) e
  # grava no PUBLICADO — o rascunho (draft) do card não é tocado
  def apply_to_stage!(by)
    Crm::ScriptVersion.snapshot!(account, kind: 'stage', agent_key: agent_key, note: "antes de aplicar a orientação ##{id}",
                                          by: by, guidance: self)
    base = Crm::CevicoScript.stage_prompt(account, agent_key).to_s.strip
    new_prompt = "#{base}\n#{formatted_line}"
    Crm::ScriptVersion.write_stage_prompt!(account, agent_key, new_prompt)
    new_prompt
  end
end
