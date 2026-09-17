# 🩺 Confirmação de cirurgia — HOJE roda fora, no N8N ("CONFIRMACAO CIRURGICA - IOP",
# 10h): planilha → contato → conversa → modelo confirmar_cirurgia. O item 168 traz
# isso para dentro (fonte = espelho do OftalmoFácil). Nós :external de propósito.
class Crm::FlowMap::Flows::SurgeryConfirmation
  FLOW = Crm::FlowMap::Flow.define(:surgery_confirmation) do
    name 'Confirmação de cirurgia'
    group 'Infraestrutura'
    icon 'i-lucide-shield-check'
    color '#64748B'
    what 'confirma a cirurgia com o paciente pelo WhatsApp — hoje roda no N8N, entra no sistema no item 168'
    config route: 'crm_integrations'
    trigger :cron, 'Todo dia 10h no N8N (fluxo externo)'

    node :planilha, 'Lê a planilha (procedimento, paciente, data, hora)', kind: :external
    node :linha, 'Para cada linha com telefone', kind: :loop
    node :contato, 'Contato existe?', kind: :decision
    node :cria_contato, 'Cria o contato (caixa 5)', kind: :external
    node :conversa, 'Conversa aberta na caixa 5?', kind: :decision
    node :cria_conversa, 'Cria a conversa', kind: :external
    node :envia, 'Envia o modelo confirmar_cirurgia (nome, data, hora)', kind: :external
    node :resposta, 'Paciente responde "confirmo"', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :planilha
    edge :planilha, :linha
    edge :linha, :contato
    edge :contato, :cria_contato, 'não'
    edge :cria_contato, :conversa
    edge :contato, :conversa, 'sim'
    edge :conversa, :cria_conversa, 'não'
    edge :cria_conversa, :envia
    edge :conversa, :envia, 'sim'
    edge :envia, :resposta
    edge :resposta, :fim

    live do |_account|
      { enabled: nil, last_run_at: nil, counters: {}, note: 'roda no N8N hoje (item 168 traz para dentro do sistema)' }
    end
  end

  def self.flow
    FLOW
  end
end
