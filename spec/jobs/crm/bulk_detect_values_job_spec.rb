require 'rails_helper'

# 💰 Auditoria 12/10 — Rodada 2 (achado #0): a varredura de valores em lote
# grava sem callbacks — não dispara "valor adicionado" em massa — e, no modo
# padrão (só vazios), não encosta em valor já preenchido.
RSpec.describe Crm::BulkDetectValuesJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil CEVICO') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Novos Contatos', position: 0) }
  let!(:vazio) { Crm::Contact.create!(contact: create(:contact, account: account), pipeline: pipeline, stage: stage) }
  let!(:preenchido) { Crm::Contact.create!(contact: create(:contact, account: account), pipeline: pipeline, stage: stage, value: 5000) }

  before do
    # automação "valor adicionado" na coluna — num lote ela NÃO pode disparar
    Crm::Automation.create!(stage: stage, name: 'orçamento → evento', trigger_type: 'value_added',
                            action_type: 'webhook', action_config: { 'url' => 'https://exemplo.test' })
    extractor = instance_double(Crm::BudgetValueExtractor, max_value: BigDecimal(7900))
    allow(Crm::BudgetValueExtractor).to receive(:new).and_return(extractor)
  end

  it 'preenche só os cards sem valor e não dispara a automação de valor adicionado', :aggregate_failures do
    expect do
      described_class.perform_now(pipeline.id, true)
    end.not_to have_enqueued_job(CrmAutomationFireJob)

    expect(vazio.reload.value.to_f).to eq(7900.0)
    expect(preenchido.reload.value.to_f).to eq(5000.0)
  end

  it 'só sobrescreve valor preenchido quando o admin pediu de propósito (only_empty=false), ainda sem automação', :aggregate_failures do
    expect do
      described_class.perform_now(pipeline.id, false)
    end.not_to have_enqueued_job(CrmAutomationFireJob)

    expect(preenchido.reload.value.to_f).to eq(7900.0)
  end

  it 'o caminho normal (card a card, pela ficha) continua disparando a automação' do
    expect do
      vazio.update!(value: 7900)
    end.to have_enqueued_job(CrmAutomationFireJob)
  end
end
