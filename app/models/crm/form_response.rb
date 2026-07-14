# Resposta de um paciente a um Crm::Form. `answers` guarda um snapshot
# de cada pergunta com o valor respondido (o formulário pode mudar depois
# sem desalinhar respostas antigas):
#   [{ "id" => "q1", "label" => "...", "type" => "choice", "value" => "..." }]
# == Schema Information
#
# Table name: crm_form_responses
#
#  id           :bigint           not null, primary key
#  answers      :jsonb            not null
#  completed_at :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  contact_id   :bigint
#  crm_form_id  :bigint           not null
#
# Indexes
#
#  index_crm_form_responses_on_account_id   (account_id)
#  index_crm_form_responses_on_contact_id   (contact_id)
#  index_crm_form_responses_on_crm_form_id  (crm_form_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (crm_form_id => crm_forms.id)
#
class Crm::FormResponse < ApplicationRecord
  self.table_name = 'crm_form_responses'

  belongs_to :form, class_name: 'Crm::Form', foreign_key: :crm_form_id
  belongs_to :account
  belongs_to :contact, class_name: '::Contact', optional: true
end
