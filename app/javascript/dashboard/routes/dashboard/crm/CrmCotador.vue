<script setup>
// 📄 GERADOR DE PROPOSTA (LIFE, 11/11/2026 · pedido do Guilherme): numa tela só, do cliente
// aos dois documentos do orçamento.
//   1. Para quem é a proposta (nome, telefone ou quem está na coluna do funil)
//   2. A conta de luz (valor de hoje + o que vai acrescentar), o telhado e a rede
//   3. Cotação nos fornecedores (AVT, Bluesun), já com a estrutura do telhado e o frete
//   4. Preço e DRE: custo do kit = média dos fornecedores com cotação completa, adequação
//      pela tabela, padrão de 25% de lucro, faixa de 18% a 30%, preço ajustável
//   5. Gerar a proposta do cliente e a justificativa do orçamento
// As contas de preço são do servidor (Crm::KitQuote::Dre); aqui só se escolhe e se mostra.
// Nó de acesso: crm.cotador (ver = abre; editar = cota e gera).
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import CrmAPI from 'dashboard/api/crm';
import ProposalClientPicker from 'dashboard/components-next/cevico/ProposalClientPicker.vue';
import CvTutorial from 'dashboard/components-next/cevico/CvTutorial.vue';
import KitQuoteAccess from './components/KitQuoteAccess.vue';
import KitQuoteCard from './components/KitQuoteCard.vue';
import {
  parseMoney,
  formatMoney as reais,
  billTotal,
  kwhFromBill,
  bestOption,
  quotesFor,
  quotesAverage,
  prefillFromSummary,
} from 'dashboard/helper/proposalBuilder';

const router = useRouter();
// PARA QUEM é a proposta (feito pela sessão do Meu Painel): o cliente escolhido fica no
// endereço (…/cotador?contact=6), para os botões "Gerar proposta" do Meu Painel, da
// conversa e da Central do cliente abrirem já nele.
const route = useRoute();
const cliente = ref(null);
const { canEdit, isAdmin } = useCevicoAccess();
const podeCotar = computed(() => canEdit('crm.cotador'));

const REDES = [
  { id: 'monofasico', nome: 'Monofásica' },
  { id: 'bifasico', nome: 'Bifásica' },
  { id: 'trifasico', nome: 'Trifásica' },
];
const TIPOS = [
  { id: 'micro', nome: 'Micro inversor' },
  { id: 'string', nome: 'Inversor string' },
];
const NOME_TIPO = {
  micro: 'Micro inversor',
  string: 'Inversor string',
  hibrido: 'Inversor híbrido',
};
const MARGENS = [0.18, 0.25, 0.3];

const carregando = ref(true);
const acesso = ref({});
const cidade = ref('');
const tarifa = ref(0.95);
const telhados = ref([]);
const geradorPdfLigado = ref(false);

// 2. a conta
const nomeCliente = ref('');
const cidadeCliente = ref('');
const contaHoje = ref('');
const acrescimos = ref([{ rotulo: '', valor: '' }]);
const consumo = ref('');
const consumoNaMao = ref(false);
const telhado = ref('ceramica');
const rede = ref('bifasico');

// 3. a cotação
const cotando = ref(false);
const resultado = ref(null);
const tipo = ref('micro');
const escolhida = ref(null);

// 4. preço e DRE
const cotacoesNaMao = ref([]);
const dre = ref(null);
const dreCarregando = ref(false);
const dreErro = ref('');
const precisaAdequacao = ref(false);
const adequacaoNaMao = ref('');
const valorNaMao = ref('');
const margemEscolhida = ref(0.25);

// 6. os orçamentos guardados deste cliente (Crm::Quote)
const historico = ref([]);
const marcando = ref(0);
// 0. todos os orçamentos gerados da conta, em caixas no topo (12/11, pedido do Guilherme)
const gerados = ref([]);
// 🗑️ lixeira (12/11): só o dono da conta vê; quem excluiu e o motivo ficam registrados
const lixeira = reactive({ disponivel: false, total: 0, lista: [] });
const aba = ref('validos');
const pickerKey = ref(0);

// 5. os documentos
const gerando = ref(false);
const documentos = reactive({ arquivos: [], aviso: '', valor: 0 });

const numero = valor =>
  new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 }).format(
    valor || 0
  );
const pct = valor =>
  `${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 }).format((valor || 0) * 100)}%`;
const tarifaTexto = computed(() =>
  new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 3 }).format(
    tarifa.value
  )
);
const erroDe = (e, padrao) => e?.response?.data?.error || padrao;

