<script setup>
// PERFIL: os dois testes (DISC 28 itens + 4 Temperamentos), o radar que
// compara os resultados, a ORDEM dos 4 (que importa!) e o arquivo de
// testes antigos para acompanhar a evolução.
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import RadarChart from './RadarChart.vue';
import {
  DISC_QUESTIONS, DISC_SCALES, TEMPERAMENT_QUESTIONS, DISC_PROFILES, DISC_DUOS,
  computeDisc, discPercentages, discRanking,
} from './discQuiz';

const props = defineProps({
  person: { type: Object, required: true },
  isMe: { type: Boolean, default: false },
});

const DIMS = ['d', 'i', 's', 'c'];
const assessments = computed(() => props.person.assessments || []);
const latestOf = kind => [...assessments.value].reverse().find(a => a.kind === kind) || null;

// compat: quem fez o DISC v1 (12 perguntas) continua com resultado válido
const latestDisc = computed(() => {
  const v2 = latestOf('disc');
  if (v2) return v2;
  const legacy = props.person.disc?.scores;
  return legacy ? { kind: 'disc', scores: legacy, ranking: discRanking(legacy), taken_at: props.person.disc.taken_at } : null;
});
const latestTemp = computed(() => latestOf('temperamentos'));

const pctOf = entry => (entry ? discPercentages(entry.scores) : null);
const rankingOf = entry => entry?.ranking || (entry ? discRanking(entry.scores) : []);
const dominantProfile = computed(() => {
  const r = rankingOf(latestDisc.value);
  return r.length ? DISC_PROFILES[r[0]] : null;
});
const duo = computed(() => {
  const r = rankingOf(latestDisc.value);
  return r.length > 1 ? DISC_DUOS[`${r[0]}${r[1]}`] : null;
});

// ── radar: DISC × Temperamentos (+ teste arquivado opcional) ──
const axes = DIMS.map(dim => ({ key: dim, label: DISC_PROFILES[dim].letter, color: DISC_PROFILES[dim].color }));
const compareAt = ref('');
const radarDatasets = computed(() => {
  const sets = [];
  if (latestDisc.value) sets.push({ label: 'DISC (trabalho)', color: '#0F5FA6', values: pctOf(latestDisc.value) });
  if (latestTemp.value) sets.push({ label: 'Temperamentos (vida)', color: '#DB2777', values: pctOf(latestTemp.value) });
  const archived = assessments.value.find(a => a.taken_at === compareAt.value);
  if (archived) sets.push({ label: `Arquivado ${fmtAt(archived.taken_at)}`, color: '#64748B', values: pctOf(archived) });
  return sets.slice(0, 3);
});

const fmtAt = iso => new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' });
const orderLabel = entry =>
  rankingOf(entry).map(dim => DISC_PROFILES[dim].letter).join(' › ');
const orderTemperaments = entry =>
  rankingOf(entry).map(dim => DISC_PROFILES[dim].temperament).join(' › ');

// ── runner dos testes (escolha + escala 0-10) ──
const quizKind = ref(null); // null | 'disc' | 'temperamentos'
const quizItems = ref([]);
const quizStep = ref(0);
const quizAnswers = ref([]);
const scaleValue = ref(5);
const savingQuiz = ref(false);

const startQuiz = kind => {
  quizKind.value = kind;
  quizItems.value =
    kind === 'disc'
      ? [
          ...DISC_QUESTIONS.map(q => ({ type: 'choice', ...q })),
          ...DISC_SCALES.map(s => ({ type: 'scale', ...s })),
        ]
      : TEMPERAMENT_QUESTIONS.map(q => ({ type: 'choice', ...q }));
  quizStep.value = 0;
  quizAnswers.value = [];
  scaleValue.value = 5;
};
const currentItem = computed(() => quizItems.value[quizStep.value] || null);
const advance = async answer => {
  quizAnswers.value.push(answer);
  if (quizStep.value < quizItems.value.length - 1) {
    quizStep.value += 1;
    scaleValue.value = 5;
    return;
  }
  savingQuiz.value = true;
  try {
    const scores = computeDisc(quizAnswers.value);
    const { data } = await CrmAPI.saveAssessment(quizKind.value, scores);
    props.person.assessments = data.assessments;
    if (data.disc) props.person.disc = data.disc;
    quizKind.value = null;
    useAlert('Teste concluído e arquivado! Esse é o seu mapa. ✨');
  } catch {
    useAlert('Não consegui salvar o resultado.');
  } finally {
    savingQuiz.value = false;
  }
};
</script>

