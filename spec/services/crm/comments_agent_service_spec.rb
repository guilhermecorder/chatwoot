require 'rails_helper'

# 💬 auditoria 10/2026 (#117): o Respondedor de Comentários não pode responder
# de novo em público o mesmo comentário — a memória de "já respondi" fica
# enquanto o comentário ainda aparece nos posts olhados, comentário de antes
# da última rodada não vai para a IA e, antes de falar, confere se a Página
# já respondeu aquele comentário.
RSpec.describe Crm::CommentsAgentService do
  let(:account) { create(:account) }
  let(:ig_id) { '1789' }
  let(:handled) { {} }
  let(:last_run_at) { 2.hours.ago.iso8601 }
  let(:comments) { [] }   # comentários do post, no formato que a Meta devolve
  let(:replies) { [] }    # respostas já existentes de cada comentário
  let(:verdict) { { 'responder' => true, 'resposta' => 'Que bom que gostou! Te chamamos no privado 💙', 'chamar_humano' => false } }
  let(:posted) { [] }
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: {
                         'api_key' => 'sk-teste',
                         'agents' => { 'comments' => { 'enabled' => true, 'page_access_token' => 'tok', 'ig_user_id' => ig_id } },
                         'comments_state' => { 'handled' => handled, 'events' => [], 'last_run_at' => last_run_at }
                       })
  end
  let(:service) { described_class.new(account) }

  def ig_comment(id, text, at)
    { 'id' => id, 'text' => text, 'username' => 'fulana', 'timestamp' => at.utc.strftime('%Y-%m-%dT%H:%M:%S+0000') }
  end

  before do
    stub_const('Crm::CommentsAgentService::BUSINESS_HOURS', (0...24)) # o teste roda a qualquer hora
    allow(HTTParty).to receive(:get) do |url, _opts|
      data = if url.end_with?("/#{ig_id}/media") then [{ 'id' => 'post1', 'caption' => 'Livre dos óculos' }]
             elsif url.end_with?('/post1/comments') then comments
             elsif url.end_with?('/replies') then replies
             else
               []
             end
      instance_double(HTTParty::Response, parsed_response: { 'data' => data })
    end
    allow(HTTParty).to receive(:post) do |url, _opts|
      posted << url
      instance_double(HTTParty::Response, success?: true)
    end
    allow(service).to receive(:ask_ai).and_return(verdict)
  end

  def saved_handled
    settings.reload.ai_config.dig('comments_state', 'handled')
  end

  describe 'quando o comentário já foi respondido há mais de 30 dias e o post continua entre os recentes' do
    let(:handled) { { 'c1' => 31.days.ago.iso8601 } }
    let(:comments) { [ig_comment('c1', 'Amei o resultado!', 32.days.ago)] }

    it 'NÃO chama a IA nem responde de novo, e a memória continua', :aggregate_failures do
      result = service.call
      expect(result).to include(replied: 0)
      expect(service).not_to have_received(:ask_ai)
      expect(posted).to be_empty
      expect(saved_handled).to have_key('c1')
    end
  end

  describe 'quando o comentário é de antes da última rodada' do
    let(:comments) { [ig_comment('velho', 'Quanto custa?', 5.hours.ago), ig_comment('novo', 'Atende sábado?', 10.minutes.ago)] }

    it 'só o comentário novo vai para a IA e recebe resposta', :aggregate_failures do
      service.call
      expect(service).to have_received(:ask_ai).once.with(hash_including(id: 'novo'))
      expect(posted).to eq(["#{described_class::GRAPH}/novo/replies"])
      expect(saved_handled.keys).to eq(['novo'])
    end
  end

  describe 'quando o agente ficou semanas parado (last_run_at antigo)' do
    let(:last_run_at) { 3.weeks.ago.iso8601 }
    let(:comments) { [ig_comment('duas_semanas', 'Quanto custa?', 2.weeks.ago), ig_comment('ontem', 'Atende sábado?', 1.day.ago)] }

    it 'ao religar, não olha mais de 7 dias para trás: só o comentário recente é respondido', :aggregate_failures do
      service.call
      expect(service).to have_received(:ask_ai).once.with(hash_including(id: 'ontem'))
      expect(posted).to eq(["#{described_class::GRAPH}/ontem/replies"])
    end
  end

  describe 'na primeira rodada (sem last_run_at)' do
    let(:last_run_at) { nil }
    let(:comments) { [ig_comment('antigo', 'Lindo!', 3.months.ago), ig_comment('recente', 'Lindo!', 2.days.ago)] }

    it 'comentário de meses atrás não é respondido; o da semana sim', :aggregate_failures do
      service.call
      expect(service).to have_received(:ask_ai).once.with(hash_including(id: 'recente'))
      expect(posted.size).to eq(1)
    end
  end

  describe 'quando a Página já respondeu o comentário (alguém da equipe, ou memória perdida)' do
    let(:comments) { [ig_comment('c9', 'Vocês atendem convênio?', 10.minutes.ago)] }
    let(:replies) { [{ 'id' => 'r1', 'from' => { 'id' => ig_id } }] }

    it 'pula sem chamar a IA e lembra para não consultar de novo', :aggregate_failures do
      service.call
      expect(service).not_to have_received(:ask_ai)
      expect(posted).to be_empty
      expect(saved_handled).to have_key('c9')
    end
  end

  describe 'quando a resposta existente é de outra pessoa (não da Página)' do
    let(:comments) { [ig_comment('c8', 'Vocês atendem convênio?', 10.minutes.ago)] }
    let(:replies) { [{ 'id' => 'r1', 'from' => { 'id' => '999' } }] }

    it 'responde normalmente' do
      service.call
      expect(posted).to eq(["#{described_class::GRAPH}/c8/replies"])
    end
  end

  describe 'memória de comentários que já sumiram da lista' do
    let(:handled) { { 'sumiu_velho' => 40.days.ago.iso8601, 'sumiu_novo' => 2.days.ago.iso8601 } }
    let(:comments) { [] }

    it 'poda só o que passou do prazo (a memória não cresce sem fim)' do
      service.call
      expect(saved_handled.keys).to eq(['sumiu_novo'])
    end

    it 'se a busca na Meta falhou, não poda nada (lista vazia não prova que o comentário sumiu)' do
      allow(HTTParty).to receive(:get).and_raise(StandardError, 'Meta fora do ar')
      service.call
      expect(saved_handled.keys).to contain_exactly('sumiu_velho', 'sumiu_novo')
    end
  end

  # Rodada 4 da auditoria: duas rodadas ao mesmo tempo (cron de 5 min + rodada
  # lenta). A gravação junta com o que já está salvo em vez de trocar pela foto
  # do começo da rodada — a marca "já respondi" da outra rodada não some.
  describe 'quando outra rodada grava a memória enquanto esta ainda roda' do
    let(:comments) { [ig_comment('meu', 'Atende sábado?', 10.minutes.ago)] }

    before do
      allow(service).to receive(:ask_ai) do
        # a outra rodada respondeu 'dela' e gravou, depois que esta já tinha lido
        cfg = settings.reload.ai_config
        cfg['comments_state'] = cfg['comments_state'].merge(
          'handled' => { 'dela' => Time.current.iso8601 },
          'events' => [{ 'at' => 1.minute.ago.iso8601, 'author' => 'outra', 'comment' => 'oi', 'status' => 'respondido' }]
        )
        settings.update!(ai_config: cfg)
        verdict
      end
    end

    it 'as marcas e os eventos das duas rodadas ficam gravados', :aggregate_failures do
      service.call
      expect(saved_handled.keys).to contain_exactly('meu', 'dela')
      events = settings.reload.ai_config.dig('comments_state', 'events')
      expect(events.pluck('author')).to contain_exactly('fulana', 'outra')
      expect(events.first['author']).to eq('fulana') # mais novo primeiro
    end
  end

  describe 'poda por prazo continua valendo com a gravação que junta' do
    let(:handled) { { 'sumiu_velho' => 40.days.ago.iso8601 } }

    it 'o comentário podado não volta pela memória gravada' do
      service.call
      expect(saved_handled).not_to have_key('sumiu_velho')
    end
  end
end