// ── 6. orçamentos guardados ──────────────────────────────────────────────
async function carregarHistorico() {
  const id = cliente.value?.contact_id;
  if (!id) {
    historico.value = [];
    return;
  }
  try {
    const { data } = await CrmAPI.getKitQuoteHistory(id);
    historico.value = data.orcamentos || [];
  } catch {
    historico.value = [];
  }
}
const ABAS = [
  { id: 'validos', nome: 'Valendo', filtro: o => o.valido && !o.enviado_em },
  { id: 'enviados', nome: 'Enviados', filtro: o => !!o.enviado_em },
  { id: 'todos', nome: 'Todos', filtro: () => true },
];
async function carregarGerados() {
  try {
    const { data } = await CrmAPI.getKitQuoteHistory();
    gerados.value = data.orcamentos || [];
    lixeira.disponivel = !!data.lixeira?.disponivel;
    lixeira.total = data.lixeira?.total || 0;
    // abre na aba que tem alguma coisa (Valendo → Enviados → Todos)
    if (!gerados.value.some(ABAS.find(x => x.id === aba.value).filtro)) {
      aba.value = ABAS.find(x => gerados.value.some(x.filtro))?.id || 'todos';
    }
  } catch {
    gerados.value = [];
  }
}
const contagem = computed(() => ({
  ...Object.fromEntries(
    ABAS.map(a => [a.id, gerados.value.filter(a.filtro).length])
  ),
  lixeira: lixeira.total,
}));
const abasVisiveis = computed(() =>
  lixeira.disponivel
    ? [...ABAS, { id: 'lixeira', nome: 'Lixeira', filtro: () => true }]
    : ABAS
);
const carregarLixeira = async () => {
  try {
    const { data } = await CrmAPI.getKitQuoteTrash();
    lixeira.lista = data.orcamentos || [];
    lixeira.total = lixeira.lista.length;
  } catch {
    lixeira.lista = [];
  }
};
watch(aba, atual => {
  if (atual === 'lixeira') carregarLixeira();
});
// histórico em ordem (12/11): mais novos, mais antigos ou maior valor, com busca pelo nome
const ORDENS = [
  { id: 'novos', nome: 'Mais novos' },
  { id: 'antigos', nome: 'Mais antigos' },
  { id: 'valor', nome: 'Maior valor' },
];
const ordem = ref('novos');
const busca = ref('');
const semAcento = t =>
  String(t || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
const geradosDaAba = computed(() => {
  const termo = semAcento(busca.value.trim());
  const base = aba.value === 'lixeira' ? lixeira.lista : gerados.value;
  const filtro = (ABAS.find(a => a.id === aba.value) || { filtro: () => true })
    .filtro;
  const lista = base
    .filter(filtro)
    .filter(o => !termo || semAcento(o.cliente?.nome).includes(termo));
  const quando = o => new Date(o.criado_em).getTime();
  if (ordem.value === 'antigos')
    return lista.sort((a, b) => quando(a) - quando(b));
  if (ordem.value === 'valor') return lista.sort((a, b) => b.valor - a.valor);
  return lista.sort((a, b) => quando(b) - quando(a));
});
const trocarNasListas = (id, novo) => {
  const troca = lista =>
    novo
      ? lista.map(o => (o.id === id ? { ...o, ...novo } : o))
      : lista.filter(o => o.id !== id);
  historico.value = troca(historico.value);
  gerados.value = troca(gerados.value);
};
// abre o cliente do orçamento no gerador (o seletor relê o ?contact=)
const abrirCliente = async orcamento => {
  await router.replace({ query: { contact: orcamento.cliente.id } });
  pickerKey.value += 1;
};
const excluirOrcamento = async (orcamento, motivo) => {
  if (marcando.value) return;
  marcando.value = orcamento.id;
  try {
    await CrmAPI.discardKitQuote(orcamento.id, motivo);
    trocarNasListas(orcamento.id, null);
    lixeira.total += 1;
    useAlert('Orçamento foi para a lixeira.');
  } catch (e) {
    useAlert(erroDe(e, 'Não foi possível excluir o orçamento.'));
  } finally {
    marcando.value = 0;
  }
};
// 📨 envia pelo WhatsApp (proposta + resumo + pergunta de fechamento)
const enviarWhatsapp = async orcamento => {
  if (marcando.value) return;
  marcando.value = orcamento.id;
  try {
    const { data } = await CrmAPI.deliverKitQuote(orcamento.id);
    trocarNasListas(orcamento.id, data.orcamento);
    useAlert(
      data.situacao === 'enviado'
        ? 'Enviado pelo WhatsApp com a pergunta de fechamento.'
        : 'Fora da janela de 24 h: foi o aviso "seu orçamento está pronto". Quando o cliente responder, o atendente manda a proposta.'
    );
  } catch (e) {
    useAlert(erroDe(e, 'Não foi possível enviar pelo WhatsApp.'));
  } finally {
    marcando.value = 0;
  }
};
// ✏️ editar o orçamento gerado (nome, cidade, telhado, validade): os PDFs saem de novo
const editarOrcamento = async (orcamento, dados) => {
  if (marcando.value) return;
  marcando.value = orcamento.id;
  try {
    const { data } = await CrmAPI.editKitQuote(orcamento.id, dados);
    trocarNasListas(orcamento.id, data.orcamento);
    // o card do orçamento automático (definido mais abaixo) também troca
    // eslint-disable-next-line no-use-before-define
    if (auto.orcamento?.id === orcamento.id) auto.orcamento = data.orcamento;
    useAlert(data.aviso || 'Orçamento atualizado, com os PDFs novos.');
  } catch (e) {
    useAlert(erroDe(e, 'Não foi possível editar o orçamento.'));
  } finally {
    marcando.value = 0;
  }
};
const restaurarOrcamento = async orcamento => {
  if (marcando.value) return;
  marcando.value = orcamento.id;
  try {
    const { data } = await CrmAPI.restoreKitQuote(orcamento.id);
    lixeira.lista = lixeira.lista.filter(o => o.id !== orcamento.id);
    lixeira.total = lixeira.lista.length;
    gerados.value = [data.orcamento, ...gerados.value];
    useAlert('Orçamento restaurado.');
  } catch (e) {
    useAlert(erroDe(e, 'Não foi possível restaurar.'));
  } finally {
    marcando.value = 0;
  }
};
// A proposta foi enviada: o cliente ganha a etiqueta "orçamento enviado", que leva o
// cartão para a coluna e começa o acompanhamento (Crm::QuoteSent).
const marcarEnviada = async orcamento => {
  if (marcando.value) return;
  marcando.value = orcamento.id;
  try {
    const { data } = await CrmAPI.markKitQuoteSent(orcamento.id);
    trocarNasListas(orcamento.id, data.orcamento);
    useAlert('Proposta marcada como enviada ao cliente.');
  } catch (e) {
    useAlert(erroDe(e, 'Não foi possível marcar como enviada.'));
  } finally {
    marcando.value = 0;
  }
};

// ── 1. cliente ───────────────────────────────────────────────────────────
watch(cliente, person => {
  router.replace({ query: person ? { contact: person.contact_id } : {} });
  nomeCliente.value = person?.name || '';
  carregarHistorico();
  if (!person) return;
  // aproveita o que o atendente já anotou (conta de luz, o que vai aumentar, cidade)
  const lido = prefillFromSummary(person.summary || []);
  if (lido.hoje && !contaHoje.value) contaHoje.value = String(lido.hoje);
  if (lido.kwh && !consumo.value) {
    consumoNaMao.value = true;
    consumo.value = String(lido.kwh);
  }
  if (lido.acrescimo && !acrescimos.value[0].rotulo) {
    acrescimos.value[0].rotulo = lido.acrescimo;
  }
  cidadeCliente.value = lido.cidade || '';
  if (lido.telhado) telhado.value = lido.telhado;
});

// botão "Preencher com os dados do cliente" (12/11): puxa de novo do resumo do cliente
// (conta de luz, o que vai aumentar, cidade e telhado), por cima do que estiver na tela
const lidoDoCliente = computed(() =>
  cliente.value ? prefillFromSummary(cliente.value.summary || []) : null
);
const temDadosDoCliente = computed(() => {
  const l = lidoDoCliente.value;
  return !!(l && (l.hoje || l.kwh || l.acrescimo || l.cidade || l.telhado));
});
const preenchido = ref('');
watch(cliente, () => {
  preenchido.value = '';
});
const preencherDoCliente = () => {
  const l = lidoDoCliente.value;
  if (!l) return;
  const feito = [];
  if (cliente.value?.name) nomeCliente.value = cliente.value.name;
  if (l.hoje) {
    contaHoje.value = String(l.hoje);
    feito.push(`conta de ${reais(l.hoje)}`);
  }
  if (l.kwh) {
    consumoNaMao.value = true;
    consumo.value = String(l.kwh);
    feito.push(`consumo de ${numero(l.kwh)} kWh`);
  }
  if (l.acrescimo) {
    acrescimos.value = [{ rotulo: l.acrescimo, valor: '' }];
    feito.push(`vai aumentar: ${l.acrescimo}`);
  }
  if (l.cidade) {
    cidadeCliente.value = l.cidade;
    feito.push(l.cidade);
  }
  if (l.telhado) {
    telhado.value = l.telhado;
    const nome = telhados.value.find(t => t.chave === l.telhado)?.nome;
    feito.push(`telhado ${nome ? nome.toLowerCase() : l.telhado}`);
  }
  preenchido.value = feito.length
    ? `Preenchido com o resumo: ${feito.join(' · ')}.`
    : 'O resumo deste cliente ainda não tem conta, telhado nem cidade.';
};

// ── 2. conta de luz → consumo ────────────────────────────────────────────
const contaTotal = computed(() => billTotal(contaHoje.value, acrescimos.value));
const consumoCalculado = computed(() =>
  kwhFromBill(contaTotal.value, tarifa.value)
);
watch(consumoCalculado, kwh => {
  if (!consumoNaMao.value) consumo.value = kwh ? String(kwh) : '';
});
const ajustarConsumo = () => {
  consumoNaMao.value = true;
};
const consumoPelaConta = () => {
  consumoNaMao.value = false;
  consumo.value = consumoCalculado.value ? String(consumoCalculado.value) : '';
};
const maisAcrescimo = () => acrescimos.value.push({ rotulo: '', valor: '' });
const tirarAcrescimo = i => {
  acrescimos.value.splice(i, 1);
  if (!acrescimos.value.length) maisAcrescimo();
};

// ── 4. preço e DRE (sempre calculado no servidor) ────────────────────────
const cotacoes = computed(() =>
  quotesFor(resultado.value?.medias, escolhida.value, cotacoesNaMao.value)
);
const media = computed(() => quotesAverage(cotacoes.value));

const pedidoDoDre = extra => ({
  kits: cotacoes.value,
  placas: escolhida.value.placas,
  tipo: escolhida.value.tipo,
  adequacao: precisaAdequacao.value ? adequacaoNaMao.value : undefined,
  ...extra,
});

const soltarArquivos = () => {
  documentos.arquivos.forEach(a => URL.revokeObjectURL(a.url));
  documentos.arquivos = [];
};

// preco: { valor } (ajustado na mão) ou { margem } (uma das pontas); sem nada, o padrão de 25%
const calcularDre = async (preco = { margem: margemEscolhida.value }) => {
  soltarArquivos(); // o preço mudou: os documentos gerados antes não valem mais
  documentos.aviso = '';
  if (!escolhida.value) return;
  if (media.value === null) {
    dre.value = null;
    dreErro.value =
      'Nenhum fornecedor deu cotação completa (kit + estrutura do telhado + frete) para este tipo. Acrescente uma cotação na mão para o sistema calcular o preço.';
    return;
  }
  dreCarregando.value = true;
  dreErro.value = '';
  try {
    const { data } = await CrmAPI.getKitQuoteDre(pedidoDoDre(preco));
    dre.value = data;
    valorNaMao.value = numero(data.valor_projeto);
    precisaAdequacao.value = !!data.adequacao?.manual;
  } catch (e) {
    dre.value = null;
    precisaAdequacao.value =
      precisaAdequacao.value || !!e?.response?.data?.precisa_adequacao;
    dreErro.value = erroDe(e, 'Não foi possível montar o DRE.');
  } finally {
    dreCarregando.value = false;
  }
};
const usarMargem = margem => {
  margemEscolhida.value = margem;
  calcularDre({ margem });
};
const usarValor = () => {
  margemEscolhida.value = null;
  calcularDre({ valor: valorNaMao.value });
};
// barra do lucro (12/11, pedido do Guilherme): o vendedor arrasta a % e o DRE recalcula
const BARRA = { min: 0.1, max: 0.4, passo: 0.005 };
const margemBarra = ref(0.25);
watch(dre, atual => {
  if (atual?.margem) margemBarra.value = Number(atual.margem);
});
let barraTimer = null;
const arrastarMargem = evento => {
  margemBarra.value = Number(evento.target.value);
  clearTimeout(barraTimer);
  barraTimer = setTimeout(() => usarMargem(margemBarra.value), 350);
};
const corDaBarra = computed(() => {
  const m = margemBarra.value;
  return m >= 0.18 - 0.0005 && m <= 0.3 + 0.0005 ? '#0d9488' : '#dc2626';
});
const margemAtiva = margem =>
  margemEscolhida.value !== null &&
  Math.abs(margemEscolhida.value - margem) < 0.0005;

const maisCotacao = () =>
  cotacoesNaMao.value.push({ fornecedor: '', valor: '' });
const tirarCotacao = i => {
  cotacoesNaMao.value.splice(i, 1);
  calcularDre();
};

// ── 3. cotação ───────────────────────────────────────────────────────────
const opcoesDoTipo = computed(() =>
  (resultado.value?.opcoes || []).filter(o => o.tipo === tipo.value)
);
const escolher = opcao => {
  escolhida.value = opcao;
  precisaAdequacao.value = false;
  adequacaoNaMao.value = '';
  margemEscolhida.value = 0.25;
  calcularDre();
};
const trocarTipo = novo => {
  tipo.value = novo;
  const melhor = bestOption(resultado.value?.opcoes, novo);
  if (melhor) {
    escolher(melhor);
  } else {
    escolhida.value = null;
    dre.value = null;
  }
};
const cotar = async () => {
  if (cotando.value) return;
  cotando.value = true;
  resultado.value = null;
  escolhida.value = null;
  dre.value = null;
  dreErro.value = '';
  try {
    const { data } = await CrmAPI.createKitQuote({
      consumo: consumo.value,
      rede: rede.value,
      telhado: telhado.value,
    });
    resultado.value = data;
    acesso.value = data.acesso || acesso.value;
    // já abre na opção completa mais barata do tipo escolhido (ou do outro, se só ele veio)
    const comOpcao = [tipo.value, ...TIPOS.map(t => t.id)].find(t =>
      bestOption(data.opcoes, t)
    );
    if (comOpcao) trocarTipo(comOpcao);
  } catch (e) {
    useAlert(erroDe(e, 'Não foi possível cotar agora. Tente de novo.'));
  } finally {
    cotando.value = false;
  }
};

// ── 5. proposta + justificativa ──────────────────────────────────────────
const paraArquivo = ({ nome, tipo: mime, base64 }) => {
  const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
  const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
  return { nome, url, imagem: String(mime).startsWith('image/') };
};
const faltaParaGerar = computed(() => {
  if (!nomeCliente.value.trim()) return 'Escolha o cliente da proposta.';
  if (!parseMoney(contaHoje.value)) return 'Informe a conta de luz de hoje.';
  if (!dre.value) return 'Escolha uma opção de kit.';
  return '';
});
const gerado = ref(false);
const gerar = async () => {
  if (gerando.value || faltaParaGerar.value) return;
  gerando.value = true;
  soltarArquivos();
  documentos.aviso = '';
  try {
    const { data } = await CrmAPI.createKitQuoteDocuments(
      pedidoDoDre({
        valor: dre.value.valor_projeto,
        cliente: {
          contact_id: cliente.value?.contact_id,
          nome: nomeCliente.value,
          cidade: cidadeCliente.value,
        },
        conta: {
          hoje: contaHoje.value,
          acrescimos: acrescimos.value.filter(a => parseMoney(a.valor) > 0),
          consumo_kwh: consumo.value,
          // a taxa mínima da CPFL que continua depende da ligação (13/11)
          rede: rede.value,
        },
        telhado: resultado.value?.telhado?.chave || telhado.value,
        opcao: escolhida.value,
      })
    );
    // guardado no cliente: os arquivos ficam na lista "Orçamentos deste cliente";
    // cliente digitado (fora da base) não tem onde guardar, então baixa daqui mesmo
    documentos.arquivos = data.orcamento
      ? []
      : (data.arquivos || []).map(paraArquivo);
    documentos.aviso = data.aviso || (data.avisos || []).join(' ');
    documentos.valor = data.dre?.valor_projeto || 0;
    gerado.value = true;
    aba.value = 'validos';
    if (data.orcamento) {
      await Promise.all([carregarHistorico(), carregarGerados()]);
      useAlert('Proposta pronta e guardada em "Orçamentos deste cliente".');
    } else if ((data.arquivos || []).length) {
      useAlert('Proposta e justificativa prontas.');
    }
  } catch (e) {
    // a conexão pode cair enquanto o servidor ainda termina e guarda a proposta:
    // antes de dizer que deu erro, confere se ela apareceu na lista do cliente
    const antes = new Set(historico.value.map(o => o.id));
    await new Promise(r => {
      setTimeout(r, 4000);
    });
    await Promise.all([carregarHistorico(), carregarGerados()]);
    const nova = historico.value.find(o => !antes.has(o.id));
    if (nova) {
      gerado.value = true;
      aba.value = 'validos';
      useAlert('Proposta pronta e guardada em "Orçamentos deste cliente".');
    } else {
      useAlert(erroDe(e, 'Não foi possível gerar os documentos.'));
    }
  } finally {
    gerando.value = false;
  }
};

// ── ⚡ orçamento em 1 clique (12/11, pedido do Guilherme): "aperto o botão, já gera o orçamento,
// ele me mostra se deu certo, eu valido e ele envia com a mensagem que o agente já enviaria".
// Faz na sequência o que o vendedor faria: puxa os dados do cliente → cota → preço (lucro 25%)
// → proposta em PDF. Para onde faltar alguma coisa e explica o quê; "Continuar" retoma.
// NÃO envia sozinho: o envio é o botão "Enviar pelo WhatsApp" do cartão, depois de conferir.
const AUTO_PASSOS = [
  { id: 'dados', nome: 'Dados do cliente (conta de luz, telhado, cidade)' },
  { id: 'cotacao', nome: 'Cotação nos fornecedores' },
  { id: 'preco', nome: 'Preço com lucro de 25%' },
  { id: 'proposta', nome: 'Proposta em PDF e resumo' },
];
const auto = reactive({
  ativo: false,
  rodando: false,
  passo: 0,
  erro: '',
  orcamento: null,
});
const autoPedido = ref(route.query.auto === '1');
const esperarPreco = async () => {
  const limite = Date.now() + 60000;
  while (dreCarregando.value && Date.now() < limite) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise(r => {
      setTimeout(r, 250);
    });
  }
};
const pararAuto = (passo, erro) => {
  auto.passo = passo;
  auto.erro = erro;
  auto.rodando = false;
};
const fazerSozinho = async () => {
  if (auto.rodando || !cliente.value || !podeCotar.value) return;
  auto.ativo = true;
  auto.rodando = true;
  auto.erro = '';
  auto.orcamento = null;
  document
    .getElementById('cot-auto')
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  // 1. dados: na 1ª vez puxa do resumo; no "Continuar" respeita o que foi digitado na tela
  auto.passo = 0;
  if (!parseMoney(contaHoje.value)) preencherDoCliente();
  if (!nomeCliente.value.trim() && cliente.value.name) {
    nomeCliente.value = cliente.value.name;
  }
  if (!parseMoney(contaHoje.value)) {
    pararAuto(
      0,
      'O resumo deste cliente ainda não tem o valor da conta de luz. Olhe a foto da conta na conversa, digite o valor aqui e aperte Continuar.'
    );
    return;
  }
  // 2. cotação (já escolhe a opção completa mais barata e calcula o preço a 25%)
  auto.passo = 1;
  await cotar();
  if (!resultado.value) {
    pararAuto(
      1,
      'A cotação não voltou. Confira os "Acessos dos fornecedores" e aperte Continuar.'
    );
    return;
  }
  if (!escolhida.value) {
    pararAuto(
      1,
      'Nenhum fornecedor trouxe um kit completo para este consumo. Escolha uma opção na etapa 3 (ou acrescente uma cotação na mão) e aperte Continuar.'
    );
    return;
  }
  // 3. preço
  auto.passo = 2;
  await esperarPreco();
  if (!dre.value) {
    pararAuto(2, dreErro.value || 'O preço não fechou. Confira a etapa 4.');
    return;
  }
  // 4. proposta
  auto.passo = 3;
  const antes = new Set(historico.value.map(o => o.id));
  await gerar();
  const novo = historico.value.find(o => !antes.has(o.id));
  if (!novo) {
    pararAuto(
      3,
      'A proposta não ficou pronta. Aperte Continuar para tentar de novo.'
    );
    return;
  }
  auto.orcamento = novo;
  auto.passo = AUTO_PASSOS.length;
  auto.rodando = false;
};
// depois de enviar (ou marcar), o cartão do painel mostra a situação nova
watch(historico, lista => {
  if (!auto.orcamento) return;
  auto.orcamento =
    lista.find(o => o.id === auto.orcamento.id) || auto.orcamento;
});
const fecharAuto = () => {
  auto.ativo = false;
  auto.erro = '';
};
// veio do botão "Gerar orçamento" da conversa (…/cotador?contact=<id>&auto=1): começa sozinho
// assim que o cliente carrega
watch(cliente, person => {
  if (!person || !autoPedido.value) return;
  autoPedido.value = false;
  nextTick(fazerSozinho);
});

