# 📞 Chamadas nativas do WhatsApp (item 167) — passos reais de
# app/services/crm/calls/webhook_service.rb e outbound_service.rb (item 170).
class Crm::FlowMap::Flows::Calls
  FLOW = Crm::FlowMap::Flow.define(:calls) do # rubocop:disable Metrics/BlockLength
    name 'Chamadas do WhatsApp'
    group 'Atendimento ao paciente'
    icon 'i-lucide-phone'
    color '#0F766E'
    what 'ligações do WhatsApp atendidas no navegador e ligação para o paciente com permissão'
    config route: 'crm_integrations_calls'
    trigger :webhook, 'Webhook da Meta (campo calls) ou botão Ligar'
    jobs 'Crm::Calls::TranscriptionJob'

    node :tipo, 'Recebida ou ligar para o paciente?', kind: :decision
    # ── recebida ──
    node :ligado, 'Chamadas ligadas com caixa configurada?', kind: :decision
    node :connect, 'Cria contato, conversa e a ligação (tocando)'
    node :horario, 'Fora do horário de atendimento?', kind: :decision
    node :recusa, 'Recusa na Meta + card + aviso de perdida', kind: :output
    node :toca, 'Toca para os atendentes escolhidos'
    node :atendeu, 'Alguém atendeu no navegador?', kind: :decision
    node :webrtc, 'Conversa por WebRTC (409 se outro já pegou)'
    node :termina, 'Encerra: duração, status e card na conversa'
    node :perdida, 'Perdida: reabre a conversa + aviso', kind: :output
    node :gravacao, 'Subiu gravação do navegador?', kind: :decision
    node :transcreve, 'Transcreve (ffmpeg → Gemini)', kind: :ai
    node :card, 'Card atualizado com a transcrição', kind: :output
    # ── ligar para o paciente ──
    node :dados, 'Caixa e telefone ok?', kind: :decision
    node :erro, 'Erro: sem caixa ou telefone', kind: :output
    node :permissao, 'Paciente já deu permissão na Meta?', kind: :decision
    node :pede, 'Pede permissão (mensagem interativa)', kind: :external
    node :resposta, 'Resposta do paciente grava no contato'
    node :connect_out, 'Liga (connect + SDP) → tocando', kind: :external
    node :atendeu_out, 'Paciente atendeu (webhook answer)'
    node :fim, 'Fim', kind: :end

    edge :trigger, :tipo
    edge :tipo, :ligado, 'recebida'
    edge :ligado, :fim, 'não'
    edge :ligado, :connect, 'sim'
    edge :connect, :horario
    edge :horario, :recusa, 'sim'
    edge :recusa, :fim
    edge :horario, :toca, 'não'
    edge :toca, :atendeu
    edge :atendeu, :webrtc, 'sim'
    edge :atendeu, :perdida, 'não'
    edge :perdida, :fim
    edge :webrtc, :termina
    edge :termina, :gravacao
    edge :gravacao, :transcreve, 'sim'
    edge :transcreve, :card
    edge :card, :fim
    edge :gravacao, :fim, 'não'
    edge :tipo, :dados, 'ligar'
    edge :dados, :erro, 'não'
    edge :erro, :fim
    edge :dados, :permissao, 'sim'
    edge :permissao, :pede, 'não'
    edge :pede, :resposta
    edge :resposta, :fim
    edge :permissao, :connect_out, 'sim'
    edge :connect_out, :atendeu_out
    edge :atendeu_out, :webrtc

    live do |account|
      cfg = agenda(account)['calls'] || {}
      calls = Crm::Call.where(account_id: account.id)
      # depois do item 169 a tabela ganha handled_by (human | ai): aqui só as humanas
      calls = calls.where(handled_by: 'human') if Crm::Call.column_names.include?('handled_by')
      today = calls.where(started_at: today_range)
      {
        enabled: cfg['enabled'] == true,
        last_run_at: calls.maximum(:started_at),
        counters: {
          'ligações hoje' => today.count,
          'atendidas hoje' => today.answered.count,
          'perdidas hoje' => today.where(status: :missed).count
        },
        note: cfg['inbox_id'].present? ? nil : 'caixa de WhatsApp ainda não escolhida'
      }
    end
  end

  def self.flow
    FLOW
  end
end
