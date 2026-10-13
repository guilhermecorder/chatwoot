require 'rails_helper'

# 🏷️ Auditoria 10/2026 (#228): o contato é a "hierarquia maior" das etiquetas.
# A etiqueta posta na conversa por QUALQUER caminho (tela, automação nativa do
# Chatwoot, macro, ação em massa) sobe ao contato — e por isso 'nao_perturbe' /
# 'perda_*' passam a valer para campanha, régua e opt-out, que leem o CONTATO.
RSpec.describe Conversation do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  it 'etiqueta posta pela tela (update_labels) continua subindo ao contato' do
    conversation.update_labels(%w[agendou])
    expect(contact.reload.label_list).to include('agendou')
  end

  it 'etiqueta posta por add_labels (caminho da automação nativa, macro e ação em massa) sobe ao contato' do
    conversation.add_labels(%w[nao_perturbe])
    expect(contact.reload.label_list).to include('nao_perturbe')
  end

  it 'automação nativa add_label → contato etiquetado e fora das mensagens ativas (opt-out)', :aggregate_failures do
    rule = create(:automation_rule, account: account,
                                    actions: [{ action_name: 'add_label', action_params: ['nao_perturbe'] }])

    AutomationRules::ActionService.new(rule, account, conversation).perform

    expect(conversation.reload.label_list).to include('nao_perturbe')
    expect(contact.reload.label_list).to include('nao_perturbe')
    expect(Crm::OptOut.excluded_contact_ids(account)).to include(contact.id)
  end

  it 'remover etiqueta por update(label_list:) (ação em massa) tira do contato quando nenhuma outra conversa a tem' do
    conversation.add_labels(%w[perda_preco])
    expect(contact.reload.label_list).to include('perda_preco')

    conversation.update(label_list: conversation.label_list - ['perda_preco'])
    expect(contact.reload.label_list).not_to include('perda_preco')
  end

  it 'na remoção, mantém no contato a etiqueta que outra conversa do mesmo paciente ainda tem' do
    other_inbox = create(:inbox, account: account)
    sibling = create(:conversation, account: account, inbox: other_inbox, contact: contact)
    sibling.add_labels(%w[perda_preco])
    conversation.add_labels(%w[perda_preco])

    conversation.update(label_list: [])
    expect(contact.reload.label_list).to include('perda_preco')
  end

  it 'conversa que nasce com etiqueta também sobe ao contato' do
    create(:conversation, account: account, inbox: inbox, contact: contact, label_list: %w[oftalmofacil])
    expect(contact.reload.label_list).to include('oftalmofacil')
  end

  it 'cadastro antigo que não passa na validação: a etiqueta da CONVERSA fica, o contato não sobe e nada estoura', :aggregate_failures do
    contact.update_column(:email, 'email-invalido') # rubocop:disable Rails/SkipsModelValidations
    allow(Rails.logger).to receive(:error).and_call_original

    expect { conversation.add_labels(%w[nao_perturbe]) }.not_to raise_error
    expect(conversation.reload.label_list).to include('nao_perturbe')
    expect(contact.reload.label_list).not_to include('nao_perturbe')
    expect(Rails.logger).to have_received(:error).with(/etiqueta não subiu ao contato #{contact.id}/)
  end
end
