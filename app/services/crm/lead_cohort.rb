# 👥 item 246 (25/09): QUANDO o lead chegou em relação à marcação da consulta —
# "consulta de lead que chegou no dia, na semana ou antes". Dias entre o
# cadastro do contato e a criação da consulta, no fuso de São Paulo.
module Crm::LeadCohort
  module_function

  KEYS = %w[mesmo_dia semana mes antes].freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  # mesmo_dia (0) · semana (1–7) · mes (8–30) · antes (>30) · sem_cadastro
  def of(contact, task)
    return 'sem_cadastro' if contact.blank? || task.created_at.blank?

    days = (task.created_at.in_time_zone(TZ).to_date - contact.created_at.in_time_zone(TZ).to_date).to_i
    return 'mesmo_dia' if days <= 0
    return 'semana' if days <= 7
    return 'mes' if days <= 30

    'antes'
  end
end
