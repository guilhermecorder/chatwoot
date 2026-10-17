# 🟠 SUSPEITA DE BLOQUEIO (Saúde do WhatsApp, 16/10/2026)
#
# A Meta não conta quem bloqueou. O sinal que sobra: a mensagem nossa chega
# na Meta ("enviado") mas nunca no celular ("entregue"). Para não confundir
# com celular desligado por uma tarde, a pessoa só é marcada quando TODAS as
# travas abaixo valem, POR NÚMERO (bloqueio é por número — quem bloqueou a
# caixa 2 continua recebendo pela caixa 5):
#
#   1. as últimas N mensagens nossas por esse número (padrão 2) ficaram só
#      em "enviado" — falhas e mensagens que nem chegaram na Meta (sem id da
#      Meta) não contam, nem as enviadas pelo celular (eco do app);
#   2. a mais antiga delas tem mais de H horas (padrão 48);
#   3. a pessoa JÁ RECEBEU antes por esse número (entregue ou lida, nos
#      últimos 60 dias) — quem nunca recebeu não "bloqueou", nunca chegou;
#   4. ela não escreveu para a clínica (em nenhum número) depois disso;
#   5. o número estava entregando para os outros na mesma época (pelo menos
#      3 entregues nas H horas seguintes) — se a caixa caiu, ninguém é marcado.
#
# Sai sozinha quando volta a entregar ou a pessoa escreve (ganchos em
# Crm::StopSignals; a varredura confere de novo). Quem tirou à mão não volta
# pelo MESMO sinal.
class Crm::BlockSuspicionScan
  KEY = 'suspeita_bloqueio'.freeze
  WINDOW = 60.days
  HEALTH_MIN_DELIVERED = 3

  attr_reader :account, :result

  def initialize(account, now: Time.current, dry_run: false)
    @account = account
    @now = now
    @dry_run = dry_run
    cfg = Crm::StopSignals.settings(account)
    @hours = cfg['horas']
    @stuck_min = cfg['presas']
    @result = { marcados: 0, mantidos: 0, tirados: 0, suspeitos: 0, horas: @hours, presas: @stuck_min }
  end

  def call
    inbox_ids = account.inboxes.where(channel_type: 'Channel::Whatsapp').pluck(:id)
    return result if inbox_ids.empty?

    by_contact = suspects(inbox_ids).group_by { |r| r['contact_id'].to_i }
    result[:suspeitos] = by_contact.size
    mark_all(by_contact)
    release_cleared(by_contact.keys)
    result
  end

  # linhas (contato × número) que passam nas 5 travas
  def suspects(inbox_ids)
    ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([suspects_sql, sql_binds(inbox_ids)])).to_a
  end

  private

  def sql_binds(inbox_ids)
    { account_id: account.id, inbox_ids: inbox_ids, since: @now - WINDOW, cutoff: @now - @hours.hours,
      stuck_min: @stuck_min, health_window: "#{@hours} hours", health_min: HEALTH_MIN_DELIVERED,
      quiet: Crm::OptOut::LABEL }
  end

  def suspects_sql # rubocop:disable Metrics/MethodLength
    <<~SQL.squish
      WITH o AS (
        SELECT m.id, m.inbox_id, c.contact_id, m.status, m.created_at,
               row_number() OVER (PARTITION BY c.contact_id, m.inbox_id ORDER BY m.created_at DESC, m.id DESC) AS rn
        FROM messages m
        JOIN conversations c ON c.id = m.conversation_id
        WHERE m.account_id = :account_id AND m.inbox_id IN (:inbox_ids)
          AND m.message_type = 1 AND m.private = false AND m.status <> 3
          AND m.source_id IS NOT NULL AND m.created_at >= :since
          AND COALESCE(m.content_attributes::text, '') NOT LIKE '%external_echo%'
      ),
      tail AS (
        SELECT contact_id, inbox_id, MIN(rn) FILTER (WHERE status IN (1, 2)) AS ok_rn
        FROM o GROUP BY contact_id, inbox_id
      ),
      cand AS (
        SELECT t.contact_id, t.inbox_id, t.ok_rn - 1 AS stuck,
               first_stuck.id AS first_stuck_id, first_stuck.created_at AS stuck_since,
               last_stuck.id AS last_stuck_id, last_ok.id AS last_ok_id
        FROM tail t
        JOIN o first_stuck ON first_stuck.contact_id = t.contact_id AND first_stuck.inbox_id = t.inbox_id AND first_stuck.rn = t.ok_rn - 1
        JOIN o last_stuck ON last_stuck.contact_id = t.contact_id AND last_stuck.inbox_id = t.inbox_id AND last_stuck.rn = 1
        JOIN o last_ok ON last_ok.contact_id = t.contact_id AND last_ok.inbox_id = t.inbox_id AND last_ok.rn = t.ok_rn
        WHERE t.ok_rn IS NOT NULL AND t.ok_rn - 1 >= :stuck_min AND first_stuck.created_at < :cutoff
      )
      SELECT cand.* FROM cand
      WHERE NOT EXISTS (
          SELECT 1 FROM messages mi JOIN conversations ci ON ci.id = mi.conversation_id
          WHERE ci.contact_id = cand.contact_id AND mi.account_id = :account_id
            AND mi.message_type = 0 AND mi.created_at > cand.stuck_since
        )
        AND NOT EXISTS (
          SELECT 1 FROM taggings tg JOIN tags tt ON tt.id = tg.tag_id
          WHERE tg.taggable_type = 'Contact' AND tg.context = 'labels' AND tg.taggable_id = cand.contact_id AND tt.name = :quiet
        )
        AND (
          SELECT COUNT(*) FROM (
            SELECT 1 FROM messages mx
            WHERE mx.inbox_id = cand.inbox_id AND mx.message_type = 1 AND mx.status IN (1, 2)
              AND mx.created_at BETWEEN cand.stuck_since AND cand.stuck_since + CAST(:health_window AS interval)
            LIMIT :health_min
          ) ok
        ) >= :health_min
    SQL
  end

  def mark_all(by_contact)
    contacts = account.contacts.where(id: by_contact.keys).index_by(&:id)
    messages = Message.where(id: by_contact.values.flatten.flat_map { |r| [r['first_stuck_id'], r['last_stuck_id'], r['last_ok_id']] })
                      .includes(:conversation).index_by(&:id)
    by_contact.each do |contact_id, rows|
      contact = contacts[contact_id]
      next if contact.nil?

      mark_one(contact, rows, messages)
    end
  end

  def mark_one(contact, rows, messages)
    caixas = rows.sort_by { |r| r['stuck_since'].to_s }.map { |r| caixa_proof(r, messages) }
    since = caixas.map { |c| c['desde'] }.min
    newest = caixas.max_by { |c| c['desde'].to_s }
    proof = { 'desde' => since, 'presas' => caixas.sum { |c| c['presas'] }, 'caixas' => caixas,
              'inbox_id' => newest['inbox_id'], 'ultima_entregue' => newest['ultima_entregue'],
              'primeira_presa' => newest['primeira_presa'], 'regra' => "#{@stuck_min}+ presas há #{@hours}h+" }
    if @dry_run
      result[:marcados] += 1 unless contact.label_list.include?(KEY)
      return
    end

    conversation = messages[newest.dig('primeira_presa', 'id')]&.conversation
    fresh = Crm::StopSignals.mark!(contact, KEY, proof, conversation: conversation, since: since)
    fresh ? result[:marcados] += 1 : result[:mantidos] += 1
  end

  def caixa_proof(row, messages)
    { 'inbox_id' => row['inbox_id'].to_i, 'presas' => row['stuck'].to_i,
      'desde' => Time.zone.parse(row['stuck_since'].to_s).iso8601,
      'primeira_presa' => Crm::StopSignals.message_summary(messages[row['first_stuck_id'].to_i]),
      'ultima_presa' => Crm::StopSignals.message_summary(messages[row['last_stuck_id'].to_i]),
      'ultima_entregue' => Crm::StopSignals.message_summary(messages[row['last_ok_id'].to_i]) }.compact
  end

  # quem está marcado e deixou de ser suspeito por um motivo CLARO (escreveu
  # ou voltou a receber) perde a marcação; sem contra-prova, fica
  def release_cleared(still_suspect_ids)
    marked = account.contacts.tagged_with(KEY).where.not(id: still_suspect_ids)
    marked.find_each do |contact|
      reason = clear_reason(contact)
      next if reason.nil?

      result[:tirados] += 1
      Crm::StopSignals.unmark!(contact, KEY, motivo: reason) unless @dry_run
    end
  end

  def clear_reason(contact)
    proof = Crm::StopSignals.evidence(contact)[KEY] || {}
    since = Time.zone.parse(proof['desde'].to_s) rescue nil # rubocop:disable Style/RescueModifier
    return 'sem registro do motivo (marcação antiga)' if since.nil?

    scope = Message.joins(:conversation).where(conversations: { contact_id: contact.id }).where('messages.created_at > ?', since)
    return 'o paciente escreveu para a clínica' if scope.exists?(message_type: :incoming)

    inbox_ids = Array(proof['caixas']).map { |c| c['inbox_id'] }.compact.presence || [proof['inbox_id']].compact
    delivered = scope.where(message_type: :outgoing, private: false, status: %i[delivered read])
    delivered = delivered.where(inbox_id: inbox_ids) if inbox_ids.any?
    delivered.exists? ? 'voltou a receber (mensagem entregue)' : nil
  end
end
