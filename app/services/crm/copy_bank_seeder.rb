# 🪝 item 397: enche o Banco de Ganchos da conta na PRIMEIRA abertura —
# os ganchos do PDF "1,000 Viral Hooks" (db/seeds/cevico/ganchos_pbl_1000.json,
# traduzidos e adaptados, com o original e o link do vídeo de referência) +
# as histórias, ofertas e reganchos da casa. Idempotente: cada fonte entra
# uma vez só (o que o time apagar ou editar depois não volta sozinho).
class Crm::CopyBankSeeder
  SEED_FILE = Rails.root.join('db/seeds/cevico/ganchos_pbl_1000.json')

  # estruturas de CORPO (a "história" do hook → story → offer)
  HISTORIAS = [
    ['Problema → Agitação → Solução',
     'Você [dor]. E o pior: [o que isso causa no dia a dia]. Existe um caminho: [solução], com [como funciona em uma frase].'],
    ['Hoje → Amanhã → A ponte',
     'Hoje, [como é a rotina com o problema]. Imagine [como seria sem ele]. O que separa um do outro é [o passo: a avaliação completa].'],
    ['Mito → Verdade',
     'Muita gente acha que [mito]. Na verdade, [verdade]. Por isso [o que a pessoa deve fazer].'],
    ['Passo a passo',
     'Funciona assim: 1) [primeiro passo]. 2) [segundo passo]. 3) [terceiro passo]. Em cada etapa, a gente explica o que está acontecendo.'],
    ['Objeção → Resposta',
     '"[objeção que o paciente fala]". É a pergunta que mais ouvimos. A resposta: [resposta franca], e [prova ou fato].'],
    ['Jornada do paciente',
     '[Nome] chegou com [situação]. Na avaliação, descobriu [o que descobriu]. Hoje, [como ficou a rotina — sem prometer resultado].'],
    ['Pergunta → Resposta → Pergunta',
     '[Pergunta que o público tem]? [Resposta curta]. Mas fica uma pergunta: [próxima dúvida]? [Resposta].'],
    ['Kishōtenketsu (4 atos)',
     '[Cena comum do dia a dia]. [Aprofunda a cena]. [A virada inesperada]. [Conclusão que amarra tudo].']
  ].freeze

  # CTAs da CEVICO (fatos em nucleo-criativo/provas/fatos.md; convites aprovados em gosto.md)
  OFERTAS = [
    ['convite', 'Se isso for interessante para você, você pode ter mais detalhes clicando em Saiba mais.'],
    ['convite', 'Sem pressa. Se fizer sentido para você, clique em Saiba mais e veja cada etapa, do primeiro exame ao dia seguinte.'],
    ['whatsapp', 'Chama a gente no WhatsApp e tira suas dúvidas com calma.'],
    ['avaliacao', 'A avaliação completa custa 150 reais e os exames da avaliação estão inclusos. Agende pelo WhatsApp.'],
    ['avaliacao', 'Quer saber se a cirurgia é para você? O primeiro passo é a avaliação: [unidade], [dia]. Chama no WhatsApp.'],
    ['unidades', 'Atendemos na Av. Paulista e no Tatuapé. Escolha a mais perto e agende pelo WhatsApp.'],
    ['salvar', 'Salva este vídeo para mostrar para [pessoa] e manda para quem vive [dor].'],
    ['comentario', 'Comenta "[palavra]" que a gente te manda o passo a passo.']
  ].freeze

  # reganchos (nucleo-criativo/moldes/rehooks.md, do post "30 ways to re-hook")
  REGANCHOS = [
    ['pergunta', 'Por que isso acontece?'], ['problema', 'Mas tem um detalhe…'],
    ['antecipar', 'Espere até ver como é lá dentro.'], ['prova', 'Não precisa acreditar na gente.'],
    ['virada', 'E aí vem a parte que ninguém conta.'], ['comentario', 'Olha o que um paciente escreveu.'],
    ['comparar', '[A] × [B]: o que muda.'], ['avisar', 'Antes de marcar qualquer cirurgia…'],
    ['desafiar', 'Sabe qual é o erro mais comum?'], ['segurar', 'Antes de te contar como se resolve…'],
    ['exemplo', 'Veja o que isso quer dizer.'], ['corrigir', 'Na verdade, não é bem assim.'],
    ['aumentar', 'E não para por aí.'], ['escondido', 'O que você não vê.'],
    ['excecao', 'A não ser que…'], ['previsao', 'Veja o que acontece depois.'],
    ['beneficio', 'E essa nem é a melhor parte.'], ['voltar', 'Lembra do começo?'],
    ['pergunta', 'Mas fica uma pergunta…']
  ].freeze

  def self.ensure!(account)
    new(account).ensure!
  end

  def initialize(account)
    @account = account
  end

  def ensure!
    blocks = @account.cevico_copy_blocks
    seed_pbl(blocks) unless blocks.exists?(fonte: 'pbl-1000')
    seed_casa(blocks) unless blocks.exists?(fonte: 'cevico')
  end

  private

  def seed_pbl(blocks)
    return unless File.exist?(SEED_FILE)

    rows = JSON.parse(File.read(SEED_FILE)).each_with_index.map do |h, i|
      row('gancho', h['categoria'], h['pt'], position: i, fonte: 'pbl-1000',
                                             extra: { original: h['en'], exemplo: h['exemplo'], referencia: h['referencia'], saude: h['saude'] })
    end
    rows.each_slice(500) { |slice| blocks.insert_all(slice) } # rubocop:disable Rails/SkipsModelValidations
  end

  def seed_casa(blocks)
    rows = HISTORIAS.each_with_index.map { |(nome, texto), i| row('historia', nome, texto, position: i) }
    rows += OFERTAS.each_with_index.map { |(cat, texto), i| row('oferta', cat, texto, position: i) }
    rows += REGANCHOS.each_with_index.map { |(cat, texto), i| row('regancho', cat, texto, position: i) }
    blocks.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
  end

  def row(kind, categoria, texto, position:, fonte: 'cevico', extra: {}) # rubocop:disable Metrics/ParameterLists
    now = Time.current
    saude = CevicoCopyBlock::SAUDE.include?(extra[:saude]) ? extra[:saude] : 'pronto'
    {
      account_id: @account.id, kind: kind, categoria: categoria, texto: texto.to_s,
      original: extra[:original], exemplo: extra[:exemplo].presence, referencia: extra[:referencia],
      saude: saude, lacunas: CevicoCopyBlock.lacunas_de(texto), fonte: fonte, position: position,
      created_at: now, updated_at: now
    }
  end
end
