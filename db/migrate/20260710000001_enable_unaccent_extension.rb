class EnableUnaccentExtension < ActiveRecord::Migration[7.1]
  # Permite busca ignorando acentos no Tratamento de dados (orcamento = orçamento)
  def up
    enable_extension 'unaccent' unless extension_enabled?('unaccent')
  end

  def down
    disable_extension 'unaccent' if extension_enabled?('unaccent')
  end
end