const carregar = async () => {
  try {
    const { data } = await CrmAPI.getKitQuote();
    acesso.value = data.acesso || {};
    cidade.value = data.cidade || '';
    tarifa.value = data.tarifa || tarifa.value;
    telhados.value = data.telhados || [];
    geradorPdfLigado.value = !!data.gerador_pdf;
  } catch (e) {
    useAlert(erroDe(e, 'Não foi possível abrir o gerador de proposta.'));
  } finally {
    carregando.value = false;
  }
};

// ── tutorial em balões (12/11, pedido do Guilherme para o Fernando): abre sozinho
// na 1ª vez neste navegador; o botão "Tutorial" no topo reabre quando quiser ──
const TUTORIAL_KEY = 'cevico:tutorial:gerador-proposta:visto';
const tutorialAberto = ref(false);
const tutorialVisto = () => {
  try {
    return window.localStorage.getItem(TUTORIAL_KEY) === '1';
  } catch {
    return true;
  }
};
const marcarTutorialVisto = () => {
  try {
    window.localStorage.setItem(TUTORIAL_KEY, '1');
  } catch {
    // sem armazenamento: só não lembra
  }
};
const TUTORIAL_PASSOS = [
  {
    icon: 'i-lucide-sparkles',
    title: 'Do cliente à proposta em 5 minutos',
    text: 'Esta tela faz o orçamento inteiro: cota o kit nos fornecedores, calcula o preço com o lucro certo e gera a proposta do cliente em PDF.\nVocê também chega aqui pelo botão “Gerar orçamento” dentro da conversa do WhatsApp. O botão fica com cadeado até o cliente mandar a conta de luz.',
  },
  {
    target: '#cot-cliente',
    icon: 'i-lucide-user-round',
    title: '1 · Para quem é',
    text: 'Digite o nome ou o telefone do cliente, ou escolha quem está numa coluna do funil.\nSe você veio pelo botão da conversa, o cliente já chega escolhido.',
  },
  {
    target: '#cot-conta',
    icon: 'i-lucide-receipt-text',
    title: '2 · A conta de luz',
    text: 'Coloque o valor da conta de hoje. Se o cliente vai comprar ar-condicionado, carro elétrico ou piscina, acrescente quanto a conta vai subir por mês.\nO sistema transforma em kWh sozinho. Se você já sabe o consumo pela conta, pode trocar o número.',
  },
  {
    target: '#cot-telhado',
    icon: 'i-lucide-house',
    title: '3 · Telhado e rede',
    text: 'Escolha o tipo de telhado e a rede (monofásica, bifásica ou trifásica).\nO telhado define a estrutura que já vem junto na cotação.',
  },
  {
    target: '#cot-cotar',
    icon: 'i-lucide-search',
    title: '4 · Cotar nos fornecedores',
    text: 'Clique em “Cotar nos fornecedores”. Em alguns segundos voltam as opções da AVT e da Bluesun, com estrutura e frete.\nEsses valores são o NOSSO custo, não o preço do cliente.',
  },
  {
    icon: 'i-lucide-list-checks',
    title: '5 · Escolha o kit',
    text: 'Escolha micro inversor ou string. O custo do kit é a média dos fornecedores que vieram completos.\nCotou na Belenergy ou na Cordeiro por fora? Dá para acrescentar a cotação à mão.',
  },
  {
    icon: 'i-lucide-calculator',
    title: '6 · O preço',
    text: 'O preço já vem com 25% de lucro, o padrão. Dá para escolher 18% ou 30%, ou digitar o valor do projeto e clicar em “Recalcular com este valor”.\nFora da faixa de 18% a 30%, o lucro aparece em vermelho.',
  },
  {
    icon: 'i-lucide-file-text',
    title: '7 · Gerar a proposta',
    text: 'Clique em “Gerar proposta e justificativa”. Em uns 20 segundos saem os arquivos para baixar: a proposta do cliente e a justificativa do orçamento (PDF) e a imagem do resumo, boa para mandar no WhatsApp.',
  },
  {
    icon: 'i-lucide-send',
    title: '8 · Mandar e marcar como enviada',
    text: 'Mande a proposta e a imagem na conversa do cliente. Depois, em “Orçamentos deste cliente”, clique em “Marcar como enviada ao cliente”: o cartão vai para a coluna Orçamento Enviado.\nTodo orçamento fica guardado ali, com os PDFs, para abrir de novo quando quiser.',
  },
  {
    icon: 'i-lucide-clock',
    title: 'O prazo que o cliente ouviu',
    text: 'O atendente promete o orçamento “entre hoje e amanhã” (no fim de semana, “segunda de manhã”). Como sai em minutos aqui, quanto antes você mandar, mais o cliente se surpreende.\nPara rever este tutorial, clique em “Tutorial” no topo da tela.',
  },
];

// as 5 etapas no topo: feita (verde), a da vez (laranja) e as que faltam
const ETAPAS = [
  { id: 'cot-cliente', nome: 'Cliente', icone: 'i-lucide-user-round' },
  { id: 'cot-conta', nome: 'Conta de luz', icone: 'i-lucide-receipt-text' },
  { id: 'cot-opcoes', nome: 'Cotação', icone: 'i-lucide-search' },
  { id: 'cot-preco', nome: 'Preço', icone: 'i-lucide-calculator' },
  { id: 'cot-proposta', nome: 'Proposta', icone: 'i-lucide-file-text' },
];
const feitas = computed(() => [
  !!nomeCliente.value.trim(),
  !!parseMoney(contaHoje.value),
  !!resultado.value,
  !!dre.value,
  gerado.value,
]);
const etapaDaVez = computed(() => feitas.value.findIndex(f => !f));
const irPara = id =>
  document
    .getElementById(id)
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
const COR_FORNECEDOR = { Bluesun: '#2563eb', AVT: '#ea580c' };
const nomeTelhado = computed(
  () => telhados.value.find(t => t.chave === telhado.value)?.nome || ''
);

onMounted(async () => {
  carregarGerados();
  await carregar();
  if (!tutorialVisto()) {
    await nextTick();
    tutorialAberto.value = true;
  }
});
onBeforeUnmount(soltarArquivos);
// textos da tela (fora do template, como pede o eslint do projeto)
const TXT = {
  autoTitulo: 'Orçamento automático de',
  autoSub:
    'O sistema faz sozinho o que você faria: puxa os dados, cota, calcula o preço e gera a proposta. Nada vai para o cliente sem você apertar Enviar.',
  autoFechar: 'Fechar',
  autoContinuar: 'Continuar',
  autoPronto:
    'Pronto! Abra a proposta e o resumo para conferir. Estando certo, aperte "Enviar pelo WhatsApp": vai a mesma mensagem que o atendente manda, com a pergunta de fechamento, e a IA continua ligada na conversa.',
  autoVoltar: 'Voltar para a conversa',
  autoBotao: 'Fazer o orçamento sozinho',
  autoDica:
    'Puxa os dados do cliente, cota nos fornecedores, calcula o preço com 25% e gera a proposta para você conferir',
  orcamentosDesteCliente: 'Orçamentos deste cliente',
  geradoEm: 'Gerado em',
  por: 'por',
  lucroDe: 'lucro de',
  semArquivos: 'Sem PDF: o gerador de PDF não estava ligado.',
  enviadaEm: 'Enviada ao cliente em',
  marcarEnviada: 'Marcar como enviada ao cliente',
  marcarEnviadaDica:
    'Marcar como enviada põe a etiqueta "orçamento enviado" no cliente: o cartão vai para a coluna Orçamento Enviado e o acompanhamento começa.',
  crm: 'CRM',
  geradorDeProposta: 'Gerador de proposta',
  aContaDeLuz: 'A conta de luz',
  nomeNaProposta: 'Nome na proposta',
  nomeDoCliente: 'Nome do cliente',
  contaDeHojeR: 'Conta de hoje (R$ por mês)',
  t300: '300',
  oQueVaiAcrescentar:
    'O que vai acrescentar (ar-condicionado, carro elétrico, piscina)',
  t2AresCondicionados: '2 ares-condicionados',
  rAMaisPor: 'R$ a mais por mês',
  tirarEstaLinha: 'Tirar esta linha',
  acrescentarOutro: 'Acrescentar outro',
  contaConsiderada: 'Conta considerada',
  porMes: 'por mês',
  r: '÷ R$',
  porKwh: 'por kWh =',
  kwhPorMes: 'kWh por mês',
  consumoUsadoNaCotacao: 'Consumo usado na cotação (kWh por mês)',
  t490: '490',
  voltarParaOConsumo: 'Voltar para o consumo calculado pela conta',
  tipoDeTelhado: 'Tipo de telhado',
  rede: 'Rede',
  opcoesDeKit: 'Opções de kit',
  kwpPara: 'kWp para',
  respondeuCom: 'respondeu com',
  opcoes: 'opções.',
  vieramSem: 'Vieram sem',
  ficamForaDoPreco: ': ficam fora do preço médio.',
  naoRespondeu: 'não respondeu.',
  nenhumaOpcaoDe: 'Nenhuma opção de',
  voltouVejaOsMotivos: 'voltou. Veja os motivos acima.',
  kit: 'kit',
  frete: '+ frete',
  placas: 'placas ·',
  kwp: 'kWp',
  precoDeCustoDo:
    'Preço de custo do kit no fornecedor. Não é o preço para o cliente.',
  precoEDreDo: 'Preço e DRE do projeto',
  custoDoKitMedia: 'Custo do kit: média das cotações completas',
  fornecedorBelenergyCordeiro: 'Fornecedor (Belenergy, Cordeiro)',
  kitEstruturaFreteR: 'Kit + estrutura + frete (R$)',
  tirarEstaCotacao: 'Tirar esta cotação',
  acrescentarCotacaoFeitaNa: 'Acrescentar cotação feita na mão',
  mediaUsada: 'Média usada:',
  aTabelaDeAdequacao: 'A tabela de adequação não tem faixa para',
  placasCom: 'placas com',
  informeOValorDa: '. Informe o valor da adequação deste projeto.',
  adequacaoR: 'Adequação (R$)',
  usarEsteValor: 'Usar este valor',
  calculandoOPreco: 'Calculando o preço.',
  lucroLiquidoDoOrcamento: 'Lucro líquido do orçamento',
  valorDoProjetoR: 'Valor do projeto (R$): ajuste se quiser',
  recalcularComEsteValor: 'Recalcular com este valor',
  deLucroLiquido: 'de lucro líquido (',
  dedutiveis: 'Dedutíveis',
  imposto: 'Imposto (',
  indedutiveis: 'Indedutíveis',
  custoTotal: 'Custo total',
  adequacao: 'Adequação:',
  quantoCobrarEmCada: 'Quanto cobrar em cada ponta',
  lucroDe18: 'Lucro de 18%',
  lucroDe25Padrao: 'Lucro de 25% (padrão)',
  lucroDe30: 'Lucro de 30%',
  lucroPorSocio: 'Lucro por sócio',
  baixar: 'Baixar',
  tutorial: 'Tutorial',
  faixaBoa: 'faixa boa: 18% a 30%',
  etapas: 'Etapas do orçamento',
  orcGerados: 'Orçamentos gerados',
  orcGeradosSub:
    'Cada proposta vale 7 dias. Os enviados ficam guardados com os PDFs.',
  buscarCliente: 'Buscar pelo nome do cliente',
  nenhumNaAba: 'Nenhum orçamento nesta aba.',
  paraQuem: 'Para quem é a proposta',
  paraQuemSub: 'Quem vai receber a proposta.',
  preencher: 'Preencher com os dados do cliente',
  contaSub: 'O valor de hoje, o que vai aumentar, o telhado e a rede.',
  lucroLiquido: 'Lucro líquido',
  aProposta: 'A proposta',
  propostaSub:
    'Proposta do cliente, justificativa e a imagem do resumo para o WhatsApp.',
  resumo: 'Resumo do orçamento',
  consumoRot: 'Consumo',
  telhadoRede: 'Telhado · rede',
  kitRot: 'Kit',
  valorProjeto: 'Valor do projeto',
  valorAparece: 'O valor aparece aqui assim que você escolher um kit.',
  reverOPasso: 'Rever o passo a passo em balões',
  oGeradorDePdf:
    'O gerador de PDF ainda não está ligado neste servidor. O preço e o DRE acima já valem.',
};
</script>

