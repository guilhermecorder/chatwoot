# == Schema Information
#
# Table name: tasks
#
#  id                  :bigint           not null, primary key
#  archived_at         :datetime
#  attendance          :string
#  booking_kind        :string
#  cancel_reason       :string
#  canceled_at         :datetime
#  cevico_born_via     :string
#  charges             :jsonb            not null
#  color               :string
#  comments            :jsonb            not null
#  completed_at        :datetime
#  confirmed_at        :datetime
#  declined_at         :datetime
#  description         :text
#  doctor              :string
#  due_at              :datetime
#  external_ref        :string
#  indicated_procedure :string
#  modality            :string
#  origin              :string
#  particular          :boolean          default(FALSE), not null
#  phone               :string
#  priority            :integer          default("medium"), not null
#  procedure           :string
#  rescheduled_count   :integer          default(0), not null
#  source              :string
#  source_detail       :string
#  status              :integer          default("todo"), not null
#  surgery_indication  :string
#  task_type           :string
#  title               :string           not null
#  unit                :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  assignee_id         :bigint
#  canceled_by_id      :bigint
#  cevico_source_id    :bigint
#  contact_id          :bigint
#  creator_id          :bigint           not null
#
# Indexes
#
#  index_tasks_on_account_and_external_ref  (account_id,external_ref) UNIQUE WHERE (external_ref IS NOT NULL)
#  index_tasks_on_account_id                (account_id)
#  index_tasks_on_account_id_and_status     (account_id,status)
#  index_tasks_on_account_id_and_unit       (account_id,unit)
#  index_tasks_on_account_type_created      (account_id,task_type,created_at)
#  index_tasks_on_account_type_due          (account_id,task_type,due_at)
#  index_tasks_on_assignee_id               (assignee_id)
#  index_tasks_on_canceled_by_id            (canceled_by_id)
#  index_tasks_on_contact_id                (contact_id)
#  index_tasks_on_creator_id                (creator_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (canceled_by_id => users.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (creator_id => users.id)
#
class Task < ApplicationRecord # rubocop:disable Metrics/ClassLength
  belongs_to :account
  belongs_to :creator, class_name: 'User'
  belongs_to :assignee, class_name: 'User', optional: true
  # 🗑️ item 304: quem mandou o agendamento para a Lixeira (nil = robô/hub)
  belongs_to :canceled_by, class_name: 'User', optional: true
  # Central do Paciente (Fase 0): consulta amarrada ao CONTATO de verdade;
  # o telefone vira fallback para paciente que ainda não existe no sistema.
  belongs_to :contact, optional: true

  # 🗑️ item 304 (30/09): agendamento (consulta/cirurgia) nunca é apagado pela
  # tela — vai para a Lixeira (canceled_at + quem + motivo) e pode voltar.
  # Só card de tarefa comum (sem paciente) continua sendo apagado de verdade.
  APPOINTMENT_TYPES = %w[consulta cirurgia].freeze
  # 'excluida_tarefas' = card ⚠️ do robô excluído no quadro de Tarefas (fica com rastro)
  # duplicada_hub = cópia vinda do Oftalmofácil unida à consulta da equipe (auditoria 10/2026, #462/#472)
  CANCEL_REASONS = %w[excluida_agenda cancelada_equipe paciente_desmarcou oftalmofacil excluida_tarefas duplicada_hub].freeze

  def appointment?
    APPOINTMENT_TYPES.include?(task_type)
  end

  # ✅ item 305 (01/10): cartões do quadro de Tarefas = tudo que NÃO é
  # agendamento da Agenda (tipo vazio também é cartão — NOT IN sozinho
  # descartaria o NULL).
  scope :board_cards, lambda {
    where('tasks.task_type IS NULL OR tasks.task_type NOT IN (?)', APPOINTMENT_TYPES)
      .where("tasks.unit IS NULL OR tasks.unit = ''")
  }

  def to_trash!(by:, reason: 'excluida_agenda')
    update!(canceled_at: Time.current, canceled_by: by, cancel_reason: reason)
  end

  # 🔐 Auditoria 10/2026 (achados #18/#130/#131/#315): o que é DA CLÍNICA TODA
  # (qualquer pessoa da equipe vê e edita): consulta/cirurgia — com ou sem
  # unidade (a IA grava consulta sem unidade), agendamento antigo só com
  # unidade, agendamento vindo de outro sistema (source) e as tarefas "⚠️" que
  # o ROBÔ abre para a equipe conferir. O resto é tarefa PESSOAL: só quem criou,
  # quem é o responsável ou o administrador. A regra é uma só, usada pela
  # lista (index/agenda_details) e pelas portas de editar/apagar.
  #
  # A tarefa ⚠️ do robô é reconhecida pelo carimbo `cevico_born_via = 'robo'`
  # (item 322) + o prefixo no título — o título sozinho não basta, porque
  # qualquer pessoa edita o título: um card pessoal renomeado para "⚠️ …" pela
  # equipe (born_via 'equipe') continua pessoal. Linhas antigas, de antes do
  # carimbo (born_via vazio), só contam quando quem criou é administrador
  # (a IA sempre cria em nome do primeiro admin).
  REVISION_PREFIX = '⚠️'.freeze
  ADMIN_CREATOR_SQL = 'tasks.creator_id IN (SELECT account_users.user_id FROM account_users ' \
                      'WHERE account_users.account_id = tasks.account_id AND account_users.role = 1)'.freeze
  REVISION_CARD_SQL = "(tasks.title LIKE :rev AND (tasks.cevico_born_via = 'robo' " \
                      "OR (tasks.cevico_born_via IS NULL AND #{ADMIN_CREATOR_SQL})))".freeze
  scope :visible_to, lambda { |user|
    where('tasks.assignee_id = :uid OR tasks.creator_id = :uid OR tasks.task_type IN (:types) ' \
          "OR (tasks.unit IS NOT NULL AND tasks.unit <> '') OR tasks.source IS NOT NULL OR #{REVISION_CARD_SQL}",
          uid: user.id, types: APPOINTMENT_TYPES, rev: "#{REVISION_PREFIX}%")
  }

  def shared_with_team?
    appointment? || unit.present? || source.present? || ai_revision_card?
  end

  # tarefa "⚠️ …" aberta pelo robô (ou antiga, criada em nome de um admin)
  def ai_revision_card?
    return false unless title.to_s.start_with?(REVISION_PREFIX)
    return true if cevico_born_via == 'robo'

    cevico_born_via.nil? && account.administrators.exists?(id: creator_id)
  end

  # 🗑️ o que a tela da Agenda desenha como agendamento (mesma regra do front,
  # isAppointmentTask): consulta/cirurgia, ou agendamento antigo só com
  # unidade e data. "Excluir" isso vai para a Lixeira, nunca apaga de vez.
  def agenda_entry?
    appointment? || (unit.present? && due_at.present?)
  end

  # "Excluir" guarda rastro (Lixeira) em vez de apagar: agendamento e a tarefa
  # ⚠️ do robô — ela é a prova de quem escapou da IA. O card ⚠️ também sai do
  # quadro (archived_at), porque o quadro de Tarefas não lê a Lixeira.
  def keeps_trace_on_delete?
    agenda_entry? || ai_revision_card?
  end

  def restore!
    update!(canceled_at: nil, canceled_by: nil, cancel_reason: nil)
  end

  # anexos da tarefa (imagem/PDF/documento — pedido de exame, print, guia):
  # visíveis para criador, responsável e admin (storage entra no backup!)
  has_many_attached :files

  validates :title, presence: true

  # 📅 item 217 (23/09): o que CONTA como agendamento.
  #   nil / 'agendamento' = consulta NOVA (o robô ou a equipe marcou nesta conversa)
  #   'registro'          = já estava marcada fora do sistema (Oftalmofácil/telefone)
  #                         e foi só lançada na Agenda — aparece como "Lançada",
  #                         fica fora de "Consultas agendadas" e da taxa
  BOOKING_KINDS = %w[agendamento registro].freeze
  validates :booking_kind, inclusion: { in: BOOKING_KINDS }, allow_blank: true
  scope :bookings, -> { where("tasks.booking_kind IS NULL OR tasks.booking_kind <> 'registro'") }

  def registered_only?
    booking_kind == 'registro'
  end

  # 🎨 item 290 (29/09): cor do agendamento na Agenda (organização livre da
  # equipe, vale para todos; nil = cor padrão do tipo). A lista é a MESMA do
  # front (helper/cevicoAgenda.js → TASK_COLORS). Não entra em indicador.
  COLORS = %w[
    #DC2626 #DB2777 #EA580C #EAB308 #84CC16 #16A34A
    #0D9488 #0891B2 #2563EB #7C3AED #86198F #475569
  ].freeze
  validates :color, inclusion: { in: COLORS }, allow_nil: true

  # 🏥 item 300 (30/09): de quem é o paciente — a equipe escolhe no formulário
  # da Agenda. 'oftalmofacil' = fala só pela caixa do Oftalmofácil, card no
  # funil do Oftalmofácil e fora dos números da CEVICO. nil = agendamento
  # antigo ou criado pelos agentes (vale a etiqueta/funil do paciente).
  ORIGINS = %w[cevico oftalmofacil].freeze
  validates :origin, inclusion: { in: ORIGINS }, allow_nil: true
  scope :not_partner_origin, -> { where("tasks.origin IS NULL OR tasks.origin <> 'oftalmofacil'") }

  def partner_origin?
    origin == 'oftalmofacil'
  end

  # 💰 item 324 (05/10): valores lançados à mão no card (com quem lançou)
  def assign_charges(list, user)
    self.charges = Crm::AppointmentPrice.stamp_charges(charges, list, user)
  end

  # 🏷️ item 322 (04/10): o agendamento nasce carimbado com a FONTE (de quem é o
  # paciente) e com o COMO (equipe, robô, sincronização…). Trocar a origem no
  # formulário recarimba; o 1º agendamento também é evidência de quem é o paciente.
  include CevicoSourceStamped
  before_update -> { cevico_stamp!(refresh: true) },
                if: -> { will_save_change_to_origin? || will_save_change_to_source? || will_save_change_to_source_detail? }
  after_save -> { Crm::Stamp.claim_contact!(contact, cevico_source_id) },
             if: -> { appointment? && contact_id.present? && (saved_change_to_contact_id? || saved_change_to_id?) }

  validate :contact_belongs_to_account

  enum status: { todo: 0, doing: 1, done: 2 }
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }

  before_save :link_contact_by_phone
  before_save :track_completion
  before_save :reset_confirmation_on_reschedule
  before_create :infer_consulta_modality
  # 🔁 item 343: retorno novo nasce sem dono individual (equipe dos retornos)
  before_create -> { Crm::TaskOwner.apply_retorno_team!(self) }
  after_update :stamp_reschedule!, if: :rescheduled_in_this_save?

  # 🔁 Auditoria 10/2026 (#2/#133): REMARCAÇÃO com carimbo próprio. Antes o
  # painel usava o updated_at — qualquer toque na consulta (✓ compareceu,
  # trocar médico, Lixeira…) virava "reagendada" no dia do toque. Agora, toda
  # vez que o rescheduled_count sobe (Agenda, IA, ferramentas), entra uma linha
  # { kind: 'rescheduled', at, from, to, by } na lista `comments` da consulta
  # (jsonb que já existe — sem migration). Se um dia virar coluna
  # rescheduled_at, só estas leituras mudam.
  RESCHEDULE_KIND = 'rescheduled'.freeze

  # todos os momentos em que a consulta foi remarcada (mais antigo primeiro)
  def rescheduled_times
    Array(comments).filter_map do |entry|
      next unless entry.is_a?(Hash) && entry['kind'] == RESCHEDULE_KIND

      Time.zone.parse(entry['at'].to_s)
    rescue ArgumentError
      nil
    end.sort
  end

  # a ÚLTIMA remarcação (nil = nunca remarcada, ou remarcada antes do carimbo existir)
  def rescheduled_at
    rescheduled_times.last
  end

  # Tudo do paciente em um lugar só: casa por contact_id (unificado) e,
  # para registros antigos sem link, pelo telefone — sem repetir o regexp
  # frágil em cada dashboard.
  def self.for_patient(account, contact)
    digits = contact.phone_number.to_s.gsub(/\D/, '')
    scope = account.tasks
    return scope.where(contact_id: contact.id) if digits.length < 8

    # auditoria 10/2026 (#239): registro antigo sem link só entra se for a
    # MESMA linha (DDD confere) — o final de 8 dígitos só acha candidatos
    legacy_ids = scope.where(contact_id: nil)
                      .where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
                      .pluck(:id, :phone)
                      .select { |_id, task_phone| Crm::AppointmentRecorder.same_phone_line?(digits, task_phone) }
                      .map(&:first)
    return scope.where(contact_id: contact.id) if legacy_ids.empty?

    scope.where('contact_id = :cid OR id IN (:ids)', cid: contact.id, ids: legacy_ids)
  end

  # Contato da conta cujo telefone bate — critério único do sistema para casar
  # telefone com contato. Auditoria 10/2026 (#239, fecha o A16 de julho): os
  # últimos 8 dígitos só acham CANDIDATOS; quem decide é a mesma linha
  # (DDD confere — Crm::AppointmentRecorder.same_phone_line?). Quando mais de
  # um cadastro bate com a linha, desempata ANTES de desistir (revisão da
  # Rodada 3): 1º quem tem o número exatamente igual ao informado (com ou sem
  # +55 — cadastro duplicado da mesma linha devolve o mais antigo, como sempre
  # foi); 2º número SEM DDD prefere o cadastro do DDD da clínica (mesma
  # convenção do Crm::AppointmentOrigin.normalize_phone). Só então, se ainda
  # não dá para saber de quem é → nil (o chamador trata como "sem cadastro").
  def self.match_contact(account, phone)
    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.length < 8

    found = account.contacts
                   .where("regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
                   .order(:id)
                   .select { |contact| Crm::AppointmentRecorder.same_phone_line?(digits, contact.phone_number) }
    return found.first if found.size <= 1

    untied = untie_phone_match(found, digits)
    return untied if untied

    Rails.logger.info "[Task.match_contact] telefone ambíguo (#{found.size} cadastros batem com a mesma linha) — sem vínculo"
    nil
  end

  # desempate entre cadastros que batem com a mesma linha: número exatamente
  # igual (com ou sem +55) vence; sem DDD, vence o cadastro do DDD da clínica
  def self.untie_phone_match(found, digits)
    key = phone_key(digits)
    exact = found.find { |contact| phone_key(contact.phone_number) == key }
    return exact if exact
    return nil unless key.length.between?(8, 9)

    found.find { |contact| phone_key(contact.phone_number) == "#{Crm::AppointmentOrigin::DEFAULT_DDD}#{key}" }
  end

  # dígitos do telefone sem o +55 e sem zero na frente, para comparar
  # "exatamente igual" entre o que foi informado e o cadastro
  def self.phone_key(phone)
    digits = phone.to_s.gsub(/\D/, '').sub(/\A0+/, '')
    digits.start_with?('55') && digits.length >= 12 ? digits[2..] : digits
  end

  private

  # Toda task nasce (ou muda de telefone) já amarrada ao contato, venha de
  # onde vier: modal da Agenda, Secretário da Agenda, Atendente Instagram,
  # automações. Quem já informou o contato explicitamente vence.
  def link_contact_by_phone # rubocop:disable Metrics/CyclomaticComplexity
    return if phone.blank?
    return if contact_id.present? && (new_record? || will_save_change_to_contact_id?)
    return unless new_record? || will_save_change_to_phone?

    matched = Task.match_contact(account, phone)
    self.contact = matched if matched
  end

  def contact_belongs_to_account
    return if contact_id.blank? || contact.nil?
    return if contact.account_id == account_id

    errors.add(:contact, 'não pertence a esta conta')
  end

  # consulta REMARCADA (outro dia/hora) volta a "não confirmada": o "sim" era
  # para a data antiga; os lembretes da nova data saem de novo (varredura 03/10)
  def reset_confirmation_on_reschedule
    return if new_record? || task_type != 'consulta' || !will_save_change_to_due_at?
    return if will_save_change_to_confirmed_at? || will_save_change_to_declined_at?

    self.confirmed_at = nil
    self.declined_at = nil
  end

  def rescheduled_in_this_save?
    saved_change_to_rescheduled_count? && rescheduled_count.to_i > rescheduled_count_before_last_save.to_i
  end

  # grava o carimbo da remarcação SOMANDO no banco (sem "lê, altera, grava" da
  # lista inteira — um comentário escrito ao mesmo tempo não se perde)
  def stamp_reschedule!
    from, to = saved_change_to_due_at || [due_at, due_at]
    who = Current.user
    entry = {
      'kind' => RESCHEDULE_KIND, 'at' => Time.current.iso8601(3),
      'from' => from&.iso8601, 'to' => to&.iso8601, 'by' => who&.id,
      'user_id' => who&.id, 'name' => who&.name.presence || 'Robô',
      'text' => "🔁 Remarcada: #{reschedule_label(from)} → #{reschedule_label(to)}"
    }
    Task.where(id: id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["comments = (CASE WHEN jsonb_typeof(comments) = 'array' THEN comments ELSE '[]'::jsonb END) || ?::jsonb", [entry].to_json]
    )
    self.comments = Array(comments) + [entry]
    clear_attribute_changes(%w[comments])
  end

  def reschedule_label(time)
    time ? time.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M') : 'sem data'
  end

  def track_completion
    return unless status_changed?

    self.completed_at = done? ? Time.current : nil
  end

  # Tipo de consulta ACOMPANHA A JORNADA do paciente: consulta criada SEM
  # tipo explícito (Secretário da Agenda, Atendente Instagram, backfill)
  # nasce como RETORNO quando o paciente já tem consulta anterior (match por
  # telefone) e como AVALIAÇÃO quando é a primeira. Escolha manual no modal
  # sempre vence (o campo vem preenchido e o hook não mexe).
  def infer_consulta_modality # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return unless task_type == 'consulta' && modality.blank?

    had_before =
      if contact_id.present?
        # unificado: histórico do CONTATO (link_contact_by_phone roda antes)
        Task.for_patient(account, contact)
            .where(task_type: 'consulta')
            .exists?(['due_at < ?', due_at || Time.current])
      else
        digits = phone.to_s.gsub(/\D/, '')
        return self.modality = 'avaliacao' if digits.length < 8

        # auditoria 10/2026 (#239): consulta anterior só conta se for a MESMA linha (DDD confere)
        account.tasks
               .where(task_type: 'consulta')
               .where('due_at < ?', due_at || Time.current)
               .where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
               .pluck(:phone)
               .any? { |task_phone| Crm::AppointmentRecorder.same_phone_line?(digits, task_phone) }
      end
    self.modality = had_before ? 'retorno' : 'avaliacao'
  end
end
