# ☀️ Gerador de proposta (LIFE, 11/11/2026): do consumo da conta de luz às opções de kit
# nos fornecedores (AVT, Bluesun), o DRE do orçamento e os dois documentos (proposta do
# cliente + justificativa), que ficam guardados no cliente (Crm::Quote).
# Nó de acesso: crm.cotador (ver = abrir a tela, ver os orçamentos guardados e saber se o botão
# da conversa libera; editar = cotar, gerar e marcar como enviada). Mexer nos acessos dos
# fornecedores é só do administrador.
class Api::V1::Accounts::Crm::KitQuotesController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  before_action :require_administrator!, only: [:update_access]

  DELIVERY_ERRORS = {
    sem_conversa: 'Este cliente não tem conversa no WhatsApp da Life (ou o modelo "orçamento pronto" não saiu).',
    sem_arquivos: 'Este orçamento não tem o PDF guardado: gere de novo com o gerador de PDF ligado.'
  }.freeze
  NO_RENDERER = 'O gerador de PDF ainda não está ligado neste servidor. Os números do orçamento estão prontos.'.freeze

  def show
    config = store.config
    render json: {
      acesso: store.status, cidade: "#{config['cidade']}/#{config['uf']}", max_opcoes: config['max_opcoes'],
      tarifa: config['tarifa'], telhados: Crm::KitQuote::ROOFS.map { |key, name| { chave: key, nome: name } },
      margem_padrao: Crm::KitQuote::Dre::STANDARD_MARGIN, faixa: [Crm::KitQuote::Dre::RANGE.begin, Crm::KitQuote::Dre::RANGE.end],
      gerador_pdf: Crm::KitQuote::Renderer.new(config).available?
    }
  end

  def create
    kwh = params[:consumo].to_s.tr(',', '.').to_f
    unless kwh.between?(30, 100_000)
      return render json: { error: 'Informe o consumo médio da conta de luz, em kWh por mês.' }, status: :unprocessable_entity
    end

    result = Crm::KitQuote::Engine.new(store.config, store.secrets, store)
                                  .run(kwh_month: kwh, grid: params[:rede].to_s, roof: params[:telhado].to_s)
    render json: result.merge('acesso' => store.status)
  end

  # DRE projetado de um kit: preço médio dos fornecedores com cotação completa + regras da planilha.
  # Sem `valor` nem `margem`, devolve o orçamento padrão (25% de lucro); com `margem`, o preço dessa
  # margem; com `valor`, recalcula com o preço ajustado na mão. `adequacao` = valor manual da adequação
  # (só quando a tabela não tem faixa para o projeto).
  def dre
    return render json: { error: 'Informe o preço do kit e a quantidade de placas.' }, status: :unprocessable_entity unless dre_ready?

    render json: dre_result
  rescue Crm::KitQuote::Dre::NoAdequacyBand => e
    render json: { error: e.message, precisa_adequacao: true }, status: :unprocessable_entity
  end

  # Os dois documentos do orçamento: os dados da proposta e da justificativa (sempre) e os PDFs
  # (quando o gerador de PDF está ligado neste servidor).
  def documents
    problem = documents_problem
    return render json: { error: problem }, status: :unprocessable_entity if problem

    render json: build_documents
  rescue Crm::KitQuote::Dre::NoAdequacyBand => e
    render json: { error: e.message, precisa_adequacao: true }, status: :unprocessable_entity
  end

  # 🔓 O botão "Gerar orçamento" da conversa já pode abrir para este cliente?
  def ready
    render json: Crm::KitQuote::Ready.new(Current.account, contact_from(params[:contact_id])).call
  end

  # 📚 Os orçamentos já gerados, do mais novo ao mais antigo: os deste cliente (contact_id) ou,
  # sem cliente, os da conta inteira (caixas "Orçamentos gerados" no topo do gerador).
  # lixeira=1: os excluídos (só o dono da conta vê). A resposta diz se a lixeira está disponível.
  def history
    trash = params[:lixeira] == '1'
    return render json: { error: 'Só o dono da conta vê a lixeira.' }, status: :forbidden if trash && !trash_access?

    scope = history_scope(trash)
    return render json: { orcamentos: [] } unless scope

    list = scope.recent.includes(:user, :contact, :deleted_by).with_attached_files.limit(params[:contact_id].present? ? 20 : 60)
    render json: { orcamentos: list.map { |quote| quote_json(quote) }, lixeira: trash_info }
  end

  # 🗑️ Manda o orçamento para a LIXEIRA (12/11): fica registrado quem excluiu, quando e o motivo; os PDFs
  # ficam guardados. Quem pode: o administrador ou quem gerou. Restaurar é só do dono da conta.
  def discard
    quote = Crm::Quote.ativos.find_by(account: Current.account, id: params[:id])
    return render json: { error: 'Orçamento não encontrado.' }, status: :not_found unless quote
    unless Current.account_user&.administrator? || quote.user_id == Current.user.id
      return render json: { error: 'Só o administrador ou quem gerou pode excluir este orçamento.' }, status: :forbidden
    end
    return render json: { error: 'Diga o motivo da exclusão.' }, status: :unprocessable_entity if params[:motivo].to_s.strip.blank?

    quote.trash!(Current.user, params[:motivo])
    render json: { ok: true, id: quote.id }
  end

  # ♻️ Volta da lixeira (só o dono da conta).
  def restore
    return render json: { error: 'Só o dono da conta restaura orçamentos.' }, status: :forbidden unless trash_access?

    quote = Crm::Quote.na_lixeira.find_by(account: Current.account, id: params[:id])
    return render json: { error: 'Orçamento não encontrado na lixeira.' }, status: :not_found unless quote

    quote.restore!
    render json: { orcamento: quote_json(quote) }
  end

  # 📨 Envia o orçamento pelo WhatsApp com a pergunta de fechamento (Crm::KitQuote::Delivery). Fora da janela de
  # 24 h, sai o modelo "orçamento pronto" e o atendente envia quando o cliente responder.
  def deliver
    quote = Crm::Quote.ativos.find_by(account: Current.account, id: params[:id])
    return render json: { error: 'Orçamento não encontrado.' }, status: :not_found unless quote

    result = Crm::KitQuote::Delivery.new(quote, sender: Current.user).call
    return render json: { error: DELIVERY_ERRORS[result] }, status: :unprocessable_entity if DELIVERY_ERRORS.key?(result)

    render json: { situacao: result.to_s, orcamento: quote_json(quote.reload) }
  end

  # 🏷️ A proposta foi enviada ao cliente: marca o orçamento e põe a etiqueta `orcamento-enviado`
  # (Crm::QuoteSent). A etiqueta leva o cartão para "Orçamento Enviado" e inicia o acompanhamento.
  def sent
    quote = Crm::Quote.find_by(account: Current.account, id: params[:id])
    return render json: { error: 'Orçamento não encontrado.' }, status: :not_found unless quote

    quote.update!(sent_at: Time.current) unless quote.sent?
    Crm::QuoteSent.call(quote.contact, value: quote.price)
    render json: { orcamento: quote_json(quote) }
  end

  # Guarda um acesso de fornecedor. Segredos entram e não voltam: a resposta é só o status.
  def update_access
    status = save_access
    return render json: { error: 'Nada para salvar.' }, status: :unprocessable_entity unless status

    render json: { acesso: status }
  rescue Crm::KitQuote::Invalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # ---------- DRE

  def dre_ready?
    dre_calculator.kit_cost.positive? && params[:placas].to_i.positive?
  end

  def dre_calculator
    @dre_calculator ||= Crm::KitQuote::Dre.new(
      kits: dre_kits, panels: params[:placas], type: params[:tipo].to_s,
      adequacy: params[:adequacao].present? ? money(params[:adequacao]) : nil, rules: params[:regras]&.to_unsafe_h
    )
  end

  def dre_result
    dre_calculator.result(money(params[:valor]), margin: params[:margem].to_s.tr(',', '.').to_f)
  end

  # Só entram na média as cotações completas (kit + estrutura + frete).
  def dre_kits
    quotes.select { |q| q['entra_na_media'] }
  end

  # As cotações do tipo escolhido: [{ fornecedor, valor, detalhe, entra_na_media }].
  # Sem a marcação, a cotação entra na média (é o caso da cotação digitada na mão).
  def quotes
    @quotes ||= Array(params[:kits]).map do |k|
      { 'fornecedor' => k[:fornecedor].to_s.squish.first(40), 'valor' => money(k[:valor]), 'detalhe' => k[:detalhe].to_s.squish.first(160),
        'entra_na_media' => k[:entra_na_media].nil? || ActiveModel::Type::Boolean.new.cast(k[:entra_na_media]) }
    end
  end

  # ---------- documentos

  def documents_problem
    return 'Escolha o cliente da proposta.' if client['nome'].blank?
    return 'Informe o valor da conta de luz de hoje.' unless bill['hoje'].positive?
    return 'Escolha uma opção de kit.' unless option['placas'].to_i.positive? && option['potencia_kwp'].to_f.positive?

    'Nenhum fornecedor tem cotação completa (kit + estrutura + frete). Acrescente uma cotação na mão.' unless dre_ready?
  end

  def build_documents
    dre = dre_result
    documents = Crm::KitQuote::Proposal.new(
      config: store.config, client: client, bill: bill, roof: params[:telhado].to_s, option: option, quotes: quotes, dre: dre
    ).call
    files = rendered(documents)
    saved = save_quote(documents, dre, files['arquivos'])
    # guardado no cliente: os PDFs abrem pela lista; a resposta não carrega o base64 de volta (fica leve)
    files = files.merge('arquivos' => []) if saved
    documents.merge('dre' => dre).merge(files).merge('orcamento' => saved && quote_json(saved))
  end

  # Guarda o orçamento no cliente (com os PDFs). Cliente digitado, fora da base, não tem onde guardar.
  def save_quote(documents, dre, files)
    contact = contact_from(client['contact_id'])
    return nil unless contact

    Crm::KitQuote::Save.call(
      account: Current.account, contact: contact, user: Current.user, documents: documents, dre: dre, floor: floor_price, files: files,
      input: { 'cliente' => client, 'conta' => bill, 'telhado' => params[:telhado].to_s, 'opcao' => option, 'cotacoes' => quotes }
    )
  end

  def contact_from(id)
    id.present? ? Current.account.contacts.find_by(id: id) : nil
  end

  def quote_json(quote)
    {
      id: quote.id, criado_em: quote.created_at.iso8601, por: quote.user&.name, tipo: quote.kind, valor: quote.price.to_f,
      margem: quote.margin.to_f, lucro: quote.payload.dig('dre', 'lucro'), na_faixa: quote.payload.dig('dre', 'na_faixa'),
      enviado_em: quote.sent_at&.iso8601, arquivos: quote_files(quote)
    }.merge(quote_extra(quote))
  end

  def quote_files(quote)
    quote.files.map { |file| { nome: file.filename.to_s, tipo: file.content_type, url: url_for(file) } }
  end

  # quem é o cliente e até quando a proposta vale (caixas "Orçamentos gerados")
  def quote_extra(quote)
    until_at = valid_until(quote)
    { cliente: { id: quote.contact_id, nome: quote.contact&.name.presence || quote.payload.dig('cliente', 'nome') },
      valida_ate: until_at.iso8601, valido: until_at.future?, piso: quote.payload['piso_negociacao'],
      aguardando_envio: quote.payload[Crm::KitQuote::Delivery::WAITING_KEY].present? }.merge(trash_json(quote))
  end

  # 🤝 piso de negociação: o preço com 20% de lucro (só para quem negocia; o atendente não vê)
  def floor_price
    { 'margem' => 0.2, 'valor' => dre_calculator.result(nil, margin: 0.2)['valor_projeto'] }
  rescue StandardError
    nil
  end

  # nil quando o cliente pedido não é desta conta
  def history_scope(trash)
    scope = Crm::Quote.where(account: Current.account)
    scope = trash ? scope.na_lixeira : scope.ativos
    return scope if params[:contact_id].blank?

    contact = contact_from(params[:contact_id])
    contact && scope.where(contact: contact)
  end

  def trash_json(quote)
    return {} unless quote.trashed?

    { excluido_em: quote.deleted_at.iso8601, excluido_por: quote.deleted_by&.name, motivo: quote.delete_reason }
  end

  # Lixeira: o dono da conta (owner_ids da tela de Acessos). Sem dono configurado, qualquer administrador.
  def trash_access?
    return false unless Current.account_user&.administrator?

    perms = CrmSetting.find_by(account: Current.account)&.agent_permissions || {}
    owners = Cevico::Access.owner_ids(perms)
    owners.empty? || owners.include?(Current.user.id.to_s)
  end

  def trash_info
    return { disponivel: false } unless trash_access?

    { disponivel: true, total: Crm::Quote.na_lixeira.where(account: Current.account).count }
  end

  # A proposta vale N dias (Crm::KitQuote::Proposal grava 'validade_dias'; padrão 7) até o fim do dia.
  def valid_until(quote)
    days = (quote.payload.dig('proposta', 'proposta', 'validade_dias') || quote.payload.dig('proposta', 'validade_dias')).to_i
    (quote.created_at.in_time_zone('America/Sao_Paulo') + (days.positive? ? days : 7).days).end_of_day
  end

  # Os PDFs, quando o gerador está ligado; senão (ou se ele falhar) o motivo, sem perder os números.
  def rendered(documents)
    renderer = Crm::KitQuote::Renderer.new(store.config)
    return { 'arquivos' => [], 'aviso' => NO_RENDERER } unless renderer.available?

    renderer.render(documents)
  rescue Crm::KitQuote::NoAccess => e
    { 'arquivos' => [], 'aviso' => e.message }
  end

  # O cliente vem da base quando a tela mandou o contato; o nome pode ser ajustado na tela.
  def client
    @client ||= begin
      given = params[:cliente]&.permit(:contact_id, :nome, :cidade, :uf).to_h
      contact = contact_from(given['contact_id'])
      { 'nome' => given['nome'].to_s.squish.presence || contact&.name.to_s, 'cidade' => given['cidade'].to_s.squish,
        'uf' => given['uf'].to_s.squish, 'contact_id' => contact&.id }
    end
  end

  def bill
    @bill ||= begin
      given = params[:conta] || {}
      additions = Array(given[:acrescimos]).map { |a| { 'rotulo' => a[:rotulo].to_s.squish.first(60), 'valor' => money(a[:valor]) } }
      { 'hoje' => money(given[:hoje]), 'acrescimos' => additions, 'consumo_kwh' => given[:consumo_kwh].to_s.tr(',', '.').to_f,
        'rede' => (given[:rede].presence || params[:rede]).to_s }
    end
  end

  def option
    @option ||= (params[:opcao]&.to_unsafe_h || {}).slice(
      'fornecedor', 'tipo', 'potencia_kwp', 'placas', 'paineis', 'inversor', 'preco', 'frete', 'total', 'completa', 'equipamento'
    )
  end

  # ---------- geral

  # Aceita número (12260.5) ou texto no formato brasileiro ("12.260,50").
  def money(value)
    return value.to_f if value.is_a?(Numeric)

    value.to_s.delete('.').tr(',', '.').to_f
  end

  def store
    @store ||= Crm::KitQuote::Store.new(Current.account)
  end

  def save_access
    given = params.permit(:fornecedor, :sessao, :avt_email, :avt_senha, :avt_token, :avt_id_cliente).to_h.compact_blank
    return store.save_session!(given['fornecedor'].to_s, given['sessao']) if given['sessao']
    return store.save_avt_login!(given['avt_email'], given['avt_senha']) if given['avt_senha']
    return store.save_avt_token!(given['avt_token']) if given['avt_token']

    store.save_avt_client!(given['avt_id_cliente']) if given['avt_id_cliente']
  end
end