<template>
  <div class="cot flex flex-col h-full w-full overflow-hidden">
    <!-- Header no padrão das telas do CRM -->
    <div
      class="cot-top flex items-center gap-3 px-6 py-4 flex-shrink-0 flex-wrap"
    >
      <button
        class="flex items-center gap-1 text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="router.push({ name: 'crm_board' })"
      >
        <span class="i-lucide-arrow-left" />
        {{ TXT.crm }}
      </button>
      <span class="text-n-slate-8">/</span>
      <h1
        class="text-base font-semibold text-n-slate-12 flex items-center gap-2"
      >
        <span class="cot-logo">
          <span class="i-lucide-file-text" />
        </span>
        {{ TXT.geradorDeProposta }}
        <CevicoViewOnlyPill v-if="!podeCotar" />
      </h1>
      <div class="flex-1" />
      <button
        type="button"
        class="cot-ghost text-n-slate-12"
        :title="TXT.reverOPasso"
        @click="tutorialAberto = true"
      >
        <span class="i-lucide-graduation-cap" />
        {{ TXT.tutorial }}
      </button>
    </div>

    <div class="flex-1 overflow-y-auto">
      <div
        class="max-w-6xl mx-auto px-4 sm:px-8 py-6 sm:py-10 flex flex-col gap-8"
      >
        <!-- as 5 etapas -->
        <nav class="cot-steps" :aria-label="TXT.etapas">
          <button
            v-for="(e, i) in ETAPAS"
            :key="e.id"
            type="button"
            class="cot-step"
            :class="{
              'is-done': feitas[i],
              'is-now': i === etapaDaVez,
            }"
            @click="irPara(e.id)"
          >
            <span class="cot-step-dot">
              <span :class="feitas[i] ? 'i-lucide-check' : e.icone" />
            </span>
            <span class="cot-step-txt">
              <span class="cot-step-n">{{ i + 1 }}</span>
              <span class="cot-step-name text-n-slate-12">{{ e.nome }}</span>
            </span>
          </button>
        </nav>

        <!-- ⚡ orçamento em 1 clique -->
        <section
          v-if="auto.ativo"
          id="cot-auto"
          class="cot-sec cot-violet cot-auto"
        >
          <div class="cot-head">
            <span class="cot-ico"><i class="i-lucide-zap" /></span>
            <div class="min-w-0 flex-1">
              <h2 class="cot-title text-n-slate-12">
                {{ TXT.autoTitulo }} {{ nomeCliente }}
              </h2>
              <p class="cot-sub text-n-slate-11">{{ TXT.autoSub }}</p>
            </div>
            <button
              type="button"
              class="cot-ghost text-n-slate-12"
              :disabled="auto.rodando"
              @click="fecharAuto"
            >
              <span class="i-lucide-x" />
              {{ TXT.autoFechar }}
            </button>
          </div>
          <ol class="cot-auto-list">
            <li
              v-for="(p, i) in AUTO_PASSOS"
              :key="p.id"
              class="cot-auto-item"
              :class="{
                'is-done': i < auto.passo,
                'is-now': i === auto.passo && auto.rodando,
                'is-err': i === auto.passo && !!auto.erro,
              }"
            >
              <span class="cot-auto-dot">
                <span
                  :class="
                    i < auto.passo
                      ? 'i-lucide-check'
                      : i === auto.passo && auto.erro
                        ? 'i-lucide-alert-triangle'
                        : i === auto.passo && auto.rodando
                          ? 'i-lucide-loader-circle animate-spin'
                          : 'i-lucide-circle'
                  "
                />
              </span>
              <span class="text-sm text-n-slate-12">{{ p.nome }}</span>
            </li>
          </ol>
          <div v-if="auto.erro" class="cot-auto-erro">
            <p class="text-sm text-n-slate-12">{{ auto.erro }}</p>
            <label v-if="auto.passo === 0" class="cot-field cot-auto-conta">
              <span class="cot-lab text-n-slate-11">{{
                TXT.contaDeHojeR
              }}</span>
              <input
                v-model="contaHoje"
                type="text"
                inputmode="decimal"
                :placeholder="TXT.t300"
                class="cot-input !mb-0 text-n-slate-12"
                @keyup.enter="fazerSozinho"
              />
            </label>
            <button
              type="button"
              class="cot-btn2 text-n-slate-12"
              @click="fazerSozinho"
            >
              <span class="i-lucide-play" />
              {{ TXT.autoContinuar }}
            </button>
          </div>
          <div v-if="auto.orcamento" class="flex flex-col gap-3">
            <p class="text-sm font-semibold text-n-slate-12">
              {{ TXT.autoPronto }}
            </p>
            <div class="cot-cards">
              <KitQuoteCard
                :orcamento="auto.orcamento"
                :mostrar-cliente="false"
                :pode-editar="podeCotar"
                :ocupado="marcando === auto.orcamento.id"
                @enviar="marcarEnviada"
                @whatsapp="enviarWhatsapp"
                @excluir="excluirOrcamento"
                @editar="editarOrcamento"
              />
            </div>
            <button
              v-if="auto.orcamento.enviado_em"
              type="button"
              class="cot-btn2 text-n-slate-12 self-start"
              @click="router.back()"
            >
              <span class="i-lucide-message-circle" />
              {{ TXT.autoVoltar }}
            </button>
          </div>
        </section>

        <!-- 0. Orçamentos gerados (toda a conta) -->
        <section
          v-if="gerados.length || lixeira.total"
          class="cot-sec cot-green"
        >
          <div class="cot-head">
            <span class="cot-ico"><i class="i-lucide-folder-check" /></span>
            <div class="min-w-0 flex-1">
              <h2 class="cot-title text-n-slate-12">{{ TXT.orcGerados }}</h2>
              <p class="cot-sub text-n-slate-11">{{ TXT.orcGeradosSub }}</p>
            </div>
            <div class="cot-seg">
              <button
                v-for="a in abasVisiveis"
                :key="a.id"
                type="button"
                :class="{ 'is-on': aba === a.id }"
                @click="aba = a.id"
              >
                {{ a.nome }}
                <span class="cot-seg-n">{{ contagem[a.id] }}</span>
              </button>
            </div>
          </div>
          <div class="flex flex-col sm:flex-row sm:items-center gap-3">
            <label class="cot-search flex-1">
              <span class="i-lucide-search text-n-slate-10" />
              <input
                v-model="busca"
                type="search"
                :placeholder="TXT.buscarCliente"
                class="!mb-0 text-n-slate-12"
              />
            </label>
            <div class="cot-seg cot-seg-sm">
              <button
                v-for="o in ORDENS"
                :key="o.id"
                type="button"
                :class="{ 'is-on': ordem === o.id }"
                @click="ordem = o.id"
              >
                {{ o.nome }}
              </button>
            </div>
          </div>
          <div v-if="geradosDaAba.length" class="cot-cards">
            <KitQuoteCard
              v-for="o in geradosDaAba"
              :key="o.id"
              :orcamento="o"
              :na-lixeira="aba === 'lixeira'"
              :pode-editar="podeCotar"
              :ocupado="marcando === o.id"
              @enviar="marcarEnviada"
              @whatsapp="enviarWhatsapp"
              @abrir="abrirCliente"
              @excluir="excluirOrcamento"
              @editar="editarOrcamento"
              @restaurar="restaurarOrcamento"
            />
          </div>
          <p v-else class="cot-empty text-n-slate-11">{{ TXT.nenhumNaAba }}</p>
        </section>

        <div class="cot-grid">
          <div class="flex flex-col gap-8 min-w-0">
            <!-- 1. Para quem é a proposta -->
            <section id="cot-cliente" class="cot-sec cot-blue">
              <div class="cot-head">
                <span class="cot-ico"><i class="i-lucide-user-round" /></span>
                <div class="min-w-0 flex-1">
                  <h2 class="cot-title text-n-slate-12">
                    <span class="cot-n">{{ 1 }}</span>
                    {{ TXT.paraQuem }}
                  </h2>
                  <p class="cot-sub text-n-slate-11">{{ TXT.paraQuemSub }}</p>
                </div>
              </div>
              <div class="cot-picker">
                <ProposalClientPicker
                  :key="pickerKey"
                  v-model="cliente"
                  :initial-contact-id="route.query.contact"
                />
              </div>
              <div
                v-if="cliente"
                class="cot-prefill flex flex-col sm:flex-row sm:items-center gap-3"
              >
                <button
                  type="button"
                  class="cot-btn2 text-n-slate-12"
                  :disabled="!podeCotar"
                  @click="preencherDoCliente"
                >
                  <span class="i-lucide-wand-sparkles" />
                  {{ TXT.preencher }}
                </button>
                <button
                  type="button"
                  class="cot-btn2 cot-btn-auto text-n-slate-12"
                  :disabled="!podeCotar || auto.rodando"
                  :title="TXT.autoDica"
                  @click="fazerSozinho"
                >
                  <span class="i-lucide-zap" />
                  {{ TXT.autoBotao }}
                </button>
                <p class="text-sm text-n-slate-11">
                  {{
                    preenchido ||
                    (temDadosDoCliente
                      ? 'Puxa a conta de luz, o que vai aumentar, a cidade e o telhado do resumo do cliente.'
                      : 'O resumo deste cliente ainda não tem a conta de luz: preencha abaixo.')
                  }}
                </p>
              </div>
            </section>

            <!-- 2. A conta de luz, o telhado e a rede -->
            <section id="cot-conta" class="cot-sec cot-amber">
              <div class="cot-head">
                <span class="cot-ico"><i class="i-lucide-receipt-text" /></span>
                <div class="min-w-0 flex-1">
                  <h2 class="cot-title text-n-slate-12">
                    <span class="cot-n">{{ 2 }}</span> {{ TXT.aContaDeLuz }}
                  </h2>
                  <p class="cot-sub text-n-slate-11">{{ TXT.contaSub }}</p>
                </div>
              </div>

              <div class="grid sm:grid-cols-2 gap-4">
                <label class="cot-field">
                  <span class="cot-lab text-n-slate-11">{{
                    TXT.nomeNaProposta
                  }}</span>
                  <input
                    v-model="nomeCliente"
                    type="text"
                    :placeholder="TXT.nomeDoCliente"
                    class="cot-input !mb-0 text-n-slate-12"
                    :disabled="!podeCotar"
                  />
                </label>
                <label class="cot-field">
                  <span class="cot-lab text-n-slate-11">{{
                    TXT.contaDeHojeR
                  }}</span>
                  <input
                    v-model="contaHoje"
                    type="text"
                    inputmode="decimal"
                    :placeholder="TXT.t300"
                    class="cot-input cot-input-lg !mb-0 text-n-slate-12"
                    :disabled="!podeCotar"
                  />
                </label>
              </div>

              <div class="cot-block">
                <p class="cot-lab text-n-slate-11">
                  {{ TXT.oQueVaiAcrescentar }}
                </p>
                <div
                  v-for="(a, i) in acrescimos"
                  :key="i"
                  class="flex flex-col sm:flex-row gap-2"
                >
                  <input
                    v-model="a.rotulo"
                    type="text"
                    :placeholder="TXT.t2AresCondicionados"
                    class="cot-input !mb-0 flex-1 text-n-slate-12"
                    :disabled="!podeCotar"
                  />
                  <div class="flex gap-2">
                    <input
                      v-model="a.valor"
                      type="text"
                      inputmode="decimal"
                      :placeholder="TXT.rAMaisPor"
                      class="cot-input !mb-0 flex-1 sm:w-44 text-n-slate-12"
                      :disabled="!podeCotar"
                    />
                    <button
                      type="button"
                      class="cot-icon-btn text-n-slate-11"
                      :title="TXT.tirarEstaLinha"
                      @click="tirarAcrescimo(i)"
                    >
                      <span class="i-lucide-x" />
                    </button>
                  </div>
                </div>
                <button
                  type="button"
                  class="cot-link self-start"
                  @click="maisAcrescimo"
                >
                  <span class="i-lucide-plus" />
                  {{ TXT.acrescentarOutro }}
                </button>
              </div>

              <div class="cot-tile cot-tile-accent cot-conta">
                <div class="flex-1 min-w-0">
                  <p class="cot-lab text-n-slate-11">
                    {{ TXT.contaConsiderada }}
                  </p>
                  <p class="cot-big text-n-slate-12">
                    {{ reais(contaTotal) }}
                    <span class="text-sm font-medium text-n-slate-11">{{
                      TXT.porMes
                    }}</span>
                  </p>
                  <p class="text-xs text-n-slate-11">
                    {{ reais(contaTotal) }} {{ TXT.r }} {{ tarifaTexto }}
                    {{ TXT.porKwh }} {{ numero(consumoCalculado) }}
                    {{ TXT.kwhPorMes }}
                  </p>
                </div>
                <label class="cot-field sm:w-56">
                  <span class="cot-lab text-n-slate-11">{{
                    TXT.consumoUsadoNaCotacao
                  }}</span>
                  <input
                    v-model="consumo"
                    type="text"
                    inputmode="decimal"
                    :placeholder="TXT.t490"
                    class="cot-input cot-input-lg !mb-0 text-n-slate-12"
                    :disabled="!podeCotar"
                    @input="ajustarConsumo"
                  />
                  <button
                    v-if="consumoNaMao && consumoCalculado"
                    type="button"
                    class="cot-link"
                    @click="consumoPelaConta"
                  >
                    {{ TXT.voltarParaOConsumo }}
                  </button>
                </label>
              </div>

              <div class="grid md:grid-cols-[1fr_auto] gap-5">
                <div id="cot-telhado" class="cot-block">
                  <p class="cot-lab text-n-slate-11">{{ TXT.tipoDeTelhado }}</p>
                  <div class="flex flex-wrap gap-2">
                    <button
                      v-for="t in telhados"
                      :key="t.chave"
                      type="button"
                      class="cot-chip text-n-slate-12"
                      :class="{ 'is-on': telhado === t.chave }"
                      :disabled="!podeCotar"
                      @click="telhado = t.chave"
                    >
                      {{ t.nome }}
                    </button>
                  </div>
                </div>
                <div class="cot-block">
                  <p class="cot-lab text-n-slate-11">{{ TXT.rede }}</p>
                  <div class="flex flex-wrap gap-2">
                    <button
                      v-for="r in REDES"
                      :key="r.id"
                      type="button"
                      class="cot-chip text-n-slate-12"
                      :class="{ 'is-on': rede === r.id }"
                      :disabled="!podeCotar"
                      @click="rede = r.id"
                    >
                      {{ r.nome }}
                    </button>
                  </div>
                </div>
              </div>

              <div
                id="cot-cotar"
                class="cot-actions flex flex-col sm:flex-row sm:items-center gap-3"
              >
                <button
                  type="button"
                  class="cot-btn"
                  :disabled="!podeCotar || cotando || !parseMoney(consumo)"
                  @click="cotar"
                >
                  <span
                    :class="
                      cotando
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-search'
                    "
                  />
                  {{ cotando ? 'Cotando' : 'Cotar nos fornecedores' }}
                </button>
                <p class="text-sm text-n-slate-11">
                  {{
                    cotando
                      ? 'Consultando AVT e Bluesun. Leva alguns segundos.'
                      : `Cotação para ${cidade}, com a estrutura do telhado e o frete.`
                  }}
                </p>
              </div>
            </section>

            <!-- 3. As opções -->
            <section v-if="resultado" id="cot-opcoes" class="cot-sec cot-teal">
              <div class="cot-head">
                <span class="cot-ico"><i class="i-lucide-boxes" /></span>
                <div class="min-w-0 flex-1">
                  <h2 class="cot-title text-n-slate-12">
                    <span class="cot-n">{{ 3 }}</span> {{ TXT.opcoesDeKit }}
                  </h2>
                  <p class="cot-sub text-n-slate-11">
                    {{ numero(resultado.potencia_necessaria_kwp) }}
                    {{ TXT.kwpPara }} {{ numero(resultado.consumo_kwh_mes) }}
                    {{ TXT.kwhPorMes }} · {{ TXT.precoDeCustoDo }}
                  </p>
                </div>
              </div>

              <div class="flex flex-wrap gap-2">
                <span
                  v-for="f in resultado.fornecedores"
                  :key="f.fornecedor"
                  class="cot-sup"
                  :class="f.ok ? (f.falta ? 'is-warn' : 'is-ok') : 'is-bad'"
                  :title="
                    f.ok
                      ? f.falta
                        ? `Vieram sem ${f.falta}: ficam fora do preço médio.`
                        : ''
                      : f.motivo
                  "
                >
                  <span
                    :class="
                      f.ok
                        ? f.falta
                          ? 'i-lucide-circle-alert'
                          : 'i-lucide-circle-check'
                        : 'i-lucide-circle-x'
                    "
                  />
                  <strong>{{ f.fornecedor }}</strong>
                  <template v-if="f.ok">
                    {{ f.opcoes }} {{ TXT.opcoes.replace('.', '') }}
                    <template v-if="f.falta">{{ `· sem ${f.falta}` }}</template>
                  </template>
                  <template v-else>{{ f.motivo || 'não respondeu' }}</template>
                </span>
              </div>

              <div class="cot-seg cot-seg-full">
                <button
                  v-for="t in TIPOS"
                  :key="t.id"
                  type="button"
                  :class="{ 'is-on': tipo === t.id }"
                  @click="trocarTipo(t.id)"
                >
                  {{ t.nome }}
                </button>
              </div>

              <p v-if="!opcoesDoTipo.length" class="cot-empty text-n-slate-11">
                {{ TXT.nenhumaOpcaoDe }} {{ NOME_TIPO[tipo].toLowerCase() }}
                {{ TXT.voltouVejaOsMotivos }}
              </p>

              <div class="flex flex-col gap-3">
                <button
                  v-for="(o, i) in opcoesDoTipo"
                  :key="i"
                  type="button"
                  class="cot-opt"
                  :class="{ 'is-on': escolhida === o }"
                  @click="escolher(o)"
                >
                  <span class="cot-opt-price">
                    <span class="cot-big text-n-slate-12">{{
                      reais(o.total)
                    }}</span>
                    <span class="text-xs text-n-slate-11">
                      {{ TXT.kit }} {{ reais(o.preco) }}
                      <template v-if="o.frete !== null">
                        {{ TXT.frete }} {{ reais(o.frete) }}
                      </template>
                    </span>
                  </span>
                  <span class="flex-1 min-w-0 flex flex-col gap-1.5">
                    <span class="flex flex-wrap items-center gap-2 text-xs">
                      <span
                        class="cot-pill"
                        :style="{
                          background: COR_FORNECEDOR[o.fornecedor] || '#475569',
                        }"
                      >
                        {{ o.fornecedor }}
                      </span>
                      <span class="font-semibold text-n-slate-12">
                        {{ o.placas }} {{ TXT.placas }}
                        {{ numero(o.potencia_kwp) }} {{ TXT.kwp }}
                      </span>
                      <span
                        class="cot-tag"
                        :class="o.completa ? 'is-ok' : 'is-bad'"
                      >
                        {{
                          o.completa
                            ? 'Com estrutura e frete'
                            : `Sem ${o.falta}`
                        }}
                      </span>
                    </span>
                    <span class="text-sm text-n-slate-12 break-words">
                      {{ o.paineis }}
                    </span>
                    <span class="text-sm text-n-slate-11 break-words">
                      {{ o.inversor }}
                    </span>
                    <span v-if="o.obs" class="text-xs text-n-slate-10">
                      {{ o.obs }}
                    </span>
                  </span>
                  <span class="cot-opt-pick">
                    <span
                      :class="
                        escolhida === o
                          ? 'i-lucide-circle-check-big'
                          : 'i-lucide-circle'
                      "
                    />
                    {{ escolhida === o ? 'Escolhida' : 'Escolher' }}
                  </span>
                </button>
              </div>
            </section>

            <!-- 4. Preço e DRE -->
            <section v-if="escolhida" id="cot-preco" class="cot-sec cot-violet">
              <div class="cot-head">
                <span class="cot-ico"><i class="i-lucide-calculator" /></span>
                <div class="min-w-0 flex-1">
                  <h2 class="cot-title text-n-slate-12">
                    <span class="cot-n">{{ 4 }}</span> {{ TXT.precoEDreDo }}
                  </h2>
                  <p class="cot-sub text-n-slate-11">
                    {{ NOME_TIPO[escolhida.tipo] }} · {{ escolhida.placas }}
                    {{ TXT.placas }} {{ numero(escolhida.potencia_kwp) }}
                    {{ TXT.kwp }}
                  </p>
                </div>
              </div>

              <!-- custo do kit: média dos fornecedores com cotação completa -->
              <div class="cot-tile flex flex-col gap-3">
                <p class="cot-lab text-n-slate-11">{{ TXT.custoDoKitMedia }}</p>
                <div
                  v-for="q in cotacoes.filter(c => !c.manual)"
                  :key="q.fornecedor"
                  class="cot-row"
                  :class="
                    q.entra_na_media ? 'text-n-slate-12' : 'text-n-slate-10'
                  "
                >
                  <strong class="w-24 flex-shrink-0">{{ q.fornecedor }}</strong>
                  <span
                    class="tabular-nums font-semibold"
                    :class="q.entra_na_media ? '' : 'line-through'"
                  >
                    {{ reais(q.valor) }}
                  </span>
                  <span class="text-xs text-n-slate-11 flex-1 min-w-0">{{
                    q.detalhe
                  }}</span>
                  <span
                    class="cot-tag"
                    :class="q.entra_na_media ? 'is-ok' : 'is-bad'"
                  >
                    {{ q.entra_na_media ? 'Entra na média' : 'Fora da média' }}
                  </span>
                </div>
                <div
                  v-for="(m, i) in cotacoesNaMao"
                  :key="`m${i}`"
                  class="flex flex-col sm:flex-row gap-2"
                >
                  <input
                    v-model="m.fornecedor"
                    type="text"
                    :placeholder="TXT.fornecedorBelenergyCordeiro"
                    class="cot-input !mb-0 flex-1 text-n-slate-12"
                  />
                  <div class="flex gap-2">
                    <input
                      v-model="m.valor"
                      type="text"
                      inputmode="decimal"
                      :placeholder="TXT.kitEstruturaFreteR"
                      class="cot-input !mb-0 flex-1 sm:w-56 text-n-slate-12"
                      @keyup.enter="calcularDre()"
                      @blur="calcularDre()"
                    />
                    <button
                      type="button"
                      class="cot-icon-btn text-n-slate-11"
                      :title="TXT.tirarEstaCotacao"
                      @click="tirarCotacao(i)"
                    >
                      <span class="i-lucide-x" />
                    </button>
                  </div>
                </div>
                <div class="flex flex-wrap items-center gap-x-5 gap-y-2">
                  <button type="button" class="cot-link" @click="maisCotacao">
                    <span class="i-lucide-plus" />
                    {{ TXT.acrescentarCotacaoFeitaNa }}
                  </button>
                  <p v-if="media !== null" class="text-sm text-n-slate-12">
                    {{ TXT.mediaUsada }}
                    <strong class="tabular-nums">{{ reais(media) }}</strong>
                  </p>
                </div>
              </div>

              <!-- adequação fora da tabela: valor manual, sem inventar -->
              <div
                v-if="precisaAdequacao"
                class="cot-alert flex flex-col sm:flex-row sm:items-end gap-3"
              >
                <p class="flex-1 text-sm text-n-slate-12">
                  {{ TXT.aTabelaDeAdequacao }}
                  {{ escolhida.placas }} {{ TXT.placasCom }}
                  {{ NOME_TIPO[escolhida.tipo].toLowerCase()
                  }}{{ TXT.informeOValorDa }}
                </p>
                <label class="cot-field sm:w-48">
                  <span class="cot-lab text-n-slate-11">{{
                    TXT.adequacaoR
                  }}</span>
                  <input
                    v-model="adequacaoNaMao"
                    type="text"
                    inputmode="decimal"
                    class="cot-input !mb-0 text-n-slate-12"
                    @keyup.enter="calcularDre()"
                  />
                </label>
                <button
                  type="button"
                  class="cot-btn2 text-n-slate-12"
                  :disabled="dreCarregando || !parseMoney(adequacaoNaMao)"
                  @click="calcularDre()"
                >
                  {{ TXT.usarEsteValor }}
                </button>
              </div>

              <p
                v-if="dreErro && !(precisaAdequacao && !dre)"
                class="cot-error"
              >
                {{ dreErro }}
              </p>
              <p v-if="dreCarregando && !dre" class="text-sm text-n-slate-11">
                {{ TXT.calculandoOPreco }}
              </p>

              <template v-if="dre">
                <!-- o preço -->
                <div class="cot-block">
                  <p class="cot-lab text-n-slate-11">
                    {{ TXT.lucroLiquidoDoOrcamento }}
                  </p>
                  <div class="cot-range">
                    <input
                      type="range"
                      class="cot-range-in"
                      :min="BARRA.min"
                      :max="BARRA.max"
                      :step="BARRA.passo"
                      :value="margemBarra"
                      :style="{
                        '--fill': `${((margemBarra - BARRA.min) / (BARRA.max - BARRA.min)) * 100}%`,
                        '--bar': corDaBarra,
                      }"
                      :disabled="!podeCotar"
                      @input="arrastarMargem"
                    />
                    <span class="cot-range-val" :style="{ color: corDaBarra }">
                      {{ pct(margemBarra) }}
                    </span>
                  </div>
                  <div class="cot-range-marks text-n-slate-10">
                    <span>{{ pct(BARRA.min) }}</span>
                    <span>{{ TXT.faixaBoa }}</span>
                    <span>{{ pct(BARRA.max) }}</span>
                  </div>
                  <div class="flex flex-wrap gap-2">
                    <button
                      v-for="m in MARGENS"
                      :key="m"
                      type="button"
                      class="cot-chip text-n-slate-12"
                      :class="{ 'is-on': margemAtiva(m) }"
                      :disabled="dreCarregando"
                      @click="usarMargem(m)"
                    >
                      {{ pct(m) }}{{ m === 0.25 ? ' · padrão' : '' }}
                    </button>
                  </div>
                </div>

                <div class="grid md:grid-cols-2 gap-4">
                  <div class="cot-tile flex flex-col gap-3">
                    <label class="cot-field">
                      <span class="cot-lab text-n-slate-11">{{
                        TXT.valorDoProjetoR
                      }}</span>
                      <input
                        v-model="valorNaMao"
                        type="text"
                        inputmode="decimal"
                        class="cot-input cot-input-xl !mb-0 text-n-slate-12"
                        @keyup.enter="usarValor"
                      />
                    </label>
                    <button
                      type="button"
                      class="cot-btn2 text-n-slate-12 self-start"
                      :disabled="dreCarregando"
                      @click="usarValor"
                    >
                      <span class="i-lucide-refresh-cw" />
                      {{ TXT.recalcularComEsteValor }}
                    </button>
                  </div>
                  <div
                    class="cot-tile cot-lucro"
                    :class="dre.na_faixa ? 'is-ok' : 'is-bad'"
                  >
                    <p class="cot-lab">{{ TXT.lucroLiquido }}</p>
                    <p class="cot-big">{{ reais(dre.lucro) }}</p>
                    <p class="text-sm font-semibold">
                      {{ pct(dre.margem) }} ·
                      {{
                        dre.na_faixa
                          ? 'dentro da faixa de 18% a 30%'
                          : 'fora da faixa de 18% a 30%: confira'
                      }}
                    </p>
                  </div>
                </div>

                <!-- o DRE -->
                <div class="grid md:grid-cols-2 gap-4 text-sm">
                  <div class="cot-tile">
                    <p class="cot-lab text-n-slate-11 mb-2">
                      {{ TXT.dedutiveis }}
                    </p>
                    <p
                      v-for="l in dre.dedutiveis.filter(x => x.valor)"
                      :key="l.nome"
                      class="cot-line text-n-slate-12"
                    >
                      <span>{{ l.nome }}</span>
                      <span class="tabular-nums whitespace-nowrap">{{
                        reais(l.valor)
                      }}</span>
                    </p>
                    <p class="cot-line cot-line-tax">
                      <span>{{ TXT.imposto }}{{ pct(dre.taxa_imposto) }})</span>
                      <span class="tabular-nums whitespace-nowrap">{{
                        reais(dre.imposto)
                      }}</span>
                    </p>
                  </div>
                  <div class="cot-tile">
                    <p class="cot-lab text-n-slate-11 mb-2">
                      {{ TXT.indedutiveis }}
                    </p>
                    <p
                      v-for="l in dre.indedutiveis.filter(x => x.valor)"
                      :key="l.nome"
                      class="cot-line text-n-slate-12"
                    >
                      <span>{{ l.nome }}</span>
                      <span class="tabular-nums whitespace-nowrap">{{
                        reais(l.valor)
                      }}</span>
                    </p>
                    <p class="cot-line cot-line-total text-n-slate-12">
                      <span>{{ TXT.custoTotal }}</span>
                      <span class="tabular-nums whitespace-nowrap">{{
                        reais(dre.custo_total)
                      }}</span>
                    </p>
                  </div>
                </div>
                <p class="text-xs text-n-slate-11">
                  {{ TXT.adequacao }}
                  <strong class="text-n-slate-12">
                    {{ dre.adequacao.faixa }} = {{ reais(dre.adequacao.valor) }}
                  </strong>
                  {{
                    dre.adequacao.manual
                      ? '(a tabela não tem faixa para este projeto)'
                      : '(tabela de adequação)'
                  }}
                </p>

                <div class="grid md:grid-cols-2 gap-4 text-sm">
                  <div class="cot-tile">
                    <p class="cot-lab text-n-slate-11 mb-2">
                      {{ TXT.quantoCobrarEmCada }}
                    </p>
                    <p class="cot-line text-n-slate-11">
                      <span>{{ TXT.lucroDe18 }}</span>
                      <span class="tabular-nums">{{
                        reais(dre.faixa.minimo)
                      }}</span>
                    </p>
                    <p class="cot-line font-semibold text-n-slate-12">
                      <span>{{ TXT.lucroDe25Padrao }}</span>
                      <span class="tabular-nums">{{
                        reais(dre.faixa.padrao)
                      }}</span>
                    </p>
                    <p class="cot-line text-n-slate-11">
                      <span>{{ TXT.lucroDe30 }}</span>
                      <span class="tabular-nums">{{
                        reais(dre.faixa.maximo)
                      }}</span>
                    </p>
                  </div>
                  <div class="cot-tile">
                    <p class="cot-lab text-n-slate-11 mb-2">
                      {{ TXT.lucroPorSocio }}
                    </p>
                    <p
                      v-for="socio in dre.socios"
                      :key="socio.nome"
                      class="cot-line text-n-slate-12"
                    >
                      <span>{{ socio.nome }} ({{ pct(socio.parte) }})</span>
                      <span class="tabular-nums">{{ reais(socio.valor) }}</span>
                    </p>
                  </div>
                </div>
              </template>
            </section>

            <!-- 5. gerar os dois documentos -->
            <section v-if="dre" id="cot-proposta" class="cot-sec cot-orange">
              <div class="cot-head">
                <span class="cot-ico"><i class="i-lucide-file-text" /></span>
                <div class="min-w-0 flex-1">
                  <h2 class="cot-title text-n-slate-12">
                    <span class="cot-n">{{ 5 }}</span>
                    {{ TXT.aProposta }}
                  </h2>
                  <p class="cot-sub text-n-slate-11">{{ TXT.propostaSub }}</p>
                </div>
              </div>
              <div class="flex flex-col sm:flex-row sm:items-center gap-3">
                <button
                  type="button"
                  class="cot-btn cot-btn-lg"
                  :disabled="!podeCotar || gerando || !!faltaParaGerar"
                  @click="gerar"
                >
                  <span
                    :class="
                      gerando
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-sparkles'
                    "
                  />
                  {{ gerando ? 'Gerando' : 'Gerar proposta e justificativa' }}
                </button>
                <p class="text-sm text-n-slate-11">
                  {{
                    faltaParaGerar ||
                    (gerando
                      ? 'Montando os dois PDFs. Leva uns 20 segundos.'
                      : `Proposta de ${reais(dre.valor_projeto)} para ${nomeCliente}.`)
                  }}
                </p>
              </div>

              <div v-if="documentos.arquivos.length" class="cot-cards">
                <a
                  v-for="a in documentos.arquivos"
                  :key="a.nome"
                  :href="a.url"
                  :download="a.nome"
                  class="cot-tile cot-file text-n-slate-12"
                >
                  <span
                    class="cot-file-ico"
                    :class="a.imagem ? 'i-lucide-image' : 'i-lucide-file-text'"
                  />
                  <span class="flex-1 min-w-0 break-words text-sm">{{
                    a.nome
                  }}</span>
                  <span class="cot-link">
                    <span class="i-lucide-download" />
                    {{ TXT.baixar }}
                  </span>
                </a>
              </div>
              <p
                v-if="documentos.aviso"
                class="cot-alert text-sm text-n-slate-12"
              >
                {{ documentos.aviso }}
              </p>
              <p
                v-else-if="!geradorPdfLigado && !documentos.arquivos.length"
                class="text-xs text-n-slate-11"
              >
                {{ TXT.oGeradorDePdf }}
              </p>
            </section>

            <!-- 6. Orçamentos guardados deste cliente -->
            <section v-if="historico.length" class="cot-sec cot-green">
              <div class="cot-head">
                <span class="cot-ico"><i class="i-lucide-history" /></span>
                <div class="min-w-0 flex-1">
                  <h2 class="cot-title text-n-slate-12">
                    {{ TXT.orcamentosDesteCliente }}
                  </h2>
                  <p class="cot-sub text-n-slate-11">
                    {{ TXT.marcarEnviadaDica }}
                  </p>
                </div>
              </div>
              <div class="cot-cards">
                <KitQuoteCard
                  v-for="o in historico"
                  :key="o.id"
                  :orcamento="o"
                  :mostrar-cliente="false"
                  :pode-editar="podeCotar"
                  :ocupado="marcando === o.id"
                  @enviar="marcarEnviada"
                  @whatsapp="enviarWhatsapp"
                  @excluir="excluirOrcamento"
                  @editar="editarOrcamento"
                />
              </div>
            </section>
          </div>

          <!-- resumo fixo ao lado (notebook) -->
          <aside class="cot-sum cot-orange">
            <p class="cot-lab text-n-slate-11">{{ TXT.resumo }}</p>
            <p class="text-base font-bold text-n-slate-12 break-words">
              {{ nomeCliente || 'Cliente ainda não escolhido' }}
            </p>
            <dl class="cot-sum-list">
              <div>
                <dt class="text-n-slate-11">{{ TXT.contaConsiderada }}</dt>
                <dd class="text-n-slate-12">{{ reais(contaTotal) }}</dd>
              </div>
              <div>
                <dt class="text-n-slate-11">{{ TXT.consumoRot }}</dt>
                <dd class="text-n-slate-12">
                  {{ consumo ? `${numero(parseMoney(consumo))} kWh` : '—' }}
                </dd>
              </div>
              <div>
                <dt class="text-n-slate-11">{{ TXT.telhadoRede }}</dt>
                <dd class="text-n-slate-12">
                  {{ nomeTelhado || '—' }} ·
                  {{ REDES.find(r => r.id === rede)?.nome }}
                </dd>
              </div>
              <div v-if="escolhida">
                <dt class="text-n-slate-11">{{ TXT.kitRot }}</dt>
                <dd class="text-n-slate-12">
                  {{ NOME_TIPO[escolhida.tipo] }} · {{ escolhida.placas }}
                  {{ TXT.placas }} {{ numero(escolhida.potencia_kwp) }}
                  {{ TXT.kwp }}
                </dd>
              </div>
            </dl>
            <div v-if="dre" class="cot-sum-total">
              <p class="cot-lab text-n-slate-11">{{ TXT.valorProjeto }}</p>
              <p class="cot-big text-n-slate-12">
                {{ reais(dre.valor_projeto) }}
              </p>
              <p
                class="text-sm font-semibold"
                :class="dre.na_faixa ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                {{ TXT.lucroDe }} {{ reais(dre.lucro) }} ({{ pct(dre.margem) }})
              </p>
            </div>
            <button
              v-if="dre"
              type="button"
              class="cot-btn w-full justify-center"
              :disabled="!podeCotar || gerando || !!faltaParaGerar"
              @click="gerar"
            >
              <span
                :class="
                  gerando
                    ? 'i-lucide-loader-circle animate-spin'
                    : 'i-lucide-sparkles'
                "
              />
              {{ gerando ? 'Gerando' : 'Gerar proposta' }}
            </button>
            <p v-else class="text-xs text-n-slate-11">{{ TXT.valorAparece }}</p>
          </aside>
        </div>

        <!-- 7. Acessos dos fornecedores (só administrador) -->
        <KitQuoteAccess v-if="isAdmin && !carregando" v-model:acesso="acesso" />
      </div>
    </div>

    <CvTutorial
      v-model="tutorialAberto"
      name="Tutorial · Gerador de proposta"
      :steps="TUTORIAL_PASSOS"
      @finish="marcarTutorialVisto"
      @close="marcarTutorialVisto"
    />
  </div>
