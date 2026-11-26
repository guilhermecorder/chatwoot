# 🚪 ACESSO DE TERCEIROS (item 420, 26/11 — ele: "conceder acesso a um terceiro,
# extremamente limitado… uma nova categoria… um ambiente novo e separado, que
# compartilha a estrutura tecnológica da agenda, mas contabiliza de forma
# totalmente isolada e não polui nada no Meu Painel").
#
# Terceiro = um LOGIN de fora da equipe (ex.: a secretária particular de um
# médico) que entra no sistema e enxerga UMA coisa só. Não é administrador
# nem atendente: é uma categoria à parte, fechada por padrão.
#
#   · o login é um usuário comum do sistema (papel "agente" no Chatwoot), mas
#     MARCADO aqui — e quem está marcado perde tudo: nenhuma porta do sistema
#     abre para ele, a não ser as do seu portal (Crm::AccessControl barra no
#     servidor, a tela nem desenha o menu);
#   · cada TIPO de portal (KINDS) diz quais portas abre. Hoje existe um:
#     'agenda_medico' = a agenda particular de UM médico. Um tipo novo no
#     futuro (ex.: laboratório parceiro vendo só os exames dele) é uma linha
#     em KINDS + a porta dele — a trava, a entrada e a tela de Acessos já
#     servem.
#
# Onde fica gravado (sem migration): crm_settings.agent_permissions['terceiros']
#   { '<user_id>' => { 'kind' => 'agenda_medico', 'label' => 'Secretária da Dra. Roberta',
#                      'doctor' => 'Dra. Roberta Negri', 'active' => true,
#                      'windows' => [{ 'dow' => 2, 'start' => '13:00', 'end' => '14:00',
#                                      'unit' => 'paulista', 'block' => 15 }],
#                      'created_at' => '…', 'created_by' => 12 } }
#
# Regras que não mudam:
#   · administrador NUNCA é terceiro (a marcação é ignorada para admin);
#   · acesso ENCERRADO ('active' => false) continua marcado: a pessoa segue
#     sem ver nada do sistema — e também não abre mais o portal.
class Cevico::ThirdParty
  STORE_KEY = 'terceiros'.freeze

  # tipo de portal → nome para a tela + as portas (controller sem o prefixo
  # api/v1/accounts/) que ele abre. NADA fora desta lista abre para o terceiro.
  KINDS = {
    'agenda_medico' => {
      'label' => 'Agenda particular de um médico',
      'hint' => 'vê e marca só as consultas particulares do médico escolhido, nos horários liberados',
      'controllers' => %w[crm/portal]
    }
  }.freeze

  # portas que TODO terceiro (ativo ou encerrado) pode chamar: só o próprio
  # portal responde "quem sou eu / acesso encerrado" por ali
  ALWAYS_OPEN = { 'crm/portal' => %w[me] }.freeze

  WINDOW_LIMIT = 30
  BLOCK_RANGE = (5..120)

  attr_reader :account, :user_id, :raw

  # ── leitura ────────────────────────────────────────────────────────────
  def self.store(account, perms: nil)
    perms ||= Cevico::Access.perms_for(account)
    (perms[STORE_KEY] || {}).to_h
  end

  # a marcação desta pessoa (nil = não é terceiro). Admin nunca é terceiro.
  def self.for(account, user, account_user: nil, perms: nil)
    return nil if account.nil? || user.nil?

    raw = store(account, perms: perms)[user.id.to_s]
    return nil unless raw.is_a?(Hash)

    account_user ||= account.account_users.find_by(user_id: user.id)
    return nil if account_user.nil? || account_user.administrator?

    new(account, user.id, raw)
  end

  def self.third_party?(account, user, account_user: nil)
    !self.for(account, user, account_user: account_user).nil?
  end

  def self.all(account)
    store(account).filter_map { |uid, raw| new(account, uid, raw) if raw.is_a?(Hash) }
  end

  def self.user_ids(account)
    store(account).keys.map(&:to_i)
  end

  # a EQUIPE de verdade: os logins da conta sem os terceiros. Listas de
  # atendentes (quem responde, quem recebe tarefa, desempenho da equipe) usam
  # isto para o terceiro não aparecer no meio do time.
  def self.team(account, scope = nil)
    scope ||= account.users
    ids = user_ids(account)
    ids.empty? ? scope : scope.where.not(users: { id: ids })
  end

  def initialize(account, user_id, raw)
    @account = account
    @user_id = user_id.to_i
    @raw = raw.to_h
  end

  def kind = raw['kind'].to_s
  def kind_spec = KINDS[kind] || {}
  def label = raw['label'].to_s
  def doctor = raw['doctor'].to_s
  def active? = raw['active'] != false && KINDS.key?(kind)
  def windows = Array(raw['windows']).select { |w| w.is_a?(Hash) }

  # esta porta abre para este terceiro?
  def allows?(controller_path, action_name)
    path = controller_path.to_s.delete_prefix('api/v1/accounts/')
    return true if Array(ALWAYS_OPEN[path]).include?(action_name.to_s)

    active? && Array(kind_spec['controllers']).include?(path)
  end

  # o que a TELA precisa saber logo na entrada (vai no perfil do usuário)
  def public_json
    { kind: kind, label: label, doctor: doctor, active: active? }
  end

  # ── gravação (só administrador chama; a trava é no controller) ─────────
  # Grava/atualiza a marcação de UMA pessoa sob a trava da linha (nenhuma
  # outra gravação de acessos se perde). Devolve a marcação gravada.
  def self.save!(account, user_id, attrs, by: nil)
    uid = user_id.to_s
    saved = nil
    Cevico::SettingMerge.merge!(account, :agent_permissions) do |perms|
      all = (perms[STORE_KEY] || {}).to_h
      current = all[uid].is_a?(Hash) ? all[uid] : { 'created_at' => Time.current.iso8601, 'created_by' => by&.id }
      saved = current.merge(sanitize(account, attrs, current))
      all[uid] = saved
      perms[STORE_KEY] = all
      perms
    end
    new(account, uid, saved)
  end

  # tira a marcação (a pessoa volta a ser um atendente comum) — uso raro,
  # só para desfazer um engano; encerrar um acesso é 'active' => false
  def self.unmark!(account, user_id)
    Cevico::SettingMerge.merge!(account, :agent_permissions) do |perms|
      all = (perms[STORE_KEY] || {}).to_h
      all.delete(user_id.to_s)
      perms[STORE_KEY] = all
      perms
    end
  end

  # "último acesso" (o portal carimba no máximo a cada 15 minutos)
  def self.touch!(account, user_id)
    uid = user_id.to_s
    Cevico::SettingMerge.merge!(account, :agent_permissions) do |perms|
      all = (perms[STORE_KEY] || {}).to_h
      all[uid] = all[uid].merge('last_seen_at' => Time.current.iso8601) if all[uid].is_a?(Hash)
      perms[STORE_KEY] = all
      perms
    end
  end

  def self.sanitize(account, attrs, current) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    attrs = attrs.to_h.transform_keys(&:to_s)
    out = {}
    out['kind'] = KINDS.key?(attrs['kind'].to_s) ? attrs['kind'].to_s : (current['kind'].presence || KINDS.keys.first)
    out['label'] = attrs['label'].to_s.strip[0, 80] if attrs.key?('label')
    out['doctor'] = attrs['doctor'].to_s.strip[0, 80] if attrs.key?('doctor')
    out['active'] = ActiveModel::Type::Boolean.new.cast(attrs['active']) != false if attrs.key?('active')
    out['windows'] = sanitize_windows(account, attrs['windows']) if attrs.key?('windows')
    out
  end

  # faixas liberadas: dia da semana (0 dom … 6 sáb), das/até (HH:MM), unidade
  # da empresa e o intervalo entre horários. Linha torta é descartada.
  def self.sanitize_windows(account, list)
    # unidade física da empresa ('online' é teleconsulta: não entra)
    units = (Cevico::Company.for(account).unit_keys.presence || Crm::AgendaSlots::UNIT_LABELS.keys) - ['online']
    Array(list).first(WINDOW_LIMIT).filter_map do |win|
      win = win.respond_to?(:to_unsafe_h) ? win.to_unsafe_h : win.to_h
      sanitize_window(win.transform_keys(&:to_s), units)
    end
  end

  def self.sanitize_window(win, units) # rubocop:disable Metrics/CyclomaticComplexity
    start = hhmm(win['start'])
    finish = hhmm(win['end'])
    dow = Integer(win['dow'].to_s, exception: false)
    return nil if start.nil? || finish.nil? || start >= finish
    return nil if dow.nil? || (0..6).exclude?(dow) || units.exclude?(win['unit'].to_s)

    block = win['block'].to_i
    { 'dow' => dow, 'start' => start, 'end' => finish, 'unit' => win['unit'].to_s,
      'block' => BLOCK_RANGE.cover?(block) ? block : 15 }
  end

  def self.hhmm(value)
    match = value.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)
    return nil unless match && match[1].to_i < 24 && match[2].to_i < 60

    format('%<h>02d:%<m>02d', h: match[1].to_i, m: match[2].to_i)
  end
end