<template>
  <!-- runner -->
  <div v-if="quizKind && currentItem" class="max-w-xl mx-auto py-4">
    <div class="flex items-center justify-between mb-1.5">
      <p class="text-[11px] font-semibold text-n-slate-10">
        {{ quizKind === 'disc' ? 'Diagnóstico DISC' : '4 Temperamentos' }} · {{ quizStep + 1 }} de {{ quizItems.length }}
      </p>
      <button class="text-[11px] text-n-slate-9 hover:text-red-500" @click="quizKind = null">cancelar</button>
    </div>
    <div class="h-2 bg-n-alpha-1 rounded-full overflow-hidden mb-4">
      <div class="h-full rounded-full transition-all duration-500" :style="{ width: `${(quizStep / quizItems.length) * 100}%`, background: 'linear-gradient(90deg, #0F766E, #2DD4BF)' }" />
    </div>

    <!-- escolha -->
    <template v-if="currentItem.type === 'choice'">
      <h3 class="text-base font-bold text-n-slate-12 mb-3">{{ currentItem.q }}</h3>
      <p class="text-[11px] text-n-slate-9 mb-3">escolha a frase que MAIS parece com você:</p>
      <button
        v-for="(opt, oi) in currentItem.options"
        :key="oi"
        class="w-full text-left rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 mb-2 text-sm text-n-slate-12 hover:border-teal-500 hover:bg-teal-500/5 transition-all disabled:opacity-50"
        :disabled="savingQuiz"
        @click="advance(opt.dim)"
      >
        {{ opt.text }}
      </button>
    </template>

    <!-- escala 0-10 -->
    <template v-else>
      <h3 class="text-base font-bold text-n-slate-12 mb-1">“{{ currentItem.text }}”</h3>
      <p class="text-[11px] text-n-slate-9 mb-5">0 = nada a ver comigo · 10 = sou eu demais</p>
      <div class="flex items-center gap-3 mb-2">
        <span class="text-xs text-n-slate-9">0</span>
        <input v-model.number="scaleValue" type="range" min="0" max="10" step="1" class="flex-1" style="accent-color: #0F766E" />
        <span class="text-xs text-n-slate-9">10</span>
      </div>
      <p class="text-center text-3xl font-black mb-4" style="color: #0F766E">{{ scaleValue }}</p>
      <button
        class="w-full h-10 rounded-xl text-sm font-bold text-white disabled:opacity-60"
        style="background: linear-gradient(135deg, #0F766E, #2DD4BF)"
        :disabled="savingQuiz"
        @click="advance({ dim: currentItem.dim, value: scaleValue })"
      >
        Confirmar →
      </button>
    </template>
  </div>

  <!-- resultados -->
  <div v-else>
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <!-- radar comparando os testes -->
      <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2">O mapa dos 4 (DISC × Temperamentos)</p>
        <template v-if="radarDatasets.length">
          <RadarChart :axes="axes" :datasets="radarDatasets" />
          <!-- a ORDEM importa -->
          <div v-if="latestDisc" class="flex items-center gap-2 flex-wrap mt-3">
            <span class="text-[10px] text-n-slate-9">DISC:</span>
            <span
              v-for="(dim, di) in rankingOf(latestDisc)"
              :key="dim"
              class="text-[11px] font-black px-2 py-0.5 rounded-full text-white"
              :style="{ background: DISC_PROFILES[dim].grad, opacity: 1 - di * 0.16 }"
            >
              {{ di + 1 }}º {{ DISC_PROFILES[dim].letter }}
            </span>
          </div>
          <div v-if="latestTemp" class="flex items-center gap-2 flex-wrap mt-1.5">
            <span class="text-[10px] text-n-slate-9">Temperamentos:</span>
            <span
              v-for="(dim, di) in rankingOf(latestTemp)"
              :key="dim"
              class="text-[11px] font-bold px-2 py-0.5 rounded-full"
              :style="{ background: `${DISC_PROFILES[dim].color}1c`, color: DISC_PROFILES[dim].color, opacity: 1 - di * 0.12 }"
            >
              {{ di + 1 }}º {{ DISC_PROFILES[dim].temperament }} ({{ pctOf(latestTemp)[dim] }}%)
            </span>
          </div>
          <!-- comparar com arquivado -->
          <div v-if="assessments.length > 1" class="mt-3">
            <select v-model="compareAt" class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1.5 text-[10px] text-n-slate-11" style="width: 14rem">
              <option value="">comparar com um teste arquivado…</option>
              <option v-for="a in [...assessments].reverse()" :key="a.taken_at" :value="a.taken_at">
                {{ a.kind === 'disc' ? 'DISC' : 'Temperamentos' }} · {{ fmtAt(a.taken_at) }} · {{ orderLabel(a) }}
              </option>
            </select>
          </div>
        </template>
        <p v-else class="text-xs text-n-slate-9 py-6 text-center">nenhum teste feito ainda.</p>
      </div>

      <!-- perfil dominante + botões -->
      <div>
        <div v-if="dominantProfile" class="rounded-xl overflow-hidden border border-n-weak mb-3">
          <div class="p-4 text-white" :style="{ background: dominantProfile.grad }">
            <div class="flex items-center gap-2">
              <span :class="dominantProfile.icon" class="text-xl" />
              <div>
                <p class="text-sm font-bold">{{ dominantProfile.letter }} — {{ dominantProfile.name }} · {{ dominantProfile.temperament }}</p>
                <p class="text-[11px] text-white/85">{{ dominantProfile.headline }}</p>
              </div>
            </div>
            <p v-if="duo" class="text-[11px] text-white/90 mt-2 bg-black/15 rounded-lg px-2.5 py-1.5">{{ duo }}</p>
          </div>
          <div class="p-4 bg-n-solid-1 space-y-3">
            <div>
              <p class="text-[10px] font-bold uppercase tracking-wide mb-1" style="color: #047857">Pontos fortes</p>
              <p v-for="s in dominantProfile.strengths" :key="s" class="text-xs text-n-slate-11 leading-relaxed">• {{ s }}</p>
            </div>
            <div>
              <p class="text-[10px] font-bold uppercase tracking-wide mb-1" style="color: #B45309">Pontos de atenção</p>
              <p v-for="s in dominantProfile.watchouts" :key="s" class="text-xs text-n-slate-11 leading-relaxed">• {{ s }}</p>
            </div>
            <div>
              <p class="text-[10px] font-bold uppercase tracking-wide mb-1" style="color: #1D4ED8">Como se comunicar</p>
              <p class="text-xs text-n-slate-11 leading-relaxed">{{ dominantProfile.communication }}</p>
            </div>
          </div>
        </div>

        <div v-if="isMe" class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <button
            class="h-10 rounded-xl text-xs font-bold text-white"
            style="background: linear-gradient(135deg, #0F5FA6, #1E7FBF)"
            @click="startQuiz('disc')"
          >
            {{ latestDisc ? 'Refazer DISC (28 itens)' : 'Fazer o DISC (28 itens)' }}
          </button>
          <button
            class="h-10 rounded-xl text-xs font-bold text-white"
            style="background: linear-gradient(135deg, #9D174D, #DB2777)"
            @click="startQuiz('temperamentos')"
          >
            {{ latestTemp ? 'Refazer 4 Temperamentos' : 'Teste dos 4 Temperamentos' }}
          </button>
        </div>
        <p v-if="isMe" class="text-[10px] text-n-slate-9 mt-1.5">todo teste novo fica ARQUIVADO — dá pra comparar a evolução no radar.</p>

        <!-- arquivo -->
        <div v-if="assessments.length" class="mt-3">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">Testes arquivados</p>
          <div v-for="a in [...assessments].reverse()" :key="a.taken_at" class="flex items-center gap-2 flex-wrap rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5 mb-1 text-[11px]">
            <span class="font-bold text-n-slate-12">{{ a.kind === 'disc' ? 'DISC' : '4 Temperamentos' }}</span>
            <span class="text-n-slate-9">{{ fmtAt(a.taken_at) }}</span>
            <span class="ml-auto font-semibold text-n-slate-11">{{ a.kind === 'disc' ? orderLabel(a) : orderTemperaments(a) }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
