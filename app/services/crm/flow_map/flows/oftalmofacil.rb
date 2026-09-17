# 🏥 Sincronização com o OftalmoFácil (item 157) — passos reais de
# app/jobs/crm/oftalmofacil_sync_job.rb e oftalmofacil_sync_service.rb (item 170).
class Crm::FlowMap::Flows::Oftalmofacil
  FLOW = Crm::FlowMap::Flow.define(:oftalmofacil) do # rubocop:disable Metrics/BlockLength
    name 'Sincronização OftalmoFácil'
    group 'Infraestrutura'
    icon 'i-lucide-refresh-cw'
    color '#0E7490'
    what 'espelha as cirurgias do OftalmoFácil e move os cards do CRM'
    config route: 'crm_integrations'
    trigger :cron, 'A cada 15 min (OftalmofacilSyncJob) ou "Sincronizar agora"'
    jobs 'Crm::OftalmofacilSyncJob'

    node :ligado, 'Conexão ligada e configurada?', kind: :decision
    node :mysql, 'Lê o banco do OftalmoFácil (só leitura)', kind: :external
    node :cursor, 'Tem cursor (não é a 1ª carga)?', kind: :decision
    node :silencia, 'Primeira carga: automações silenciadas'
    node :lote, 'Lotes de 500 cirurgias', kind: :loop
    node :espelha, 'Espelha a cirurgia (idempotente)'
    node :status, 'Classifica o status'
    node :paciente, 'Casa o paciente: telefone → CPF → nome → cria'
    node :enriquece, 'Enriquece o cadastro'
    node :coluna, 'Coluna-alvo: Agendada / Realizada / Pós'
    node :adiante, 'Card já está adiante?', kind: :decision
    node :mantem, 'Nunca volta o card'
    node :move, 'Move: valor + histórico + automações se recente'
    node :etiquetas, 'Etiquetas cancelada / falta'
    node :grava, 'Grava cursor + resumo', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligado
    edge :ligado, :fim, 'não'
    edge :ligado, :mysql, 'sim'
    edge :mysql, :cursor
    edge :cursor, :silencia, 'não'
    edge :silencia, :lote
    edge :cursor, :lote, 'sim'
    edge :lote, :espelha
    edge :espelha, :status
    edge :status, :paciente
    edge :paciente, :enriquece
    edge :enriquece, :coluna
    edge :coluna, :adiante
    edge :adiante, :mantem, 'sim'
    edge :mantem, :etiquetas
    edge :adiante, :move, 'não'
    edge :move, :etiquetas
    edge :etiquetas, :grava
    edge :grava, :fim

    live do |account|
      cfg = agenda(account)['oftalmofacil'] || {}
      result = cfg['last_result']
      {
        enabled: cfg['enabled'] == true,
        last_run_at: cfg['last_run_at'],
        counters: {
          'último sync' => cfg['last_sync_at'].present? ? Time.zone.parse(cfg['last_sync_at'].to_s)&.strftime('%d/%m %H:%M') : '—',
          'cirurgias espelhadas' => Crm::OftalmofacilSurgery.where(account_id: account.id).count
        },
        note: result.is_a?(String) ? result.truncate(120) : nil
      }
    end
  end

  def self.flow
    FLOW
  end
end
