# 💰 Rodada 5 da auditoria (#198, 13/10): o "Faturamento fechado" que sai do
# histórico de colunas (Meu Painel/KpiBag, PRO MAX do Dashboard CRM).
# Antes: somava o valor do card em TODA entrada em "Cirurgia Realizada" —
# inclusive as cargas em massa (`bulk`, item 309: importação de 10/07,
# re-arrumação de 14/07, carga do Oftalmofácil de 14/09) e cada vez que o
# mesmo card saía e voltava para a coluna (o valor dobrava).
# Agora (mesma ideia do Crm::AcquisitionPatients): só entrada de verdade
# (`entered`) e UM valor por card — a PRIMEIRA entrada dele no período.
module Crm::RevenueEntries
  STAGE_SQL = "crm_contact_stage_logs.stage_name ILIKE '%cirurgia realizada%'".freeze

  # a entrada só vale se o mesmo card não entrou antes, no mesmo período,
  # numa coluna de cirurgia realizada (empate na hora: vale o id menor)
  FIRST_IN_PERIOD_SQL = <<~SQL.squish.freeze
    NOT EXISTS (
      SELECT 1 FROM crm_contact_stage_logs anterior
      WHERE anterior.crm_contact_id = crm_contact_stage_logs.crm_contact_id
        AND anterior.event_type = :entered
        AND anterior.stage_name ILIKE '%cirurgia realizada%'
        AND anterior.entered_at >= :since
        AND (anterior.entered_at < crm_contact_stage_logs.entered_at
             OR (anterior.entered_at = crm_contact_stage_logs.entered_at AND anterior.id < crm_contact_stage_logs.id))
    )
  SQL

  module_function

  # scope: Crm::StageLog (com joins(:crm_contact) para somar o valor do card);
  # devolve só as entradas que contam como faturamento no período
  def first_entries(scope, since, until_at)
    scope.where(entered_at: since..until_at, event_type: Crm::StageLogBulk::ENTERED)
         .where(STAGE_SQL)
         .where(FIRST_IN_PERIOD_SQL, entered: Crm::StageLogBulk::ENTERED, since: since)
  end
end
