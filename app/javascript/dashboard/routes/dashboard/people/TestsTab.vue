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
  isAdmin: { type: Boolean, default: false },
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

const fmtAt = iso => new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' });

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

// ── item 61: sobrepostos (radar único) OU lado a lado (um gráfico
// completo por teste: radar próprio + barras % em ordem de ranking) ──
const viewMode = ref('overlay'); // 'overlay' | 'side'
const sideCards = computed(() => {
  const cards = [];
  if (latestDisc.value)
    cards.push({ key: 'disc', title: 'DISC (trabalho)', color: '#0F5FA6', entry: latestDisc.value, temperament: false });
  if (latestTemp.value)
    cards.push({ key: 'temp', title: '4 Temperamentos (vida)', color: '#DB2777', entry: latestTemp.value, temperament: true });
  return cards;
});
const barsFor = entry => {
  const pct = pctOf(entry) || {};
  return rankingOf(entry).map(dim => ({ dim, pct: pct[dim] || 0 }));
};

const orderLabel = entry =>
  rankingOf(entry).map(dim => DISC_PROFILES[dim].letter).join(' › ');
const orderTemperaments = entry =>
  rankingOf(entry).map(dim => DISC_PROFILES[dim].temperament).join(' › ');

// ── TRAVA de 90 dias (item 81): refazer 1x por trimestre ──
// (o backend é quem manda; aqui é só o aviso amigável no botão)
const RETAKE_DAYS = 90;
const retakeAt = kind => {
  // p/ o DISC, considera também o legado v1 (auditoria P3 — igual ao backend)
  const latest = kind === 'disc' ? latestDisc.value : latestOf(kind);
  if (!latest?.taken_at) return null;
  const at = new Date(latest.taken_at);
  at.setDate(at.getDate() + RETAKE_DAYS);
  return at > new Date() ? at : null;
};
const retakeLocked = kind => !props.isAdmin && !!retakeAt(kind);
const retakeLabel = kind =>
  retakeAt(kind)?.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' });

// ── VER AS RESPOSTAS (item 81: autoconhecimento) ──
// a própria pessoa (e o admin) revê o que respondeu em cada pergunta
const answersOf = entry => entry?.answers || [];
const viewingAnswers = ref(null); // entry do assessment aberto
const viewingProfile = computed(() => {
  const r = rankingOf(viewingAnswers.value || {});
  return r?.length ? DISC_PROFILES[r[0]] : null;
});

// ── runner dos testes (escolha + escala 0-10) ──
const quizKind = ref(null); // null | 'disc' | 'temperamentos'
const quizItems = ref([]);
const quizStep = ref(0);
const quizAnswers = ref([]);
const quizDetail = ref([]); // pergunta a pergunta, para o autoconhecimento
const scaleValue = ref(5);
const savingQuiz = ref(false);

