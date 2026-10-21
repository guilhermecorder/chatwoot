# 🏷️ item 322: registro que nasce CARIMBADO — de quem é (cevico_source_id) e
# como nasceu (cevico_born_via). As regras moram em Crm::Stamp; aqui é só o
# gancho no modelo, para nenhum caminho de criação escapar.
module CevicoSourceStamped
  extend ActiveSupport::Concern

  included do
    belongs_to :cevico_source, class_name: 'Crm::Source', optional: true
    before_create :cevico_stamp!
    scope :of_cevico_source, ->(source) { where(cevico_source_id: source) }
  end

  def cevico_stamp!(refresh: false)
    Crm::Stamp.apply(self, refresh: refresh)
    true
  end
end
