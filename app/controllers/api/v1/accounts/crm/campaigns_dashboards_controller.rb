# Dashboard das campanhas de mensagem modelo (WhatsApp): investimento,
# volume, tipo de mensagem, responsividade e conversões (consultas
# agendadas / cirurgias via stage_logs) — no mesmo espírito do Dashboard CRM.
class Api::V1::Accounts::Crm::CampaignsDashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  # Rodada 5 (#385): colunas de cirurgia sem pós-operatório e sem indicação
  SURGERY_EXCLUDE = %w[%pós% %indica%].freeze

  def show
    since, until_at = resolve_range
    cost = params[:cost_per_message].to_f # R$ por mensagem modelo (informado na tela)

    # ⏸ revisão R3 (#415): pausada e falhou também entram — o que já saiu foi
    # cobrado pela Meta e precisa aparecer no investimento (started_at já existe)
    campaigns = Current.account.crm_campaigns
                       .where(status: %i[processing completed paused failed])
                       .where(started_at: since..until_at)
                       .order(started_at: :desc)

    rows = campaigns.map { |c| campaign_row(c, cost) }

    render json: {
      period_days: ((until_at - since) / 1.day).ceil,
      totals: build_totals(rows, cost),
      by_template: build_by_template(rows),
      campaigns: rows
    }
  end

  private

  # régua padrão CEVICO (06/08) via concern; presets antigos (week / N dias)
  # continuam valendo por compatibilidade
  def resolve_range
    standard_period_range || legacy_range
  end

  def legacy_range
    now = TZ.now
    case params[:preset]
    when 'today'     then [now.beginning_of_day, now]
    when 'yesterday' then [now.yesterday.beginning_of_day, now.yesterday.end_of_day]
    when 'week'      then [now.beginning_of_week.beginning_of_day, now]
    else
      period = [[params[:period].to_i, 7].max, 1825].min
      [(now - period.days).beginning_of_day, now]
    end
  end

  def campaign_row(campaign, cost)
    sent = campaign.campaign_contacts.count
    replies = replies_count(campaign)
    agendamentos = stage_entries_count(campaign, schedule_stage_ids)
    cirurgias = surgery_counts(campaign)

    {
      id: campaign.id,
      name: campaign.name,
      template: campaign.template_params['name'],
      started_at: campaign.started_at,
      status: campaign.status,
      sent: sent,
      replies: replies,
      reply_rate: pct(replies, sent),
      agendamentos: agendamentos,
      agendamentos_rate: pct(agendamentos, sent),
      **surgery_fields(cirurgias, sent),
      potential_value: potential_value(campaign),
      investment: (sent * cost).round(2)
    }
  end

  def build_totals(rows, cost)
    sent = rows.sum { |r| r[:sent] }
    replies = rows.sum { |r| r[:replies] }
    agendamentos = rows.sum { |r| r[:agendamentos] }
    cirurgias = { agendadas: rows.sum { |r| r[:cirurgias_agendadas] }, realizadas: rows.sum { |r| r[:cirurgias_realizadas] } }
    {
      campaigns: rows.size,
      sent: sent,
      investment: (sent * cost).round(2),
      cost_per_message: cost,
      replies: replies,
      reply_rate: pct(replies, sent),
      agendamentos: agendamentos,
      agendamentos_rate: pct(agendamentos, sent),
      **surgery_fields(cirurgias, sent),
      potential_value: rows.sum { |r| r[:potential_value] }.round(2)
    }
  end

  def build_by_template(rows)
    rows.group_by { |r| r[:template].presence || 'Sem modelo' }
        .map do |template, list|
          sent = list.sum { |r| r[:sent] }
          replies = list.sum { |r| r[:replies] }
          { template: template, campaigns: list.size, sent: sent, replies: replies, reply_rate: pct(replies, sent) }
        end
        .sort_by { |t| -t[:sent] }
  end

  # respondeu = mensagem recebida na conversa da campanha depois do envio
  def replies_count(campaign)
    campaign.campaign_contacts
            .where.not(conversation_id: nil)
            .joins('INNER JOIN messages ON messages.conversation_id = crm_campaign_contacts.conversation_id ' \
                   'AND messages.message_type = 0 AND messages.created_at > crm_campaign_contacts.sent_at')
            .distinct
            .count(:id)
  end

  # Rodada 5 (#385): cirurgia AGENDADA × REALIZADA são números diferentes
  # (antes um só contador pegava qualquer coluna com "cirurgia" no nome e a
  # tela chamava de "realizadas"). Quem já chegou em "Cirurgia Realizada"
  # também conta como agendada — a realizada sempre cabe na agendada.
  def surgery_counts(campaign)
    {
      agendadas: stage_entries_count(campaign, surgery_booked_stage_ids | surgery_done_stage_ids),
      realizadas: stage_entries_count(campaign, surgery_done_stage_ids)
    }
  end

  # `cirurgias`/`cirurgias_rate` = realizadas: a tela antiga (aba aberta
  # antes da atualização) mostra esse número com o rótulo "Cirurgias realizadas"
  def surgery_fields(counts, sent)
    {
      cirurgias_agendadas: counts[:agendadas], cirurgias_agendadas_rate: pct(counts[:agendadas], sent),
      cirurgias_realizadas: counts[:realizadas], cirurgias_realizadas_rate: pct(counts[:realizadas], sent),
      cirurgias: counts[:realizadas], cirurgias_rate: pct(counts[:realizadas], sent)
    }
  end

  # destinatários cujo card ENTROU na(s) etapa(s) depois do disparo
  # Rodada 5: carga em massa (`bulk`, item 309) não é paciente entrando na coluna
  def stage_entries_count(campaign, stage_ids)
    return 0 if stage_ids.empty? || campaign.started_at.blank?

    crm_ids = recipient_crm_contacts(campaign).select(:id)
    Crm::StageLog.where(crm_contact_id: crm_ids, stage_id: stage_ids, event_type: Crm::StageLogBulk::ENTERED)
                 .where('entered_at > ?', campaign.started_at)
                 .distinct
                 .count(:crm_contact_id)
  end

  # valor em campanha: soma dos valores dos cards dos destinatários
  def potential_value(campaign)
    recipient_crm_contacts(campaign).sum('COALESCE(value, 0)').to_f.round(2)
  end

  def recipient_crm_contacts(campaign)
    Crm::Contact.joins(:pipeline)
                .where(crm_pipelines: { account_id: Current.account.id })
                .where(contact_id: campaign.campaign_contacts.select(:contact_id))
  end

  def schedule_stage_ids
    @schedule_stage_ids ||= stage_ids_matching('%agendamento%')
  end

  # Rodada 5 (#385): fora pós-operatório e indicação, como no Dashboard CRM
  def surgery_booked_stage_ids
    @surgery_booked_stage_ids ||= stage_ids_matching('%cirurgia agendada%', exclude: SURGERY_EXCLUDE)
  end

  def surgery_done_stage_ids
    @surgery_done_stage_ids ||= stage_ids_matching('%cirurgia realizada%', exclude: SURGERY_EXCLUDE)
  end

  def stage_ids_matching(pattern, exclude: %w[%pós%])
    scope = Crm::Stage.joins(:pipeline)
                      .where(crm_pipelines: { account_id: Current.account.id })
                      .where('crm_stages.name ILIKE ?', pattern)
    exclude.each { |out| scope = scope.where.not('crm_stages.name ILIKE ?', out) }
    scope.pluck(:id)
  end

  def pct(part, total)
    total.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end
end
