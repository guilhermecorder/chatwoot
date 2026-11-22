<script setup>
// 🏆 18/11/2026: aba RANKING do Banco de Ganchos (Guilherme: "ter um
// ranqueamento real e testar infinitos ganchos, mas sempre sabendo o que
// funciona"). Mostra, por TIPO de gancho e por gancho:
//   • uso (quantas vezes o botão Usar foi apertado);
//   • resultado dos anúncios da Meta ligados às criações (Crm::CopyBankRanking).
// Visual: número grande + barra; um botão troca a régua.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import { TIPO } from './cbMeta';

const emit = defineEmits(['irPara']);

const loading = ref(true);
const dados = ref({ criacoes: [], tipos: [], ganchos: [], resumo: {} });
const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAPI.getCopyRanking();
    dados.value = data;
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para montar o ranking.');
  } finally {
    loading.value = false;
  }
};
onMounted(load);

const nf = (n, casas = 0) =>
  Number(n || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: casas,
    maximumFractionDigits: casas,
  });
// as réguas: como mostrar, e se "menor é melhor"
const REGUAS = [
  { key: 'conversas_mil', label: 'Conversas por mil', fmt: v => nf(v, 1), sub: 'conversas a cada mil impressões' },
  { key: 'gancho_pct', label: 'Taxa de gancho', fmt: v => `${nf(v, 0)}%`, sub: 'viu 3 s ÷ impressões' },
  { key: 'custo_conversa', label: 'Custo por conversa', fmt: v => `R$ ${nf(v, 2)}`, sub: 'gasto ÷ conversas', menor: true },
  { key: 'usos', label: 'Uso', fmt: v => `${nf(v)}×`, sub: 'vezes que foi usado' },
];
const temResultado = computed(() => (dados.value.resumo?.ligadas || 0) > 0);
const regua = ref('usos');
const R = computed(() => REGUAS.find(r => r.key === regua.value));
const escolherRegua = k => {
  regua.value = k;
};
// primeira abertura: se já há anúncio ligado, a régua de resultado é a padrão
const pronto = computed(() => !loading.value);
const iniciou = ref(false);
const reguaInicial = () => {
  if (iniciou.value || loading.value) return;
  iniciou.value = true;
  if (temResultado.value) regua.value = 'conversas_mil';
};

