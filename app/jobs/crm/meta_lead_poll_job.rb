# 🔄 08/11 (LIFE): busca os leads novos dos formulários do Meta a cada 5
# minutos, para toda conta com página + token de página. É a garantia de que
# o lead chega mesmo sem o webhook (app do Meta ainda em desenvolvimento, aviso
# perdido…). Olha as últimas 2 horas: o que o webhook já trouxe conta como
# duplicado e não entra de novo (nem recebe outra boas-vindas).
class Crm::MetaLeadPollJob < ApplicationJob
  queue_as :low

  WINDOW = 2.hours

  def perform
    CrmSetting.where("meta_ads_config ->> 'page_id' <> ''")
              .where("meta_ads_config ->> 'page_access_token' <> ''")
              .where("COALESCE(meta_ads_config ->> 'lead_poll', 'true') <> 'false'")
              .pluck(:account_id).each do |account_id|
      Crm::MetaLeadImportJob.perform_later(account_id, WINDOW.ago.to_i)
    end
  end
end
