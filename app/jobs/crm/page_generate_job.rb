# Item 111 (23/07): montar/escrever página com IA em SEGUNDO PLANO.
# A geração demora mais do que o proxy espera com a conexão aberta
# ("internet error" em produção) — então o clique só AGENDA; o resultado
# fica no Redis por 15 minutos e o editor consulta até ficar pronto.
class Crm::PageGenerateJob < ApplicationJob
  queue_as :default

  RESULT_TTL = 15.minutes

  def self.result_key(job_id)
    "cevico:pagegen:#{job_id}"
  end

  # status por PÁGINA (modo "ambiente de montagem": a aba do rascunho
  # acompanha a construção por aqui; o resultado vai direto pro banco)
  def self.page_key(page_id)
    "cevico:pagegen:page:#{page_id}"
  end

  def self.page_status(page_id)
    raw = Redis::Alfred.get(page_key(page_id))
    raw.present? ? JSON.parse(raw) : nil
  end

  def perform(account_id, job_id, options = {})
    account = Account.find_by(id: account_id)
    return if account.blank?

    page = options['page_id'].present? ? account.cevico_pages.find_by(id: options['page_id']) : nil
    result = run_service(account, options)
    payload = result[:error] ? { status: 'error', error: result[:error] } : { status: 'done', result: result }
    # guarda-corpo: "pronta" sem NENHUMA seção = algo deu errado na IA —
    # melhor avisar do que entregar página vazia como sucesso
    if payload[:status] == 'done' && CevicoPage.normalize_ai_sections(result[:sections] || result['sections']).empty?
      payload = { status: 'error', error: 'A IA terminou sem conteúdo de seções — tente de novo (se repetir, me avise).' }
    end
    apply_result_to_page(page, result) if page && payload[:status] == 'done'
    write_status(job_id, page, payload)
  rescue StandardError => e
    Rails.logger.error "[Crm::PageGenerateJob] #{e.class}: #{e.message}"
    write_status(job_id, options['page_id'].present? ? CevicoPage.find_by(id: options['page_id']) : nil,
                 { status: 'error',
                   error: "Não consegui gerar agora (#{e.class.name.demodulize}). Tente de novo em instantes." })
  end

  private

  # resultado da IA vai DIRETO pra página (rascunho): a aba de montagem
  # recarrega e mostra pronta; slug/status/categoria ficam como estão
  def apply_result_to_page(page, result)
    page.update!(
      title: result[:title].presence || page.title,
      subtitle: result[:subtitle].to_s,
      emoji: result[:emoji].presence || page.emoji,
      meta_title: result[:meta_title].to_s,
      meta_description: result[:meta_description].to_s,
      cta_label: result[:cta_label].presence || page.cta_label,
      sections: CevicoPage.normalize_ai_sections(result[:sections])
    )
  end

  def write_status(job_id, page, payload)
    Redis::Alfred.setex(self.class.result_key(job_id), payload.to_json, RESULT_TTL)
    return if page.blank?

    Redis::Alfred.setex(self.class.page_key(page.id),
                        { status: payload[:status], error: payload[:error] }.compact.to_json, RESULT_TTL)
  end

  def run_service(account, options)
    if options['copy'].present?
      Crm::PageBuilderService.new(
        account: account, copy: options['copy'].to_s,
        category: options['category'].presence || 'captacao'
      ).call
    else
      form = options['form_id'].present? ? account.crm_forms.find_by(id: options['form_id']) : nil
      Crm::CopywriterService.new(
        account: account, briefing: options['briefing'].to_s,
        category: options['category'].presence || 'captacao', form: form
      ).call
    end
  end
end
