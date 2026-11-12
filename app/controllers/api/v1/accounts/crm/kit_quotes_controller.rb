# ☀️ Gerador de proposta (LIFE, 11/11/2026): do consumo da conta de luz às opções de kit
# nos fornecedores (AVT, Bluesun), o DRE do orçamento e os dois documentos (proposta do
# cliente + justificativa), que ficam guardados no cliente (Crm::Quote).
# Nó de acesso: crm.cotador (ver = abrir a tela, ver os orçamentos guardados e saber se o botão
# da conversa libera; editar = cotar, gerar e marcar como enviada). Mexer nos acessos dos
# fornecedores é só do administrador.
class Api::V1::Accounts::Crm::KitQuotesController < Api::V1::Accounts::BaseController
  before_action :require_administrator!, only: [:update_access]

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

  # 📚 Os orçamentos já gerados para este cliente, do mais novo ao mais antigo.
  def history
    contact = contact_from(params[:contact_id])
    list = contact ? Crm::Quote.where(account: Current.account, contact: contact).recent.includes(:user).with_attached_files.limit(20) : []
    render json: { orcamentos: list.map { |quote| quote_json(quote) } }
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
    documents.merge('dre' => dre).merge(files).merge('orcamento' => saved && quote_json(saved))
  end

  # Guarda o orçamento no cliente (com os PDFs). Cliente digitado, fora da base, não tem onde guardar.
  def save_quote(documents, dre, files)
    contact = contact_from(client['contact_id'])
    return nil unless contact

    quote = Crm::Quote.create!(
      account: Current.account, contact: contact, user: Current.user, kind: dre['tipo'], price: dre['valor_projeto'], margin: dre['margem'],
      payload: documents.merge('dre' => dre, 'cliente' => client, 'conta' => bill, 'telhado' => params[:telhado].to_s,
                               'opcao' => option, 'cotacoes' => quotes)
    )
    quote.attach_rendered(files)
    quote
  end

  def contact_from(id)
    id.present? ? Current.account.contacts.find_by(id: id) : nil
  end

  def quote_json(quote)
    {
      id: quote.id, criado_em: quote.created_at.iso8601, por: quote.user&.name, tipo: quote.kind, valor: quote.price.to_f,
      margem: quote.margin.to_f, lucro: quote.payload.dig('dre', 'lucro'), na_faixa: quote.payload.dig('dre', 'na_faixa'),
      enviado_em: quote.sent_at&.iso8601,
      arquivos: quote.files.map { |file| { nome: file.filename.to_s, tipo: file.content_type, url: url_for(file) } }
    }
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
      { 'hoje' => money(given[:hoje]), 'acrescimos' => additions, 'consumo_kwh' => given[:consumo_kwh].to_s.tr(',', '.').to_f }
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
