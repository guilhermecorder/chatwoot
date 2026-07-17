# Perfil de desenvolvimento de uma pessoa do time (ambiente Pessoas):
# resultado do diagnóstico DISC / 4 temperamentos + objetivos e metas
# pessoais com progresso rastreado. Um registro por pessoa.
# == Schema Information
#
# Table name: cevico_people_profiles
#
#  id          :bigint           not null, primary key
#  assessments :jsonb            not null
#  disc        :jsonb            not null
#  goals       :jsonb            not null
#  life        :jsonb            not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_cevico_people_profiles_on_account_id              (account_id)
#  index_cevico_people_profiles_on_account_id_and_user_id  (account_id,user_id) UNIQUE
#  index_cevico_people_profiles_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class CevicoPeopleProfile < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
end
