# 📊 Pesquisa de satisfação pós-cirurgia (item 256): a cada 15 min; cada conta
# só age na HORA configurada (Agentes de IA → "Pesquisa de satisfação (NPS)").
# Toda a regra mora em Crm::NpsSurvey.
class Crm::NpsSurveySendJob < ApplicationJob
  queue_as :scheduled_jobs

  # now: só os testes passam (congelar o relógio)
  def perform(now = nil)
    Crm::NpsSurvey.run_all(now)
  end
end