const ordenar = lista => {
  const k = regua.value;
  const com = lista.filter(x => x[k] !== null && x[k] !== undefined && (k !== 'usos' || x[k] > 0));
  const sem = lista.filter(x => !com.includes(x));
  com.sort((a, b) => (R.value.menor ? a[k] - b[k] : b[k] - a[k]));
  return { com, sem };
};
const tipos = computed(() => {
  reguaInicial();
  return ordenar(dados.value.tipos || []);
});
const ganchos = computed(() => ordenar(dados.value.ganchos || []));
const maior = lista => Math.max(...lista.map(x => Number(x[regua.value]) || 0), 0.0001);
const largura = (x, lista) => `${Math.max(4, Math.round(((Number(x[regua.value]) || 0) / maior(lista)) * 100))}%`;
const tipoInfo = k => TIPO[k] || { label: k || 'Sem modelo', color: '#64748b', icon: 'i-lucide-pen-line' };
const detalhe = x =>
  [
    x.usos ? `usado ${x.usos}×` : '',
    x.criacoes ? `${x.criacoes} criaç${x.criacoes > 1 ? 'ões' : 'ão'}` : '',
    x.anuncios ? `${x.anuncios} anúncio${x.anuncios > 1 ? 's' : ''}` : '',
    x.impressoes ? `${nf(x.impressoes)} impressões` : '',
  ]
    .filter(Boolean)
    .join(' · ');
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div>
    <div class="flex items-center gap-3 flex-wrap mb-5">
      <span class="cv-icon cv-icon-lg">
        <span class="i-lucide-trophy text-xl" />
      </span>
      <h2 class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight flex-1">
        Ranking
      </h2>
      <button class="cv-btn cv-btn-sm cv-btn-ghost" :disabled="loading" @click="load">
        <span class="i-lucide-refresh-cw" />
        Atualizar
      </button>
    </div>

    <p v-if="loading" class="text-sm text-n-slate-10">Montando o ranking…</p>

    <template v-else-if="pronto">
      <!-- os 4 números -->
      <div class="grid grid-cols-2 xl:grid-cols-4 gap-3 mb-6">
        <div class="cv-sub p-4">
          <p class="text-3xl font-bold text-n-slate-12 leading-none">{{ nf(dados.resumo.criacoes) }}</p>
          <p class="text-xs text-n-slate-10 mt-2">criações salvas</p>
        </div>
        <div class="cv-sub p-4">
          <p class="text-3xl font-bold text-n-slate-12 leading-none">{{ nf(dados.resumo.ligadas) }}</p>
          <p class="text-xs text-n-slate-10 mt-2">com anúncio ligado</p>
        </div>
        <div class="cv-sub p-4">
          <p class="text-3xl font-bold text-n-slate-12 leading-none">{{ nf(dados.resumo.impressoes) }}</p>
          <p class="text-xs text-n-slate-10 mt-2">impressões</p>
        </div>
        <div class="cv-sub p-4">
          <p class="text-3xl font-bold text-n-slate-12 leading-none">{{ nf(dados.resumo.conversas) }}</p>
          <p class="text-xs text-n-slate-10 mt-2">conversas</p>
        </div>
      </div>

      <!-- sem anúncio ligado: como ligar -->
      <div v-if="!temResultado" class="cv-sub p-4 sm:p-5 mb-6 flex items-center gap-4 flex-wrap">
        <span class="w-10 h-10 rounded-[13px] flex-shrink-0 flex items-center justify-center text-white bg-[#2563eb]">
          <span class="i-lucide-link text-xl" />
        </span>
        <div class="flex-1 min-w-[14rem]">
          <p class="font-bold text-n-slate-12">Falta ligar os anúncios</p>
          <p class="text-sm text-n-slate-11">
            Por enquanto o ranking mostra só o uso. Salve a criação e ponha o código dela (ex.: CRI-12) no nome do anúncio na Meta.
          </p>
        </div>
        <button class="cv-btn cv-blue" @click="emit('irPara', 'criacoes')">Ver as criações</button>
      </div>

      <!-- a régua -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <div class="cv-seg flex-wrap">
          <button
            v-for="r in REGUAS"
            :key="r.key"
            class="cv-seg-item"
            :class="{ 'cv-seg-on': regua === r.key }"
            @click="escolherRegua(r.key)"
          >
            {{ r.label }}
          </button>
        </div>
        <p class="text-sm text-n-slate-10">{{ R.sub }}</p>
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-5 gap-6">
        <!-- por TIPO -->
        <div class="xl:col-span-2 min-w-0">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Tipos de gancho</p>
          <p v-if="!tipos.com.length" class="text-sm text-n-slate-10">Ainda sem dado nesta régua.</p>
          <div v-else class="rounded-2xl border border-n-weak divide-y divide-n-weak overflow-hidden">
            <div v-for="(t, i) in tipos.com" :key="t.tipo || 'sem'" class="px-4 py-3">
              <div class="flex items-center gap-3 min-w-0">
                <span class="text-sm font-bold text-n-slate-10 w-5 flex-shrink-0">{{ i + 1 }}</span>
                <span
                  class="w-8 h-8 rounded-[10px] flex-shrink-0 flex items-center justify-center text-white"
                  :style="{ background: tipoInfo(t.tipo).color }"
                >
                  <span :class="tipoInfo(t.tipo).icon" />
                </span>
                <p class="flex-1 min-w-0 font-bold text-n-slate-12 truncate">{{ tipoInfo(t.tipo).label }}</p>
                <p class="text-xl font-bold text-n-slate-12 flex-shrink-0">{{ R.fmt(t[regua]) }}</p>
              </div>
              <div class="h-1.5 rounded-full bg-n-alpha-2 mt-2 overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: largura(t, tipos.com), background: tipoInfo(t.tipo).color }" />
              </div>
              <p class="text-xs text-n-slate-10 mt-1.5">{{ detalhe(t) }}</p>
            </div>
          </div>
        </div>

        <!-- por GANCHO -->
        <div class="xl:col-span-3 min-w-0">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Ganchos</p>
          <p v-if="!ganchos.com.length" class="text-sm text-n-slate-10">Ainda sem dado nesta régua.</p>
          <div v-else class="rounded-2xl border border-n-weak divide-y divide-n-weak overflow-hidden">
            <div v-for="(g, i) in ganchos.com" :key="g.block_id" class="px-4 py-3">
              <div class="flex items-start gap-3 min-w-0">
                <span class="text-sm font-bold text-n-slate-10 w-5 flex-shrink-0 pt-0.5">{{ i + 1 }}</span>
                <div class="flex-1 min-w-0">
                  <p class="text-[11px] font-semibold uppercase tracking-wide" :style="{ color: tipoInfo(g.tipo).color }">
                    {{ tipoInfo(g.tipo).label }}
                  </p>
                  <p class="text-[15px] font-medium text-n-slate-12 leading-snug break-words">{{ g.texto }}</p>
                </div>
                <p class="text-xl font-bold text-n-slate-12 flex-shrink-0">{{ R.fmt(g[regua]) }}</p>
              </div>
              <div class="h-1.5 rounded-full bg-n-alpha-2 mt-2 overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: largura(g, ganchos.com), background: tipoInfo(g.tipo).color }" />
              </div>
              <p class="text-xs text-n-slate-10 mt-1.5">{{ detalhe(g) }}</p>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
