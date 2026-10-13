# 🤖 Lembrete com IA (item 315) — etapa "IA" dos robôs de follow-up:
# Crm::FollowupAiNudgeService escreve a cutucada a partir da conversa.
class Crm::FlowMap::Flows::FollowupAi
  FLOW = Crm::FlowMap::Flow.define(:followup_ia) do
    name 'Lembrete com IA (follow-up)'
    group 'Atendimento ao paciente'
    icon 'i-lucide-bot-message-square'
    color '#0F5FA6'
    what 'escreve a cutucada retomando o ponto em que a conversa parou'
    config tab: 'robos'
    trigger :event, 'Etapa "IA" do robô venceu (Crm::FollowupBotJob)'
    jobs 'Crm::FollowupBotJob'

    node :teto, 'Teto de 15 chamadas por rodada?', kind: :decision
    node :escreve, 'IA lê a conversa + etiquetas e escreve', kind: :ai
    node :reserva, 'Etapa tem texto de reserva?', kind: :decision
    node :de_novo, 'Tenta na próxima rodada (até 3×) ou termina sem envio'
    node :envia, 'Cutucada sai marcada como IA', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :teto
    edge :teto, :fim, 'cheio (sai na próxima rodada)'
    edge :teto, :escreve, 'ok'
    edge :escreve, :envia, 'escreveu'
    edge :escreve, :reserva, 'falhou'
    edge :reserva, :envia, 'sim (usa o texto de reserva)'
    edge :reserva, :de_novo, 'não (sem chave ou 3 falhas = sem envio)'
    edge :de_novo, :fim
    edge :envia, :fim
  end

  def self.flow
    FLOW
  end
end
