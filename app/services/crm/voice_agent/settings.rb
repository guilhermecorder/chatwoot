# 🤖📞 Agente de Ligação (item 169): leitor de ai_config['voice'] com defaults.
# (esqueleto — construído no contrato docs/AGENTE_LIGACAO.md §3)
class Crm::VoiceAgent::Settings
  attr_reader :account

  def initialize(account, crm_settings: nil)
    @account = account
    @crm_settings = crm_settings
  end

  def to_h
    {}
  end
end
