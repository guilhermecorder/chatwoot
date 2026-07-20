# Ambiente PESSOAS (RH e desenvolvimento): cada pessoa vê o próprio
# espaço (DISC/temperamentos, objetivos e metas, histórico de feedbacks
# do Mentor); admin vê o time inteiro para combinar pessoas e montar
# times fortes. O DISC é respondido pela PRÓPRIA pessoa.
class Api::V1::Accounts::Crm::PeopleController < Api::V1::Accounts::BaseController
  def show
    users = visible_users
    profiles = Current.account.cevico_people_profiles.where(user_id: users.map(&:id)).index_by(&:user_id)
    feedbacks = Crm::WeeklyFeedback.where(account: Current.account, user_id: users.map(&:id))
                                   .order(week_start: :desc).limit(200).group_by(&:user_id)

    render json: {
      me: Current.user.id,
      admin: Current.account_user.administrator?,
      people: users.map { |u| person_json(u, profiles[u.id], feedbacks[u.id] || []) }
    }
  end

  # a própria pessoa grava o resultado do seu DISC (admin pode refazer o seu)
  def save_disc
    profile = own_profile
    scores = params.require(:scores).permit(:d, :i, :s, :c).to_h.transform_values(&:to_i)
    return render json: { error: 'Resultado inválido.' }, status: :unprocessable_entity if scores.values.sum.zero?

    profile.update!(disc: {
                      'scores' => scores,
                      'dominant' => scores.max_by { |_k, v| v }.first,
                      'taken_at' => Time.current.iso8601
                    })
    render json: { disc: profile.disc }
  end

  RETAKE_DAYS = 90

  # arquiva um teste (disc v2 / 4 temperamentos): histórico completo fica
  # em assessments; o mais recente de cada tipo vale como atual.
  # Item 81: guarda também as RESPOSTAS (autoconhecimento) e trava o
  # refazer em 90 dias (1x por trimestre; admin não trava).
  def save_assessment # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    profile = own_profile
    type = params[:kind].to_s
    return render json: { error: 'Tipo inválido.' }, status: :unprocessable_entity unless %w[disc temperamentos].include?(type)

    unless Current.account_user.administrator?
      last = last_taken_at(profile, type)
      if last && last > RETAKE_DAYS.days.ago
        liberado = (last + RETAKE_DAYS.days).strftime('%d/%m/%Y')
        return render json: { error: "Este teste pode ser refeito 1x a cada 3 meses — libera em #{liberado}." },
                      status: :unprocessable_entity
      end
    end

    scores = params.require(:scores).permit(:d, :i, :s, :c).to_h.transform_values(&:to_f)
    return render json: { error: 'Resultado inválido.' }, status: :unprocessable_entity if scores.values.sum.zero?

    entry = { 'kind' => type, 'scores' => scores,
              'ranking' => scores.sort_by { |_k, v| -v }.map(&:first),
              'answers' => sanitize_answers,
              'taken_at' => Time.current.iso8601 }
    # auditoria P4: lê→acrescenta→grava SOB TRAVA (o with_lock relê o
    # registro) — mesmo padrão anti-clobber do fix do follow-up
    profile.with_lock do
      profile.update!(assessments: (Array(profile.assessments) + [entry]).last(40))
      # compat: o DISC mais novo também atualiza o campo antigo (card do time)
      if type == 'disc'
        profile.update!(disc: { 'scores' => scores.transform_values(&:to_i),
                                'dominant' => entry['ranking'].first, 'taken_at' => entry['taken_at'] })
      end
    end
    render json: { assessments: profile.assessments, disc: profile.disc }
  end

  # espaço de VIDA (Roda da Vida, horizontes, hábitos) — só a própria pessoa
  def save_life # rubocop:disable Metrics/AbcSize
    profile = own_profile
    life = profile.life || {}
    life['wheel_history'] = sanitize_wheel if params.key?(:wheel)
    life['horizons'] = params.permit(horizons: {})[:horizons].to_h if params.key?(:horizons)
    life['habits'] = Array(params[:habits]).first(40).map { |h| h.permit!.to_h } if params.key?(:habits)
    profile.update!(life: life)
    render json: { life: profile.life }
  end

  # objetivos/metas: a pessoa edita os seus; admin edita de qualquer um
  def save_goals
    target_id = params[:user_id].presence&.to_i || Current.user.id
    if target_id != Current.user.id && !Current.account_user.administrator?
      return render json: { error: 'Você só edita os seus objetivos.' }, status: :forbidden
    end

    user = Current.account.users.find(target_id)
    profile = Current.account.cevico_people_profiles.find_or_create_by!(user: user)
    profile.update!(goals: sanitize_goals(params[:goals]))
    render json: { goals: profile.goals }
  end

  private

  def visible_users
    return Current.account.users.order(:name) if Current.account_user.administrator?

    [Current.user]
  end

  def own_profile
    Current.account.cevico_people_profiles.find_or_create_by!(user: Current.user)
  end

  # última vez que a pessoa fez o teste — inclui o DISC LEGADO (v1, salvo
  # só em profile.disc) para a trava de 90 dias valer também pra ele
  # (auditoria P3)
  def last_taken_at(profile, type)
    stamps = Array(profile.assessments).select { |a| a['kind'] == type }
                                       .filter_map { |a| safe_time(a['taken_at']) }
    stamps << safe_time(profile.disc&.dig('taken_at')) if type == 'disc'
    stamps.compact.max
  end

  def safe_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # respostas pergunta a pergunta (autoconhecimento): [{q, a, dim}]
  def sanitize_answers
    Array(params[:answers]).first(60).filter_map do |ans|
      q = ans[:q].to_s.strip
      next if q.blank?

      { 'q' => q[0, 300], 'a' => ans[:a].to_s.strip[0, 300], 'dim' => ans[:dim].to_s[0, 1] }
    end
  end

  GOAL_STATUSES = %w[andamento concluido pausado].freeze

  # objetivos: [{id, title, why, due_on, status, metas: [{text, done}], updates: [{at, text}]}]
  def sanitize_goals(goals) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    Array(goals).first(30).filter_map do |g|
      next if g[:title].blank?

      {
        'id' => g[:id].presence || SecureRandom.hex(4),
        'title' => g[:title].to_s[0, 200],
        'why' => g[:why].to_s[0, 500],
        'due_on' => g[:due_on].presence,
        'status' => GOAL_STATUSES.include?(g[:status]) ? g[:status] : 'andamento',
        'metas' => Array(g[:metas]).first(20).map { |m| { 'text' => m[:text].to_s[0, 200], 'done' => m[:done] == true || m[:done] == 'true' } },
        'updates' => Array(g[:updates]).last(30).map { |u| { 'at' => u[:at].to_s, 'text' => u[:text].to_s[0, 300] } }
      }
    end
  end

  # nova avaliação da Roda da Vida entra no HISTÓRICO (compara evolução)
  def sanitize_wheel
    profile = own_profile
    history = Array(profile.life&.dig('wheel_history'))
    scores = params.require(:wheel).permit!.to_h.transform_values { |v| v.to_f.clamp(0, 10) }
    history << { 'scores' => scores, 'note' => params[:wheel_note].to_s[0, 1000], 'at' => Time.current.iso8601 }
    history.last(24)
  end

  def person_json(user, profile, feedbacks) # rubocop:disable Metrics/CyclomaticComplexity
    {
      user_id: user.id,
      name: user.available_name,
      email: user.email,
      disc: profile&.disc || {},
      assessments: profile&.assessments || [],
      # vida é PRIVADA: só a própria pessoa recebe (nem admin vê)
      life: user.id == Current.user.id ? (profile&.life || {}) : nil,
      goals: profile&.goals || [],
      feedbacks: feedbacks.first(24).map do |f|
        { week_start: f.week_start, cadence: f.cadence, stats: f.stats, feedback: f.feedback }
      end
    }
  end
end
