# Radar de Oportunidades — ações do carrossel do Meu Painel (item 63).
#
# attend: a pessoa tocou em "Atender agora" → o aviso SAI da fila oficial
# (o -1 vale para todo mundo, não só na tela de quem clicou). Fica um
# registro em attended_log para medir a EFICÁCIA do Radar (item 83:
# conversões geradas depois do aviso). Se o paciente continuar sem
# resposta, a próxima auditoria do Radar recoloca o aviso sozinha.
class Api::V1::Accounts::Crm::RadarController < Api::V1::Accounts::BaseController
  ATTENDED_LOG_CAP = 200

  def attend
    settings = CrmSetting.find_by(account: Current.account)
    return render json: { error: 'Radar não configurado.' }, status: :unprocessable_entity if settings.blank?

    conversation_id = params[:conversation_id].to_i
    removed = nil

    with_ai_config_lock(settings) do |ai|
      state = ai['opportunity_state'] ||= {}
      alerts = Array(state['alerts'])
      removed = alerts.find { |a| a['conversation_id'].to_i == conversation_id }
      state['alerts'] = alerts.reject { |a| a['conversation_id'].to_i == conversation_id }

      if removed
        log = Array(state['attended_log'])
        log.unshift(removed.merge('attended_at' => Time.current.iso8601,
                                  'attended_by' => Current.user.name))
        state['attended_log'] = log.first(ATTENDED_LOG_CAP)
      end
      ai
    end

    render json: { removed: removed.present?, remaining: remaining_count(settings) }
  end

  private

  # mesmo espírito do Cevico::AttributeMerge: relê e grava o ai_config
  # dentro de uma trava de linha — sem apagar chaves de outros processos
  def with_ai_config_lock(settings)
    settings.with_lock do
      ai = (settings.ai_config || {}).deep_dup
      updated = yield(ai)
      settings.update_column(:ai_config, updated) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def remaining_count(settings)
    Array(settings.reload.ai_config&.dig('opportunity_state', 'alerts')).size
  end
end
