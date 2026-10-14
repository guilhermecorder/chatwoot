# 🏥 FUNIL DO OFTALMOFÁCIL para CONSULTAS (item 300, 30/09). Até aqui o funil
# dos parceiros só recebia cirurgia (o sync do hub). Pedido do Guilherme: o
# paciente do Oftalmofácil que tem consulta marcada e recebe o lembrete de
# confirmação precisa ter o card "no CRM da Oftalmofácil" — nunca no da CEVICO.
#
# As colunas "Consulta Agendada" e "Consulta Confirmada" são achadas pelo NOME
# dentro do funil dos parceiros (agenda_config.oftalmofacil.partner_pipeline_id);
# se ainda não existem, nascem no começo do funil. Card deste funil NUNCA
# dispara automação (cerca dos parceiros, item 231) e nunca volta para trás.
#
# 🧭 item 341 (13/10, Ambientes do CRM): conversa nova na caixa do
# Oftalmofácil abre o card AQUI, na coluna "Novo Contato" (a primeira), e a
# "Cirurgia Realizada" passa a existir também neste funil (cirurgia realizada
# = paciente que passou por uma coluna com esse nome). As que já existem
# ficam onde estão; as que faltam nascem no lugar certo (ordem em STAGES).
#
# 🧩 item 344 (13/10 noite, PRÉ-DEFINIÇÃO): "veja quais colunas precisam haver
# no CRM para que fique tudo acertado… você pode construir inclusive uma pré
# definição, para agilizar e facilitar". O funil do parceiro espelha a jornada
# da CEVICO (sem "Envio de Orçamento": quem vende é o parceiro) — 11 colunas,
# cada uma com o seu PAPEL, para a cerca (CardRouter), o sync do hub, a
# confirmação e os indicadores acharem sempre a coluna equivalente. O nome é
# procurado SEM acento e sem maiúscula ("Cirúrgica" = "cirurgica").
module Crm::PartnerFunnel # rubocop:disable Metrics/ModuleLength
  module_function

  # ordem = ordem das colunas no funil; match = como achar a coluna pelo nome
  # (sem acento); not = o que NÃO pode estar no nome
  # (nomes de produção 13/10 também valem: "Novo paciente", "Cirurgia",
  # "2º Olho", "Consulta Pós Op", "Desmarcou a Consulta", "Retornos"). As
  # colunas por TIPO (Exame, Consulta, Lente Rígida, Intravítrea) não são
  # etapa: o tipo virou etiqueta + filtro no card (Crm::AppointmentKind)
  STAGES = {
    new: { name: 'Novo Contato', match: /novos? (contatos?|pacientes?)/, color: '#64748B' },
    booked: { name: 'Consulta Agendada', match: /consulta agendada|agendamento de consulta/, color: '#2563EB' },
    canceled: { name: 'Desmarcou a Consulta', match: /desmarc/, color: '#F97316' },
    confirmed: { name: 'Consulta Confirmada', match: /consulta confirmada/, color: '#16A34A' },
    missed: { name: 'Não Foi à Consulta', match: /nao foi/, color: '#DC2626' },
    consulted: { name: 'Consulta Realizada', match: /consulta realizada/, color: '#0891B2' },
    indicated: { name: 'Indicação de Cirurgia', match: /indicacao/, not: /sem indicacao/, color: '#D97706' },
    not_indicated: { name: 'Sem Indicação Cirúrgica', match: /sem indicacao/, color: '#94A3B8' },
    not_closed: { name: 'Não Fechou Ainda', match: /nao fechou/, color: '#F59E0B' },
    surgery: { name: 'Cirurgia Agendada', match: /cirurgia agendada|\Acirurgias?\z|olho/, color: '#7C3AED' },
    realized: { name: 'Cirurgia Realizada', match: /cirurgia realizada/, color: '#0D9488' },
    postop: { name: 'Pós Operatório', match: /pos.?op/, color: '#0F766E' },
    # 🧩 item 344: "ele tem algumas outras questões, como cirurgia realizada,
    # retorno, pós op" — Retorno é a última etapa (a coluna "Retornos" de
    # produção vira esta)
    retorno: { name: 'Retorno', match: /retorno/, color: '#16A34A' }
  }.freeze
  ORDER = STAGES.keys.freeze

  def pipeline(account)
    id = Crm::PartnerGuard.partner_pipeline_id(account)
    id && account.crm_pipelines.find_by(id: id)
  end

  # garante todas as colunas do funil (botão da pré-definição e rake de migração)
  def ensure_stages!(account)
    ORDER.filter_map { |key| stage!(account, key) }
  end

  # 🧩 item 344: botão da pré-definição — cria as que faltam e põe o funil na
  # ORDEM DA JORNADA; colunas que não são da jornada (ex.: "Exame", "Retornos")
  # vão para o fim, com os cards dentro (nada é apagado nem renomeado)
  def apply_preset!(account)
    funnel = pipeline(account)
    return nil if funnel.nil?

    ensure_stages!(account)
    journey = ORDER.filter_map { |key| find_stage(funnel, key) }
    rest = funnel.stages.order(:position).reject { |stage| journey.include?(stage) }
    Crm::Stage.transaction do
      (journey + rest).each_with_index { |stage, i| stage.update_columns(position: i) } # rubocop:disable Rails/SkipsModelValidations
    end
    funnel
  end

  def fold(text)
    I18n.transliterate(text.to_s).downcase.squish
  end

  # papel de uma coluna pelo nome (nil = não é nenhuma das colunas da jornada)
  def role_of(name)
    folded = fold(name)
    ORDER.detect do |key|
      spec = STAGES[key]
      folded.match?(spec[:match]) && !(spec[:not] && folded.match?(spec[:not]))
    end
  end

  # a coluna de um papel dentro de QUALQUER funil (a primeira pela posição)
  def find_stage(funnel, key)
    return nil if funnel.nil? || STAGES[key].nil?

    funnel.stages.order(:position).detect { |stage| role_of(stage.name) == key }
  end

  # PRÉ-DEFINIÇÃO: o que já existe e o que falta no funil (prévia da tela)
  def preset_preview(account)
    funnel = pipeline(account)
    return nil if funnel.nil?

    {
      pipeline_id: funnel.id, pipeline_name: funnel.name,
      columns: ORDER.map do |key|
        found = find_stage(funnel, key)
        { key: key, name: STAGES[key][:name], exists: found.present?, current_name: found&.name }
      end,
      extras: funnel.stages.order(:position).reject { |stage| role_of(stage.name) }.map(&:name),
      in_order: in_order?(funnel)
    }
  end

  # as colunas da jornada vêm primeiro e na ordem certa?
  def in_order?(funnel)
    stages = funnel.stages.order(:position).to_a
    journey = ORDER.filter_map { |key| find_stage(funnel, key) }
    stages.first(journey.size) == journey
  end

  # create: false (prévia do rake) devolve a coluna que NASCERIA, sem gravar
  def stage!(account, key, create: true)
    funnel = pipeline(account)
    spec = STAGES[key]
    return nil if funnel.nil? || spec.nil?

    found = find_stage(funnel, key)
    return found if found
    return funnel.stages.new(name: "#{spec[:name]} (nova)", color: spec[:color]) unless create

    create_stage(funnel, key)
  end

  # põe (ou anda) o card do paciente na coluna pedida; devolve o nome da
  # coluna quando mexeu, nil quando não precisou
  def place!(account, contact, key) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if contact.blank?

    stage = stage!(account, key)
    return nil if stage.nil?

    card = Crm::Contact.find_or_initialize_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
    return nil if card.persisted? && (card.stage_id == stage.id || card.stage&.position.to_i > stage.position.to_i)

    card.origin ||= 'oftalmofacil'
    card.stage_id = stage.id
    card.save!
    Crm::PartnerGuard.forget!(account)
    stage.name
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn "[Crm::PartnerFunnel] contato #{contact&.id}: #{e.message}"
    nil
  end

  # coluna nova entra logo DEPOIS da anterior que já existe na ordem
  # (Novo Contato → … → Cirurgia Realizada); sem nenhuma anterior, entra antes
  # da próxima que existe; funil vazio = no começo
  def create_stage(funnel, key) # rubocop:disable Metrics/AbcSize
    spec = STAGES[key]
    index = ORDER.index(key)
    before = ORDER[0...index].reverse.lazy.filter_map { |k| find_stage(funnel, k) }.first
    if before
      funnel.stages.where('position > ?', before.position).update_all('position = position + 1') # rubocop:disable Rails/SkipsModelValidations
      return funnel.stages.create!(name: spec[:name], color: spec[:color], position: before.position + 1)
    end

    after = ORDER[(index + 1)..].lazy.filter_map { |k| find_stage(funnel, k) }.first
    position = after ? after.position : funnel.stages.minimum(:position).to_i
    funnel.stages.where('position >= ?', position).update_all('position = position + 1') # rubocop:disable Rails/SkipsModelValidations
    funnel.stages.create!(name: spec[:name], color: spec[:color], position: position)
  end
end
