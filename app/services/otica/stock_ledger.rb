# 📦 LIVRO DE ESTOQUE (fase 2): a ÚNICA porta para mudar o saldo de um
# produto. Cada mudança vira uma Otica::StockMove com o saldo depois; o
# produto é travado (with_lock) para duas vendas ao mesmo tempo não perderem
# peça. Venda: apply_order! compara o que a O.S. precisa com o que já saiu
# por ela e emite só a diferença (gravar, alterar, cancelar, devolver — tudo
# passa por aqui e fica certo mesmo repetido).
class Otica::StockLedger
  # kind entrada/saida: quantity = quanto movimentar; ajuste: quantity = SALDO NOVO
  def self.record!(product:, kind:, quantity:, origin: 'manual', reference: nil, unit_cost: nil, notes: '', user: nil) # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
    product.with_lock do
      before = product.quantity
      delta = case kind.to_s
              when 'entrada' then quantity.to_i
              when 'saida' then -quantity.to_i
              when 'ajuste' then quantity.to_i - before
              else raise ArgumentError, 'Tipo de movimentação inválido.'
              end
      return nil if delta.zero?

      after = before + delta
      if after.negative? && kind.to_s == 'saida' && !allow_negative?
        raise ArgumentError,
              "#{product.name}: saldo não pode ficar negativo (tem #{before}, pediu #{delta.abs})."
      end

      product.update!(quantity: after)
      product.stock_moves.create!(
        account_id: product.account_id, kind: kind.to_s, origin: origin.to_s, quantity: delta.abs, delta: delta,
        balance_after: after, unit_cost: unit_cost, reference: reference, notes: notes.to_s[0, 300], created_by_id: user&.id
      )
    end
  end

  # a loja pode vender o que o sistema ainda não conhece (saldo entra depois
  # pelo inventário) — a venda NÃO pode travar por estoque errado
  def self.allow_negative?
    true
  end

  # saldo novo direto (edição do produto, CSV do SavWin)
  def self.set_quantity!(product, new_quantity, origin:, notes: '', user: nil)
    record!(product: product, kind: 'ajuste', quantity: new_quantity.to_i, origin: origin, notes: notes, user: user)
  end

  # a O.S. em dia com o estoque: status que "vendeu" baixa o que falta
  # baixar; cancelada/devolvida/orçamento devolve o que saiu
  def self.apply_order!(order, user: nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    sells = %w[aberta em_producao pronta entregue].include?(order.status)
    wanted = Hash.new(0)
    if sells
      order.items.includes(:product).find_each do |item|
        next if item.product.nil? || !item.product.stock_tracked?

        wanted[item.product_id] += item.quantity
      end
    end
    already = Hash.new(0)
    Otica::StockMove.where(reference: order).find_each { |m| already[m.product_id] -= m.delta } # saídas contam positivo
    origin = if sells then 'venda'
             elsif order.status == 'devolvida' then 'devolucao'
             else
               'cancelamento'
             end
    (wanted.keys | already.keys).each do |product_id|
      diff = wanted[product_id] - already[product_id]
      next if diff.zero?

      product = Otica::Product.find_by(id: product_id)
      next if product.nil?

      record!(product: product, kind: diff.positive? ? 'saida' : 'entrada', quantity: diff.abs,
              origin: diff.positive? ? 'venda' : origin, reference: order, user: user,
              notes: diff.positive? ? "baixa pela #{order.label}" : "volta ao estoque (#{order.label})")
    end
  end
end
