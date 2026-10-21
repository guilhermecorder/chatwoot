# Erro devolvido pela API da ElevenLabs — mensagem crua (para o Henrique
# ler na tela), status HTTP e o corpo da resposta, para o log da sincronização.
class Crm::VoiceAgent::Error < StandardError
  attr_reader :status, :body

  def initialize(message = 'A ElevenLabs não respondeu como esperado.', status = nil, body = nil)
    @status = status
    @body = body
    super(message)
  end
end