</template>

<style scoped>
/* 🎨 Gerador de proposta · rodada visual de 12/11 (pedido do Guilherme: "mais bonita, mais colorida,
   mais organizada"). Cada etapa é um bloco reto com a sua cor (--c): fio no topo, ícone em quadrado,
   título grande; campos e chips com contraste; resumo fixo ao lado no notebook. */
.cot {
  background: #f3f4f6;
}
.dark .cot {
  background: #0c0d0f;
}
.cot-top {
  background: #fff;
  border-bottom: 1px solid #e5e7eb;
}
.dark .cot-top {
  background: #121316;
  border-bottom-color: #26282c;
}
.cot-logo {
  width: 32px;
  height: 32px;
  border-radius: 10px;
  display: grid;
  place-items: center;
  color: #fff;
  background: linear-gradient(135deg, #f59e0b, #ea580c);
}
.cot-logo > span {
  width: 17px;
  height: 17px;
}
.cot-ghost {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  padding: 0 12px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  border: 1px solid rgb(15 23 42 / 0.14);
}
.dark .cot-ghost {
  border-color: rgb(255 255 255 / 0.14);
}

/* etapas */
.cot-steps {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 8px;
}
.cot-step {
  position: relative;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  border-radius: 14px;
  background: #fff;
  border: 1px solid #e5e7eb;
  text-align: left;
}
.dark .cot-step {
  background: #16181b;
  border-color: #2b2e33;
}
.cot-step-dot {
  flex-shrink: 0;
  width: 30px;
  height: 30px;
  border-radius: 10px;
  display: grid;
  place-items: center;
  color: #64748b;
  background: rgb(100 116 139 / 0.14);
}
.cot-step-dot > span {
  width: 16px;
  height: 16px;
}
.cot-step.is-done .cot-step-dot {
  color: #fff;
  background: #16a34a;
}
.cot-step.is-now {
  border-color: #ea580c;
  box-shadow: 0 0 0 3px rgb(234 88 12 / 0.15);
}
.cot-step.is-now .cot-step-dot {
  color: #fff;
  background: linear-gradient(135deg, #f59e0b, #ea580c);
}
.cot-step-txt {
  display: flex;
  flex-direction: column;
  min-width: 0;
  line-height: 1.15;
}
.cot-step-n {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: #94a3b8;
}
.cot-step-name {
  font-size: 13px;
  font-weight: 700;
}
@media (max-width: 720px) {
  .cot-step {
    flex-direction: column;
    gap: 6px;
    padding: 8px 4px;
    text-align: center;
  }
  .cot-step-n {
    display: none;
  }
  .cot-step-name {
    font-size: 11px;
  }
}

/* layout com o resumo ao lado */
.cot-grid {
  display: grid;
  gap: 32px;
  align-items: start;
}
@media (min-width: 1100px) {
  .cot-grid {
    grid-template-columns: minmax(0, 1fr) 300px;
  }
}

/* as cores de cada etapa */
.cot-green {
  --c: #16a34a;
}
.cot-blue {
  --c: #2563eb;
}
.cot-amber {
  --c: #d97706;
}
.cot-teal {
  --c: #0d9488;
}
.cot-violet {
  --c: #7c3aed;
}
.cot-orange {
  --c: #ea580c;
}

/* bloco de cada etapa */
.cot-sec {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 20px;
  padding: 24px 20px;
  border-radius: 22px;
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--c) 7%, #fff) 0,
    #fff 120px
  );
  border: 1px solid color-mix(in srgb, var(--c) 26%, #e5e7eb);
  box-shadow: 0 14px 34px -26px color-mix(in srgb, var(--c) 70%, transparent);
  scroll-margin-top: 16px;
}
@media (min-width: 640px) {
  .cot-sec {
    padding: 28px;
  }
}
.cot-sec::before {
  content: '';
  position: absolute;
  left: 24px;
  right: 24px;
  top: -1px;
  height: 3px;
  border-radius: 0 0 4px 4px;
  background: var(--c);
}
.dark .cot-sec {
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--c) 13%, #141518) 0,
    #141518 140px
  );
  border-color: color-mix(in srgb, var(--c) 32%, #26282c);
  box-shadow: 0 18px 40px -30px color-mix(in srgb, var(--c) 80%, transparent);
}
.cot-head {
  display: flex;
  align-items: center;
  gap: 14px;
  flex-wrap: wrap;
}
.cot-ico {
  flex-shrink: 0;
  width: 42px;
  height: 42px;
  border-radius: 13px;
  display: grid;
  place-items: center;
  color: #fff;
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--c) 78%, #fff),
    var(--c)
  );
  box-shadow: 0 8px 18px -10px var(--c);
}
.cot-ico > i {
  width: 21px;
  height: 21px;
}
.cot-title {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 18px;
  font-weight: 800;
  letter-spacing: -0.01em;
  line-height: 1.2;
}
.cot-n {
  display: inline-grid;
  place-items: center;
  width: 22px;
  height: 22px;
  border-radius: 7px;
  font-size: 12px;
  font-weight: 800;
  color: var(--c);
  background: color-mix(in srgb, var(--c) 14%, transparent);
}
.cot-sub {
  font-size: 13px;
  margin-top: 3px;
  line-height: 1.4;
}

