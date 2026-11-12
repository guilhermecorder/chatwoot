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
const tarifa = ref(1.035);
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
const dataHora = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
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
// A proposta foi enviada: o cliente ganha a etiqueta "orçamento enviado", que leva o
// cartão para a coluna e começa o acompanhamento (Crm::QuoteSent).
const marcarEnviada = async orcamento => {
  if (marcando.value) return;
  marcando.value = orcamento.id;
  try {
    const { data } = await CrmAPI.markKitQuoteSent(orcamento.id);
    historico.value = historico.value.map(o =>
      o.id === orcamento.id ? data.orcamento : o
    );
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
  if (lido.acrescimo && !acrescimos.value[0].rotulo) {
    acrescimos.value[0].rotulo = lido.acrescimo;
  }
  cidadeCliente.value = lido.cidade || '';
  if (lido.telhado) telhado.value = lido.telhado;
});

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
    if (data.orcamento) await carregarHistorico();
    if ((data.arquivos || []).length) {
      useAlert('Proposta e justificativa prontas.');
    }
  } catch (e) {
    useAlert(erroDe(e, 'Não foi possível gerar os documentos.'));
  } finally {
    gerando.value = false;
  }
};

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

onMounted(async () => {
  await carregar();
  if (!tutorialVisto()) {
    await nextTick();
    tutorialAberto.value = true;
  }
});
onBeforeUnmount(soltarArquivos);
// textos da tela (fora do template, como pede o eslint do projeto)
const TXT = {
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
  reverOPasso: 'Rever o passo a passo em balões',
  oGeradorDePdf:
    'O gerador de PDF ainda não está ligado neste servidor. O preço e o DRE acima já valem.',
};
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-solid-1 overflow-hidden">
    <!-- Header no padrão das telas do CRM -->
    <div
      class="flex items-center gap-3 px-6 py-4 border-b border-n-weak flex-shrink-0 flex-wrap"
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
        <span
          class="w-8 h-8 rounded-xl flex items-center justify-center bg-gradient-to-br from-[#b45309] to-[#f59e0b]"
        >
          <span class="i-lucide-file-text text-white text-base" />
        </span>
        {{ TXT.geradorDeProposta }}
        <CevicoViewOnlyPill v-if="!podeCotar" />
      </h1>
      <div class="flex-1" />
      <button
        type="button"
        class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1"
        :title="TXT.reverOPasso"
        @click="tutorialAberto = true"
      >
        <span class="i-lucide-graduation-cap" />
        {{ TXT.tutorial }}
      </button>
    </div>

    <div class="flex-1 overflow-y-auto p-4 sm:p-10">
      <div class="max-w-3xl mx-auto flex flex-col gap-6">
        <!-- 1. Para quem é a proposta -->
        <div id="cot-cliente">
          <ProposalClientPicker
            v-model="cliente"
            :initial-contact-id="route.query.contact"
          />
        </div>

        <!-- 2. A conta de luz, o telhado e a rede -->
        <section
          id="cot-conta"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 sm:p-6 flex flex-col gap-5"
        >
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ TXT.aContaDeLuz }}
          </h2>

          <div class="grid sm:grid-cols-2 gap-3">
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ TXT.nomeNaProposta }}
              <input
                v-model="nomeCliente"
                type="text"
                :placeholder="TXT.nomeDoCliente"
                class="!mb-0 h-11 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
                :disabled="!podeCotar"
              />
            </label>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ TXT.contaDeHojeR }}
              <input
                v-model="contaHoje"
                type="text"
                inputmode="decimal"
                :placeholder="TXT.t300"
                class="!mb-0 h-11 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-lg text-n-slate-12"
                :disabled="!podeCotar"
              />
            </label>
          </div>

          <div class="flex flex-col gap-2">
            <p class="text-xs text-n-slate-11">
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
                class="!mb-0 h-11 flex-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
                :disabled="!podeCotar"
              />
              <div class="flex gap-2">
                <input
                  v-model="a.valor"
                  type="text"
                  inputmode="decimal"
                  :placeholder="TXT.rAMaisPor"
                  class="!mb-0 h-11 flex-1 sm:w-44 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
                  :disabled="!podeCotar"
                />
                <button
                  type="button"
                  class="h-11 w-11 flex-shrink-0 rounded-xl border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center justify-center"
                  :title="TXT.tirarEstaLinha"
                  @click="tirarAcrescimo(i)"
                >
                  <span class="i-lucide-x" />
                </button>
              </div>
            </div>
            <button
              type="button"
              class="self-start text-xs font-semibold text-n-slate-11 hover:text-n-slate-12 flex items-center gap-1"
              @click="maisAcrescimo"
            >
              <span class="i-lucide-plus" />
              {{ TXT.acrescentarOutro }}
            </button>
          </div>

          <div
            class="rounded-xl bg-n-alpha-1 p-4 flex flex-col sm:flex-row sm:items-end gap-3"
          >
            <div class="flex-1">
              <p class="text-xs text-n-slate-11">{{ TXT.contaConsiderada }}</p>
              <p class="text-xl font-semibold text-n-slate-12">
                {{ reais(contaTotal) }}
                <span class="text-sm font-normal text-n-slate-11">{{
                  TXT.porMes
                }}</span>
              </p>
              <p class="mt-1 text-xs text-n-slate-10">
                {{ reais(contaTotal) }} {{ TXT.r }} {{ tarifaTexto }}
                {{ TXT.porKwh }} {{ numero(consumoCalculado) }}
                {{ TXT.kwhPorMes }}
              </p>
            </div>
            <label class="sm:w-52 flex flex-col gap-1 text-xs text-n-slate-11">
              {{ TXT.consumoUsadoNaCotacao }}
              <input
                v-model="consumo"
                type="text"
                inputmode="decimal"
                :placeholder="TXT.t490"
                class="!mb-0 h-11 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-lg text-n-slate-12"
                :disabled="!podeCotar"
                @input="ajustarConsumo"
              />
            </label>
          </div>
          <button
            v-if="consumoNaMao && consumoCalculado"
            type="button"
            class="self-start -mt-3 text-xs font-semibold text-n-slate-11 hover:text-n-slate-12"
            @click="consumoPelaConta"
          >
            {{ TXT.voltarParaOConsumo }}
          </button>

          <div id="cot-telhado" class="flex flex-col gap-2">
            <p class="text-xs text-n-slate-11">{{ TXT.tipoDeTelhado }}</p>
            <div class="flex flex-wrap gap-2">
              <button
                v-for="t in telhados"
                :key="t.chave"
                type="button"
                class="h-10 px-4 rounded-xl text-sm border"
                :class="
                  telhado === t.chave
                    ? 'border-n-amber-9 bg-n-amber-3 text-n-slate-12 font-semibold'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                "
                :disabled="!podeCotar"
                @click="telhado = t.chave"
              >
                {{ t.nome }}
              </button>
            </div>
          </div>

          <div class="flex flex-col gap-2">
            <p class="text-xs text-n-slate-11">{{ TXT.rede }}</p>
            <div class="flex flex-wrap gap-2">
              <button
                v-for="r in REDES"
                :key="r.id"
                type="button"
                class="h-10 px-4 rounded-xl text-sm border"
                :class="
                  rede === r.id
                    ? 'border-n-amber-9 bg-n-amber-3 text-n-slate-12 font-semibold'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                "
                :disabled="!podeCotar"
                @click="rede = r.id"
              >
                {{ r.nome }}
              </button>
            </div>
          </div>

          <div
            id="cot-cotar"
            class="flex flex-col sm:flex-row sm:items-center gap-3"
          >
            <button
              type="button"
              class="h-11 px-6 rounded-xl text-sm font-semibold text-white flex items-center justify-center gap-2 disabled:opacity-50 bg-[#f59e0b]"
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
            <p class="text-xs text-n-slate-10">
              {{
                cotando
                  ? 'Consultando AVT e Bluesun. Leva alguns segundos.'
                  : `Cotação para ${cidade}, com a estrutura do telhado e o frete.`
              }}
            </p>
          </div>
        </section>

        <!-- 3. As opções -->
        <section
          v-if="resultado"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 sm:p-6 flex flex-col gap-4"
        >
          <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <h2 class="text-sm font-semibold text-n-slate-12">
              {{ TXT.opcoesDeKit }}
            </h2>
            <p class="text-xs text-n-slate-11">
              {{ numero(resultado.potencia_necessaria_kwp) }} {{ TXT.kwpPara }}
              {{ numero(resultado.consumo_kwh_mes) }} {{ TXT.kwhPorMes }}
            </p>
          </div>

          <div class="flex flex-col gap-2">
            <div
              v-for="f in resultado.fornecedores"
              :key="f.fornecedor"
              class="flex items-start gap-2 text-xs"
              :class="f.ok ? 'text-n-slate-11' : 'text-n-ruby-11'"
            >
              <span
                class="mt-0.5 flex-shrink-0"
                :class="
                  f.ok
                    ? 'i-lucide-circle-check text-n-teal-10'
                    : 'i-lucide-circle-alert'
                "
              />
              <span v-if="f.ok">
                <strong class="text-n-slate-12">{{ f.fornecedor }}</strong>
                {{ TXT.respondeuCom }} {{ f.opcoes }} {{ TXT.opcoes }}
                <template v-if="f.falta">
                  {{ TXT.vieramSem }} {{ f.falta }}{{ TXT.ficamForaDoPreco }}
                </template>
              </span>
              <span v-else>
                <strong>{{ f.fornecedor }}</strong> {{ TXT.naoRespondeu }}
                {{ f.motivo }}
              </span>
            </div>
          </div>

          <!-- micro ou string: quem gera escolhe -->
          <div class="flex gap-2">
            <button
              v-for="t in TIPOS"
              :key="t.id"
              type="button"
              class="h-11 flex-1 rounded-xl text-sm border"
              :class="
                tipo === t.id
                  ? 'border-n-amber-9 bg-n-amber-3 text-n-slate-12 font-semibold'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
              "
              @click="trocarTipo(t.id)"
            >
              {{ t.nome }}
            </button>
          </div>

          <p v-if="!opcoesDoTipo.length" class="text-sm text-n-slate-11">
            {{ TXT.nenhumaOpcaoDe }} {{ NOME_TIPO[tipo].toLowerCase() }}
            {{ TXT.voltouVejaOsMotivos }}
          </p>

          <button
            v-for="(o, i) in opcoesDoTipo"
            :key="i"
            type="button"
            class="rounded-2xl border p-4 flex flex-col sm:flex-row gap-3 text-left"
            :class="
              escolhida === o
                ? 'border-n-amber-9 bg-n-amber-2'
                : 'border-n-weak bg-n-solid-1 hover:bg-n-alpha-1'
            "
            @click="escolher(o)"
          >
            <span class="sm:w-40 flex-shrink-0 flex flex-col">
              <span class="text-lg font-semibold text-n-slate-12">
                {{ reais(o.total) }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ TXT.kit }} {{ reais(o.preco) }}
                <template v-if="o.frete !== null">
                  {{ TXT.frete }} {{ reais(o.frete) }}
                </template>
              </span>
            </span>
            <span class="flex-1 min-w-0 flex flex-col gap-1">
              <span class="flex flex-wrap items-center gap-2 text-xs">
                <span
                  class="px-2 py-0.5 rounded-full font-semibold text-white bg-[#b45309]"
                >
                  {{ o.fornecedor }}
                </span>
                <span class="text-n-slate-11">
                  {{ o.placas }} {{ TXT.placas }} {{ numero(o.potencia_kwp) }}
                  {{ TXT.kwp }}
                </span>
                <span
                  class="px-2 py-0.5 rounded-full font-semibold"
                  :class="
                    o.completa
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-ruby-3 text-n-ruby-11'
                  "
                >
                  {{ o.completa ? 'Com estrutura e frete' : `Sem ${o.falta}` }}
                </span>
              </span>
              <span class="text-sm text-n-slate-12 break-words">
                {{ o.paineis }}
              </span>
              <span class="text-sm text-n-slate-12 break-words">
                {{ o.inversor }}
              </span>
              <span v-if="o.obs" class="text-xs text-n-slate-10">
                {{ o.obs }}
              </span>
            </span>
            <span
              class="self-start sm:self-center text-xs font-semibold flex items-center gap-1"
              :class="escolhida === o ? 'text-n-amber-11' : 'text-n-slate-10'"
            >
              <span
                :class="
                  escolhida === o ? 'i-lucide-circle-check' : 'i-lucide-circle'
                "
              />
              {{ escolhida === o ? 'Escolhida' : 'Escolher' }}
            </span>
          </button>
          <p class="text-xs text-n-slate-10">
            {{ TXT.precoDeCustoDo }}
          </p>
        </section>

        <!-- 4. Preço e DRE -->
        <section
          v-if="escolhida"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 sm:p-6 flex flex-col gap-5"
        >
          <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <h2 class="text-sm font-semibold text-n-slate-12">
              {{ TXT.precoEDreDo }}
            </h2>
            <p class="text-xs text-n-slate-11">
              {{ NOME_TIPO[escolhida.tipo] }} · {{ escolhida.placas }}
              {{ TXT.placas }} {{ numero(escolhida.potencia_kwp) }}
              {{ TXT.kwp }}
            </p>
          </div>

          <!-- custo do kit: média dos fornecedores com cotação completa -->
          <div class="flex flex-col gap-2">
            <p class="text-xs font-semibold text-n-slate-10 uppercase">
              {{ TXT.custoDoKitMedia }}
            </p>
            <div
              v-for="q in cotacoes.filter(c => !c.manual)"
              :key="q.fornecedor"
              class="flex flex-wrap items-baseline gap-x-3 gap-y-0.5 text-sm"
              :class="q.entra_na_media ? 'text-n-slate-12' : 'text-n-slate-10'"
            >
              <strong class="w-24">{{ q.fornecedor }}</strong>
              <span
                class="tabular-nums"
                :class="q.entra_na_media ? '' : 'line-through'"
              >
                {{ reais(q.valor) }}
              </span>
              <span class="text-xs text-n-slate-11">{{ q.detalhe }}</span>
              <span
                class="text-xs font-semibold"
                :class="q.entra_na_media ? 'text-n-teal-11' : 'text-n-ruby-11'"
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
                class="!mb-0 h-10 flex-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
              />
              <div class="flex gap-2">
                <input
                  v-model="m.valor"
                  type="text"
                  inputmode="decimal"
                  :placeholder="TXT.kitEstruturaFreteR"
                  class="!mb-0 h-10 flex-1 sm:w-56 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12"
                  @keyup.enter="calcularDre()"
                  @blur="calcularDre()"
                />
                <button
                  type="button"
                  class="h-10 w-10 flex-shrink-0 rounded-xl border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center justify-center"
                  :title="TXT.tirarEstaCotacao"
                  @click="tirarCotacao(i)"
                >
                  <span class="i-lucide-x" />
                </button>
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-x-4 gap-y-1">
              <button
                type="button"
                class="text-xs font-semibold text-n-slate-11 hover:text-n-slate-12 flex items-center gap-1"
                @click="maisCotacao"
              >
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
            class="rounded-xl border border-n-amber-7 bg-n-amber-2 p-4 flex flex-col sm:flex-row sm:items-end gap-3"
          >
            <p class="flex-1 text-sm text-n-slate-12">
              {{ TXT.aTabelaDeAdequacao }}
              {{ escolhida.placas }} {{ TXT.placasCom }}
              {{ NOME_TIPO[escolhida.tipo].toLowerCase()
              }}{{ TXT.informeOValorDa }}
            </p>
            <label class="sm:w-48 flex flex-col gap-1 text-xs text-n-slate-11">
              {{ TXT.adequacaoR }}
              <input
                v-model="adequacaoNaMao"
                type="text"
                inputmode="decimal"
                class="!mb-0 h-11 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-lg text-n-slate-12"
                @keyup.enter="calcularDre()"
              />
            </label>
            <button
              type="button"
              class="h-11 px-5 rounded-xl text-sm font-semibold border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
              :disabled="dreCarregando || !parseMoney(adequacaoNaMao)"
              @click="calcularDre()"
            >
              {{ TXT.usarEsteValor }}
            </button>
          </div>

          <p
            v-if="dreErro && !(precisaAdequacao && !dre)"
            class="rounded-xl bg-n-ruby-3 p-4 text-sm text-n-ruby-11"
          >
            {{ dreErro }}
          </p>
          <p v-if="dreCarregando && !dre" class="text-sm text-n-slate-11">
            {{ TXT.calculandoOPreco }}
          </p>

          <template v-if="dre">
            <!-- o preço -->
            <div class="flex flex-col gap-3">
              <p class="text-xs font-semibold text-n-slate-10 uppercase">
                {{ TXT.lucroLiquidoDoOrcamento }}
              </p>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="m in MARGENS"
                  :key="m"
                  type="button"
                  class="h-11 px-4 rounded-xl text-sm border"
                  :class="
                    margemAtiva(m)
                      ? 'border-n-amber-9 bg-n-amber-3 text-n-slate-12 font-semibold'
                      : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                  "
                  :disabled="dreCarregando"
                  @click="usarMargem(m)"
                >
                  {{ pct(m) }}{{ m === 0.25 ? ' (padrão)' : '' }}
                </button>
              </div>
              <div class="flex flex-col sm:flex-row sm:items-end gap-3">
                <label
                  class="flex-1 flex flex-col gap-1 text-xs text-n-slate-11"
                >
                  {{ TXT.valorDoProjetoR }}
                  <input
                    v-model="valorNaMao"
                    type="text"
                    inputmode="decimal"
                    class="!mb-0 h-12 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-2xl font-semibold text-n-slate-12"
                    @keyup.enter="usarValor"
                  />
                </label>
                <button
                  type="button"
                  class="h-12 px-5 rounded-xl text-sm font-semibold border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
                  :disabled="dreCarregando"
                  @click="usarValor"
                >
                  {{ TXT.recalcularComEsteValor }}
                </button>
              </div>
            </div>

            <div
              class="rounded-xl p-4 flex flex-wrap items-baseline gap-x-4 gap-y-1"
              :class="dre.na_faixa ? 'bg-n-teal-3' : 'bg-n-ruby-3'"
            >
              <p class="text-2xl font-semibold text-n-slate-12">
                {{ reais(dre.lucro) }}
              </p>
              <p class="text-sm text-n-slate-12">
                {{ TXT.deLucroLiquido }}{{ pct(dre.margem) }})
              </p>
              <p
                class="text-xs font-semibold"
                :class="dre.na_faixa ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                {{
                  dre.na_faixa
                    ? 'Dentro da faixa de 18% a 30%'
                    : 'Fora da faixa de 18% a 30%: confira antes de enviar'
                }}
              </p>
            </div>

            <!-- o DRE -->
            <div class="grid sm:grid-cols-2 gap-x-8 gap-y-4 text-sm">
              <div>
                <p class="text-xs font-semibold text-n-slate-10 uppercase">
                  {{ TXT.dedutiveis }}
                </p>
                <p
                  v-for="l in dre.dedutiveis.filter(x => x.valor)"
                  :key="l.nome"
                  class="flex justify-between gap-3 py-0.5 text-n-slate-12"
                >
                  <span>{{ l.nome }}</span>
                  <span class="tabular-nums whitespace-nowrap">
                    {{ reais(l.valor) }}
                  </span>
                </p>
                <p class="flex justify-between gap-3 py-0.5 text-n-amber-11">
                  <span>{{ TXT.imposto }}{{ pct(dre.taxa_imposto) }})</span>
                  <span class="tabular-nums whitespace-nowrap">
                    {{ reais(dre.imposto) }}
                  </span>
                </p>
              </div>
              <div>
                <p class="text-xs font-semibold text-n-slate-10 uppercase">
                  {{ TXT.indedutiveis }}
                </p>
                <p
                  v-for="l in dre.indedutiveis.filter(x => x.valor)"
                  :key="l.nome"
                  class="flex justify-between gap-3 py-0.5 text-n-slate-12"
                >
                  <span>{{ l.nome }}</span>
                  <span class="tabular-nums whitespace-nowrap">
                    {{ reais(l.valor) }}
                  </span>
                </p>
                <p
                  class="flex justify-between gap-3 py-0.5 mt-1 border-t border-n-weak font-semibold text-n-slate-12"
                >
                  <span>{{ TXT.custoTotal }}</span>
                  <span class="tabular-nums whitespace-nowrap">
                    {{ reais(dre.custo_total) }}
                  </span>
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

            <div
              class="grid sm:grid-cols-2 gap-x-8 gap-y-3 text-xs text-n-slate-11"
            >
              <div>
                <p class="font-semibold text-n-slate-10 uppercase">
                  {{ TXT.quantoCobrarEmCada }}
                </p>
                <p class="flex justify-between py-0.5">
                  <span>{{ TXT.lucroDe18 }}</span>
                  <span class="tabular-nums">
                    {{ reais(dre.faixa.minimo) }}
                  </span>
                </p>
                <p class="flex justify-between py-0.5 text-n-slate-12">
                  <span>{{ TXT.lucroDe25Padrao }}</span>
                  <span class="tabular-nums">
                    {{ reais(dre.faixa.padrao) }}
                  </span>
                </p>
                <p class="flex justify-between py-0.5">
                  <span>{{ TXT.lucroDe30 }}</span>
                  <span class="tabular-nums">
                    {{ reais(dre.faixa.maximo) }}
                  </span>
                </p>
              </div>
              <div>
                <p class="font-semibold text-n-slate-10 uppercase">
                  {{ TXT.lucroPorSocio }}
                </p>
                <p
                  v-for="socio in dre.socios"
                  :key="socio.nome"
                  class="flex justify-between py-0.5"
                >
                  <span>{{ socio.nome }} ({{ pct(socio.parte) }})</span>
                  <span class="tabular-nums">{{ reais(socio.valor) }}</span>
                </p>
              </div>
            </div>

            <!-- 5. gerar os dois documentos -->
            <div class="border-t border-n-weak pt-5 flex flex-col gap-3">
              <div class="flex flex-col sm:flex-row sm:items-center gap-3">
                <button
                  type="button"
                  class="h-12 px-6 rounded-xl text-sm font-semibold text-white flex items-center justify-center gap-2 disabled:opacity-50 bg-[#f59e0b]"
                  :disabled="!podeCotar || gerando || !!faltaParaGerar"
                  @click="gerar"
                >
                  <span
                    :class="
                      gerando
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-file-text'
                    "
                  />
                  {{ gerando ? 'Gerando' : 'Gerar proposta e justificativa' }}
                </button>
                <p class="text-xs text-n-slate-10">
                  {{
                    faltaParaGerar ||
                    (gerando
                      ? 'Montando os dois PDFs. Leva uns 20 segundos.'
                      : `Proposta de ${reais(dre.valor_projeto)} para ${nomeCliente}, com a justificativa do orçamento.`)
                  }}
                </p>
              </div>

              <div
                v-if="documentos.arquivos.length"
                class="flex flex-col gap-2"
              >
                <a
                  v-for="a in documentos.arquivos"
                  :key="a.nome"
                  :href="a.url"
                  :download="a.nome"
                  class="rounded-xl border border-n-weak p-3 flex items-center gap-3 text-sm text-n-slate-12 hover:bg-n-alpha-1"
                >
                  <span
                    class="text-lg text-n-amber-10"
                    :class="a.imagem ? 'i-lucide-image' : 'i-lucide-file-text'"
                  />
                  <span class="flex-1 min-w-0 break-words">{{ a.nome }}</span>
                  <span
                    class="text-xs font-semibold text-n-slate-11 flex items-center gap-1"
                  >
                    <span class="i-lucide-download" />
                    {{ TXT.baixar }}
                  </span>
                </a>
              </div>
              <p
                v-if="documentos.aviso"
                class="rounded-xl bg-n-amber-2 border border-n-amber-7 p-3 text-xs text-n-slate-12"
              >
                {{ documentos.aviso }}
              </p>
              <p
                v-else-if="!geradorPdfLigado && !documentos.arquivos.length"
                class="text-xs text-n-slate-10"
              >
                {{ TXT.oGeradorDePdf }}
              </p>
            </div>
          </template>
        </section>

        <!-- 6. Orçamentos guardados deste cliente -->
        <section
          v-if="historico.length"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 sm:p-6 flex flex-col gap-3"
        >
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ TXT.orcamentosDesteCliente }}
          </h2>
          <div
            v-for="o in historico"
            :key="o.id"
            class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
          >
            <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <p class="text-lg font-semibold text-n-slate-12 tabular-nums">
                {{ reais(o.valor) }}
              </p>
              <p class="text-sm text-n-slate-12">
                {{ NOME_TIPO[o.tipo] || o.tipo }}
              </p>
              <p
                class="text-xs font-semibold"
                :class="o.na_faixa ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                {{ TXT.lucroDe }} {{ pct(o.margem) }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{ TXT.geradoEm }} {{ dataHora(o.criado_em) }}
                <template v-if="o.por">{{ TXT.por }} {{ o.por }}</template>
              </p>
            </div>
            <div v-if="o.arquivos.length" class="flex flex-wrap gap-2">
              <a
                v-for="a in o.arquivos"
                :key="a.nome"
                :href="a.url"
                target="_blank"
                rel="noopener noreferrer"
                class="h-9 px-3 rounded-xl border border-n-weak text-xs font-semibold text-n-slate-12 hover:bg-n-alpha-1 inline-flex items-center gap-1.5"
              >
                <span
                  class="text-sm text-n-amber-10"
                  :class="
                    String(a.tipo).startsWith('image/')
                      ? 'i-lucide-image'
                      : 'i-lucide-file-text'
                  "
                />
                {{ a.nome }}
              </a>
            </div>
            <p v-else class="text-xs text-n-slate-10">{{ TXT.semArquivos }}</p>
            <p
              v-if="o.enviado_em"
              class="text-xs font-semibold text-n-teal-11 flex items-center gap-1.5"
            >
              <span class="i-lucide-circle-check" />
              {{ TXT.enviadaEm }} {{ dataHora(o.enviado_em) }}
            </p>
            <button
              v-else-if="podeCotar"
              type="button"
              class="self-start h-9 px-4 rounded-xl text-xs font-semibold border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 flex items-center gap-1.5 disabled:opacity-50"
              :disabled="marcando === o.id"
              @click="marcarEnviada(o)"
            >
              <span class="i-lucide-send" />
              {{ TXT.marcarEnviada }}
            </button>
          </div>
          <p class="text-xs text-n-slate-10">{{ TXT.marcarEnviadaDica }}</p>
        </section>

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
