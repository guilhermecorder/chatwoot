# 🧠 Leitor do follow-up (13/10) — Crm::FollowupConversationReader, chamado
# pelo Crm::FollowupBotJob antes da 1ª cutucada de cada silêncio.
class Crm::FlowMap::Flows::FollowupReader
  FLOW = Crm::FlowMap::Flow.define(:followup_leitor) do # rubocop:disable Metrics/BlockLength
    name 'Leitor do follow-up'
    group 'Atendimento ao paciente'
    icon 'i-lucide-scan-eye'
    color '#0F5FA6'
    what 'lê a conversa antes da cutucada: só cutuca quem ficou com algo a responder'
    config tab: 'robos'
    trigger :event, 'Cutucada venceu (Crm::FollowupBotJob)'
    jobs 'Crm::FollowupBotJob'

    node :ja_lida, 'Já leu este silêncio?', kind: :decision
    node :le, 'IA lê as últimas 16 mensagens (Haiku)', kind: :ai
    node :regra, 'Sem chave / IA fora: regra de frases'
    node :carimbo, 'Atendente de IA carimbou a despedida?', kind: :decision
    node :situacao, 'Aberta, encerrada, adiada ou recusou?', kind: :decision
    node :cutuca, 'Aberta → a cutucada segue', kind: :output
    node :segura, 'Encerrada → nenhum robô cutuca', kind: :output
    node :reativa, 'Adiada → 1 mensagem modelo em N dias (padrão 7)', kind: :output
    node :etiqueta, 'Recusou → etiqueta perda_sem_interesse + nota', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ja_lida
    edge :ja_lida, :situacao, 'sim (usa a leitura guardada)'
    edge :ja_lida, :le, 'não'
    edge :le, :regra, 'falhou'
    edge :le, :carimbo
    edge :regra, :carimbo
    edge :carimbo, :segura, 'sim e leitura = aberta'
    edge :carimbo, :situacao, 'não'
    edge :situacao, :cutuca, 'aberta'
    edge :situacao, :segura, 'encerrada'
    edge :situacao, :reativa, 'adiada'
    edge :situacao, :etiqueta, 'recusou'
    edge :cutuca, :fim
    edge :segura, :fim
    edge :reativa, :fim
    edge :etiqueta, :fim

    live do |account|
      attr = Crm::FollowupClosure::ATTR
      reads = Conversation.where(account_id: account.id)
                          .where("(conversations.additional_attributes -> '#{attr}' ->> 'at')::timestamptz >= ?", Time.current.beginning_of_day)
                          .group(Arel.sql("conversations.additional_attributes -> '#{attr}' ->> 'situacao'")).count
      {
        enabled: Crm::FollowupBot.where(account_id: account.id).active.exists?,
        counters: { 'leituras hoje' => reads.values.sum, 'seguradas hoje' => reads.except('aberta').values.sum }
      }
    end
  end

  def self.flow
    FLOW
  end
end
