# HUB DOS FORMULÁRIOS (item 73): contamos ENVIOS do link (sent_count) e a
# RETENÇÃO card a card (funnel_stats: {'open'=>n, 'q:<id>'=>n, 'done'=>n})
# para mostrar envio × respostas, % de conversão e o gráfico de abandono
# por formulário. Aditiva.
class AddFunnelStatsToCrmForms < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_forms, :sent_count, :integer, null: false, default: 0
    add_column :crm_forms, :funnel_stats, :jsonb, null: false, default: {}
  end
end
