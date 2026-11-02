# 📊 ANÁLISE DA LOJA (02/11/2026): a página do SavWin gerada no Mac
# (OTICA/analise/savwin.py) vive aqui dentro, só para quem está logado na
# conta da ótica. Cada envio é uma versão; a tela mostra a mais nova num
# iframe sandbox. Ler = nó otica.analise (ver). Enviar = só administrador
# (pela tela ou pela API com o token de acesso do usuário: `--enviar`).
class Api::V1::Accounts::Crm::Otica::ReportsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  HISTORY_LIMIT = 30

  # enviar: a conta precisa ser do ramo ótica (o nó só existe lá) E a pessoa, administradora
  before_action -> { require_access('otica.analise', :view) }, only: [:create]
  before_action :require_administrator!, only: [:create]

  def index
    reports = Current.account.otica_reports.newest_first.includes(:created_by).limit(HISTORY_LIMIT)
    render json: { reports: reports.map(&:as_json_otica), latest_id: reports.first&.id }
  end

  # GET …/reports/latest → o HTML da versão mais nova (text/html, sem cache, sem robô)
  def latest
    report = Current.account.otica_reports.latest
    return render json: { error: 'Nenhuma análise foi enviada ainda.' }, status: :not_found if report.nil?

    render_report_html(report)
  end

  # GET …/reports/:id/html → o HTML de uma versão específica
  def html
    render_report_html(Current.account.otica_reports.find(params[:id]))
  end

  # POST …/reports (multipart: file=index.html, title, note)
  def create
    upload = params[:file]
    return render json: { error: 'Envie o arquivo index.html gerado pela análise.' }, status: :unprocessable_entity if upload.blank?

    report = Current.account.otica_reports.new(title: params[:title].to_s, note: params[:note].to_s, created_by: Current.user)
    report.file.attach(upload)
    if report.save
      render json: { report: report.as_json_otica }
    else
      render json: { error: report.errors.full_messages.join(' ') }, status: :unprocessable_entity
    end
  end

  private

  # a página inteira, do jeito que foi gerada: a tela coloca num iframe sandbox
  # (srcdoc). Cabeçalhos: nada de cache, nada de indexação, nada de iframe de fora.
  def render_report_html(report)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow, noarchive'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    response.headers['Content-Disposition'] = 'inline'
    render html: report.html.html_safe, content_type: 'text/html', layout: false # rubocop:disable Rails/OutputSafety
  end
end