/* o seletor de cliente (componente do Meu Painel) entra sem a moldura própria */
.cot-picker :deep(> section) {
  padding: 0;
  border: 0;
  background: transparent;
}
.cot-picker :deep(> section > h2) {
  display: none;
}
.cot-picker :deep(> section > div:first-of-type) {
  margin-top: 0;
}

/* campos */
.cot-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.cot-lab {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.cot-block {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.cot-input {
  height: 46px !important;
  width: 100%;
  padding: 0 14px !important;
  border-radius: 12px !important;
  font-size: 15px !important;
  background: #fff !important;
  border: 1px solid #d4d8de !important;
  transition:
    border-color 0.15s,
    box-shadow 0.15s;
}
.cot-input:focus {
  outline: none;
  border-color: var(--c) !important;
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--c) 22%, transparent) !important;
}
.dark .cot-input {
  background: #0d0e10 !important;
  border-color: #34373d !important;
}
.dark .cot-input:focus {
  border-color: var(--c) !important;
}
.cot-input-lg {
  font-size: 20px !important;
  font-weight: 700;
}
.cot-input-xl {
  height: 56px !important;
  font-size: 26px !important;
  font-weight: 800;
}
.cot-icon-btn {
  flex-shrink: 0;
  width: 46px;
  height: 46px;
  border-radius: 12px;
  display: grid;
  place-items: center;
  border: 1px solid #d4d8de;
}
.dark .cot-icon-btn {
  border-color: #34373d;
}
.cot-link {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 13px;
  font-weight: 700;
  color: var(--c);
}
.cot-link > span {
  width: 15px;
  height: 15px;
}

