# 🎂 ANIVERSÁRIOS DA EQUIPE (item 331, 06/10 — pedido dele: "crie uma
# notificação para todos os agentes adicionarem suas datas de aniversário…
# quando for aniversário, avisar o Meu Painel de todos, no topo, com
# 'aniversariante do dia' e também 'aniversariantes do mês'").
#
# Cada pessoa informa o próprio dia e mês (ano é opcional) no Meu Painel; quem
# ainda não informou vê o convite no topo até preencher. Admin pode informar
# por alguém. Mora em crm_settings.agenda_config['birthdays'] =
# { "<user_id>" => { "day" => 6, "month" => 10, "year" => 1990 | nil } } —
# sem tabela nova, gravado sob trava relendo a config fresca.
class Crm::Birthdays
  KEY = 'birthdays'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def initialize(account)
    @account = account
  end

  # o que o Meu Painel mostra para esta pessoa
  def payload(user, admin: false)
    today = TZ.today
    mine = entries[user.id.to_s]
    { mine: mine, today: on_day(today), month: in_month(today), missing: admin ? missing_names : missing_names.size,
      people: (admin ? people.map { |u| { id: u.id, name: u.name } } : []) }
  end

  # grava dia/mês (ano opcional) de uma pessoa; dia inválido levanta ArgumentError
  def set!(user_id, day:, month:, year: nil)
    day = day.to_i
    month = month.to_i
    year = year.presence&.to_i
    Date.new(year || 2000, month, day) # valida (29/02 sem ano passa)
    raise ArgumentError, 'ano fora do razoável' if year && !year.between?(1920, TZ.today.year)

    write { |all| all.merge(user_id.to_s => { 'day' => day, 'month' => month, 'year' => year }.compact) }
  end

  def clear!(user_id)
    write { |all| all.except(user_id.to_s) }
  end

  # [{ user_id, name, day, month, age }] de quem faz aniversário nesta data
  def on_day(date)
    list.select { |e| e[:day] == date.day && e[:month] == date.month }
  end

  # os do mês, em ordem de dia
  def in_month(date)
    list.select { |e| e[:month] == date.month }.sort_by { |e| e[:day] }
  end

  def missing_names
    people.reject { |u| entries.key?(u.id.to_s) }.map(&:name).sort
  end

  private

  def settings
    @settings ||= CrmSetting.find_or_create_by!(account: @account)
  end

  def entries
    (settings.agenda_config || {})[KEY] || {}
  end

  def people
    @people ||= @account.users.order(:name).to_a
  end

  def list
    by_id = people.index_by { |u| u.id.to_s }
    entries.filter_map do |user_id, e|
      user = by_id[user_id]
      next if user.nil?

      age = e['year'].present? ? TZ.today.year - e['year'].to_i : nil
      { user_id: user.id, name: user.name, day: e['day'].to_i, month: e['month'].to_i, age: age }
    end
  end

  def write
    settings.with_lock do
      config = settings.reload.agenda_config || {}
      settings.update!(agenda_config: config.merge(KEY => yield((config[KEY] || {}).dup)))
    end
    entries
  end
end
