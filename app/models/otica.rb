# 👓 SUA ÓTICA (fase 1, 22/10/2026): o módulo da loja. As tabelas são
# otica_* e vivem por conta — a clínica não as usa.
module Otica
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def self.table_name_prefix
    'otica_'
  end

  # a data de HOJE na loja (São Paulo) — toda regra de data da ótica usa esta
  def self.today
    TZ.today
  end
end