/* chips (telhado, rede, lucro) */
.cot-chip {
  height: 40px;
  padding: 0 16px;
  border-radius: 999px;
  font-size: 14px;
  font-weight: 500;
  background: #fff;
  border: 1px solid #d4d8de;
  transition: all 0.15s;
}
.cot-chip:hover {
  border-color: var(--c);
}
.dark .cot-chip {
  background: #0d0e10;
  border-color: #34373d;
}
.cot-chip.is-on,
.dark .cot-chip.is-on {
  color: #fff;
  font-weight: 700;
  background: var(--c);
  border-color: var(--c);
  box-shadow: 0 8px 16px -10px var(--c);
}

/* caixas internas */
.cot-tile {
  padding: 16px 18px;
  border-radius: 16px;
  background: #fff;
  border: 1px solid #e5e7eb;
}
.dark .cot-tile {
  background: rgb(255 255 255 / 0.035);
  border-color: #2b2e33;
}
.cot-tile-accent,
.dark .cot-tile-accent {
  background: color-mix(in srgb, var(--c) 10%, transparent);
  border-color: color-mix(in srgb, var(--c) 35%, transparent);
}
.cot-conta {
  display: flex;
  flex-direction: column;
  gap: 14px;
}
@media (min-width: 640px) {
  .cot-conta {
    flex-direction: row;
    align-items: flex-end;
  }
}
.cot-big {
  font-size: 28px;
  font-weight: 800;
  letter-spacing: -0.02em;
  line-height: 1.15;
  font-variant-numeric: tabular-nums;
}