const startQuiz = kind => {
  if (retakeLocked(kind)) {
    useAlert(`Este teste pode ser refeito 1x a cada 3 meses — libera em ${retakeLabel(kind)}.`);
    return;
  }
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
  quizDetail.value = [];
  scaleValue.value = 5;
};
const currentItem = computed(() => quizItems.value[quizStep.value] || null);
const advance = async (answer, detail) => {
  quizAnswers.value.push(answer);
  if (detail) quizDetail.value.push(detail);
  if (quizStep.value < quizItems.value.length - 1) {
    quizStep.value += 1;
    scaleValue.value = 5;
    return;
  }
  savingQuiz.value = true;
  try {
    const scores = computeDisc(quizAnswers.value);
    const { data } = await CrmAPI.saveAssessment(quizKind.value, scores, quizDetail.value);
    props.person.assessments = data.assessments;
    if (data.disc) props.person.disc = data.disc;
    quizKind.value = null;
    useAlert('Teste concluído e arquivado! Esse é o seu mapa. ✨');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o resultado.');
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
        @click="advance(opt.dim, { q: currentItem.q, a: opt.text, dim: opt.dim })"
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
        @click="advance({ dim: currentItem.dim, value: scaleValue }, { q: currentItem.text, a: `${scaleValue}/10`, dim: currentItem.dim })"
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
        <div class="flex items-center justify-between gap-2 flex-wrap mb-2">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">O mapa dos 4 (DISC × Temperamentos)</p>
          <!-- botões em linha: sobrepostos × lado a lado (item 61) -->
          <div v-if="latestDisc && latestTemp" class="flex items-center gap-1">
            <button
              class="px-2.5 h-6 rounded-full text-[10px] font-bold border transition-colors"
              :class="viewMode === 'overlay' ? 'text-white border-transparent' : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
              :style="viewMode === 'overlay' ? 'background: linear-gradient(135deg, #0F5FA6, #DB2777)' : ''"
              @click="viewMode = 'overlay'"
            >
              Sobrepostos
            </button>
            <button
              class="px-2.5 h-6 rounded-full text-[10px] font-bold border transition-colors"
              :class="viewMode === 'side' ? 'text-white border-transparent' : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
              :style="viewMode === 'side' ? 'background: linear-gradient(135deg, #0F5FA6, #DB2777)' : ''"
              @click="viewMode = 'side'"
            >
              Lado a lado
            </button>
          </div>
        </div>

        <!-- LADO A LADO: um gráfico completo por teste -->
        <template v-if="viewMode === 'side' && sideCards.length">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div
              v-for="card in sideCards"
              :key="card.key"
              class="rounded-lg border border-n-weak bg-n-solid-2 p-3"
            >
              <p class="text-[10px] font-bold text-center mb-1" :style="{ color: card.color }">{{ card.title }}</p>
              <RadarChart
                :axes="axes"
                :datasets="[{ label: card.title, color: card.color, values: pctOf(card.entry) }]"
                :size="200"
              />
              <!-- barras % em ordem de ranking (a ORDEM importa) -->
              <div class="mt-2 space-y-1.5">
                <div v-for="(bar, bi) in barsFor(card.entry)" :key="bar.dim">
                  <div class="flex items-center justify-between">
                    <span class="text-[10px] font-bold" :style="{ color: DISC_PROFILES[bar.dim].color }">
                      {{ bi + 1 }}º {{ card.temperament ? DISC_PROFILES[bar.dim].temperament : `${DISC_PROFILES[bar.dim].letter} — ${DISC_PROFILES[bar.dim].name}` }}
                    </span>
                    <span class="text-[10px] font-black text-n-slate-11">{{ bar.pct }}%</span>
                  </div>
                  <div class="h-1.5 bg-n-alpha-1 rounded-full overflow-hidden">
                    <div
                      class="h-full rounded-full transition-all duration-700"
                      :style="{ width: `${bar.pct}%`, background: DISC_PROFILES[bar.dim].grad }"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </template>

        <!-- SOBREPOSTOS: radar único comparando os testes -->
        <template v-else-if="radarDatasets.length">
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
            <select v-model="compareAt" class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1.5 text-[10px] text-n-slate-11" style="width: 14rem; margin-bottom: 0">
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
            class="h-10 rounded-xl text-xs font-bold text-white disabled:opacity-50"
            style="background: linear-gradient(135deg, #0F5FA6, #1E7FBF)"
            :disabled="retakeLocked('disc')"
            :title="retakeLocked('disc') ? `Refazer libera em ${retakeLabel('disc')}` : ''"
            @click="startQuiz('disc')"
          >
            <template v-if="retakeLocked('disc')">🔒 Refazer libera em {{ retakeLabel('disc') }}</template>
            <template v-else>{{ latestDisc ? 'Refazer DISC (28 itens)' : 'Fazer o DISC (28 itens)' }}</template>
          </button>
          <button
            class="h-10 rounded-xl text-xs font-bold text-white disabled:opacity-50"
            style="background: linear-gradient(135deg, #9D174D, #DB2777)"
            :disabled="retakeLocked('temperamentos')"
            :title="retakeLocked('temperamentos') ? `Refazer libera em ${retakeLabel('temperamentos')}` : ''"
            @click="startQuiz('temperamentos')"
          >
            <template v-if="retakeLocked('temperamentos')">🔒 Refazer libera em {{ retakeLabel('temperamentos') }}</template>
            <template v-else>{{ latestTemp ? 'Refazer 4 Temperamentos (24 itens)' : 'Teste dos 4 Temperamentos (24 itens)' }}</template>
          </button>
        </div>
        <p v-if="isMe" class="text-[10px] text-n-slate-9 mt-1.5">
          todo teste novo fica ARQUIVADO — dá pra comparar a evolução no radar. Cada teste pode ser refeito 1x a cada 3 meses.
        </p>

        <!-- arquivo (item 81: com acesso às respostas) -->
        <div v-if="assessments.length" class="mt-3">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">Testes arquivados</p>
          <div v-for="a in [...assessments].reverse()" :key="a.taken_at" class="flex items-center gap-2 flex-wrap rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5 mb-1 text-[11px]">
            <span class="font-bold text-n-slate-12">{{ a.kind === 'disc' ? 'DISC' : '4 Temperamentos' }}</span>
            <span class="text-n-slate-9">{{ fmtAt(a.taken_at) }}</span>
            <span class="ml-auto font-semibold text-n-slate-11">{{ a.kind === 'disc' ? orderLabel(a) : orderTemperaments(a) }}</span>
            <button
              v-if="(isMe || isAdmin) && answersOf(a).length"
              class="text-[10px] font-bold px-2 py-0.5 rounded-full border border-n-weak text-n-slate-11 hover:border-teal-500 hover:text-teal-600 transition-colors"
              @click="viewingAnswers = a"
            >
              ver respostas
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- ══ MODAL: minhas respostas (autoconhecimento, item 81) ══ -->
    <div
      v-if="viewingAnswers"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="viewingAnswers = null"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-xl max-h-[85vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" :style="{ background: viewingProfile?.grad || 'linear-gradient(135deg, #0F766E, #2DD4BF)' }" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
          <div>
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ viewingAnswers.kind === 'disc' ? 'DISC' : '4 Temperamentos' }} — respostas
            </h2>
            <p class="text-[11px] text-n-slate-9">
              feito em {{ fmtAt(viewingAnswers.taken_at) }} · {{ answersOf(viewingAnswers).length }} pergunta(s) ·
              conhecer as próprias escolhas é o primeiro passo do desenvolvimento
            </p>
          </div>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="viewingAnswers = null" />
        </div>

        <!-- análise do perfil daquele teste -->
        <div v-if="viewingProfile" class="px-5 py-3 border-b border-n-weak flex-shrink-0" :style="{ background: `${viewingProfile.color}0d` }">
          <p class="text-xs font-bold" :style="{ color: viewingProfile.color }">
            <span :class="viewingProfile.icon" class="text-sm align-middle" />
            Resultado: {{ viewingAnswers.kind === 'disc' ? `${viewingProfile.letter} — ${viewingProfile.name}` : viewingProfile.temperament }}
            <span class="font-normal text-n-slate-10">· {{ viewingProfile.headline }}</span>
          </p>
          <div class="flex items-center gap-1.5 mt-1.5 flex-wrap">
            <span
              v-for="(dim, di) in rankingOf(viewingAnswers)"
              :key="dim"
              class="text-[10px] font-black px-1.5 py-0.5 rounded-full text-white"
              :style="{ background: DISC_PROFILES[dim].grad, opacity: 1 - di * 0.16 }"
            >
              {{ di + 1 }}º {{ viewingAnswers.kind === 'disc' ? DISC_PROFILES[dim].letter : DISC_PROFILES[dim].temperament }} · {{ (pctOf(viewingAnswers) || {})[dim] }}%
            </span>
          </div>
        </div>

        <div class="px-5 py-4 overflow-y-auto space-y-2.5">
          <div v-for="(ans, ai) in answersOf(viewingAnswers)" :key="ai" class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2">
            <p class="text-[11px] text-n-slate-10 mb-1">{{ ai + 1 }}. {{ ans.q }}</p>
            <p class="text-xs font-semibold text-n-slate-12 flex items-start gap-1.5">
              <span
                v-if="DISC_PROFILES[ans.dim]"
                class="flex-shrink-0 text-[9px] font-black px-1.5 py-0.5 rounded-full text-white mt-px"
                :style="{ background: DISC_PROFILES[ans.dim].grad }"
                :title="DISC_PROFILES[ans.dim].name"
              >{{ DISC_PROFILES[ans.dim].letter }}</span>
              <span>{{ ans.a }}</span>
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
