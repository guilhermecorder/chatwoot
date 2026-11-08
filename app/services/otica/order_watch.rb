# 👓📦 VIGIA DOS PEDIDOS (08/11/2026): "demora mais ou menos uma semana para
# concluir o óculos… esse status a gente precisa monitorar de forma meio
# automática". Todo dia de manhã (Otica::OrderWatchJob, 8h) o vigia olha as
# O.S. abertas de cada loja e abre TAREFA para a equipe (Meu Painel) quando:
#   1. o laboratório passou da previsão e a lente não chegou   → "cobrar o laboratório"
#   2. a O.S. passou do prazo prometido e ainda não ficou pronta → "avisar o cliente / acertar prazo"
#   3. a O.S. está aberta há 2 dias e ninguém pediu ao laboratório → "pedir as lentes"
#   4. o óculos está pronto há 3 dias e o cliente não retirou     → "chamar o cliente"
# Uma tarefa por O.S. e por motivo enquanto estiver aberta (sem repetir todo
# dia). As mudanças de etapa continuam sendo da Val, na tela Produção (lente
# chegou → pronta → entregue); a Jornada "óculos pronto" e o card no CRM já
# acompanham cada etapa (Otica::CrmBridge). A Val virtual lê o resumo do pedido
# (summary_for) para responder "já ficou pronto?" pelo WhatsApp.
class Otica::OrderWatch
  TASK_TYPE = 'otica_pedido'.freeze
  OPEN_WITHOUT_LAB_DAYS = 2
  READY_WAITING_DAYS = 3

  def self.run_all!
    Account.find_each.sum { |account| Crm::AgendaSlots.otica?(account) ? new(account).run! : 0 }
  end

  # texto curto para o contexto da Val virtual (pós-compra): o pedido aberto
  # mais recente do cliente, ou o último entregue
  def self.summary_for(contact)
    return 'nenhum pedido encontrado no cadastro (pergunte o nome e o número da O.S., ou passe para a equipe)' if contact.nil?

    orders = Otica::Order.where(account_id: contact.account_id, contact_id: contact.id).includes(:lab_orders)
    order = orders.where(status: Otica::Order::OPEN_STATUSES).order(:sold_on, :id).last || orders.order(:sold_on, :id).last
    return 'nenhum pedido encontrado no cadastro (pergunte o nome e o número da O.S., ou passe para a equipe)' if order.nil?

    new(order.account).describe(order)
  end

  def initialize(account)
    @account = account
    @today = Otica.today
  end

  # devolve quantas tarefas abriu
  def run!
    opened = 0
    @account.otica_orders.open_orders.includes(:lab_orders, :contact, :seller).find_each do |order|
      checks(order).each do |kind, title, detail|
        opened += 1 if open_task!(order, kind, title, detail)
      end
    end
    opened
  end

  # [kind, título, detalhe] de cada alerta desta O.S.
  def checks(order) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    list = []
    late_labs = order.lab_orders.select { |l| l.late?(@today) }
    if late_labs.any?
      lab = late_labs.first
      list << ['lab_atrasado', "Laboratório atrasado: #{order.label}",
               "#{lab.supplier&.name || 'laboratório'} prometeu para #{fmt(lab.expected_on)} e a lente não chegou. Cobrar e, se mudar, " \
               'avisar o cliente pelo WhatsApp.']
    end
    if order.late?(@today) && order.status != 'pronta'
      list << ['prazo_estourado', "Passou do prazo prometido: #{order.label}",
               "Prometido para #{fmt(order.due_on)} e ainda #{Otica::Order::STATUSES[order.status].downcase}. Acertar o prazo e avisar o cliente."]
    end
    live_labs = order.lab_orders.reject { |l| l.status == 'cancelado' }
    if order.status == 'aberta' && live_labs.empty? && order.sold_on <= @today - OPEN_WITHOUT_LAB_DAYS && order.items.any?
      list << ['sem_laboratorio', "Pedir as lentes ao laboratório: #{order.label}",
               "Venda de #{fmt(order.sold_on)} sem pedido ao laboratório há #{(@today - order.sold_on).to_i} dias."]
    end
    days = order.days_ready(@today)
    if days && days >= READY_WAITING_DAYS
      list << ['pronto_sem_retirada', "Óculos pronto há #{days} dias sem retirada: #{order.label}",
               'Chamar o cliente pelo WhatsApp e combinar a retirada (a Val virtual pode marcar o horário).']
    end
    list
  end

  # resumo em palavras simples (vai ao prompt da Val virtual)
  def describe(order) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    parts = ["#{order.label} de #{fmt(order.sold_on)}: #{stage_text(order)}"]
    live = order.lab_orders.reject { |l| l.status == 'cancelado' }
    if order.open? && live.any?
      pending = live.reject { |l| l.status == 'recebido' }
      if pending.any?
        lab = pending.first
        parts << "lentes no laboratório#{" (#{lab.supplier.name})" if lab.supplier}, previsão de chegada #{fmt(lab.expected_on) || 'a confirmar'}" \
                 "#{' (ATRASADA)' if lab.late?(@today)}"
      else
        parts << 'lentes já chegaram do laboratório'
      end
    end
    parts << "prazo prometido ao cliente: #{fmt(order.due_on)}#{' (PASSOU)' if order.late?(@today) && order.status != 'pronta'}" if order.open? && order.due_on
    parts << "pronto para retirar desde #{fmt(order.ready_at)}" if order.status == 'pronta' && order.ready_at
    parts << "retirado em #{fmt(order.delivered_at)}" if order.status == 'entregue' && order.delivered_at
    parts << "valor R$ #{format('%.2f', order.net.to_f).tr('.', ',')}#{" · falta pagar R$ #{format('%.2f', order.balance).tr('.', ',')}" if order.balance.positive?}"
    parts.join(' · ')
  end

  private

  def stage_text(order)
    case order.status
    when 'aberta' then 'venda registrada, lentes ainda não pedidas ao laboratório'
    when 'em_producao' then 'em produção'
    when 'pronta' then 'PRONTO para retirar na loja'
    when 'entregue' then 'entregue'
    when 'orcamento' then 'só orçamento, não fechado'
    else Otica::Order::STATUSES[order.status].to_s.downcase
    end
  end

  # uma tarefa ABERTA por O.S. e motivo; concluída e o problema continua → nasce outra
  # (o external_ref é único por tarefa, por isso leva a hora)
  def open_task!(order, kind, title, detail)
    prefix = "otica:os:#{order.id}:#{kind}:"
    return false if @account.tasks.where(task_type: TASK_TYPE, status: %i[todo doing]).where('external_ref LIKE ?', "#{prefix}%").exists?

    ref = "#{prefix}#{SecureRandom.hex(4)}" # único por tarefa (índice único do external_ref)

    creator = @account.administrators.first || @account.users.first
    return false if creator.nil?

    @account.tasks.create!(
      title: "📦 #{title}", description: "#{detail}\n\nCliente: #{order.contact&.name || 'sem cadastro'}",
      task_type: TASK_TYPE, external_ref: ref, priority: :high, status: :todo, due_at: Otica::TZ.now.end_of_day,
      contact: order.contact, phone: order.contact&.phone_number,
      creator: creator, assignee: order.seller || creator
    )
    true
  rescue StandardError => e
    raise e if Rails.env.test? # nos testes o erro aparece; em produção só o aviso no log

    Rails.logger.warn "[Otica::OrderWatch] O.S. #{order.id} (#{kind}): #{e.message}"
    false
  end

  def fmt(value)
    return nil if value.blank?

    value.respond_to?(:in_time_zone) && !value.is_a?(Date) ? value.in_time_zone(Otica::TZ).strftime('%d/%m') : value.strftime('%d/%m')
  end
end