/* botões */
.cot-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  height: 48px;
  padding: 0 22px;
  border-radius: 14px;
  font-size: 15px;
  font-weight: 700;
  color: #fff;
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--c) 75%, #fbbf24),
    var(--c)
  );
  box-shadow: 0 12px 24px -14px var(--c);
  transition: filter 0.15s;
}
.cot-btn:hover:not(:disabled) {
  filter: brightness(1.06);
}
.cot-btn:disabled {
  opacity: 0.45;
  box-shadow: none;
}
.cot-btn > span {
  width: 18px;
  height: 18px;
}
.cot-btn-lg {
  height: 54px;
  padding: 0 26px;
  font-size: 16px;
}
.cot-btn2 {
  flex-shrink: 0;
  white-space: nowrap;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 42px;
  padding: 0 16px;
  border-radius: 12px;
  font-size: 13px;
  font-weight: 700;
  border: 1px solid color-mix(in srgb, var(--c) 45%, #d4d8de);
}
.cot-btn2:disabled {
  opacity: 0.5;
}

/* ⚡ orçamento em 1 clique */
.cot-btn-auto {
  --c: #7c3aed;
  background: #7c3aed;
  border-color: #7c3aed;
  color: #fff;
}
.cot-auto-list {
  display: grid;
  gap: 10px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.cot-auto-item {
  display: flex;
  align-items: center;
  gap: 12px;
  opacity: 0.55;
}
.cot-auto-item.is-done,
.cot-auto-item.is-now,
.cot-auto-item.is-err {
  opacity: 1;
}
.cot-auto-dot {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 999px;
  font-size: 15px;
  color: #7c3aed;
  background: color-mix(in srgb, #7c3aed 12%, transparent);
}
.cot-auto-item.is-done .cot-auto-dot {
  color: #fff;
  background: #16a34a;
}
.cot-auto-item.is-err .cot-auto-dot {
  color: #fff;
  background: #dc2626;
}
.cot-auto-erro {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px;
  padding: 14px 16px;
  border-radius: 14px;
  background: color-mix(in srgb, #dc2626 10%, transparent);
  border: 1px solid color-mix(in srgb, #dc2626 35%, transparent);
}
.cot-auto-erro p {
  flex: 1 1 280px;
  margin: 0;
}
.cot-auto-conta {
  flex: 0 1 200px;
}

/* controle segmentado (abas e micro × string) */
.cot-seg {
  display: inline-flex;
  gap: 4px;
  padding: 4px;
  border-radius: 14px;
  background: rgb(15 23 42 / 0.06);
}
.dark .cot-seg {
  background: rgb(255 255 255 / 0.06);
}
.cot-seg > button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  height: 36px;
  padding: 0 14px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 700;
  color: #64748b;
}
.cot-seg > button.is-on {
  color: #fff;
  background: var(--c);
  box-shadow: 0 6px 14px -8px var(--c);
}
.cot-seg-n {
  min-width: 20px;
  height: 20px;
  padding: 0 6px;
  border-radius: 999px;
  font-size: 11px;
  display: inline-grid;
  place-items: center;
  background: rgb(15 23 42 / 0.08);
}
.cot-seg > button.is-on .cot-seg-n {
  background: rgb(255 255 255 / 0.25);
}
.cot-seg-full {
  display: flex;
}
.cot-seg-full > button {
  flex: 1;
  height: 42px;
  font-size: 14px;
}

/* barra do lucro */
.cot-range {
  display: flex;
  align-items: center;
  gap: 14px;
}
.cot-range-in {
  flex: 1;
  height: 8px;
  border-radius: 999px;
  appearance: none;
  -webkit-appearance: none;
  background: linear-gradient(
    90deg,
    var(--bar) 0 var(--fill),
    rgb(100 116 139 / 0.25) var(--fill) 100%
  );
  cursor: pointer;
}
.cot-range-in::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 26px;
  height: 26px;
  border-radius: 999px;
  background: #fff;
  border: 3px solid var(--bar);
  box-shadow: 0 4px 12px -4px rgb(0 0 0 / 0.4);
}
.cot-range-in::-moz-range-thumb {
  width: 22px;
  height: 22px;
  border-radius: 999px;
  background: #fff;
  border: 3px solid var(--bar);
}
.cot-range-val {
  min-width: 68px;
  text-align: right;
  font-size: 24px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
}
.cot-range-marks {
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  font-weight: 600;
  margin-top: -4px;
}

/* busca e ordem do histórico */
.cot-search {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 42px;
  padding: 0 12px;
  border-radius: 12px;
  background: #fff;
  border: 1px solid #d4d8de;
}
.dark .cot-search {
  background: #0d0e10;
  border-color: #34373d;
}
.cot-search > span {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
}
.cot-search > input {
  flex: 1;
  height: 40px;
  border: 0 !important;
  background: transparent !important;
  box-shadow: none !important;
  padding: 0 !important;
  font-size: 14px;
}
.cot-seg-sm > button {
  height: 34px;
  font-size: 12px;
}
.cot-prefill {
  padding: 12px 14px;
  border-radius: 14px;
  background: color-mix(in srgb, var(--c) 7%, transparent);
  border: 1px dashed color-mix(in srgb, var(--c) 40%, transparent);
}

/* fornecedores e opções */
.cot-sup {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 32px;
  padding: 0 12px;
  border-radius: 999px;
  font-size: 12px;
}
.cot-sup > span {
  width: 15px;
  height: 15px;
}
.cot-sup.is-ok {
  color: #0f766e;
  background: rgb(20 184 166 / 0.14);
}
.cot-sup.is-warn {
  color: #b45309;
  background: rgb(245 158 11 / 0.16);
}
.cot-sup.is-bad {
  color: #b91c1c;
  background: rgb(239 68 68 / 0.14);
}
.dark .cot-sup.is-ok {
  color: #5eead4;
}
.dark .cot-sup.is-warn {
  color: #fcd34d;
}
.dark .cot-sup.is-bad {
  color: #fca5a5;
}
.cot-opt {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 18px;
  border-radius: 18px;
  text-align: left;
  background: #fff;
  border: 1px solid #e5e7eb;
  transition:
    border-color 0.15s,
    box-shadow 0.15s;
}
@media (min-width: 640px) {
  .cot-opt {
    flex-direction: row;
    align-items: center;
  }
}
.cot-opt:hover {
  border-color: color-mix(in srgb, var(--c) 55%, #e5e7eb);
}
.dark .cot-opt {
  background: #16181b;
  border-color: #2b2e33;
}
.cot-opt.is-on,
.dark .cot-opt.is-on {
  border-color: var(--c);
  background: color-mix(in srgb, var(--c) 9%, transparent);
  box-shadow: 0 0 0 2px var(--c);
}
.cot-opt-price {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
@media (min-width: 640px) {
  .cot-opt-price {
    width: 170px;
  }
}
.cot-opt-pick {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 700;
  color: #94a3b8;
}
.cot-opt-pick > span {
  width: 18px;
  height: 18px;
}
.cot-opt.is-on .cot-opt-pick {
  color: var(--c);
}
.cot-pill {
  padding: 3px 9px;
  border-radius: 999px;
  font-weight: 700;
  color: #fff;
}
.cot-tag {
  padding: 3px 9px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
  white-space: nowrap;
}
.cot-tag.is-ok {
  color: #0f766e;
  background: rgb(20 184 166 / 0.15);
}
.cot-tag.is-bad {
  color: #b91c1c;
  background: rgb(239 68 68 / 0.13);
}
.dark .cot-tag.is-ok {
  color: #5eead4;
}
.dark .cot-tag.is-bad {
  color: #fca5a5;
}

/* preço e DRE */
.cot-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 12px;
  font-size: 14px;
}
.cot-lucro {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 4px;
}
.cot-lucro.is-ok,
.dark .cot-lucro.is-ok {
  color: #0f766e;
  background: rgb(20 184 166 / 0.12);
  border-color: rgb(20 184 166 / 0.4);
}
.cot-lucro.is-bad,
.dark .cot-lucro.is-bad {
  color: #b91c1c;
  background: rgb(239 68 68 / 0.1);
  border-color: rgb(239 68 68 / 0.4);
}
.dark .cot-lucro.is-ok {
  color: #5eead4;
}
.dark .cot-lucro.is-bad {
  color: #fca5a5;
}
.cot-line {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 5px 0;
  border-bottom: 1px dashed rgb(15 23 42 / 0.08);
}
.dark .cot-line {
  border-bottom-color: rgb(255 255 255 / 0.07);
}
.cot-line:last-child {
  border-bottom: 0;
}
.cot-line-tax {
  color: #b45309;
  font-weight: 600;
}
.dark .cot-line-tax {
  color: #fbbf24;
}
.cot-line-total {
  margin-top: 4px;
  padding-top: 8px;
  font-weight: 800;
  border-top: 1px solid rgb(15 23 42 / 0.15);
}
.dark .cot-line-total {
  border-top-color: rgb(255 255 255 / 0.15);
}
.cot-alert {
  padding: 14px 16px;
  border-radius: 14px;
  background: rgb(245 158 11 / 0.12);
  border: 1px solid rgb(245 158 11 / 0.45);
}
.cot-error {
  padding: 14px 16px;
  border-radius: 14px;
  font-size: 14px;
  color: #b91c1c;
  background: rgb(239 68 68 / 0.1);
}
.dark .cot-error {
  color: #fca5a5;
}
.cot-empty {
  padding: 18px;
  border-radius: 14px;
  font-size: 14px;
  text-align: center;
  border: 1px dashed rgb(100 116 139 / 0.35);
}

/* caixas de orçamentos e arquivos */
.cot-cards {
  display: grid;
  gap: 14px;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
}
.cot-file {
  display: flex;
  align-items: center;
  gap: 12px;
}
.cot-file-ico {
  width: 22px;
  height: 22px;
  color: var(--c);
}

/* resumo fixo */
.cot-sum {
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 22px;
  border-radius: 22px;
  background: #fff;
  border: 1px solid color-mix(in srgb, var(--c) 30%, #e5e7eb);
  box-shadow: 0 18px 40px -30px color-mix(in srgb, var(--c) 80%, transparent);
  border-top: 3px solid var(--c);
}
@media (min-width: 1100px) {
  .cot-sum {
    position: sticky;
    top: 0;
  }
}
.dark .cot-sum {
  background: #141518;
  border-color: color-mix(in srgb, var(--c) 32%, #26282c);
  border-top-color: var(--c);
}
.cot-sum-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin: 0;
}
.cot-sum-list > div {
  display: flex;
  flex-direction: column;
  gap: 1px;
}
.cot-sum-list dt {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}
.cot-sum-list dd {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
}
.cot-sum-total {
  padding: 14px;
  border-radius: 14px;
  background: color-mix(in srgb, var(--c) 9%, transparent);
}
</style>
