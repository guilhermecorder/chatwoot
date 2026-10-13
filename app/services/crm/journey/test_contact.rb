# 🧪 Para quem vai o botão "Testar no meu número" da jornada — auditoria R3
# (#416). Regras, do lado mais seguro para o paciente:
# - número já marcado como celular de teste DESTA pessoa → vai;
# - número com rastro de paciente (consulta na Agenda, card no funil,
#   cirurgia do hub) → NUNCA (erro de digitação não pode mandar teste a paciente);
# - número novo, ou contato sem rastro, → só com a caixinha "este celular é
#   meu" marcada (own_phone); daí o contato fica marcado como celular de teste
#   da pessoa e não precisa confirmar de novo.
# O contato de teste nasce nomeado ("Teste da jornada · Fulano") e marcado,
# um por pessoa — não é um "paciente fantasma" por número digitado.
#
# O contato de teste NÃO é paciente: quem lê a marca (`test_contact?`) sai
# cedo — CrmListener (não ganha card no funil nem carimbo de origem),
# Crm::Stamp, Atendente IA (ResponderAgentJob) e o universo de leads
# (Crm::LeadsUniverse). Ele também recebe a etiqueta `nao_perturbe`, que
# campanhas, régua, NPS e robôs de follow-up já respeitam. O envio de teste
# da jornada ignora essa etiqueta de propósito (Dispatcher#quiet_blocker).
class Crm::Journey::TestContact
  # marca no contato: "este é o celular de teste da pessoa <user_id>"
  KEY = 'cevico_jornada_teste_user_id'.freeze

  # é o celular de teste de alguém da equipe? (lido por listener, IA, leads)
  def self.test_contact?(contact)
    contact.present? && (contact.additional_attributes || {})[KEY].present?
  end

  def initialize(account:, user:, phone:, own_phone: false)
    @account = account
    @user = user
    @phone = phone.to_s.delete('^0-9')
    @own_phone = ActiveModel::Type::Boolean.new.cast(own_phone) == true
  end

  # [contato, nil] quando pode testar; [nil, motivo] quando não
  def resolve
    existing = Task.match_contact(@account, @phone)
    return [existing, nil] if existing && mine?(existing)
    if existing && patient?(existing)
      return [nil, "Esse número é de #{existing.name} (paciente cadastrado). O teste só vai para o seu próprio celular."]
    end
    return [nil, 'Marque "este celular é meu" para testar — o teste nunca vai para o celular de um paciente.'] unless @own_phone

    [existing ? mark!(existing) : create!, nil]
  end

  private

  def mine?(contact)
    (contact.additional_attributes || {})[KEY].to_s == @user.id.to_s
  end

  # tem rastro de paciente: consulta na Agenda, card no funil ou cirurgia do hub
  def patient?(contact)
    @account.tasks.exists?(contact_id: contact.id) ||
      Crm::Contact.exists?(contact_id: contact.id) ||
      Crm::OftalmofacilSurgery.exists?(account: @account, contact_id: contact.id)
  end

  def mark!(contact)
    Cevico::AttributeMerge.merge!(contact) { |attrs| attrs.merge(KEY => @user.id) }
    silence!(contact)
  end

  def create!
    contact = @account.contacts.create!(name: "Teste da jornada · #{@user.available_name}", phone_number: "+#{@phone}",
                                        additional_attributes: { KEY => @user.id })
    silence!(contact)
  end

  # etiqueta nao_perturbe: campanhas, régua, NPS e follow-up nunca mandam nada
  # para o celular de teste (o teste da jornada em si ignora a etiqueta)
  def silence!(contact)
    Crm::OptOut.apply!(contact)
    contact
  end
end
