# 📞 Chamadas nativas de WhatsApp (item 167): coloca o desvio das ligações
# na frente do job de webhooks do WhatsApp. "zz_" para carregar por último;
# to_prepare refaz o prepend a cada reload em desenvolvimento.
Rails.application.config.to_prepare do
  Webhooks::WhatsappEventsJob.prepend(Cevico::WhatsappCallsWebhook)
end
