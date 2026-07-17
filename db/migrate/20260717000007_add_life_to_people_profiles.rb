# PESSOAS v2: espaço de desenvolvimento pessoal do líder — Roda da Vida
# (histórico de avaliações), objetivos por horizonte de tempo e fichas de
# hábitos/crenças; testes (DISC/temperamentos) arquivados. Aditiva.
class AddLifeToPeopleProfiles < ActiveRecord::Migration[7.0]
  def change
    add_column :cevico_people_profiles, :life, :jsonb, null: false, default: {}
    add_column :cevico_people_profiles, :assessments, :jsonb, null: false, default: []
  end
end
