# Fonte leve para o Crm::SendTemplateService quando não há Campanha/Régua
# de verdade por trás (lembretes, automações de coluna, assistente virtual,
# mensagens da jornada). Uma só definição — antes eram 4 cópias do Struct.
Crm::TemplateSource = Struct.new(:account, :inbox, :sender, :template_params, :message_preview, :name) do
  def account_id = account.id
  def inbox_id = inbox.id
end
