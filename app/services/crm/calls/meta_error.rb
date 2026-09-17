# Erro devolvido pela Graph API nas ligações — mensagem crua da Meta (para o
# Henrique ler) + código, para o controller montar o texto humano.
class Crm::Calls::MetaError < StandardError
  attr_reader :code

  def initialize(message = 'A Meta não respondeu como esperado.', code = nil)
    @code = code
    super(message)
  end
end
