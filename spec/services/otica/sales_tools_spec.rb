require 'rails_helper'

# 💬 08/11: venda pelo WhatsApp — consultoria de lentes, negociação com política de desconto e fechamento
RSpec.describe Otica::SalesTools do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:frame) { Otica::Product.create!(account: account, kind: 'armacao', name: 'Gatinho vinho', list_price: 400, quantity: 1, max_discount_pct: 10) }
  let!(:mono) { Otica::Product.create!(account: account, kind: 'lente', name: 'Visão simples AR', lens_type: 'visao_simples', lens_treatment: 'antirreflexo', list_price: 300, pitch: 'Pra quem usa um grau só, o dia todo.') }
  let!(:blue) { Otica::Product.create!(account: account, kind: 'lente', name: 'Filtro azul', lens_type: 'visao_simples', lens_treatment: 'filtro azul', list_price: 450, pitch: 'Pra quem vive na tela.', max_discount_pct: 20) }
  let!(:multi) do
    Otica::Product.create!(account: account, kind: 'lente', name: 'Multifocal HB', lens_type: 'multifocal', list_price: 1200, pitch: 'Perto e longe num óculos só.').tap do |l|
      l.photo.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'lente.png', content_type: 'image/png')
    end
  end

  before do
    CrmSetting.create!(account: account, ai_config: { 'gemini_api_key' => 'AIza-teste' })
    Cevico::Company.save!(account, 'segment' => 'otica')
  end

  def tools(live:)
    described_class.new(conversation: conversation, agent_key: 'atendente_agendamento', live: live)
  end

  describe 'pedir_fotos' do
    it 'em sombra só simula; ao vivo manda a orientação (texto padrão ou da loja) com o cartão-exemplo quando ele existe', :aggregate_failures do
      out, = tools(live: false).call('pedir_fotos', {})
      expect(out).to include(ok: true, simulado: true, com_exemplo: false)
      expect(conversation.messages.outgoing.count).to eq(0)

      out, resumo = tools(live: true).call('pedir_fotos', {})
      expect(out).to include(ok: true, com_exemplo: false)
      expect(resumo).to eq('orientação enviada')
      expect(conversation.messages.outgoing.last.content).to eq(Otica::TextSpacing.space(described_class::DEFAULT_PHOTO_GUIDE))
      expect(conversation.messages.outgoing.last.attachments).to be_empty

      # chamou de novo no mesmo dia ("topo!"): não repete o envio
      out, resumo = tools(live: true).call('pedir_fotos', {})
      expect(out).to include(ok: true, repetido: true)
      expect(resumo).to eq('já enviada hoje')
      expect(conversation.messages.outgoing.count).to eq(1)

      # outra conversa, com texto da loja e cartão-exemplo cadastrados
      described_class.save_config!(account, 'orientacao_foto' => 'Manda duas fotos, assim como no exemplo!')
      CrmSetting.find_by(account: account).otica_photo_example.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'exemplo.png', content_type: 'image/png')
      outra = create(:conversation, account: account, inbox: inbox, contact: contact)
      out, resumo = described_class.new(conversation: outra, agent_key: 'atendente_visagista', live: true).call('pedir_fotos', {})
      expect(out).to include(ok: true, com_exemplo: true)
      expect(resumo).to include('cartão-exemplo')
      last = outra.messages.outgoing.last
      expect(last.content).to eq('Manda duas fotos, assim como no exemplo!')
      expect(last.attachments.one? && last.attachments.first.file_type == 'image').to be(true)
      expect(last.additional_attributes).to include('cevico_pedir_fotos' => true)
    end
  end

  describe 'mostrar_lentes' do
    it 'em sombra lista (rotina puxa a multifocal) sem enviar; ao vivo envia a imagem da lente que tem foto', :aggregate_failures do
      out, resumo = tools(live: false).call('mostrar_lentes', { 'rotina' => 'perto e longe', 'quantidade' => 3 })
      expect(out).to include(ok: true, simulado: true, imagens_enviadas: 0)
      expect(out[:lentes].pluck(:lente)).to eq(['Multifocal HB', 'Visão simples AR', 'Filtro azul'])
      expect(out[:lentes].first).to include(valor_cheio: 1200.0, pra_quem: 'Perto e longe num óculos só.', tem_imagem: true)
      expect(resumo).to include('3 lente(s)')
      expect(conversation.messages.outgoing.count).to eq(0)

      out, = tools(live: true).call('mostrar_lentes', { 'rotina' => 'tela o dia todo', 'quantidade' => 2 })
      expect(out[:lentes].pluck(:lente)).to eq(['Filtro azul', 'Multifocal HB']) # tela → filtro azul primeiro; foto desempata
      expect(out).to include(imagens_enviadas: 1, simulado: false)
      sent = conversation.messages.outgoing.last
      expect(sent.content).to eq('Multifocal HB: Perto e longe num óculos só.')
      expect(sent.attachments.first.file_type).to eq('image')
    end
  end

  describe 'conferir_desconto' do
    it 'aprova quando o valor cabe no desconto máximo de cada produto; senão contrapropõe o piso redondo', :aggregate_failures do
      sales = tools(live: false)
      # cheio 400 + 450 = 850 · piso 360 + 360 = 720
      out, resumo = sales.call('conferir_desconto', { 'armacao_id' => frame.id, 'lente_id' => blue.id, 'valor_pedido' => 750 })
      expect(out).to include(ok: true, aprovado: true, valor_fechamento: 750.0, preco_cheio: 850.0, simulado: true)
      expect(resumo).to eq('pediu R$ 750,00 → aprovado R$ 750,00')

      out, = sales.call('conferir_desconto', { 'armacao_id' => frame.id, 'lente_id' => blue.id, 'valor_pedido' => 600 })
      expect(out).to include(aprovado: false, melhor_valor: 720.0)
      expect(out[:aviso]).to include('R$ 720,00').and include('Nunca ofereça menos')

      # acima do cheio não vira "desconto negativo": fecha no cheio
      out, = sales.call('conferir_desconto', { 'armacao_id' => frame.id, 'lente_id' => blue.id, 'valor_pedido' => 900 })
      expect(out[:valor_fechamento]).to eq(850.0)
    end

    it 'usa o desconto padrão da loja quando o produto não tem o seu; ao vivo manda o balão "me dá um instante" e espera', :aggregate_failures do
      described_class.save_config!(account, 'default_discount_pct' => '15')
      sales = tools(live: true)
      allow(sales).to receive(:sleep)
      # frame 10% (próprio) → 360 · mono sem % → padrão 15% → 255 · piso 615 → redondo 620
      out, = sales.call('conferir_desconto', { 'armacao_id' => frame.id, 'lente_id' => mono.id, 'valor_pedido' => 500 })
      expect(out).to include(aprovado: false, melhor_valor: 620.0, simulado: false)
      expect(sales).to have_received(:sleep).with(described_class::CHECK_WAIT)
      expect(conversation.messages.outgoing.last.content).to eq(Otica::TextSpacing.space(described_class::CHECK_TEXT)) # espaçado
      expect(conversation.messages.where(message_type: :activity).last.content).to include('contraproposta R$ 620,00')

      sales.call('conferir_desconto', { 'armacao_id' => frame.id, 'lente_id' => mono.id, 'valor_pedido' => 500 })
      sales.call('conferir_desconto', { 'armacao_id' => frame.id, 'lente_id' => mono.id, 'valor_pedido' => 500 })
      out, = sales.call('conferir_desconto', { 'armacao_id' => frame.id, 'lente_id' => mono.id, 'valor_pedido' => 700 })
      expect(out[:ok]).to be(false)
      expect(out[:motivo]).to include('3 conferências')
    end

    it 'recusa produto inexistente ou valor zerado' do
      expect(tools(live: false).call('conferir_desconto', { 'armacao_id' => 999, 'lente_id' => mono.id, 'valor_pedido' => 10 }).first[:ok]).to be(false)
      expect(tools(live: false).call('conferir_desconto', { 'armacao_id' => frame.id, 'lente_id' => mono.id, 'valor_pedido' => 0 }).first[:ok]).to be(false)
    end
  end

  describe 'registrar_fechamento' do
    it 'ao vivo abre a tarefa para a equipe, carimba a conversa e devolve a chave Pix; em sombra só simula', :aggregate_failures do
      described_class.save_config!(account, 'pix_key' => '11955020981', 'payment_link' => 'https://pag.exemplo/loja')
      out, = tools(live: false).call('registrar_fechamento', { 'armacao_id' => frame.id, 'lente_id' => multi.id, 'valor' => 1500, 'forma_pagamento' => 'pix' })
      expect(out).to include(ok: true, simulado: true)
      expect(out[:pagamento]).to include(tipo: 'pix', chave_pix: '11955020981')
      expect(account.tasks.count).to eq(0)

      out, resumo = tools(live: true).call('registrar_fechamento', { 'armacao_id' => frame.id, 'lente_id' => multi.id, 'valor' => 1500,
                                                                     'forma_pagamento' => 'link', 'observacao' => 'receita de 2025 em mãos' })
      expect(out).to include(ok: true, simulado: false)
      expect(out[:pagamento]).to include(tipo: 'link', link: 'https://pag.exemplo/loja')
      expect(resumo).to include('R$ 1500,00 · link')
      task = account.tasks.last
      expect(task).to be_present
      expect(task.title).to include('Venda fechada pelo WhatsApp: R$ 1500,00')
      expect(task.description).to include('Gatinho vinho').and include('Multifocal HB').and include('receita de 2025')
      expect(conversation.reload.additional_attributes['cevico_venda']).to include('valor' => 1500.0, 'forma' => 'link', 'armacao_id' => frame.id)

      out, = tools(live: true).call('registrar_fechamento', { 'valor' => 800, 'forma_pagamento' => 'na_loja' })
      expect(out[:pagamento][:tipo]).to eq('na_loja')
      expect(tools(live: true).call('registrar_fechamento', { 'valor' => 0, 'forma_pagamento' => 'pix' }).first[:ok]).to be(false)
    end
  end

  # 🔁 08/11 (noite): "hoje não temos o formato ideal; posso te chamar daqui a uma semana?" → sim → tarefa na data
  describe 'agendar_retorno' do
    it 'em sombra simula; ao vivo abre UMA tarefa por cliente na data combinada (chamada nova só atualiza)', :aggregate_failures do
      out, resumo = tools(live: false).call('agendar_retorno', { 'motivo' => 'gatinho ou oval pro rosto redondo' })
      expect(out).to include(ok: true, simulado: true, dias: 7)
      expect(resumo).to eq('retorno simulado em 7 dias')
      expect(account.tasks.count).to eq(0)

      out, resumo = tools(live: true).call('agendar_retorno', { 'dias' => 5, 'motivo' => 'gatinho ou oval pro rosto redondo' })
      expect(out).to include(ok: true, dias: 5)
      expect(resumo).to start_with('retorno em ')
      task = account.tasks.last
      expect(task.task_type).to eq('otica_retorno')
      expect(task.title).to include('Chamar Maria Silva').and include('gatinho ou oval')
      expect(task.due_at.to_date).to eq((Otica::TZ.now + 5.days).to_date)
      expect(task.contact).to eq(contact)
      expect(conversation.messages.where(message_type: :activity).last.content).to include('Retorno combinado')

      tools(live: true).call('agendar_retorno', { 'dias' => 10, 'motivo' => 'armação preta fininha' })
      expect(account.tasks.where(task_type: 'otica_retorno').count).to eq(1)
      expect(task.reload.due_at.to_date).to eq((Otica::TZ.now + 10.days).to_date)
      expect(task.title).to include('armação preta fininha')

      expect(tools(live: true).call('agendar_retorno', { 'motivo' => '' }).first[:ok]).to be(false)
      expect(tools(live: true).call('agendar_retorno', { 'dias' => 90, 'motivo' => 'x' }).first[:dias]).to eq(30)
    end
  end

  it 'as três ferramentas entram no Atendente da ótica pela Crm::ResponderTools e registram a ação', :aggregate_failures do
    rt = Crm::ResponderTools.new(conversation: conversation, agent_key: 'atendente_agendamento', live: false)
    expect(rt.definitions.pluck(:name)).to include('experimentar_armacoes', 'mostrar_lentes', 'conferir_desconto', 'registrar_fechamento', 'agendar_retorno')
    out = rt.call('mostrar_lentes', { 'rotina' => 'leitura' })
    expect(out[:ok]).to be(true)
    expect(rt.acoes.last).to include('ferramenta' => 'mostrar_lentes', 'ok' => true, 'simulado' => true)
  end

  describe 'status_do_pedido' do
    it 'devolve o pedido aberto do cliente em palavras simples; sem pedido, manda perguntar e passar para a equipe', :aggregate_failures do
      out, resumo = tools(live: false).call('status_do_pedido', {})
      expect(out[:ok]).to be(false)
      expect(resumo).to eq('sem pedido')

      o = account.otica_orders.create!(contact: contact, status: 'pronta', sold_on: Otica.today - 6, ready_at: Time.zone.now, created_by_id: admin.id)
      out, resumo = tools(live: false).call('status_do_pedido', {})
      expect(out[:ok]).to be(true)
      expect(out[:pedidos].first).to include(os: o.number, status: 'pronta', pronto: true)
      expect(out[:pedidos].first[:resumo]).to include('PRONTO para retirar na loja')
      expect(resumo).to include('pronta')
      # o pós-compra só tem o status; as de venda são dos atendentes de aquisição
      expect(described_class.definitions('atendente_pos_op').pluck(:name)).to eq(['status_do_pedido'])
      expect(described_class.definitions('atendente_agendamento').pluck(:name)).to eq(described_class::NAMES)
    end
  end
end
