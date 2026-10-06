# Aba RESULTADOS do ambiente de Páginas (plano 100+ páginas com ads):
# por página e por origem (Google Ads, Google orgânico/SEO, Meta, funil,
# direto) — visitas, cliques no WhatsApp, leads que chegaram na caixa com
# Protocolo, quantos agendaram consulta e quantos fecharam cirurgia (com
# receita). O lado "quanto custou" continua no relatório de Anúncios;
# aqui a pergunta é "qual PÁGINA e qual ORIGEM trazem paciente de verdade".
#
# Item 329 (05/10): o painel ganhou as taxas de conversão etapa a etapa, a
# comparação com o período anterior, a série para os gráficos em linha, os
# DIAGNÓSTICOS automáticos por página e a COLEÇÃO DE INSIGHTS (o que a equipe
# decidiu fazer, com antes × depois). A conta mora em Cevico::TrafficReport.
class Api::V1::Accounts::Crm::PagesReportsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod
  before_action -> { require_capability(:pages) }

  # GET /api/v1/accounts/:id/crm/pages_report?preset=month (régua padrão)
  # ou ?since=YYYY-MM-DD&until=YYYY-MM-DD (legado)
  def show
    render json: {
      since: since_date,
      until: until_date,
      sources: Cevico::TrafficSource::SOURCES,
      rows: report.rows,
      protocol: report.protocol,
      totals: report.totals,
      previous: { since: previous.since_date, until: previous.until_date, totals: previous.totals },
      series: report.series,
      insights: insights,
      collection: log.list,
      pages: pages_json
    }
  end

  # POST /crm/pages_report/save_insight — guarda um insight na coleção ou
  # muda a situação dele (a fazer → aplicado → descartado)
  def save_insight
    attrs = params.permit(:id, :key, :page_id, :title, :text, :origin, :status).to_h.symbolize_keys
    blank = attrs[:id].blank? && attrs[:title].blank?
    return render json: { error: 'Escreva o insight antes de guardar.' }, status: :unprocessable_entity if blank

    render json: { collection: log.save!(attrs, user: Current.user) }
  end

  # POST /crm/pages_report/remove_insight
  def remove_insight
    render json: { collection: log.remove!(params[:id]) }
  end

  # POST /crm/pages_report/ai_suggestions?page_id= — sugestões da IA para UMA
  # página, com os números do período escolhido na régua
  def ai_suggestions
    page = Current.account.cevico_pages.find(params[:page_id])
    row = report.rows_with_idle.find { |r| r[:page_id] == page.id }
    result = Crm::PageOptimizerService.new(
      page: page, row: row, insights: insights.select { |i| i[:page_id] == page.id },
      period: "#{since_date.strftime('%d/%m')} a #{until_date.strftime('%d/%m/%Y')}"
    ).call
    render json: result, status: result[:error] ? :unprocessable_entity : :ok
  end

  private

  def report
    @report ||= Cevico::TrafficReport.new(Current.account, since_date, until_date)
  end

  # o período ANTERIOR de mesmo tamanho (para "subiu / caiu")
  def previous
    @previous ||= begin
      days = (until_date - since_date).to_i + 1
      Cevico::TrafficReport.new(Current.account, since_date - days, since_date - 1)
    end
  end

  def insights
    @insights ||= Cevico::PageInsights.new(rows: report.rows_with_idle, totals: report.totals).call
  end

  def log
    @log ||= Cevico::InsightLog.new(Current.account)
  end

  # as páginas da conta (para escolher em qual guardar um insight escrito à
  # mão e para abrir o ambiente de montagem a partir de um insight)
  def pages_json
    Current.account.cevico_pages.order(:title).map do |page|
      { id: page.id, title: page.title, slug: page.slug, emoji: page.emoji, status: page.status,
        public_url: Cevico::PublicSite.page_url(page.slug),
        builder_url: "#{Cevico::PublicSite.base_url}/p/rascunho/#{page.preview_token}?edit=#{page.edit_token}" }
    end
  end

  # régua padrão CEVICO (06/08) via concern; since/until soltos = legado
  def standard_range
    @standard_range ||= standard_period_range
  end

  def since_date
    @since_date ||= standard_range ? standard_range.first.to_date : parse_date(params[:since], 30.days.ago.to_date)
  end

  def until_date
    @until_date ||= standard_range ? standard_range.last.to_date : parse_date(params[:until], Date.current)
  end

  def parse_date(value, fallback)
    Date.parse(value.to_s)
  rescue StandardError
    fallback
  end
end
