# 🗂️ COLEÇÃO DE INSIGHTS das Páginas (item 329, 05/10 — "um ambiente com
# coleta de insights"). O que a equipe decidiu guardar para melhorar uma
# página: veio de um diagnóstico automático, de uma sugestão da IA ou foi
# escrito à mão. Cada insight anda por três situações:
#
#   todo       a fazer
#   done       aplicado na página (guarda a data — é dela que sai o antes × depois)
#   dismissed  descartado
#
# ANTES × DEPOIS: para insight aplicado numa página, compara a taxa de clique
# no WhatsApp e os leads dos dias DEPOIS da mudança com o mesmo número de dias
# ANTES dela (no máximo 30). Com pouca visita o resultado vem marcado como
# "ainda cedo" — não dá para concluir.
#
# Mora em crm_settings.agenda_config['page_insights'] (sem tabela nova), no
# máximo MAX itens, gravado sob trava relendo a config fresca.
class Cevico::InsightLog
  KEY = 'page_insights'.freeze
  MAX = 200
  STATUSES = %w[todo done dismissed].freeze
  ORIGINS = %w[auto ia manual].freeze
  WINDOW = 30
  ENOUGH_VIEWS = 30

  def initialize(account)
    @account = account
  end

  def list
    entries.map { |entry| entry.merge('result' => result_for(entry)) }
  end

  # cria (sem id) ou atualiza (com id). Devolve a lista nova.
  def save!(attrs, user:)
    write do |all|
      entry = all.find { |e| e['id'] == attrs[:id].to_s } if attrs[:id].present?
      if entry
        update_entry(entry, attrs)
      else
        all.unshift(new_entry(attrs, user))
      end
      all.first(MAX)
    end
  end

  def remove!(id)
    write { |all| all.reject { |e| e['id'] == id.to_s } }
  end

  private

  def settings
    @settings ||= CrmSetting.find_or_create_by!(account: @account)
  end

  def entries
    Array((settings.agenda_config || {})[KEY])
  end

  def write
    settings.with_lock do
      config = settings.reload.agenda_config || {}
      settings.update!(agenda_config: config.merge(KEY => yield(Array(config[KEY]).map(&:dup))))
    end
    list
  end

  def new_entry(attrs, user) # rubocop:disable Metrics/AbcSize
    status = clean_status(attrs[:status]) || 'todo'
    { 'id' => SecureRandom.hex(5), 'key' => attrs[:key].to_s.presence, 'page_id' => attrs[:page_id].presence&.to_i,
      'title' => attrs[:title].to_s.strip[0, 160], 'text' => attrs[:text].to_s.strip[0, 2000],
      'origin' => ORIGINS.include?(attrs[:origin].to_s) ? attrs[:origin].to_s : 'manual',
      'status' => status, 'applied_at' => (Date.current.iso8601 if status == 'done'),
      'created_at' => Time.current.iso8601, 'created_by' => user&.name.to_s }.compact
  end

  def update_entry(entry, attrs)
    entry['title'] = attrs[:title].to_s.strip[0, 160] if attrs[:title].present?
    entry['text'] = attrs[:text].to_s.strip[0, 2000] if attrs.key?(:text)
    status = clean_status(attrs[:status])
    return if status.nil? || status == entry['status']

    entry['status'] = status
    entry['applied_at'] = status == 'done' ? Date.current.iso8601 : nil
  end

  def clean_status(value)
    STATUSES.include?(value.to_s) ? value.to_s : nil
  end

  # ── antes × depois ────────────────────────────────────────────────────
  def result_for(entry)
    applied = parse_date(entry['applied_at'])
    return nil if entry['status'] != 'done' || applied.nil? || entry['page_id'].blank?

    days = ((Date.current - applied).to_i + 1).clamp(1, WINDOW)
    after = window(entry['page_id'], applied, applied + days - 1)
    before = window(entry['page_id'], applied - days, applied - 1)
    { 'days' => days, 'before' => before, 'after' => after,
      'early' => after['views'] < ENOUGH_VIEWS || before['views'] < ENOUGH_VIEWS }
  end

  def window(page_id, from, to)
    views, clicks = @account.cevico_page_traffic.where(cevico_page_id: page_id, date: from..to)
                            .pick(Arel.sql('COALESCE(SUM(views), 0)'), Arel.sql('COALESCE(SUM(cta_clicks), 0)'))
    { 'views' => views.to_i, 'cta' => clicks.to_i, 'click_rate' => rate(clicks, views), 'leads' => leads_between(page_id, from, to) }
  end

  def leads_between(page_id, from, to)
    @account.contacts
            .where("(additional_attributes -> 'page_ads' ->> 'page_id') = ?", page_id.to_s)
            .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz BETWEEN ? AND ?", from.beginning_of_day, to.end_of_day)
            .count
  end

  def rate(part, total)
    total.to_i.positive? ? (part.to_f / total.to_i * 100).round(1) : 0.0
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
