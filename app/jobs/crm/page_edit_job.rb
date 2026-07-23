# Item 112 Fase 1: aplica uma instrução do CHAT DO CONSTRUTOR na página
# de rascunho, em segundo plano. A aba do Ambiente de Montagem acompanha
# pelo MESMO status por página do PageGenerateJob (running/done/error) e
# recarrega quando fica pronta; a resposta do agente ("reply") vai junto.
class Crm::PageEditJob < ApplicationJob
  queue_as :default

  def perform(account_id, page_id, instruction)
    account = Account.find_by(id: account_id)
    page = account&.cevico_pages&.find_by(id: page_id)
    return if page.blank?

    result = Crm::PageEditorService.new(account: account, page: page, instruction: instruction.to_s).call
    result = result.to_h.deep_stringify_keys
    if result['error'].present?
      return write_status(page, { status: 'error', error: result['error'] })
    end

    sections = CevicoPage.normalize_ai_sections(result['sections'])
    if sections.empty?
      return write_status(page, { status: 'error', error: 'A correção voltou sem seções — nada foi alterado. Tente reformular o pedido.' })
    end

    page.update!(
      title: result['title'].presence || page.title,
      subtitle: result['subtitle'].to_s,
      emoji: result['emoji'].presence || page.emoji,
      meta_title: result['meta_title'].to_s,
      meta_description: result['meta_description'].to_s,
      cta_label: result['cta_label'].presence || page.cta_label,
      sections: sections
    )
    write_status(page, { status: 'done', reply: result['reply'].to_s[0, 1200] })
  rescue StandardError => e
    Rails.logger.error "[Crm::PageEditJob] #{e.class}: #{e.message}"
    page = CevicoPage.find_by(id: page_id)
    write_status(page, { status: 'error', error: "Não consegui aplicar (#{e.class.name.demodulize}). Tente de novo." }) if page
  end

  private

  def write_status(page, payload)
    Redis::Alfred.setex(Crm::PageGenerateJob.page_key(page.id), payload.compact.to_json, Crm::PageGenerateJob::RESULT_TTL)
  end
end
