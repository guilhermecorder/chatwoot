# 🚦 SAÚDE DO WHATSAPP (16/10/2026): nota e limites de cada número, modelos,
# quem não quer mais receber (CERTO × SUSPEITA, com o motivo) e o que veio
# antes do silêncio. Ver: relatorios.whatsapp_saude; mexer (chavinhas,
# tirar/confirmar marcação, conferir agora): editar.
class Api::V1::Accounts::Crm::WhatsappHealthsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  def show
    render json: Crm::WhatsappHealthReport.new(account: Current.account).call
  end

  # POST /crm/whatsapp_health/settings — { robos: { certo_sem_marketing: true, … }, horas, presas }
  def settings
    permitted = params.permit(:horas, :presas, robos: Crm::StopSignals::ROBOT_DEFAULTS.keys)
    render json: { rules: Crm::StopSignals.save_settings!(Current.account, permitted.to_h) }
  end

  # POST /crm/whatsapp_health/unmark — { contact_id, key } — "não é isso":
  # tira a etiqueta e a varredura não remarca pelo mesmo sinal
  def unmark
    contact = Current.account.contacts.find(params[:contact_id])
    ok = Crm::StopSignals.unmark!(contact, params[:key].to_s, motivo: 'tirada à mão na tela Saúde do WhatsApp',
                                                              by: Current.user, dismiss: true)
    render json: { ok: ok }
  end

  # POST /crm/whatsapp_health/confirm — { contact_id, key } — a equipe conferiu
  # a suspeita e é pedido de parar mesmo: vira nao_perturbe (certo)
  def confirm
    contact = Current.account.contacts.find(params[:contact_id])
    key = params[:key].to_s
    proof = (Crm::StopSignals.evidence(contact)[key] || {}).merge('confirmado_por' => Current.user&.name, 'confirmado_de' => key)
    Crm::StopSignals.add_label!(contact, Crm::OptOut::LABEL) unless contact.label_list.include?(Crm::OptOut::LABEL)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      signals = (attrs[Crm::StopSignals::ATTR_KEY] || {}).to_h
      signals[Crm::OptOut::LABEL] = proof.merge('at' => Time.current.iso8601)
      attrs.merge(Crm::StopSignals::ATTR_KEY => signals)
    end
    if key != Crm::OptOut::LABEL
      Crm::StopSignals.unmark!(contact, key, motivo: 'confirmada como pedido de parar (virou nao_perturbe)',
                                             by: Current.user)
    end
    render json: { ok: true }
  end

  # POST /crm/whatsapp_health/scan — roda a varredura agora (fila)
  def scan
    Crm::WhatsappHealthJob.perform_later(Current.account.id)
    render json: { ok: true, queued: true }
  end
end
