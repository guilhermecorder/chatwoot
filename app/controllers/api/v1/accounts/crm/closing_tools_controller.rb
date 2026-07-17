# FERRAMENTAS DE FECHAMENTO (high ticket): o arsenal da pessoa que fecha —
# script CEVICO editável, MAPA DE OBJEÇÕES por estágio gerado pela IA
# (objeções mais frequentes + respostas que converteram) e ferramentas
# importantes. Time inteiro LÊ; admin edita e regenera o mapa.
class Api::V1::Accounts::Crm::ClosingToolsController < Api::V1::Accounts::BaseController
  def show # rubocop:disable Metrics/CyclomaticComplexity
    cfg = crm_settings&.ai_config || {}
    render json: {
      script: crm_settings&.agenda_config&.dig('closing_script'),
      objection_map: cfg.dig('agents', 'sales', 'objection_map'),
      sales_agent_enabled: cfg.dig('agents', 'sales', 'enabled') == true,
      tools: crm_settings&.agenda_config&.dig('important_tools') || []
    }
  end

  def update_script
    return forbidden unless Current.account_user.administrator?

    settings = CrmSetting.find_or_create_by!(account: Current.account)
    cfg = settings.agenda_config || {}
    cfg['closing_script'] = params[:script].to_s[0, 20_000]
    settings.update!(agenda_config: cfg)
    render json: { script: cfg['closing_script'] }
  end

  def generate_map
    return forbidden unless Current.account_user.administrator?

    Crm::ObjectionMapJob.perform_later(Current.account.id)
    render json: { success: true, message: 'Mapa de objeções em produção! A IA está lendo as conversas que converteram — volte em alguns minutos.' }
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: Current.account)
  end

  def forbidden
    render json: { error: 'Só administradores.' }, status: :forbidden
  end
end
