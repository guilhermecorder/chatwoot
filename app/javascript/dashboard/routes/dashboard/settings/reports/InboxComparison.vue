<script setup>
// 🆚 COMPARATIVO DE CAIXAS (item 413, 24/11). Pedido do Guilherme: "quero um
// ambiente de comparativo de caixas, em que eu posso entender no detalhe…
// comparar uma caixa de entrada com outra… prompt, modelo".
// A conta é de TURMA: quem CHEGOU por aquela caixa no período e o que virou
// dessas mesmas pessoas (Crm::InboxComparison). Em ordem de leitura:
//   quais caixas → o placar → a tabela lado a lado → o dia a dia →
//   frente a frente (duas caixas, no detalhe, com a conta da confiança) →
//   quem atende em cada caixa (motor e Roteiro de verdade) → o dinheiro.
// Filosofia da casa: cada número diz de onde veio (fórmula escrita embaixo).
import { ref, computed, watch, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CompareRuler from 'dashboard/components-next/cevico/CompareRuler.vue';
import TimelineChart from 'dashboard/components-next/cevico/TimelineChart.vue';
import FunnelSteps from 'dashboard/components-next/cevico/FunnelSteps.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useCevicoCompare } from 'dashboard/composables/useCevicoCompare';
import { compareParams, variation } from 'dashboard/helper/cevicoComparison';
import {
  rate,
  funnelRates,
  confidence,
  confidenceText,
  bestIndex,
  humanMinutes,
} from 'dashboard/helper/cevicoInboxCompare';
import CrmAPI from 'dashboard/api/crm';

const pal = useCevicoPalette({
  scope: 'report:inbox_comparison',
  blocks: [
    { id: 'placar', label: 'Placar', icon: 'i-lucide-trophy' },
    { id: 'tabela', label: 'Lado a lado', icon: 'i-lucide-table-2' },
    { id: 'tempo', label: 'Dia a dia', icon: 'i-lucide-trending-up' },
    { id: 'duelo', label: 'Frente a frente', icon: 'i-lucide-swords' },
    { id: 'atende', label: 'Quem atende', icon: 'i-lucide-bot' },
    { id: 'dinheiro', label: 'Dinheiro', icon: 'i-lucide-coins' },
  ],
});
const { cvVars, blockVars } = pal;

const loading = ref(true);
const data = ref(null);
const period = ref({ preset: 'last7', from: '', to: '' });
const { compare, setCompare } = useCevicoCompare('cevico_inbox_compare');
const hidden = ref([]); // caixas que a pessoa tirou da comparação
const duelA = ref(null);
const duelB = ref(null);
const chartView = ref('taxa');
let seq = 0;
let primed = false; // as operacionais só são escondidas sozinhas na primeira carga

const num = v => Number(v || 0).toLocaleString('pt-BR');
const pct = v =>
  v === null || v === undefined
    ? '—'
    : `${Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
const brl = v =>
  v === null || v === undefined
    ? '—'
    : Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const usd = v =>
  `US$ ${Number(v || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: Number(v || 0) < 1 ? 4 : 2,
  })}`;

const load = async () => {
  seq += 1;
  const mine = seq;
  loading.value = true;
  try {
    const { data: payload } = await CrmAPI.getInboxComparison({
      preset: period.value.preset,
      ...(period.value.preset === 'custom'
        ? { from: period.value.from, to: period.value.to }
        : {}),
      ...compareParams(compare.value),
    });
    if (mine === seq) data.value = payload;
  } catch {
    if (mine === seq) useAlert('Não consegui montar o comparativo agora.');
  } finally {
    if (mine === seq) loading.value = false;
  }
};
watch(
  () => [JSON.stringify(period.value), JSON.stringify(compare.value)],
  load
);
onMounted(load);

// ── as caixas, já com as taxas calculadas ─────────────────────────────────
const todas = computed(() =>
  (data.value?.caixas || []).map(c => ({
    ...c,
    taxas: funnelRates(c.funil),
    taxasAntes: funnelRates(c.anterior),
  }))
);
// de saída: as portas de entrada que receberam gente; caixa operacional entra se a pessoa pedir
const padraoFora = computed(() =>
  todas.value.filter(c => !c.porta).map(c => c.inbox_id)
);
const foraSet = computed(() => new Set(hidden.value));
const caixas = computed(() =>
  todas.value.filter(c => !foraSet.value.has(c.inbox_id))
);
watch(
  () => (data.value?.caixas || []).map(c => c.inbox_id).join(','),
  () => {
    const ids = todas.value.map(c => c.inbox_id);
    // primeira carga: esconde as operacionais; depois respeita a escolha da pessoa
    if (!primed && todas.value.length) {
      primed = true;
      if (todas.value.some(c => c.porta)) hidden.value = padraoFora.value;
    }
    hidden.value = hidden.value.filter(id => ids.includes(id));
    const visiveis = caixas.value;
    if (!visiveis.some(c => c.inbox_id === duelA.value))
      duelA.value = visiveis[0]?.inbox_id ?? null;
    if (
      !visiveis.some(c => c.inbox_id === duelB.value) ||
      duelB.value === duelA.value
    )
      duelB.value =
        visiveis.find(c => c.inbox_id !== duelA.value)?.inbox_id ?? null;
  },
  { immediate: true }
);
const toggle = id => {
  hidden.value = foraSet.value.has(id)
    ? hidden.value.filter(x => x !== id)
    : [...hidden.value, id];
};

const rotuloBase = computed(
  () => data.value?.comparacao?.rotulo || 'período anterior'
);
const financeiro = computed(() => !!data.value?.financeiro);
const vazio = computed(
  () => !!data.value && !todas.value.some(c => c.funil.chegaram)
);

// ── PLACAR: a frase + os campeões ────────────────────────────────────────
const MIN_TURMA = 20; // abaixo disso a taxa balança demais para ganhar medalha
const campeao = (pick, { lowerIsBetter = false } = {}) => {
  const aptas = caixas.value.filter(c => c.funil.chegaram >= MIN_TURMA);
  const i = bestIndex(aptas.map(pick), { lowerIsBetter });
  return i < 0 ? null : aptas[i];
};
const placar = computed(() => {
  const list = [
    {
      key: 'agenda',
      titulo: 'Quem mais agenda',
      icon: 'i-lucide-calendar-plus',
      caixa: campeao(c => c.taxas.agendaram),
      valor: c => pct(c.taxas.agendaram),
      sub: c =>
        `${num(c.funil.agendaram)} de ${num(c.funil.chegaram)} que chegaram`,
    },
    {
      key: 'orc',
      titulo: 'Melhor do orçamento para a consulta',
      icon: 'i-lucide-receipt',
      caixa: campeao(c => c.taxas.orcamento_consulta),
      valor: c => pct(c.taxas.orcamento_consulta),
      sub: c => `${num(c.funil.orcamento)} receberam orçamento`,
    },
    {
      key: 'resp',
      titulo: 'Onde o paciente mais responde',
      icon: 'i-lucide-messages-square',
      caixa: campeao(c => c.taxas.responderam),
      valor: c => pct(c.taxas.responderam),
      sub: c => `${num(c.funil.responderam)} escreveram de novo`,
    },
  ];
  if (financeiro.value)
    list.push({
      key: 'custo',
      titulo: 'Consulta marcada mais barata',
      icon: 'i-lucide-piggy-bank',
      caixa: campeao(c => c.custo?.por_agendamento, { lowerIsBetter: true }),
      valor: c => brl(c.custo.por_agendamento),
      sub: c => `${brl(c.custo.investimento)} em anúncio`,
    });
  return list;
});
const fraseTopo = computed(() => {
  // a soma é só das caixas LIGADAS na comparação (as desligadas não entram)
  const chegaram = caixas.value.reduce((t, c) => t + c.funil.chegaram, 0);
  const agendaram = caixas.value.reduce((t, c) => t + c.funil.agendaram, 0);
  if (!chegaram) return 'Ninguém novo chegou pelas caixas escolhidas.';
  const lider = campeao(c => c.taxas.agendaram);
  const base = `${num(chegaram)} pessoas chegaram pelas caixas escolhidas e ${num(agendaram)} já agendaram (${pct(rate(agendaram, chegaram))}).`;
  return lider
    ? `${base} Quem mais agenda: ${lider.nome}, com ${pct(lider.taxas.agendaram)}.`
    : `${base} Ainda não há volume para apontar a melhor caixa (mínimo de ${MIN_TURMA} pessoas por caixa).`;
});
const pessoas = n => (Number(n) === 1 ? '1 pessoa' : `${num(n)} pessoas`);

// ── TABELA LADO A LADO ────────────────────────────────────────────────────
const LINHAS = computed(() => {
  const rows = [
    {
      key: 'chegaram',
      label: 'Chegaram',
      hint: 'contatos novos cuja primeira conversa foi nesta caixa',
      val: c => c.funil.chegaram,
      antes: c => c.anterior.chegaram,
      show: c => num(c.funil.chegaram),
      conta: 'numero',
    },
    {
      key: 'responderam',
      label: 'Responderam',
      hint: 'escreveram de novo depois da nossa primeira resposta',
      val: c => c.taxas.responderam,
      antes: c => c.taxasAntes.responderam,
      show: c => pct(c.taxas.responderam),
      sub: c => pessoas(c.funil.responderam),
    },
    {
      key: 'orcamento',
      label: 'Receberam orçamento',
      hint: 'entraram na coluna de orçamento',
      val: c => c.taxas.orcamento,
      antes: c => c.taxasAntes.orcamento,
      show: c => pct(c.taxas.orcamento),
      sub: c => pessoas(c.funil.orcamento),
    },
    {
      key: 'agendaram',
      label: 'Agendaram consulta',
      hint: 'entraram na coluna de agendamento (a taxa oficial)',
      val: c => c.taxas.agendaram,
      antes: c => c.taxasAntes.agendaram,
      show: c => pct(c.taxas.agendaram),
      sub: c => pessoas(c.funil.agendaram),
      forte: true,
    },
    {
      key: 'orcamento_consulta',
      label: 'Do orçamento para a consulta',
      hint: 'dos que receberam orçamento, quantos agendaram',
      val: c => c.taxas.orcamento_consulta,
      antes: c => c.taxasAntes.orcamento_consulta,
      show: c => pct(c.taxas.orcamento_consulta),
    },
    {
      key: 'compareceram',
      label: 'Compareceram',
      hint: 'dos que agendaram, quantos foram à consulta',
      val: c => c.taxas.compareceram,
      antes: c => c.taxasAntes.compareceram,
      show: c => pct(c.taxas.compareceram),
      sub: c => pessoas(c.funil.compareceram),
    },
    {
      key: 'cirurgias',
      label: 'Marcaram cirurgia',
      hint: 'dos que chegaram, quantos já têm cirurgia na Agenda',
      val: c => c.taxas.cirurgias,
      antes: c => c.taxasAntes.cirurgias,
      show: c => pct(c.taxas.cirurgias),
      sub: c => pessoas(c.funil.cirurgias),
    },
    {
      key: 'resposta',
      label: 'Tempo até a 1ª resposta',
      hint: 'da primeira mensagem do paciente até a nossa (mediana)',
      val: c => c.tempos.primeira_resposta_min,
      show: c => humanMinutes(c.tempos.primeira_resposta_min),
      lower: true,
    },
    {
      key: 'ate_agendar',
      label: 'Tempo até agendar',
      hint: 'da chegada até entrar na coluna de agendamento (mediana)',
      val: c => c.tempos.ate_agendar_h,
      show: c =>
        c.tempos.ate_agendar_h === null
          ? '—'
          : humanMinutes(c.tempos.ate_agendar_h * 60),
      lower: true,
    },
  ];
  if (financeiro.value)
    rows.push(
      {
        key: 'invest',
        label: 'Gasto em anúncio',
        hint: 'a parte do gasto que trouxe gente para esta caixa',
        val: c => c.custo?.investimento || null,
        show: c => (c.custo?.investimento ? brl(c.custo.investimento) : '—'),
        conta: 'numero',
        neutro: true,
      },
      {
        key: 'cpl',
        label: 'Custo por pessoa que chegou',
        hint: 'gasto ÷ chegaram',
        val: c => c.custo?.por_lead,
        show: c => brl(c.custo?.por_lead),
        lower: true,
      },
      {
        key: 'cpa',
        label: 'Custo por consulta agendada',
        hint: 'gasto ÷ agendaram',
        val: c => c.custo?.por_agendamento,
        show: c => brl(c.custo?.por_agendamento),
        lower: true,
        forte: true,
      }
    );
  return rows.map(row => {
    const best =
      row.neutro || row.conta === 'numero'
        ? -1
        : bestIndex(
            caixas.value.map(c =>
              c.funil.chegaram >= MIN_TURMA ? row.val(c) : null
            ),
            { lowerIsBetter: !!row.lower }
          );
    return {
      ...row,
      cells: caixas.value.map((c, i) => ({
        id: c.inbox_id,
        texto: row.show(c),
        sub: row.sub ? row.sub(c) : '',
        best: i === best,
        dif:
          row.antes && row.val(c) !== null
            ? variation(row.val(c), row.antes(c), {
                pontos: row.conta !== 'numero',
              })
            : null,
      })),
    };
  });
});

// ── DIA A DIA ─────────────────────────────────────────────────────────────
const VIEWS = [
  { key: 'taxa', label: 'Taxa de agendamento' },
  { key: 'chegaram', label: 'Chegaram' },
  { key: 'agendaram', label: 'Agendaram' },
];
const chartLines = computed(() =>
  caixas.value.map(c => ({
    key: String(c.inbox_id),
    label: c.nome,
    color: c.cor,
    values: c.serie[chartView.value] || [],
    dots: true,
  }))
);
const chartFormat = v => (chartView.value === 'taxa' ? pct(v) : num(v));
const HINTS = {
  taxa: 'de quem chegou em cada dia, quantos já agendaram; os dias mais recentes ainda sobem, porque a turma segue agendando.',
  chegaram: 'contatos novos por dia em cada caixa.',
  agendaram:
    'pelo dia em que a pessoa CHEGOU (não pelo dia em que agendou): mostra quanto cada turma rendeu.',
};
const chartHint = computed(() => HINTS[chartView.value]);

// ── FRENTE A FRENTE ───────────────────────────────────────────────────────
const porId = id => caixas.value.find(c => c.inbox_id === id) || null;
const A = computed(() => porId(duelA.value));
const B = computed(() => porId(duelB.value));
const conf = computed(() =>
  A.value && B.value
    ? confidence(
        A.value.funil.agendaram,
        A.value.funil.chegaram,
        B.value.funil.agendaram,
        B.value.funil.chegaram
      )
    : null
);
const confFrase = computed(() =>
  A.value && B.value
    ? confidenceText(conf.value, A.value.nome, B.value.nome)
    : ''
);
// posição do ponteiro na régua: 0 = certeza da A, 100 = certeza da B
const confPos = computed(() => (conf.value ? conf.value.chance : 50));
const degraus = c => [
  { label: 'Chegaram', value: c.funil.chegaram, color: c.cor },
  { label: 'Responderam', value: c.funil.responderam, color: c.cor },
  { label: 'Orçamento', value: c.funil.orcamento, color: c.cor },
  { label: 'Agendaram', value: c.funil.agendaram, color: c.cor },
  { label: 'Compareceram', value: c.funil.compareceram, color: c.cor },
  { label: 'Cirurgia', value: c.funil.cirurgias, color: c.cor },
];
const degrausCelular = c =>
  degraus(c).map(d => ({ ...d, share: rate(d.value, c.funil.chegaram) || 0 }));
const fatia = (n, c) => rate(n, c.funil.chegaram) || 0;

// ── QUEM ATENDE ───────────────────────────────────────────────────────────
const MODO = { a: 'variante A', b: 'variante B', split: 'sorteio A × B' };
const configTexto = c => {
  if (!c.config?.length) return ['Nenhum atendente de IA lê nesta caixa.'];
  return c.config.map(a => {
    const motor = a.motores_por_coluna?.length
      ? `${a.motor} + por coluna: ${a.motores_por_coluna.join(', ')}`
      : a.motor;
    const teste = a.teste
      ? ` · teste ligado (${MODO[a.teste.modo] || a.teste.modo}): ${
          a.teste.roteiro_b === 'v2' ? 'Roteiro 2' : 'Roteiro 1'
        }${a.teste.motor_b ? ` + ${a.teste.motor_b}` : ''}`
      : ' · Roteiro 1';
    return `${a.nome}: ${motor}${teste}`;
  });
};
const semRegistro = c => Math.max(0, c.ia.conversas - c.ia.com_registro);
</script>

<template>
  <div class="cv-page cv-overlay cvx-root" :style="cvVars">
    <CevicoHero
      :pal="pal"
      title="Comparativo de caixas"
      subtitle="cada caixa de entrada lado a lado: quem chegou por ela, até onde foi, quem atendeu e quanto custou"
      icon="i-lucide-swords"
    />

    <div class="flex items-center gap-3 flex-wrap mb-4">
      <PeriodRuler v-model="period" glass class="max-w-full" />
      <CompareRuler
        :model-value="compare"
        :resolved="data?.comparacao"
        glass
        @update:model-value="setCompare"
      />
      <button
        class="cv-btn cv-btn-ghost cv-btn-sm flex-shrink-0"
        :disabled="loading"
        @click="load"
      >
        <span class="i-lucide-refresh-cw text-xs" />
        Atualizar
      </button>
    </div>

    <SkeletonScreen v-if="loading && !data" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ quais caixas entram ══ -->
      <div class="mb-6">
        <p class="text-[11px] text-n-slate-10 mb-2">
          Toque numa caixa para tirar ou pôr na comparação. As portas de entrada
          já vêm ligadas; as operacionais (confirmação, pós) ficam à mão.
        </p>
        <div class="flex items-center gap-2 flex-wrap">
          <button
            v-for="c in todas"
            :key="c.inbox_id"
            type="button"
            class="cvx-caixa"
            :class="{ 'cvx-caixa--off': foraSet.has(c.inbox_id) }"
            :style="{ '--cx': c.cor }"
            :aria-pressed="!foraSet.has(c.inbox_id)"
            @click="toggle(c.inbox_id)"
          >
            <span class="cvx-ponto" />
            {{ c.nome }}
            <small>{{ num(c.funil.chegaram) }}</small>
          </button>
        </div>
      </div>

      <div v-if="vazio" class="cv-block p-6 sm:p-9 mb-6">
        <p class="text-sm text-n-slate-11">
          Ninguém novo chegou pelas caixas neste período. Escolha um período
          maior na régua acima.
        </p>
      </div>

      <template v-else>
        <!-- ══ PLACAR ══ -->
        <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('placar')">
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            {{ fraseTopo }}
          </h2>
          <p class="text-xs text-n-slate-10 mt-2 mb-6">
            Conta de turma: segue as mesmas pessoas, da chegada em diante. Quem
            chegou há pouco ainda pode agendar, então o período mais recente
            sempre sobe um pouco depois.
          </p>
          <div class="cvx-placar">
            <div v-for="p in placar" :key="p.key" class="cv-sub p-5">
              <p class="cvx-rotulo">
                <span :class="p.icon" aria-hidden="true" />
                {{ p.titulo }}
              </p>
              <template v-if="p.caixa">
                <p class="cvx-campeao">
                  <span class="cvx-ponto" :style="{ '--cx': p.caixa.cor }" />
                  {{ p.caixa.nome }}
                </p>
                <p class="cvx-grande">{{ p.valor(p.caixa) }}</p>
                <p class="text-[11px] text-n-slate-10">{{ p.sub(p.caixa) }}</p>
              </template>
              <p v-else class="text-xs text-n-slate-10 mt-2">
                ainda não dá para comparar: precisa de duas caixas com
                {{ MIN_TURMA }} pessoas ou mais e com esse número
              </p>
            </div>
          </div>
        </div>

        <!-- ══ LADO A LADO ══ -->
        <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('tabela')">
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Lado a lado, etapa por etapa
          </h2>
          <p class="text-xs text-n-slate-10 mt-1 mb-5">
            A melhor caixa de cada linha fica marcada (só concorre quem recebeu
            {{ MIN_TURMA }} pessoas ou mais). A setinha compara com
            {{ rotuloBase }}.
          </p>
          <div class="cvx-rolagem">
            <table class="cvx-tabela">
              <thead>
                <tr>
                  <th />
                  <th v-for="c in caixas" :key="c.inbox_id">
                    <span class="cvx-ponto" :style="{ '--cx': c.cor }" />
                    {{ c.nome }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in LINHAS"
                  :key="row.key"
                  :class="{ 'cvx-forte': row.forte }"
                >
                  <th>
                    {{ row.label }}
                    <small>{{ row.hint }}</small>
                  </th>
                  <td
                    v-for="cell in row.cells"
                    :key="cell.id"
                    :class="{ 'cvx-melhor': cell.best }"
                  >
                    <b>{{ cell.texto }}</b>
                    <small v-if="cell.sub">{{ cell.sub }}</small>
                    <small
                      v-if="cell.dif && cell.dif.curto !== '—'"
                      :class="`cvx-var--${cell.dif.estado}`"
                    >
                      {{ cell.dif.seta }} {{ cell.dif.curto }}
                    </small>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- ══ DIA A DIA ══ -->
        <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('tempo')">
          <div class="flex items-start gap-3 flex-wrap mb-1">
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12 flex-1 min-w-[240px]"
            >
              Cada caixa ao longo do período
            </h2>
            <div class="cv-seg cv-seg-sm flex-wrap max-w-full">
              <button
                v-for="view in VIEWS"
                :key="view.key"
                class="cv-seg-item"
                :class="{ 'cv-seg-on': chartView === view.key }"
                @click="chartView = view.key"
              >
                {{ view.label }}
              </button>
            </div>
          </div>
          <p class="text-xs text-n-slate-10 mt-2 mb-5">{{ chartHint }}</p>
          <TimelineChart
            :labels="data.rotulos"
            :lines="chartLines"
            :left-format="chartFormat"
            :height="280"
            bridge-gaps
            empty-text="ninguém chegou no período"
          />
        </div>

        <!-- ══ FRENTE A FRENTE ══ -->
        <div
          v-if="caixas.length >= 2 && A && B"
          class="cv-block p-6 sm:p-9 mb-6"
          :style="blockVars('duelo')"
        >
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Frente a frente: duas caixas no detalhe
          </h2>
          <p class="text-xs text-n-slate-10 mt-1 mb-5">
            Escolha as duas. A régua diz se a diferença na taxa de agendamento é
            de verdade ou se ainda pode ser acaso.
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-5">
            <label class="cvx-escolha" :style="{ '--cx': A.cor }">
              <span class="cvx-ponto" />
              <select v-model="duelA" class="cv-input">
                <option
                  v-for="c in caixas"
                  :key="c.inbox_id"
                  :value="c.inbox_id"
                  :disabled="c.inbox_id === duelB"
                >
                  {{ c.nome }}
                </option>
              </select>
            </label>
            <label class="cvx-escolha" :style="{ '--cx': B.cor }">
              <span class="cvx-ponto" />
              <select v-model="duelB" class="cv-input">
                <option
                  v-for="c in caixas"
                  :key="c.inbox_id"
                  :value="c.inbox_id"
                  :disabled="c.inbox_id === duelA"
                >
                  {{ c.nome }}
                </option>
              </select>
            </label>
          </div>

          <!-- a conta da confiança -->
          <div class="cv-sub p-5 mb-6">
            <p class="text-sm font-bold text-n-slate-12">{{ confFrase }}</p>
            <div class="cvx-regua" aria-hidden="true">
              <span class="cvx-regua-a" :style="{ background: A.cor }" />
              <span class="cvx-regua-b" :style="{ background: B.cor }" />
              <span class="cvx-regua-pino" :style="{ left: `${confPos}%` }" />
            </div>
            <div
              class="flex justify-between text-[11px] text-n-slate-10 gap-3 flex-wrap"
            >
              <span>
                {{ A.nome }}: {{ pct(A.taxas.agendaram) }} ({{
                  num(A.funil.agendaram)
                }}
                de {{ num(A.funil.chegaram) }})
              </span>
              <span>
                {{ B.nome }}: {{ pct(B.taxas.agendaram) }} ({{
                  num(B.funil.agendaram)
                }}
                de {{ num(B.funil.chegaram) }})
              </span>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div
              v-for="c in [A, B]"
              :key="c.inbox_id"
              class="cv-sub p-5 min-w-0"
            >
              <p class="text-sm font-bold text-n-slate-12 mb-1">
                <span class="cvx-ponto" :style="{ '--cx': c.cor }" />
                {{ c.nome }}
              </p>
              <p
                v-for="linha in configTexto(c)"
                :key="linha"
                class="text-[11px] text-n-slate-10"
              >
                {{ linha }}
              </p>

              <!-- o caminho: degraus no computador, barras no celular -->
              <div class="hidden sm:block mt-4">
                <FunnelSteps
                  :steps="degraus(c)"
                  :height="130"
                  start-text="de quem chegou"
                />
              </div>
              <div class="sm:hidden space-y-3 mt-4">
                <div v-for="d in degrausCelular(c)" :key="d.label">
                  <div class="flex items-baseline justify-between gap-2 mb-1">
                    <span class="text-xs text-n-slate-11">{{ d.label }}</span>
                    <span
                      class="text-xs tabular-nums whitespace-nowrap text-n-slate-12"
                    >
                      <b class="text-sm">{{ num(d.value) }}</b>
                      · {{ pct(d.share) }}
                    </span>
                  </div>
                  <div class="h-2.5 rounded-full bg-n-alpha-2 overflow-hidden">
                    <div
                      class="h-full rounded-full"
                      :style="{
                        width: `${Math.max(d.value ? 2 : 0, d.share)}%`,
                        background: c.cor,
                      }"
                    />
                  </div>
                </div>
              </div>

              <dl class="cvx-fatos">
                <div>
                  <dt>Do orçamento para a consulta</dt>
                  <dd>{{ pct(c.taxas.orcamento_consulta) }}</dd>
                </div>
                <div>
                  <dt>1ª resposta em</dt>
                  <dd>{{ humanMinutes(c.tempos.primeira_resposta_min) }}</dd>
                </div>
                <div>
                  <dt>Agendam em</dt>
                  <dd>
                    {{
                      c.tempos.ate_agendar_h === null
                        ? '—'
                        : humanMinutes(c.tempos.ate_agendar_h * 60)
                    }}
                  </dd>
                </div>
                <div>
                  <dt>Alguém da equipe escreveu</dt>
                  <dd>
                    {{ num(c.tempos.com_humano) }}
                    <small>
                      ({{ pct(rate(c.tempos.com_humano, c.funil.chegaram)) }})
                    </small>
                  </dd>
                </div>
              </dl>

              <!-- em que coluna a turma está agora -->
              <p class="cvx-rotulo mt-5">Onde essa turma está agora</p>
              <div v-if="c.colunas.length" class="space-y-2 mt-2">
                <div v-for="col in c.colunas" :key="col.nome">
                  <div class="flex items-baseline justify-between gap-2">
                    <span class="text-xs text-n-slate-11">{{ col.nome }}</span>
                    <span
                      class="text-xs tabular-nums whitespace-nowrap text-n-slate-12"
                    >
                      <b>{{ num(col.n) }}</b> · {{ pct(fatia(col.n, c)) }}
                    </span>
                  </div>
                  <div class="h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
                    <div
                      class="h-full rounded-full"
                      :style="{
                        width: `${Math.max(2, fatia(col.n, c))}%`,
                        background: c.cor,
                      }"
                    />
                  </div>
                </div>
              </div>
              <p v-else class="text-xs text-n-slate-10 mt-2">sem cards ainda</p>

              <!-- de quais campanhas veio -->
              <p class="cvx-rotulo mt-5">De onde essa turma veio</p>
              <div class="cvx-rolagem mt-2">
                <table class="cvx-mini">
                  <thead>
                    <tr>
                      <th>Campanha</th>
                      <th>Chegaram</th>
                      <th>Agendaram</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="camp in c.campanhas" :key="camp.nome">
                      <td>{{ camp.nome }}</td>
                      <td>{{ num(camp.chegaram) }}</td>
                      <td>
                        {{ num(camp.agendaram) }}
                        <small>
                          ({{ pct(rate(camp.agendaram, camp.chegaram)) }})
                        </small>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>

        <!-- ══ QUEM ATENDE ══ -->
        <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('atende')">
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Quem atende em cada caixa: motor e Roteiro
          </h2>
          <p class="text-xs text-n-slate-10 mt-1 mb-6">
            Conversas abertas no período. O motor e o Roteiro são lidos do
            registro de cada conversa; esse registro passou a ser guardado
            sempre em 24/11/2026. Antes disso só existe para conversa que estava
            num teste A/B.
          </p>
          <div class="cvx-cartoes">
            <div
              v-for="c in caixas"
              :key="c.inbox_id"
              class="cv-sub p-5 min-w-0"
            >
              <p class="text-sm font-bold text-n-slate-12 mb-1">
                <span class="cvx-ponto" :style="{ '--cx': c.cor }" />
                {{ c.nome }}
              </p>
              <p
                v-for="linha in configTexto(c)"
                :key="linha"
                class="text-[11px] text-n-slate-10"
              >
                Hoje · {{ linha }}
              </p>
              <dl class="cvx-fatos">
                <div>
                  <dt>Conversas novas</dt>
                  <dd>{{ num(c.ia.conversas) }}</dd>
                </div>
                <div>
                  <dt>Respondidas pela IA</dt>
                  <dd>
                    {{ num(c.ia.atendidas) }}
                    <small>({{ num(c.ia.respostas) }} respostas)</small>
                  </dd>
                </div>
                <div>
                  <dt>A IA chamou a equipe</dt>
                  <dd>
                    {{ num(c.ia.humano) }}
                    <small>
                      ({{ pct(rate(c.ia.humano, c.ia.atendidas)) }})
                    </small>
                  </dd>
                </div>
                <div v-if="financeiro">
                  <dt>Custo da IA</dt>
                  <dd>
                    {{ usd(c.ia.custo_usd) }}
                    <small v-if="c.ia.custo_por_conversa_usd !== null">
                      ({{ usd(c.ia.custo_por_conversa_usd) }} por conversa)
                    </small>
                  </dd>
                </div>
              </dl>
              <p class="cvx-rotulo mt-4">Motor que respondeu</p>
              <div
                v-if="c.ia.modelos.length"
                class="flex flex-wrap gap-1.5 mt-2"
              >
                <span v-for="m in c.ia.modelos" :key="m.id" class="cv-chip">
                  {{ m.nome }} · {{ num(m.conversas) }}
                </span>
              </div>
              <p v-else class="text-xs text-n-slate-10 mt-2">sem registro</p>
              <p class="cvx-rotulo mt-4">Roteiro usado</p>
              <div
                v-if="c.ia.roteiros.length"
                class="flex flex-wrap gap-1.5 mt-2"
              >
                <span v-for="r in c.ia.roteiros" :key="r.id" class="cv-chip">
                  {{ r.nome }} · {{ num(r.conversas) }}
                </span>
              </div>
              <p v-else class="text-xs text-n-slate-10 mt-2">sem registro</p>
              <p v-if="semRegistro(c)" class="text-[11px] text-n-slate-10 mt-3">
                {{ num(semRegistro(c)) }} conversa(s) sem registro de IA
                (anteriores a 24/11 ou atendidas só pela equipe).
              </p>
            </div>
          </div>
        </div>

        <!-- ══ DINHEIRO (só administrador) ══ -->
        <div
          v-if="financeiro"
          class="cv-block p-6 sm:p-9 mb-6"
          :style="blockVars('dinheiro')"
        >
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Quanto custou cada caixa
          </h2>
          <p class="text-xs text-n-slate-10 mt-1 mb-5">
            <template v-if="data.meta?.total">
              O Meta gastou {{ brl(data.meta.total) }} no período. Cada real vai
              para a caixa onde o anúncio dele abriu conversa
              <template v-if="data.meta.metodo === 'conversas'">
                (os números por anúncio de hoje ainda não chegaram; a divisão
                está pela proporção das conversas vindas de anúncio) </template
              >.
              <template v-if="data.meta.sem_caixa > 0">
                {{ brl(data.meta.sem_caixa) }} não abriram conversa em caixa
                nenhuma (campanha que leva para o site, por exemplo) e ficam
                fora da conta por caixa.
              </template>
            </template>
            <template v-else-if="data.meta?.aviso">
              Meta: {{ data.meta.aviso }}.
            </template>
            <template v-else>Sem gasto do Meta no período.</template>
            <template v-if="data.google?.error">
              Google: {{ data.google.error }}.
            </template>
          </p>
          <div class="cvx-rolagem">
            <table class="cvx-mini cvx-mini--larga">
              <thead>
                <tr>
                  <th>Caixa</th>
                  <th>Gasto em anúncio</th>
                  <th>Por pessoa que chegou</th>
                  <th>Por orçamento</th>
                  <th>Por consulta agendada</th>
                  <th>Por comparecimento</th>
                  <th>Por cirurgia</th>
                  <th>IA</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="c in caixas" :key="c.inbox_id">
                  <td>
                    <span class="cvx-ponto" :style="{ '--cx': c.cor }" />
                    {{ c.nome }}
                    <small v-if="c.custo.partes.length" class="block">
                      {{ c.custo.partes.map(p => p.origem).join(' + ') }}
                    </small>
                    <small v-if="c.custo.aviso" class="block cvx-var--atencao">
                      {{ c.custo.aviso }}
                    </small>
                  </td>
                  <td>
                    {{ c.custo.investimento ? brl(c.custo.investimento) : '—' }}
                  </td>
                  <td>{{ brl(c.custo.por_lead) }}</td>
                  <td>{{ brl(c.custo.por_orcamento) }}</td>
                  <td>
                    <b>{{ brl(c.custo.por_agendamento) }}</b>
                  </td>
                  <td>{{ brl(c.custo.por_comparecimento) }}</td>
                  <td>{{ brl(c.custo.por_cirurgia) }}</td>
                  <td>{{ usd(c.custo.ia_usd) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>
    </template>
  </div>
</template>

<style lang="scss" scoped>
.cvx-ponto {
  display: inline-block;
  width: 0.625rem;
  height: 0.625rem;
  border-radius: 999px;
  background: var(--cx, #2563eb);
  margin-right: 0.35rem;
  flex-shrink: 0;
}
.cvx-caixa {
  display: inline-flex;
  align-items: center;
  gap: 0.15rem;
  padding: 0.4rem 0.8rem;
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 600;
  color: rgb(var(--slate-12));
  border: 1px solid color-mix(in srgb, var(--cx) 45%, transparent);
  background: color-mix(in srgb, var(--cx) 9%, transparent);
  transition:
    opacity 0.15s,
    background 0.15s;
  small {
    margin-left: 0.35rem;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    color: rgb(var(--slate-10));
  }
  &--off {
    opacity: 0.45;
    background: transparent;
    border-style: dashed;
  }
}
.cvx-placar {
  display: grid;
  gap: 1rem;
  grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
}
.cvx-rotulo {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.6875rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: rgb(var(--slate-10));
}
.cvx-campeao {
  margin-top: 0.75rem;
  font-size: 0.8125rem;
  font-weight: 700;
  color: rgb(var(--slate-12));
}
.cvx-grande {
  font-size: 2rem;
  line-height: 1.1;
  font-weight: 800;
  letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-12));
  white-space: nowrap;
}
.cvx-rolagem {
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}
.cvx-tabela {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  font-size: 0.8125rem;
  thead th {
    text-align: right;
    font-weight: 700;
    padding: 0.5rem 0.75rem;
    white-space: nowrap;
    color: rgb(var(--slate-12));
    border-bottom: 1px solid rgb(var(--slate-6) / 0.6);
  }
  tbody th {
    text-align: left;
    font-weight: 600;
    padding: 0.7rem 0.75rem 0.7rem 0;
    min-width: 190px;
    max-width: 240px;
    color: rgb(var(--slate-12));
    border-bottom: 1px solid rgb(var(--slate-6) / 0.35);
    small {
      display: block;
      font-weight: 400;
      font-size: 0.6875rem;
      color: rgb(var(--slate-10));
    }
  }
  td {
    text-align: right;
    padding: 0.7rem 0.75rem;
    min-width: 132px;
    font-variant-numeric: tabular-nums;
    border-bottom: 1px solid rgb(var(--slate-6) / 0.35);
    vertical-align: top;
    b {
      display: block;
      font-size: 0.9375rem;
      color: rgb(var(--slate-12));
      white-space: nowrap;
    }
    small {
      display: block;
      font-size: 0.6875rem;
      color: rgb(var(--slate-10));
      white-space: nowrap;
    }
  }
  .cvx-forte td b {
    font-size: 1.125rem;
  }
  .cvx-melhor {
    background: rgb(5 150 105 / 0.1);
    border-radius: 0.5rem;
    b {
      color: #047857;
    }
  }
}
// celular: a etiqueta encolhe e perde a explicação, para caberem duas caixas na tela
@media (max-width: 640px) {
  .cvx-tabela {
    thead th {
      white-space: normal;
      padding: 0.5rem 0.4rem;
      font-size: 0.75rem;
    }
    tbody th {
      // só no celular a etiqueta fica presa ao rolar para o lado
      position: sticky;
      left: 0;
      z-index: 1;
      background: rgb(var(--slate-1) / 0.94);
      min-width: 98px;
      max-width: 110px;
      font-size: 0.75rem;
      padding-right: 0.4rem;
      small {
        display: none;
      }
    }
    td {
      min-width: 84px;
      padding: 0.6rem 0.3rem;
      b {
        font-size: 0.875rem;
      }
    }
    .cvx-forte td b {
      font-size: 1rem;
    }
  }
}
.dark .cvx-tabela .cvx-melhor b,
.dark .cvx-var--bom {
  color: #34d399 !important;
}
.dark .cvx-var--atencao {
  color: #fbbf24 !important;
}
.cvx-var--bom {
  color: #047857 !important;
}
.cvx-var--atencao {
  color: #b45309 !important;
}
.cvx-escolha {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  select {
    flex: 1;
    min-width: 0;
  }
}
.cvx-regua {
  position: relative;
  display: flex;
  height: 0.5rem;
  border-radius: 999px;
  overflow: visible;
  margin: 1rem 0 0.6rem;
  .cvx-regua-a,
  .cvx-regua-b {
    flex: 1;
    opacity: 0.35;
  }
  .cvx-regua-a {
    border-radius: 999px 0 0 999px;
  }
  .cvx-regua-b {
    border-radius: 0 999px 999px 0;
  }
  .cvx-regua-pino {
    position: absolute;
    top: 50%;
    width: 1rem;
    height: 1rem;
    border-radius: 999px;
    background: rgb(var(--slate-12));
    border: 2px solid rgb(var(--slate-1));
    transform: translate(-50%, -50%);
    transition: left 0.3s ease;
  }
}
.cvx-fatos {
  display: grid;
  gap: 0.75rem;
  grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
  margin-top: 1.25rem;
  dt {
    font-size: 0.6875rem;
    color: rgb(var(--slate-10));
  }
  dd {
    font-size: 0.9375rem;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: rgb(var(--slate-12));
    small {
      font-weight: 400;
      font-size: 0.6875rem;
      color: rgb(var(--slate-10));
    }
  }
}
.cvx-cartoes {
  display: grid;
  gap: 1.25rem;
  grid-template-columns: repeat(auto-fit, minmax(270px, 1fr));
}
.cvx-mini {
  width: 100%;
  font-size: 0.75rem;
  border-collapse: collapse;
  th {
    text-align: right;
    font-weight: 600;
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    color: rgb(var(--slate-10));
    padding: 0.4rem 0.5rem;
    white-space: nowrap;
  }
  td {
    text-align: right;
    padding: 0.5rem;
    font-variant-numeric: tabular-nums;
    color: rgb(var(--slate-12));
    border-top: 1px solid rgb(var(--slate-6) / 0.35);
    white-space: nowrap;
    small {
      font-size: 0.6875rem;
      color: rgb(var(--slate-10));
    }
  }
  th:first-child,
  td:first-child {
    text-align: left;
    white-space: normal;
    min-width: 150px;
  }
  &--larga {
    min-width: 760px;
    font-size: 0.8125rem;
  }
}
</style>
