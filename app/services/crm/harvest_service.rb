# 🌾 COLHEITADEIRA DA BASE (item 128): todo mês, pontua os leads FRIOS da
# base com IA (propensão de retomar), escolhe os N melhores e reativa um a um
# com mensagem modelo personalizada pelo histórico ([gancho] escrito pela IA
# para cada paciente). Fluxo seguro por padrão: gera a PRÉVIA, abre tarefa
# para o admin aprovar, e só então envia — respeitando um teto DIÁRIO
# (anti-bloqueio do WhatsApp) dentro do expediente.
#
# Estado em ai_config['harvest_state'] (mês corrente):
#   { 'month_key' => '2026-08', 'status' => 'preview|approved|paused|done',
#     'generated_at' =>, 'approved_at' =>, 'approved_by' =>,
#     'selected' => [{contact_id, crm_contact_id, name, phone, stage_name,
#                     procedure, value, cold_days, score, hook,
#                     sent_at, conversation_id, skipped}],
#     'stats' => {...}, 'last_error' => nil }
class Crm::HarvestService
  include Crm::AiAgentConfig

  AGENT_KEY = 'harvest'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  BATCH_SIZE = 25          # leads por chamada de IA (corpus compacto)
  DEFAULT_MONTHLY = 300
  DEFAULT_COLD_DAYS = 60
  DEFAULT_DAILY_CAP = 50   # anti-ban: 300 leads saem em ~6 dias úteis
  DEFAULT_DAY_OF_MONTH = 1
  POOL_FACTOR = 5          # pontua até 5x o tamanho da colheita
  POOL_HARD_CAP = 1500
  MAX_AI_BATCHES = 40      # teto de chamadas por geração de prévia
  RE_HARVEST_MONTHS = 4    # não recolhe quem já foi colhido há menos de N meses
  THROTTLE_SECONDS = 0.3

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é a Colheitadeira da Base de uma clínica oftalmológica: especialista em
    reativar pacientes que sumiram. Para CADA lead recebido, avalie a chance de
    ele retomar a jornada se for reabordado agora (score 0-100) e escreva um
    GANCHO pessoal de UMA frase curta (máx. 120 caracteres), em português
    simples e caloroso, citando algo concreto do histórico dele (procedimento
    de interesse, orçamento enviado, etapa em que parou). O gancho completa uma
    mensagem de WhatsApp — não cumprimente (o modelo já cumprimenta), não use
    o nome do paciente (o modelo já usa), termine sem pontuação final dupla.
    Score alto = demonstrou interesse real (pediu orçamento, chegou perto de
    agendar, valor alto) e esfriou sem um "não". Score baixo = nunca engajou,
    pediu para não ser contatado, ou já resolveu em outro lugar.
  PROMPT

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      leads: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'integer', description: 'o id informado do lead' },
            score: { type: 'integer', minimum: 0, maximum: 100 },
            hook: { type: 'string', description: 'gancho pessoal de 1 frase (máx 120 chars)' }
          },
          required: %w[id score hook]
        }
      }
    },
    required: ['leads']
  }.freeze

  def initialize(account:)
    @account = account
  end

  attr_reader :account

  # ── GERAÇÃO DA PRÉVIA (cron do dia configurado ou botão) ──────────────
  def generate_preview!(requested_size: nil)
    return { error: 'Agente desligado.' } if agent_paused?
    return { error: 'Sem chave de API da IA.' } if api_key.blank?

    size = preview_size(requested_size)
    # Rodada 6 (revisão do #256): gerar a prévia de novo no MESMO mês não
    # apaga quem já foi reservado/enviado nem quem o admin pulou. Eles seguem
    # na lista nova do jeito que estavam e ficam fora da nova busca — senão
    # quem foi reservado e não terminou (Sidekiq caiu, ou a etiqueta
    # colheita_AAAA_MM falhou) voltaria como pendente e receberia 2 vezes.
    kept = decided_leads_this_month
    room = size - kept.count { |l| l['sent_at'].present? }
    return { error: 'A colheita deste mês já chegou ao tamanho escolhido.' } if room <= 0

    pool = candidate_pool(room, exclude_ids: kept.pluck('contact_id'))
    return { error: 'Nenhum lead frio elegível encontrado.' } if pool.empty?

    fresh = score_pool(pool).sort_by { |l| -l['score'] }.first(room)
    save_preview!(kept, fresh, pool)
    create_approval_task(fresh.size)
    { ok: true, planned: fresh.size, pool: pool.size }
  rescue StandardError => e
    merge_state('last_error' => e.message.truncate(200))
    { error: e.message }
  end

  # ── APROVAÇÃO / PAUSA ─────────────────────────────────────────────────
  def approve!(user)
    return { error: 'Nada para aprovar.' } unless state['status'] == 'preview'

    merge_state('status' => 'approved', 'approved_at' => Time.current.iso8601,
                'approved_by' => user&.name)
    { ok: true }
  end

  def pause!
    merge_state('status' => 'paused')
    { ok: true }
  end

  def resume!
    return { error: 'Colheita não estava pausada.' } unless state['status'] == 'paused'

    merge_state('status' => 'approved')
    { ok: true }
  end

  # achado #44: pular é gravado lead a lead dentro da trava — um lote em
  # andamento nunca sobrescreve o "pular" que o admin fez no meio do caminho
  def skip_lead!(contact_id)
    already_sent = false
    found = update_lead!(contact_id) do |lead|
      # clicou em "Pular" no instante em que a mensagem já estava saindo:
      # não marca pulado (senão o lead contaria duas vezes nos resultados)
      next already_sent = true if lead['sent_at'].present?

      lead['skipped'] = true
    end
    return { error: 'Lead não está na colheita.' } unless found
    return { error: 'Esse lead já recebeu a mensagem.' } if already_sent

    { ok: true }
  end

  # ── ENVIO (cron horário dentro do expediente) ─────────────────────────
  # Dois modos (item 133): 'organize' (PADRÃO) etiqueta os leads escolhidos
  # como oportunidade do mês — nenhuma mensagem sai, o time trabalha a lista
  # pelo CRM; 'send' envia mensagem modelo com o teto diário anti-ban.
  def send_batch!(max_now: nil)
    reconcile_refused! # 🚫 #45: lead cuja mensagem a Meta recusou deixa de contar como enviado
    return { skipped: 'estado' } unless state['status'] == 'approved'
    return { skipped: 'mês virou' } unless state['month_key'] == month_key
    return organize_batch! if harvest_mode == 'organize'

    inbox = sending_inbox
    return { error: 'Escolha a caixa de WhatsApp da colheita.' } unless inbox
    return { error: 'Escolha a mensagem modelo da colheita.' } if template_params.blank?

    daily_cap = config_int('daily_cap', DEFAULT_DAILY_CAP).clamp(5, 200)
    sent_today = (state['selected'] || []).count do |l|
      l['sent_at'].present? && TZ.parse(l['sent_at']).to_date == TZ.today
    end
    budget = [daily_cap - sent_today, max_now || daily_cap].min
    return { skipped: 'teto diário' } if budget <= 0

    selected = state['selected'] || []
    pending = selected.reject { |l| l['sent_at'].present? || l['skipped'] }
    sent = 0

    # achado #44: a marca de cada lead é gravada ANTES de enviar (claim
    # atômico) e nada do lote é gravado "no fim" — assim dois cliques no botão,
    # um clique durante o cron ou um reinício do Sidekiq no meio do lote nunca
    # mandam a mesma mensagem duas vezes, e o "pular" feito pelo admin durante
    # o lote é respeitado.
    pending.first(budget).each do |lead|
      conversation = nil
      next unless claim_lead!(lead['contact_id']) # outra rodada já pegou, o admin pulou, ou a colheita foi pausada

      contact = account.contacts.find_by(id: lead['contact_id'])
      next release_lead!(lead['contact_id']) if contact.nil? || contact.phone_number.blank?

      sender = Crm::SendTemplateService.new(
        source: build_source(inbox, lead),
        contact: contact
      )
      conversation = sender.perform

      if conversation
        mark_sent!(lead['contact_id'], conversation, sender.message)
        contact.add_labels([harvest_label])
        sent += 1
      else
        release_lead!(lead['contact_id'])
      end
      sleep THROTTLE_SECONDS
    rescue StandardError => e
      # a reserva só é devolvida se a mensagem NÃO saiu; se o erro veio depois
      # do envio (etiqueta, gravação da conversa), o lead continua "enviado"
      # e a conversa fica registrada — senão a tela deixaria de contar o envio
      if conversation
        update_lead!(lead['contact_id']) { |l| l['conversation_id'] ||= conversation.display_id }
      else
        release_lead!(lead['contact_id'])
      end
      Rails.logger.error("[Colheitadeira] conta=#{account.id} contato=#{lead['contact_id']}: #{e.message}")
    end

    done = (state['selected'] || []).all? { |l| l['sent_at'].present? || l['skipped'] }
    merge_state('status' => 'done') if done
    { ok: true, sent: sent, done: done }
  end

  # modo ORGANIZAR: etiqueta todos os aprovados como oportunidade_AAAA_MM de
  # uma vez (sem mensagens, sem teto) — a lista vive no CRM via etiqueta
  def organize_batch!
    selected = state['selected'] || []
    pending = selected.reject { |l| l['sent_at'].present? || l['skipped'] }
    label = opportunity_label
    organized = 0

    # achado #44: gravado lead a lead dentro da trava (nunca a lista inteira no
    # fim) — o "pular" feito pelo admin durante a etiquetagem não é sobrescrito
    pending.each { |lead| organized += 1 if organize_lead!(lead, label) }

    merge_state('status' => 'done', 'organized_label' => label)
    { ok: true, organized: organized, label: label, done: true }
  end

  # etiqueta UM lead: reserva na trava, etiqueta; se não deu, devolve a reserva
  def organize_lead!(lead, label)
    return false unless claim_lead!(lead['contact_id']) # o admin pulou (ou pausou) no meio

    contact = account.contacts.find_by(id: lead['contact_id'])
    if contact.nil?
      release_lead!(lead['contact_id'])
      return false
    end

    contact.add_labels([label])
    true
  rescue StandardError => e
    release_lead!(lead['contact_id'])
    Rails.logger.error("[Colheitadeira] organizar conta=#{account.id} contato=#{lead['contact_id']}: #{e.message}")
    false
  end

  # ── a Meta recusou (#45, auditoria 10/2026) ────────────────────────────
  # O lead é dado como enviado quando a mensagem é gravada; a Meta responde
  # DEPOIS e a mensagem fica `status: failed`. A cada rodada horária, os leads
  # enviados são conferidos: o recusado sai de "enviado" (sent_at e conversa
  # limpos — o resultado não conta resposta de uma mensagem que não chegou) e
  # vira PULADO com o motivo (skip_reason), como já acontece quando o envio
  # nem sai. Sem reenvio automático: o número que a Meta recusa agora seria
  # recusado de novo na hora seguinte — a equipe vê o motivo e decide.
  def reconcile_refused!
    leads = (state['selected'] || []).select { |l| l['sent_at'].present? && l['message_id'].present? }
    refused = Crm::SendTemplateService.refused(leads.pluck('message_id'))
    leads.each do |lead|
      next unless refused.key?(lead['message_id'])

      refuse_lead!(lead['contact_id'], refused[lead['message_id']])
      drop_harvest_label!(lead['contact_id'])
    end
  rescue StandardError => e
    Rails.logger.warn("[Colheitadeira] conferência das recusas conta=#{account.id}: #{e.message}")
  end

  # a etiqueta colheita_AAAA_MM sai junto (revisão da Rodada 3): quem nunca
  # recebeu a mensagem não pode ficar fora das próximas colheitas
  # (blocked_contact_ids) nem aparecer no CRM como colhido
  def drop_harvest_label!(contact_id)
    contact = account.contacts.find_by(id: contact_id)
    return if contact.nil? || contact.label_list.exclude?(harvest_label)

    contact.update!(label_list: contact.label_list - [harvest_label])
  rescue StandardError => e
    Rails.logger.warn("[Colheitadeira] etiqueta do recusado contato=#{contact_id}: #{e.message}")
  end

  def harvest_mode
    %w[organize send].include?(config['mode']) ? config['mode'] : 'organize'
  end

  def opportunity_label
    "oportunidade_#{month_key.tr('-', '_')}"
  end

  # ── RESULTADOS (tela) ─────────────────────────────────────────────────
  def results
    selected = state['selected'] || []
    sent = selected.select { |l| l['sent_at'].present? }
    conv_ids = sent.map { |l| l['conversation_id'] }.compact
    replied = 0
    if conv_ids.any?
      by_display = account.conversations.where(display_id: conv_ids).index_by(&:display_id)
      replied = sent.count do |l|
        conv = by_display[l['conversation_id']]
        conv && conv.messages.incoming.where('created_at > ?', l['sent_at']).exists?
      end
    end
    state.merge(
      'stats' => (state['stats'] || {}).merge(
        'sent' => sent.size, 'replied' => replied,
        'skipped' => selected.count { |l| l['skipped'] },
        'pending' => selected.count { |l| l['sent_at'].blank? && !l['skipped'] },
        # reservado sem conversa: o Sidekiq caiu entre a reserva e o envio (modo
        # 'send'); ninguém reenvia sozinho — o admin decide à mão
        'sem_conversa' => (harvest_mode == 'send' ? sent.count { |l| l['conversation_id'].blank? } : 0)
      )
    )
  end

  def state
    (ai_config || {})['harvest_state'] || {}
  end

  def month_key
    TZ.today.strftime('%Y-%m')
  end

  private

  def preview_size(requested_size)
    (requested_size || config_int('monthly_size', DEFAULT_MONTHLY)).clamp(10, 1000)
  end

  # grava a prévia nova: quem já tinha destino neste mês (kept) + os novos
  def save_preview!(kept, fresh, pool)
    write_state(
      'month_key' => month_key,
      'status' => 'preview',
      'generated_at' => Time.current.iso8601,
      'approved_at' => nil, 'approved_by' => nil,
      'selected' => kept + fresh,
      'stats' => { 'pool' => pool.size, 'scored_by_ai' => pool.count { |l| l['ai'] }, 'planned' => fresh.size,
                   'kept' => kept.size },
      'last_error' => nil
    )
  end

  # leads da colheita DESTE mês que já têm destino: reservados/enviados
  # (sent_at) ou pulados. Mês anterior não conta (a lista nova começa limpa).
  def decided_leads_this_month
    return [] unless state['month_key'] == month_key

    (state['selected'] || []).select { |l| l['sent_at'].present? || l['skipped'] }
  end

  # ── SELEÇÃO (SQL) ─────────────────────────────────────────────────────
  def candidate_pool(size, exclude_ids:)
    pipeline = account.crm_pipelines.order(:position).first
    return [] unless pipeline

    cold_days = config_int('cold_days', DEFAULT_COLD_DAYS).clamp(14, 365)
    stage_ids = Array(config['stage_ids']).map(&:to_i).select(&:positive?)
    scope = pipeline.crm_contacts.joins(:contact).includes(:contact, :stage)
    scope = if stage_ids.any?
              scope.where(stage_id: stage_ids)
            else
              # padrão: fora colunas de encerramento (cirurgia feita/pós/perda)
              closed = pipeline.stages.select { |s| s.name =~ /realizada|p[oó]s|perda/i }.map(&:id)
              closed.any? ? scope.where.not(stage_id: closed) : scope
            end

    scope = scope.where("contacts.phone_number IS NOT NULL AND contacts.phone_number <> ''")
                 .where('contacts.last_activity_at < ? OR contacts.last_activity_at IS NULL', cold_days.days.ago)

    blocked = blocked_contact_ids(exclude_ids)
    scope = scope.where.not(contact_id: blocked) if blocked.any?

    cap = [size * POOL_FACTOR, POOL_HARD_CAP].min
    cards = scope.order(Arel.sql('crm_contacts.value DESC NULLS LAST, contacts.last_activity_at DESC NULLS LAST'))
                 .limit(cap).to_a
    hydrate_pool(cards)
  end

  # quem pediu para não ser contatado, virou perda, ou já foi colhido há pouco
  # (+ extra: quem já tem destino na colheita deste mês — Rodada 6)
  def blocked_contact_ids(extra)
    # 🚦 + sinais de quem não quer receber com a chavinha "robôs param" ligada (16/10)
    optout_tags = ActsAsTaggableOn::Tag.where('name IN (?) OR name LIKE ?', ['nao_perturbe', *Crm::StopSignals.robot_stop_labels(account)], 'perda\\_%').ids
    recent_harvest_tags = ActsAsTaggableOn::Tag.where('name LIKE ?', 'colheita\\_%').ids

    ids = Crm::PartnerGuard.excluded_contact_ids(account) + extra.map(&:to_i) # 🚧 item 231 (cerca dos parceiros)
    if optout_tags.any?
      ids += ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', context: 'labels', tag_id: optout_tags)
                                      .pluck(:taggable_id)
    end
    if recent_harvest_tags.any?
      ids += ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', context: 'labels', tag_id: recent_harvest_tags)
                                      .where('created_at > ?', RE_HARVEST_MONTHS.months.ago)
                                      .pluck(:taggable_id)
    end
    ids.uniq
  end

  # última mensagem recebida + insight salvo, em 2 consultas p/ o pool todo
  def hydrate_pool(cards)
    contact_ids = cards.map(&:contact_id)

    last_incoming = Message.reorder(nil)
                           .where(message_type: :incoming)
                           .joins(:conversation)
                           .where(conversations: { contact_id: contact_ids })
                           .select('DISTINCT ON (conversations.contact_id) conversations.contact_id, messages.content')
                           .order('conversations.contact_id, messages.created_at DESC')
                           .to_a.index_by(&:contact_id)

    insights = account.conversations.where(contact_id: contact_ids)
                      .where("additional_attributes -> 'ai_insight' IS NOT NULL")
                      .pluck(:contact_id, Arel.sql("additional_attributes -> 'ai_insight' ->> 'level'"))
                      .to_h

    cards.map do |card|
      contact = card.contact
      cold = contact.last_activity_at ? ((Time.current - contact.last_activity_at) / 86_400).round : 999
      {
        'contact_id' => contact.id,
        'crm_contact_id' => card.id,
        'name' => contact.name.to_s.truncate(40),
        'phone' => contact.phone_number,
        'stage_name' => card.stage&.name,
        'procedure' => card.procedure_of_interest.presence,
        'value' => card.value.to_f,
        'cold_days' => cold,
        'insight_level' => insights[contact.id],
        'last_message' => last_incoming[contact.id]&.content.to_s.truncate(140),
        'score' => heuristic_score(card, cold),
        'hook' => nil, 'ai' => false,
        'sent_at' => nil, 'conversation_id' => nil, 'skipped' => false
      }
    end
  end

  # nota de reserva quando a IA não alcança o pool inteiro (teto de chamadas)
  def heuristic_score(card, cold)
    score = 30
    score += 25 if card.value.to_f.positive?
    score += 10 if card.procedure_of_interest.present?
    score += 10 if cold < 120
    score
  end

  # ── PONTUAÇÃO (IA em lotes) ───────────────────────────────────────────
  def score_pool(pool)
    batches = pool.each_slice(BATCH_SIZE).first(MAX_AI_BATCHES)
    batches.each do |batch|
      lines = batch.map do |l|
        extras = []
        extras << "interesse prévio: #{l['insight_level']}" if l['insight_level']
        extras << "última msg: \"#{l['last_message']}\"" if l['last_message'].present?
        "id=#{l['contact_id']} | etapa: #{l['stage_name']} | procedimento: #{l['procedure'] || '—'} | " \
          "orçamento: R$#{l['value'].to_i} | frio há #{l['cold_days']}d#{extras.any? ? ' | ' + extras.join(' | ') : ''}"
      end

      message = client.messages.create(
        model: model, max_tokens: 4096, system_: cached_system,
        output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
        messages: [{ role: 'user', content: "Avalie estes #{batch.size} leads frios:\n\n#{lines.join("\n")}" }]
      )
      record_usage(message)
      parsed = JSON.parse(message.content.find { |b| b.type == :text }&.text || '{}')
      Array(parsed['leads']).each do |row|
        lead = batch.find { |l| l['contact_id'] == row['id'].to_i }
        next unless lead

        lead['score'] = row['score'].to_i.clamp(0, 100)
        lead['hook'] = row['hook'].to_s.truncate(120)
        lead['ai'] = true
      end
    rescue StandardError => e
      Rails.logger.error("[Colheitadeira] lote de pontuação falhou conta=#{account.id}: #{e.message}")
    end
    pool
  end

  # ── ENVIO: fonte para o SendTemplateService ───────────────────────────
  HarvestSource = Struct.new(:account, :inbox, :sender, :template_params, :message_preview, :name) do
    def account_id
      account.id
    end

    def inbox_id
      inbox.id
    end
  end

  def build_source(inbox, lead)
    params = personalize_params(template_params, lead)
    HarvestSource.new(account, inbox, sender_user, params,
                      config['message_preview'].presence || 'Colheitadeira da Base',
                      "Colheita #{month_key}")
  end

  # [gancho] e [procedimento] nos valores das variáveis do modelo escolhido.
  # [nome] o LiquidTemplateProcessor já resolve via {{contact.first_name}}.
  def personalize_params(params, lead)
    deep = params.deep_dup
    body = deep.dig('processed_params', 'body') || {}
    body.transform_values! do |v|
      v.to_s
       .gsub(/\[gancho\]/i, lead['hook'].presence || fallback_hook(lead))
       .gsub(/\[procedimento\]/i, lead['procedure'].presence || 'sua consulta')
    end
    deep
  end

  def fallback_hook(lead)
    if lead['value'].to_f.positive?
      'seu orçamento continua guardado aqui com a gente'
    else
      'sua avaliação ficou pendente por aqui'
    end
  end

  def template_params
    config['template_params'].presence
  end

  def sending_inbox
    inbox = account.inboxes.find_by(id: config['inbox_id'])
    return nil unless inbox&.channel_type == 'Channel::Whatsapp'

    inbox
  end

  def sender_user
    account.administrators.first
  end

  def harvest_label
    "colheita_#{month_key.tr('-', '_')}"
  end

  # tarefa de aprovação para o admin (idempotente por MÊS — Rodada 6: antes a
  # trava era o título inteiro, que leva o número de leads; gerar a prévia de
  # novo com outro número abria uma 2ª tarefa). Se já existe a do mês, só
  # atualiza o número na tarefa que ainda está aberta.
  def create_approval_task(planned)
    return unless config_bool('require_approval', true)

    prefix = "🌾 Colheita de #{TZ.today.strftime('%B/%Y')} pronta"
    title = "#{prefix} — #{planned} leads aguardando sua aprovação"
    same_month = account.tasks.where('title LIKE ?', "#{ActiveRecord::Base.sanitize_sql_like(prefix)}%")
    if same_month.exists?
      same_month.where.not(status: :done).find_each { |task| task.update(title: title) }
      return
    end

    account.tasks.create!(
      title: title,
      description: "A Colheitadeira pontuou a base fria e separou os #{planned} leads mais propensos. " \
                   'Revise a prévia em Automações → Agentes → Colheitadeira e clique em Aprovar para começar os envios.',
      task_type: 'gestao', priority: :high, status: :todo,
      due_at: 3.days.from_now,
      creator: account.administrators.first
    )
  rescue StandardError => e
    Rails.logger.error("[Colheitadeira] tarefa de aprovação falhou conta=#{account.id}: #{e.message}")
  end

  # ── config/estado ─────────────────────────────────────────────────────
  def config
    agent_config || {}
  end

  def config_int(key, default)
    v = config[key].to_i
    v.positive? ? v : default
  end

  def config_bool(key, default)
    config.key?(key) ? config[key] == true : default
  end

  def write_state(new_state)
    settings = CrmSetting.find_by(account: account)
    settings.with_lock do
      ai = (settings.reload.ai_config || {}).deep_dup
      ai['harvest_state'] = new_state
      settings.update_column(:ai_config, ai) # rubocop:disable Rails/SkipsModelValidations
    end
    @ai_config = nil # força releitura do estado na próxima consulta
  end

  def merge_state(patch)
    settings = CrmSetting.find_by(account: account)
    settings.with_lock do
      ai = (settings.reload.ai_config || {}).deep_dup
      ai['harvest_state'] = (ai['harvest_state'] || {}).merge(patch)
      settings.update_column(:ai_config, ai) # rubocop:disable Rails/SkipsModelValidations
    end
    @ai_config = nil # força releitura do estado na próxima consulta
  end

  # ── marca POR LEAD, dentro da trava (achado #44) ──────────────────────
  # Altera UM lead do estado: relê o estado FRESCO dentro da trava da linha,
  # aplica o bloco e grava. Nunca grava a lista inteira de uma vez — a
  # alteração de uma rodada não apaga o que outra (ou o admin) acabou de
  # gravar. O bloco recebe o lead e o estado fresco da colheita (status etc.).
  # Devolve true se o lead existe na colheita.
  def update_lead!(contact_id)
    settings = CrmSetting.find_by(account: account)
    return false unless settings

    found = false
    settings.with_lock do
      ai = (settings.reload.ai_config || {}).deep_dup
      fresh_state = ai['harvest_state'] || {}
      lead = (fresh_state['selected'] || []).find { |l| l['contact_id'] == contact_id.to_i }
      next unless lead

      found = true
      yield lead, fresh_state
      settings.update_column(:ai_config, ai) # rubocop:disable Rails/SkipsModelValidations
    end
    @ai_config = nil # força releitura do estado na próxima consulta
    found
  end

  # Reserva o lead ANTES de enviar: se outra rodada já reservou (sent_at), o
  # admin pulou (skipped) ou clicou em "Pausar" enquanto este lote rodava,
  # devolve false e ninguém manda a mensagem. Mesmo desenho do claim do lembrete.
  def claim_lead!(contact_id)
    claimed = false
    update_lead!(contact_id) do |lead, fresh_state|
      next if fresh_state['status'] != 'approved' # pausou no meio do lote: o resto não sai
      next if lead['sent_at'].present? || lead['skipped']

      claimed = true
      lead['sent_at'] = Time.current.iso8601
    end
    claimed
  end

  # enviado: guarda a conversa e o id da mensagem (a rodada seguinte confere se a Meta recusou, #45)
  def mark_sent!(contact_id, conversation, message)
    update_lead!(contact_id) do |l|
      l['conversation_id'] = conversation.display_id
      l['message_id'] = message&.id
    end
  end

  # a Meta recusou a mensagem: sai de "enviado" e vira pulado com o motivo (#45)
  def refuse_lead!(contact_id, error)
    update_lead!(contact_id) do |l|
      l['sent_at'] = nil
      l['conversation_id'] = nil
      l['message_id'] = nil
      l['skipped'] = true
      l['skip_reason'] = "a Meta recusou: #{error.to_s.truncate(160)}"
    end
  end

  # Envio não saiu: devolve a reserva e marca o lead como pulado
  def release_lead!(contact_id)
    update_lead!(contact_id) do |lead|
      lead['sent_at'] = nil
      lead['conversation_id'] = nil
      lead['skipped'] = true
    end
  end
end
