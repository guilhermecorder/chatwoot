# 📥 item 238 (25/09): de qual CONVERSA (e caixa de entrada) cada agendamento
# saiu — uma regra só para o ambiente Agendamentos e o card "Marcadas na
# Agenda" do Meu Painel, para os números por caixa baterem nas duas telas.
# Regra: "Conversa #123" na descrição (vale a ÚLTIMA citada = reagendamento
# mais recente); sem rastro, a conversa mais recente do paciente.
module Crm::TaskConversations
  module_function

  # { task_id => Conversation | nil }
  def for(account, tasks) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    wanted = {}
    tasks.each do |t|
      ids = t.description.to_s.scan(/Conversa #(\d+)/).flatten
      wanted[t.id] = ids.last.to_i if ids.any?
    end
    by_display = account.conversations.where(display_id: wanted.values.uniq).includes(:inbox).index_by(&:display_id)
    fallback_ids = tasks.reject { |t| by_display[wanted[t.id]] }.filter_map(&:contact_id).uniq
    latest = account.conversations.where(contact_id: fallback_ids).includes(:inbox)
                    .order(last_activity_at: :desc).group_by(&:contact_id).transform_values(&:first)
    tasks.to_h { |t| [t.id, by_display[wanted[t.id]] || latest[t.contact_id]] }
  end

  # [{ inbox_id:, name:, count: }] do maior para o menor ("sem conversa" no fim)
  def count_by_inbox(account, tasks) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    self.for(account, tasks).values
        .group_by { |c| c&.inbox_id }
        .map { |id, list| { inbox_id: id, name: list.first&.inbox&.name.presence || 'sem conversa', count: list.size } }
        .sort_by { |h| [h[:inbox_id].nil? ? 1 : 0, -h[:count]] }
  end
end
