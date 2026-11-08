require 'rails_helper'

# ⏰ 08/11/2026 (LIFE): tarefa com DIA E HORA ("daqui a 3, 4 dias eu te chamo")
RSpec.describe Crm::HandoffTask do
  let(:account) { create(:account) }
  let!(:fernando) { create(:user, account: account, role: :administrator, name: 'Fernando Srair') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Marcos Silva', phone_number: '+5519999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tz) { Crm::HandoffTask::TZ }
  let(:retorno_at) { (tz.now + 3.days).change(hour: 9, min: 0) }

  before do
    create(:user, account: account, role: :administrator, name: 'Guilherme')
    CrmSetting.find_or_create_by!(account: account)
              .update!(ai_config: { 'agents' => { 'atendente_agendamento' => { 'task_assignee_id' => fernando.id } } })
  end

  def abrir(motivo, due_at: nil)
    Crm::HandoffTask.open!(account: account, contact: contact, conversation: conversation, agent_key: 'atendente_agendamento',
                           motivo: motivo, detalhes: 'onde: casa · conta R$ 700 · telhado 2', due_at: due_at)
  end

  it 'nasce SEPARADA da tarefa de hoje, com o prazo, para o responsável do card, e agenda o aviso do dia', :aggregate_failures do
    hoje = abrir('Orçamento: conta recebida')[:task]
    retorno = nil
    expect { retorno = abrir('Retorno: chamar em 3 a 4 dias (cliente vai pensar)', due_at: retorno_at)[:task] }
      .to have_enqueued_job(Crm::TaskDueAlertJob).with(kind_of(Integer), conversation.id).at(retorno_at)
    expect(retorno.id).not_to eq(hoje.id)
    expect(retorno.due_at).to eq(retorno_at)
    expect(retorno.assignee).to eq(fernando)
    expect(retorno.title).to eq('⏰ Marcos Silva — Retorno: chamar em 3 a 4 dias (cliente vai pensar)')
  end

  it 'uma tarefa normal depois não cai dentro da tarefa com data futura (nem o contrário no mesmo dia)', :aggregate_failures do
    retorno = abrir('Retorno: chamar em 3 a 4 dias', due_at: retorno_at)[:task]
    hoje = abrir('Cliente com pressa no orçamento')[:task]
    expect(hoje.id).not_to eq(retorno.id)
    again = abrir('Retorno: lembrar da esposa', due_at: retorno_at + 1.hour)
    expect(again[:created]).to be(false)
    expect(again[:task].id).to eq(retorno.id)
  end

  describe Crm::TaskDueAlertJob do
    it 'no dia: aviso no Radar do responsável; feita ou cancelada: nada', :aggregate_failures do
      retorno = abrir('Retorno: chamar em 3 a 4 dias', due_at: retorno_at)[:task]
      travel_to(retorno_at + 1.minute) do
        described_class.perform_now(retorno.id, conversation.id)
      end
      alert = CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts').last
      expect(alert).to include('kind' => 'tarefa_no_prazo', 'task_id' => retorno.id, 'user_id' => fernando.id,
                               'conversation_id' => conversation.display_id, 'acao' => 'Chamar o cliente agora')
      expect(alert['motivo']).to include('Hoje é o dia', 'Marcos Silva')

      retorno.update!(status: :done)
      CrmSetting.find_by(account: account).update!(ai_config: {})
      described_class.perform_now(retorno.id, conversation.id)
      expect(CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts')).to be_nil
    end

    it 'data mudada na tela: agenda o aviso para o prazo novo (e acha a conversa do contato)', :aggregate_failures do
      retorno = abrir('Retorno', due_at: retorno_at)[:task]
      novo = retorno_at + 2.days
      expect { retorno.update!(due_at: novo) }.to have_enqueued_job(described_class).with(retorno.id, nil).at(novo)
      travel_to(novo + 1.minute) { described_class.perform_now(retorno.id, nil) }
      alert = CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts').last
      expect(alert).to include('kind' => 'tarefa_no_prazo', 'conversation_id' => conversation.display_id)
    end

    it 'prazo mudado para depois: não avisa antes da hora' do
      retorno = abrir('Retorno', due_at: retorno_at)[:task]
      retorno.update!(due_at: retorno_at + 2.days)
      travel_to(retorno_at + 1.minute) { described_class.perform_now(retorno.id, conversation.id) }
      expect(CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts')).to be_nil
    end
  end
end
