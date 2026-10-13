# 🔒 Rodada 6 da auditoria (#210/#227/#270): dados da CEVICO pendurados no
# paciente (Contact) e o que acontece com cada um quando o paciente é APAGADO
# (botão Excluir contato / pedido de exclusão da LGPD). Antes só o card tinha
# regra (e em segundo plano), e o banco barrava a exclusão com erro 500.
# A migration 20261013010000 põe a MESMA regra nas chaves do banco.
#   - apaga junto (dado do paciente): card do funil, anotações clínicas (com
#     as fotos), respostas de formulário, participação em campanha e links de
#     página. O histórico de colunas do card fica (não tem dado pessoal).
#   - mantém sem paciente: consultas/tarefas da Agenda e cirurgias do hub (o
#     horário não pode sumir da agenda).
# Mesclar duplicados NÃO passa por aqui: o Cevico::ContactMergeRecords leva
# tudo para o contato que fica ANTES de apagar o duplicado.
module CevicoContactData
  extend ActiveSupport::Concern

  included do
    # cards do CRM CEVICO deste contato (1 por funil, na prática 1)
    has_many :crm_contacts, class_name: 'Crm::Contact', dependent: :destroy
    has_many :crm_clinical_notes, class_name: 'Crm::ClinicalNote', dependent: :destroy
    has_many :crm_form_responses, class_name: 'Crm::FormResponse', dependent: :delete_all
    has_many :crm_campaign_contacts, class_name: 'Crm::CampaignContact', dependent: :delete_all
    has_many :cevico_page_refs, class_name: 'CevicoPageRef', dependent: :delete_all
    has_many :tasks, dependent: :nullify
    has_many :crm_oftalmofacil_surgeries, class_name: 'Crm::OftalmofacilSurgery', dependent: :nullify
  end
end
