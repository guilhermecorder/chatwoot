# == Schema Information
#
# Table name: crm_contacts
#
#  id                    :bigint           not null, primary key
#  cevico_born_via       :string
#  notes                 :text
#  origin                :string
#  procedure_of_interest :string
#  stage_moved_at        :datetime
#  value                 :decimal(15, 2)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  assignee_id           :bigint
#  cevico_source_id      :bigint
#  contact_id            :bigint           not null
#  pipeline_id           :bigint           not null
#  stage_id              :bigint           not null
#
# Indexes
#
#  index_crm_contacts_on_assignee_id                 (assignee_id)
#  index_crm_contacts_on_contact_id                  (contact_id)
#  index_crm_contacts_on_contact_id_and_pipeline_id  (contact_id,pipeline_id) UNIQUE
#  index_crm_contacts_on_pipeline_id                 (pipeline_id)
#  index_crm_contacts_on_stage_id                    (stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#  fk_rails_...  (stage_id => crm_stages.id)
#
class Crm::Contact < ApplicationRecord
  self.table_name = 'crm_contacts'

  include CevicoSourceStamped # 🏷️ item 322: nasce com a fonte do funil + como nasceu

  belongs_to :contact,  class_name: '::Contact'
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :stage,    class_name: 'Crm::Stage'
  belongs_to :assignee, class_name: 'User', optional: true
  # 🔒 R2 da auditoria (#300): SEM dependent: :destroy — o histórico de colunas
  # ("entrou em X em tal dia") fica guardado no banco mesmo quando o card sai
  # do funil (a tabela não tem chave estrangeira; crm_contact_id não aceita
  # nulo, por isso não dá para "desligar" o log do card sem migration).
  # ATENÇÃO: os painéis por coluna fazem join com crm_contacts (KpiBagService,
  # FunnelService, home#..., StageLogBulk), então o card removido SAI desses
  # painéis; só a taxa de agendamento (BookingRate, sem join) continua contando.
  # Para o removido voltar a contar precisa de soft-delete = migration da
  # Rodada 6 (Lixeira de card), se o Guilherme quiser.
  has_many   :stage_logs, class_name: 'Crm::StageLog', foreign_key: :crm_contact_id, inverse_of: :crm_contact # rubocop:disable Rails/HasManyOrHasOneDependent

  validates :contact_id, uniqueness: { scope: :pipeline_id, message: 'already exists in this pipeline' }

  # "Remover do funil" com rastro (R2 #300): fecha o log da coluna atual (o
  # tempo na coluna fica certo), escreve uma nota na ficha do paciente dizendo
  # QUEM removeu e de qual funil/coluna, registra no log do servidor e só então
  # apaga o card. Os stage_logs ficam (ver has_many acima).
  def remove_from_pipeline!(by: nil)
    now = Time.current
    who = by&.name.presence || 'sistema'
    transaction do
      stage_logs.where(left_at: nil).find_each { |log| log.close!(now) }
      contact.notes.create!(
        user_id: by&.id,
        content: "Removido do funil «#{pipeline.name}» (estava em «#{stage.name}») por #{who}. " \
                 'O histórico de colunas deste card fica guardado no banco (sai dos painéis por coluna).'
      )
      destroy!
    end
    Rails.logger.info("[CEVICO crm] card #{id} (contato #{contact_id}) removido do funil #{pipeline_id} por #{who} (user #{by&.id})")
    true
  end

  # 🧭 item 341 (Ambientes do CRM): paciente de OUTRO ambiente (ex.: caixa 12
  # Oftalmofácil) nunca ganha card no funil da CEVICO — o card nasce no funil
  # do ambiente dele, na coluna equivalente (Crm::CardRouter)
  before_validation(on: :create) { Crm::CardRouter.route!(self) }
  after_create  :log_initial_stage
  # 🏷️ item 322: o 1º card é evidência de quem é o paciente (primeira evidência carimba)
  after_create  -> { Crm::Stamp.claim_contact!(contact, cevico_source_id) }
  after_update  :log_stage_change, if: :saved_change_to_stage_id?
  after_update  :fire_value_automations, if: :saved_change_to_value?
  # ✅ item 300: card entrou em "Consulta Confirmada" → a próxima consulta do
  # paciente fica confirmada na Agenda (equipe arrastou ou o N8N moveu)
  after_save :reflect_confirmation, if: :saved_change_to_stage_id?

  private

  def reflect_confirmation
    return if Crm::CardRouter.quiet? # 🧭 item 341: a migração entre ambientes não mexe na Agenda

    Crm::ConfirmationReflector.from_stage(self)
  end

  def log_initial_stage
    now = Time.current
    update_column(:stage_moved_at, now)
    stage_logs.create!(
      stage_id:   stage_id,
      stage_name: stage.name,
      stage_color: stage.color,
      event_type:  'entered',
      entered_at:  now
    )
  end

  def log_stage_change
    now = Time.current
    previous_stage_id = saved_change_to_stage_id.first

    # Fecha o log da etapa anterior
    open_log = stage_logs.find_by(stage_id: previous_stage_id, left_at: nil)
    open_log&.close!(now)

    # Abre log para nova etapa
    stage_logs.create!(
      stage_id:    stage_id,
      stage_name:  stage.name,
      stage_color: stage.color,
      event_type:  'entered',
      entered_at:  now
    )

    update_column(:stage_moved_at, now)
  end

  # Gatilho "Valor adicionado no card": quando o card GANHA valor (> 0),
  # dispara as automações desse gatilho na coluna atual — vale para todos os
  # caminhos que preenchem valor (board, orçamento detectado, ação set_value).
  # Uso típico: "recebeu orçamento em Novos Contatos → mover p/ Envio de Orçamento".
  def fire_value_automations
    return unless value.to_f.positive?

    Crm::Automation.where(stage_id: stage_id, active: true, trigger_type: 'value_added').find_each do |automation|
      # trava anti-loop: valor que muda não pode disparar outra escrita de valor
      next if automation.action_type == 'set_value'

      delay = automation.delay_minutes.to_i
      job = delay.positive? ? CrmAutomationFireJob.set(wait: delay.minutes) : CrmAutomationFireJob
      job.perform_later(automation.id, contact_id, {
                          event_type: 'value_added',
                          value: value.to_f
                        })
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::Contact] value_added automations: #{e.message}"
  end
end
