require 'rails_helper'

# 🔐 Auditoria rodada 2 (Páginas): a IA em segundo plano não reescreve uma
# página que foi PUBLICADA enquanto ela trabalhava — a geração começou num
# rascunho, mas o site já está no ar quando o resultado chega.
RSpec.describe Crm::PageGenerateJob do
  let(:account) { create(:account) }
  let(:page) do
    CevicoPage.create!(account: account, title: 'Antes', slug: 'rascunho-ia', status: 'draft',
                       sections: [], ab_variants: [], team_comments: [], daily_stats: {})
  end
  let(:ai_result) do
    { title: 'Depois', subtitle: 'novo', sections: [{ type: 'hero', title: 'Oi', text: 'texto' }] }
  end

  def status_of(page)
    Crm::PageGenerateJob.page_status(page.id)
  end

  describe 'geração em segundo plano' do
    before do
      allow(Crm::CopywriterService).to receive(:new).and_return(instance_double(Crm::CopywriterService, call: ai_result))
    end

    it 'aplica o resultado no rascunho' do
      described_class.perform_now(account.id, 'job1', 'briefing' => 'x', 'page_id' => page.id)
      expect(page.reload.title).to eq('Depois')
      expect(status_of(page)['status']).to eq('done')
    end

    it 'não grava se a página foi publicada no meio do caminho', :aggregate_failures do
      allow(Crm::CopywriterService).to receive(:new) do
        page.update!(status: 'published') # o admin publicou enquanto a IA trabalhava
        instance_double(Crm::CopywriterService, call: ai_result)
      end

      described_class.perform_now(account.id, 'job2', 'briefing' => 'x', 'page_id' => page.id)
      expect(page.reload.title).to eq('Antes')
      expect(status_of(page)).to include('status' => 'error')
      expect(status_of(page)['error']).to include('publicada enquanto a IA trabalhava')
    end

    it 'admin que pediu a IA numa página JÁ publicada continua sendo atendido' do
      page.update!(status: 'published')
      described_class.perform_now(account.id, 'job3', 'briefing' => 'x', 'page_id' => page.id, 'allow_published' => true)
      expect(page.reload.title).to eq('Depois')
    end
  end

  describe Crm::PageEditJob do
    it 'chat do construtor não reescreve página publicada no meio do caminho', :aggregate_failures do
      allow(Crm::PageEditorService).to receive(:new) do
        page.update!(status: 'published')
        instance_double(Crm::PageEditorService,
                        call: { title: 'Depois', sections: [{ type: 'hero', title: 'Oi', text: 'texto' }], reply: 'feito' })
      end

      described_class.perform_now(account.id, page.id, 'troque o título')
      expect(page.reload.title).to eq('Antes')
      expect(status_of(page)).to include('status' => 'error')
    end
  end
end
