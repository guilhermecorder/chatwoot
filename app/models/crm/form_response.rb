# Resposta de um paciente a um Crm::Form. `answers` guarda um snapshot
# de cada pergunta com o valor respondido (o formulário pode mudar depois
# sem desalinhar respostas antigas):
#   [{ "id" => "q1", "label" => "...", "type" => "choice", "value" => "..." }]
# == Schema Information
#
# Table name: crm_form_responses
#
#  id           :bigint           not null, primary key
#  answers      :jsonb            not null
#  completed_at :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  contact_id   :bigint
#  crm_form_id  :bigint           not null
#
# Indexes
#
#  index_crm_form_responses_on_account_id   (account_id)
#  index_crm_form_responses_on_contact_id   (contact_id)
#  index_crm_form_responses_on_crm_form_id  (crm_form_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (crm_form_id => crm_forms.id)
#
class Crm::FormResponse < ApplicationRecord
  self.table_name = 'crm_form_responses'

  belongs_to :form, class_name: 'Crm::Form', foreign_key: :crm_form_id
  belongs_to :account
  belongs_to :contact, class_name: '::Contact', optional: true

  # 🔐 Auditoria 10/2026 (achado #118, paliativo sem migration): resposta que
  # veio pelo LINK LIMPO (sem token) e caiu num cadastro que JÁ EXISTIA foi
  # identificada só por nome + WhatsApp digitados — ninguém provou que é o
  # dono do telefone. A marca fica dentro do próprio `answers`, num item
  # especial (id '_cevico', type 'meta') que nenhuma tela mostra como resposta:
  #   { "id" => "_cevico", "type" => "meta", "verified" => false,
  #     "via" => "link_limpo", "informed_name" => "nome que a pessoa digitou" }
  META_ID = '_cevico'.freeze

  # 🔐 Rodada 4 (achado #119): de onde veio a marca
  #   'link_limpo'    = cadastro que já existia; aguarda o código do WhatsApp
  #   'cadastro_novo' = telefone desconhecido; paciente criado SEM card
  #   'codigo'        = o paciente digitou o código certo → confirmada
  VIA_CLEAN_LINK = 'link_limpo'.freeze
  VIA_NEW_CONTACT = 'cadastro_novo'.freeze
  VIA_CODE = 'codigo'.freeze

  # informed_phone: só quando o teto diário de cadastros novos estourou e a
  # resposta ficou SEM paciente — o telefone digitado fica na marca para a
  # equipe conseguir falar com a pessoa
  def self.unverified_meta(informed_name: nil, via: VIA_CLEAN_LINK, informed_phone: nil)
    { 'id' => META_ID, 'type' => 'meta', 'verified' => false, 'via' => via,
      'informed_name' => informed_name.to_s.strip[0, 120].presence,
      'informed_phone' => informed_phone.to_s.gsub(/\D/, '')[0, 13].presence }.compact
  end

  def meta
    Array(answers).find { |a| a.is_a?(Hash) && a['id'] == META_ID } || {}
  end

  # resposta do link limpo em cadastro existente que ainda não foi confirmada
  # pelo código (só essas recebem/validam código)
  def awaiting_code?
    !verified? && meta['via'] == VIA_CLEAN_LINK
  end

  # o paciente digitou o código certo: a marca vira "confirmada" (fica o
  # registro de que foi pelo código e o nome digitado)
  def confirm_by_code!
    confirmed = meta.merge('verified' => true, 'via' => VIA_CODE, 'confirmed_at' => Time.current.iso8601)
    update!(answers: answer_items + [confirmed])
  end

  # false só quando a marca diz isso de forma explícita; link assinado e
  # respostas antigas continuam confirmadas
  def verified?
    meta['verified'] != false
  end

  # só as respostas de verdade (sem o item de marca)
  def answer_items
    Array(answers).reject { |a| a.is_a?(Hash) && a['id'] == META_ID }
  end
end
