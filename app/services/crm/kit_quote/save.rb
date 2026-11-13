# 💾 Guarda o orçamento no cliente (Crm::Quote + PDFs) e atualiza cartão e ficha (Crm::KitQuote::CardUpdate).
# Usado pelo Gerador de proposta (KitQuotesController#documents) e pelo orçamento automático (Crm::KitQuote::AutoBuild).
class Crm::KitQuote::Save
  def self.call(**args)
    new(**args).call
  end

  def initialize(account:, contact:, user:, documents:, dre:, input:, floor:, files:) # rubocop:disable Metrics/ParameterLists
    @account = account
    @contact = contact
    @user = user
    @documents = documents
    @dre = dre
    @input = input # { 'cliente', 'conta', 'telhado', 'opcao', 'cotacoes' } + extras (ex.: 'automatico')
    @floor = floor
    @files = files
  end

  def call
    return nil unless @contact

    quote = Crm::Quote.create!(
      account: @account, contact: @contact, user: @user, kind: @dre['tipo'], price: @dre['valor_projeto'], margin: @dre['margem'],
      payload: @documents.merge('dre' => @dre, 'piso_negociacao' => @floor).merge(@input)
    )
    quote.attach_rendered(@files)
    Crm::KitQuote::CardUpdate.call(quote)
    quote
  end
end
