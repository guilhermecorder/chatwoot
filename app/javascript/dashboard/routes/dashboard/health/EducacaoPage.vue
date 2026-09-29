<script setup>
// EDUCAÇÃO (rodadas 36–37) — pedido dele 28/09: "ambiente de educação com
// as principais informações e dúvidas sobre todos os pilares"; 29/09:
// "liberar os outros treinos das outras semanas, o objetivo e intenção de
// cada exercício, o que acontece nas séries de força, como funciona a
// construção muscular e o emagrecimento, e um ambiente com a filosofia".
// 4 ÁREAS: Pilares (7 pilares + glossário) · Treinos (3 ciclos + Bônus
// lidos da prescrição real do config, com a intenção de cada exercício)
// · Ciência (5 temas) · Filosofia. Conteúdo em educacao.js.
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  PILLARS, pillarOf, GLOSSARY,
  CYCLE_INTENTS, SESSION_INTENTS, exerciseIntent,
  SCIENCE, PHILOSOPHY,
} from './educacao';
import { mainProgramOf, weekOf, METHOD_LABELS } from './warrior';
import { LARANJA, GRAD_NOITE, GRAD_LARANJA, GRAD_ROYAL } from './palette';

const route = useRoute();
const router = useRouter();
const accountScopedRoute = name => ({ name, params: { accountId: route.params.accountId } });
const go = name => router.push(accountScopedRoute(name));
const scrollTop = () => document.querySelector('.hub-page')?.scrollTo?.({ top: 0, behavior: 'smooth' });

// ── 4 áreas (URL guarda ?v=) ───────────────────────────────────────
const VIEWS = [
  { key: 'pilares', ico: 'i-lucide-layout-grid', label: 'Pilares' },
  { key: 'treinos', ico: 'i-lucide-dumbbell', label: 'Treinos' },
  { key: 'ciencia', ico: 'i-lucide-atom', label: 'Ciência' },
  { key: 'filosofia', ico: 'i-lucide-feather', label: 'Filosofia' },
];
const view = ref(VIEWS.some(v => v.key === route.query.v) ? route.query.v : 'pilares');

// ── pilares (URL guarda ?p=) ───────────────────────────────────────
const TABS = [...PILLARS.map(p => ({ key: p.key, ico: p.ico, label: p.label })), { key: 'glossario', ico: 'i-lucide-book-a', label: 'Glossário' }];
const current = ref(TABS.some(t => t.key === route.query.p) ? route.query.p : 'programa');
const pillar = computed(() => pillarOf(current.value));
const openFaq = ref(-1);
const nextTab = computed(() => TABS[TABS.findIndex(t => t.key === current.value) + 1] || null);

// ── ciência (URL guarda ?t=) ───────────────────────────────────────
const topicKey = ref(SCIENCE.some(s => s.key === route.query.t) ? route.query.t : SCIENCE[0].key);
const topic = computed(() => SCIENCE.find(s => s.key === topicKey.value) || SCIENCE[0]);
const nextTopic = computed(() => SCIENCE[SCIENCE.findIndex(s => s.key === topicKey.value) + 1] || null);

watch([view, current, topicKey], ([v, p, t]) => {
  openFaq.value = -1;
  router.replace({ query: { ...route.query, v, p, t } });
  scrollTop();
});

// ── busca (pilares + glossário + ciência + filosofia + exercícios) ──
const q = ref('');
const norm = s => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const hits = computed(() => {
  const t = norm(q.value.trim());
  if (t.length < 2) return [];
  const out = [];
  PILLARS.forEach(p => {
    p.principios.forEach(x => {
      if (norm(`${x.t} ${x.d}`).includes(t)) out.push({ kind: 'Princípio', where: p.label, t: x.t, d: x.d, go: { v: 'pilares', p: p.key } });
    });
    p.faq.forEach((x, i) => {
      if (norm(`${x.q} ${x.a}`).includes(t)) out.push({ kind: 'Dúvida', where: p.label, t: x.q, d: x.a, go: { v: 'pilares', p: p.key, faq: i } });
    });
  });
  GLOSSARY.forEach(g => {
    if (norm(`${g.t} ${g.d}`).includes(t)) out.push({ kind: 'Termo', where: 'Glossário', t: g.t, d: g.d, go: { v: 'pilares', p: 'glossario' } });
  });
  SCIENCE.forEach(s => {
    [...s.steps, ...s.practice.map(x => ({ t: s.title, d: x }))].forEach(x => {
      if (norm(`${x.t} ${x.d}`).includes(t)) out.push({ kind: 'Ciência', where: s.title, t: x.t, d: x.d, go: { v: 'ciencia', t: s.key } });
    });
  });
  PHILOSOPHY.ideas.forEach(x => {
    if (norm(`${x.t} ${x.d}`).includes(t)) out.push({ kind: 'Filosofia', where: 'Filosofia', t: x.t, d: x.d, go: { v: 'filosofia' } });
  });
  allExercises.value.forEach(x => {
    if (norm(`${x.name} ${x.intent?.musc} ${x.intent?.why}`).includes(t)) out.push({ kind: 'Exercício', where: x.cycleName, t: x.name, d: x.intent?.musc || x.scheme, go: { v: 'treinos', c: x.cycleId } });
  });
  return out.slice(0, 40);
});
const openHit = h => {
  q.value = '';
  view.value = h.go.v;
  if (h.go.p) current.value = h.go.p;
  if (h.go.t) topicKey.value = h.go.t;
  if (h.go.c) selCycle.value = h.go.c;
  if (h.go.faq != null) openFaq.value = h.go.faq;
};

// ── programas do config: Warrior 24 (principal) + Rotina Bônus ─────
const programs = ref([]);
const programsLoaded = ref(false);
const todayISO = new Date().toISOString().slice(0, 10);
onMounted(async () => {
  try {
    const { data } = await CrmAPI.getHealth();
    programs.value = data?.config?.programs || [];
  } catch {
    programs.value = [];
  } finally {
    programsLoaded.value = true;
  }
});
const program = computed(() => mainProgramOf(programs.value));
const rawWeek = computed(() => (program.value ? weekOf(program.value, todayISO) : null));
const finished = computed(() => !!rawWeek.value && rawWeek.value > 24);
const week = computed(() => (rawWeek.value ? Math.min(rawWeek.value, 24) : null));

// ciclos navegáveis: os do principal + os da Bônus (etiquetados)
const cycles = computed(() => {
  const main = (program.value?.cycles || []).map(c => ({ ...c, bonus: false, programName: program.value?.name }));
  const bonusProg = programs.value.find(p => p.id === 'warrior_bonus');
  const bonus = (bonusProg?.cycles || []).map(c => ({ ...c, id: c.id || 'bonus', bonus: true, programName: bonusProg.name, note: bonusProg.note }));
  return [...main, ...bonus];
});
const selCycle = ref(route.query.c || null);
const cycle = computed(() => cycles.value.find(c => c.id === selCycle.value) || cycles.value[0] || null);
const cycleTab = c => (c.bonus ? 'Bônus' : `${c.name.replace('Treino ', 'Ciclo ')} · ${String(c.focus || '').replace(/^Fase \d — /, '')}`);
const cycleIntent = c => CYCLE_INTENTS[c?.bonus ? 'bonus' : c?.id] || null;
const sessionIntent = key => SESSION_INTENTS[key] || null;
const methodLabel = m => METHOD_LABELS[m] || m || 'Séries';
const allExercises = computed(() =>
  cycles.value.flatMap(c =>
    (c.sessions || []).flatMap(s =>
      (s.exercises || []).map(e => ({ ...e, cycleId: c.id, cycleName: c.bonus ? 'Rotina Bônus' : c.name, intent: exerciseIntent(e.name) }))
    )
  )
);
const cycleWeeksLabel = c => (c.bonus ? '8 semanas · bloco alternativo' : `semanas ${c.week_start}–${c.week_end}`);
const cycleStateOf = c => {
  if (c.bonus || !week.value) return 'idle';
  if (finished.value || week.value > c.week_end) return 'done';
  if (week.value >= c.week_start) return 'now';
  return 'next';
};

// mapa das 24 semanas (pilar do método)
const CYCLES_MAP = [
  { n: 1, name: 'Ciclo 1', focus: 'Base', from: 1, to: 8, d: 'Aprender os movimentos, achar as cargas e construir força nos compostos.' },
  { n: 2, name: 'Ciclo 2', focus: 'Peitoral', from: 9, to: 16, d: 'Troca de alguns exercícios pra dar mais trabalho ao peitoral; hip thrust nas pernas.' },
  { n: 3, name: 'Ciclo 3', focus: 'Ombros', from: 17, to: 24, d: 'Ombros em foco: desenvolvimento sentado, agachamento frontal e barra pronada.' },
];
const cycleState = c => {
  if (!week.value) return 'idle';
  if (finished.value || week.value > c.to) return 'done';
  if (week.value >= c.from) return 'now';
  return 'next';
};
</script>

<template>
  <div class="hub-page hub-edu flex-1 overflow-auto p-4 pb-20 sm:p-6 md:pb-6">
    <div class="max-w-5xl mx-auto">
      <!-- cabeçalho -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" :style="{ background: GRAD_NOITE }">
          <span class="i-lucide-graduation-cap text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="hub-h1">Educação</h1>
          <p class="text-[11px] text-n-slate-10">princípios, treinos, ciência e filosofia do programa — em linguagem simples</p>
        </div>
      </div>

      <!-- busca -->
      <div class="hub-edu-search mb-4">
        <span class="i-lucide-search hub-ico" />
        <input v-model="q" type="search" placeholder="Buscar: jejum, refeed, RPT, platô, búlgaro, cortisol…" class="hub-edu-search-in" />
        <button v-if="q" class="hub-edu-search-x" title="Limpar" @click="q = ''"><span class="i-lucide-x" /></button>
      </div>
      <div v-if="q.trim().length >= 2" class="hub-block p-5 mb-8">
        <p class="hub-label"><span class="i-lucide-search hub-ico" />{{ hits.length ? `${hits.length} resultado${hits.length > 1 ? 's' : ''}` : 'nada encontrado' }}</p>
        <div v-if="hits.length" class="hub-list">
          <button v-for="(h, i) in hits" :key="i" class="hub-row w-full text-left hover:bg-n-alpha-1" @click="openHit(h)">
            <span class="hub-tag is-soft flex-shrink-0">{{ h.kind }}</span>
            <span class="min-w-0 flex-1">
              <span class="block text-[13px] font-bold text-n-slate-12 truncate">{{ h.t }}</span>
              <span class="block text-[11px] text-n-slate-10 truncate">{{ h.where }} · {{ h.d }}</span>
            </span>
            <span class="i-lucide-chevron-right hub-ico flex-shrink-0" :style="{ color: LARANJA }" />
          </button>
        </div>
        <p v-else class="text-xs text-n-slate-10">Tente outra palavra — ou navegue pelas áreas abaixo.</p>
      </div>

      <!-- 4 áreas -->
      <div class="hub-seg hub-seg-full mb-6">
        <button v-for="v in VIEWS" :key="v.key" :class="{ 'is-on': view === v.key }" @click="view = v.key">
          <span :class="v.ico" />{{ v.label }}
        </button>
      </div>

      <!-- ═══════════════ PILARES ═══════════════ -->
      <template v-if="view === 'pilares'">
        <div class="hub-seg hub-seg-wrap mb-6">
          <button v-for="t in TABS" :key="t.key" :class="{ 'is-on': current === t.key }" @click="current = t.key">
            <span :class="t.ico" />{{ t.label }}
          </button>
        </div>

        <template v-if="current === 'glossario'">
          <div class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-book-a" /></span>
              <div class="hub-sec-text">
                <p class="hub-sec-title">Glossário</p>
                <p class="hub-sec-sub">os termos que aparecem nas telas do HUB, em uma frase</p>
              </div>
            </div>
            <div class="hub-list">
              <div v-for="g in GLOSSARY" :key="g.t" class="hub-row">
                <span class="hub-edu-term">{{ g.t }}</span>
                <span class="text-[12.5px] leading-snug text-n-slate-11 min-w-0 flex-1">{{ g.d }}</span>
              </div>
            </div>
          </div>
        </template>

        <template v-else>
          <div class="hub-sec mb-5">
            <span class="hub-sec-ico"><span :class="pillar.ico" /></span>
            <div class="hub-sec-text">
              <p class="hub-h" style="margin: 0">{{ pillar.label }}</p>
              <p class="hub-sec-sub">{{ pillar.sub }}</p>
            </div>
          </div>

          <div v-if="current === 'metodo'" class="hub-block p-5 mb-8">
            <p class="hub-label"><span class="i-lucide-map hub-ico" />Mapa das 24 semanas<template v-if="finished"> · programa principal concluído (semana {{ rawWeek }} desde o início)</template><template v-else-if="week"> · você está na semana {{ week }}</template></p>
            <div class="hub-grid-3">
              <div v-for="c in CYCLES_MAP" :key="c.n" class="hub-crystal hub-edu-cycle" :class="[`is-${cycleState(c)}`, cycleState(c) === 'now' ? 't-orange' : 't-royal']">
                <div class="flex items-center gap-2 mb-2">
                  <span class="hub-acc-n" :style="cycleState(c) === 'now' ? { background: GRAD_LARANJA } : cycleState(c) === 'done' ? { background: GRAD_ROYAL } : { background: 'rgba(148,163,184,0.35)' }">{{ c.n }}</span>
                  <div class="min-w-0">
                    <p class="text-[13.5px] font-extrabold leading-tight text-n-slate-12">{{ c.name }} · {{ c.focus }}</p>
                    <p class="text-[11px] text-n-slate-10">semanas {{ c.from }}–{{ c.to }}<template v-if="cycleState(c) === 'now'"> · <b :style="{ color: LARANJA }">agora</b></template><template v-else-if="cycleState(c) === 'done'"> · concluído</template></p>
                  </div>
                </div>
                <div class="hub-edu-weeks">
                  <i v-for="w in 8" :key="w" :class="{ 'is-done': week && (finished || c.from + w - 1 < week), 'is-now': week && !finished && c.from + w - 1 === week }" />
                </div>
                <p class="text-[12px] leading-snug text-n-slate-11 mt-2">{{ c.d }}</p>
                <button class="hub-tag mt-3" @click="selCycle = `c${c.n}`; view = 'treinos'"><span class="i-lucide-dumbbell hub-ico" style="width: 13px; height: 13px" />ver os treinos</button>
              </div>
            </div>
            <p v-if="!program" class="text-[11px] text-n-slate-10 mt-3">Sem programa configurado: o mapa fica sem a marca da semana atual.</p>
            <p v-else-if="finished" class="text-[11px] text-n-slate-10 mt-3">As 24 semanas do programa principal já passaram. Pra recomeçar, ajuste a data de início na aba Treino; enquanto isso vale a Rotina Bônus ou uma Growth Phase.</p>
          </div>

          <div class="hub-block p-5 mb-8">
            <p class="hub-label"><span class="i-lucide-clock-3 hub-ico" />Em 1 minuto</p>
            <div class="hub-grid-3 mb-5" :class="{ 'hub-grid-4': pillar.numeros.length === 4 }">
              <div v-for="n in pillar.numeros" :key="n.l" class="hub-kpi hub-crystal t-royal">
                <span class="hub-kpi-l"><span :class="n.ico" />{{ n.l }}</span>
                <p class="hub-kpi-v is-royal">{{ n.v }}</p>
                <p class="hub-kpi-s">{{ n.s }}</p>
              </div>
            </div>
            <div class="hub-edu-lead">
              <p v-for="(t, i) in pillar.resumo" :key="i">{{ t }}</p>
            </div>
          </div>

          <div class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-lightbulb" /></span>
              <div class="hub-sec-text">
                <p class="hub-sec-title">Princípios</p>
                <p class="hub-sec-sub">o que sustenta este pilar — {{ pillar.principios.length }} fundamentos</p>
              </div>
            </div>
            <div class="hub-grid-2">
              <div v-for="(p, i) in pillar.principios" :key="i" class="hub-crystal hub-edu-card t-royal">
                <span class="hub-edu-card-ico"><span :class="p.ico" /></span>
                <p class="hub-edu-card-t">{{ p.t }}</p>
                <p class="hub-edu-card-d">{{ p.d }}</p>
              </div>
            </div>
          </div>

          <div class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-message-circle-question" /></span>
              <div class="hub-sec-text">
                <p class="hub-sec-title">Dúvidas frequentes</p>
                <p class="hub-sec-sub">toque numa pergunta pra abrir a resposta</p>
              </div>
            </div>
            <div class="flex flex-col gap-2.5">
              <div v-for="(f, i) in pillar.faq" :key="i" class="hub-acc" :class="{ 'is-open': openFaq === i }">
                <button class="hub-acc-head" @click="openFaq = openFaq === i ? -1 : i">
                  <span class="hub-acc-n" :style="openFaq === i ? { background: GRAD_LARANJA } : {}">{{ i + 1 }}</span>
                  <span class="text-[13.5px] font-bold text-n-slate-12 flex-1 leading-snug">{{ f.q }}</span>
                  <span class="i-lucide-chevron-down hub-ico flex-shrink-0 transition-transform" :class="{ 'rotate-180': openFaq === i }" :style="{ color: LARANJA }" />
                </button>
                <div v-if="openFaq === i" class="hub-acc-body pt-3">
                  <p class="text-[13px] leading-relaxed text-n-slate-11">{{ f.a }}</p>
                </div>
              </div>
            </div>
          </div>

          <div class="hub-block p-5 mb-8">
            <p class="hub-label"><span class="i-lucide-app-window hub-ico" />Onde isso vive no HUB</p>
            <div class="flex gap-2 flex-wrap">
              <button v-for="h in pillar.hub" :key="h.route" class="hub-tag" style="height: 36px; padding: 0 14px; font-size: 12px" @click="go(h.route)">
                <span :class="h.ico" class="hub-ico" style="width: 14px; height: 14px" />{{ h.label }}
                <span class="i-lucide-arrow-up-right hub-ico" style="width: 12px; height: 12px; opacity: 0.6" />
              </button>
            </div>
            <div class="flex items-center gap-2 flex-wrap mt-5 pt-4" style="border-top: 1px solid rgba(65, 105, 225, 0.16)">
              <span class="text-[11px] text-n-slate-10">Conteúdo montado a partir da planilha do programa e da configuração do HUB, em palavras próprias. Não substitui orientação médica.</span>
              <div class="flex-1" />
              <button v-if="nextTab" class="h-9 px-4 rounded-xl text-xs font-bold text-white inline-flex items-center gap-1.5" :style="{ background: GRAD_ROYAL }" @click="current = nextTab.key">
                Próximo: {{ nextTab.label }}
                <span class="i-lucide-arrow-right hub-ico" style="width: 14px; height: 14px" />
              </button>
            </div>
          </div>
        </template>
      </template>

      <!-- ═══════════════ TREINOS ═══════════════ -->
      <template v-else-if="view === 'treinos'">
        <div v-if="!programsLoaded" class="flex justify-center py-16"><Spinner /></div>
        <div v-else-if="!cycles.length" class="hub-block p-5 mb-8">
          <p class="text-sm text-n-slate-11">Nenhum programa configurado ainda. Os treinos aparecem aqui assim que o Warrior estiver no sistema.</p>
        </div>
        <template v-else>
          <div class="hub-seg hub-seg-wrap mb-6">
            <button v-for="c in cycles" :key="c.id" :class="{ 'is-on': cycle && cycle.id === c.id }" @click="selCycle = c.id">
              <span :class="c.bonus ? 'i-lucide-sparkles' : 'i-lucide-flag'" />{{ cycleTab(c) }}
            </button>
          </div>

          <!-- intenção do ciclo -->
          <div class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span :class="cycle.bonus ? 'i-lucide-sparkles' : 'i-lucide-flag'" /></span>
              <div class="hub-sec-text">
                <p class="hub-h" style="margin: 0">{{ cycle.bonus ? 'Rotina Bônus' : cycle.name.replace('Treino ', 'Ciclo ') }}<span class="hub-h-sub">{{ cycle.focus }}</span></p>
                <p class="hub-sec-sub">{{ cycleWeeksLabel(cycle) }} · treinos {{ (cycle.sessions || []).map(s => s.key).join(', ') }} · {{ (cycle.sessions || []).reduce((n, s) => n + (s.exercises || []).length, 0) }} exercícios<template v-if="cycleStateOf(cycle) === 'now'"> · <b :style="{ color: LARANJA }">é o ciclo atual</b></template></p>
              </div>
            </div>
            <div v-if="cycleIntent(cycle)" class="hub-edu-lead">
              <p><b>{{ cycleIntent(cycle).title }}.</b> {{ cycleIntent(cycle).text }}</p>
            </div>
            <p v-if="cycle.note" class="text-[12px] text-n-slate-10 mt-3"><span class="i-lucide-info hub-ico-inline" /> {{ cycle.note }}</p>
          </div>

          <!-- sessões -->
          <div v-for="s in cycle.sessions" :key="s.key" class="hub-block p-5 mb-8">
            <div class="hub-sec">
              <span class="hub-acc-n" style="width: 34px; height: 34px; border-radius: 11px; font-size: 15px" :style="{ background: GRAD_ROYAL }">{{ s.key }}</span>
              <div class="hub-sec-text">
                <p class="hub-sec-title">Treino {{ s.key }}<template v-if="s.weekday"> · {{ s.weekday }}</template><span v-if="sessionIntent(s.key)" class="hub-h-sub">{{ sessionIntent(s.key).title }}</span></p>
                <p class="hub-sec-sub">{{ sessionIntent(s.key)?.text || `${(s.exercises || []).length} exercícios` }}</p>
              </div>
            </div>

            <div class="flex flex-col gap-3">
              <div v-for="(e, i) in s.exercises" :key="i" class="hub-crystal hub-edu-ex t-royal">
                <div class="flex items-start gap-3">
                  <span class="hub-edu-ex-n">{{ i + 1 }}</span>
                  <div class="min-w-0 flex-1">
                    <p class="hub-edu-ex-t">{{ e.name }}</p>
                    <p v-if="exerciseIntent(e.name)" class="hub-edu-ex-m">{{ exerciseIntent(e.name).musc }}</p>
                    <div class="flex gap-1.5 flex-wrap mt-2">
                      <span class="hub-tag is-on"><span class="i-lucide-triangle hub-ico" style="width: 12px; height: 12px" />{{ methodLabel(e.method) }}</span>
                      <span class="hub-tag"><span class="i-lucide-repeat hub-ico" style="width: 12px; height: 12px" />{{ e.scheme }}</span>
                      <span v-if="e.rest" class="hub-tag"><span class="i-lucide-timer hub-ico" style="width: 12px; height: 12px" />descanso {{ e.rest }}</span>
                      <span v-if="e.warmup" class="hub-tag"><span class="i-lucide-flame hub-ico" style="width: 12px; height: 12px" />aquece: {{ e.warmup }}</span>
                    </div>
                  </div>
                </div>
                <div class="hub-edu-ex-body">
                  <div v-if="e.progression" class="hub-edu-ex-row">
                    <span class="hub-edu-ex-l"><span class="i-lucide-trending-up" />Progressão</span>
                    <span class="hub-edu-ex-v">{{ e.progression }}<template v-if="e.note"> · {{ e.note }}</template></span>
                  </div>
                  <template v-if="exerciseIntent(e.name)">
                    <div class="hub-edu-ex-row">
                      <span class="hub-edu-ex-l"><span class="i-lucide-target" />Objetivo e intenção</span>
                      <span class="hub-edu-ex-v">{{ exerciseIntent(e.name).why }}</span>
                    </div>
                    <div class="hub-edu-ex-row">
                      <span class="hub-edu-ex-l is-orange"><span class="i-lucide-hand" />Execução</span>
                      <span class="hub-edu-ex-v">{{ exerciseIntent(e.name).cue }}</span>
                    </div>
                  </template>
                  <div v-else class="hub-edu-ex-row">
                    <span class="hub-edu-ex-l"><span class="i-lucide-target" />Objetivo e intenção</span>
                    <span class="hub-edu-ex-v">Exercício adicionado à ficha; intenção ainda não descrita.</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="hub-block p-5 mb-8">
            <p class="hub-label"><span class="i-lucide-app-window hub-ico" />Onde isso vive no HUB</p>
            <div class="flex gap-2 flex-wrap">
              <button class="hub-tag" style="height: 36px; padding: 0 14px; font-size: 12px" @click="go('hub_health')"><span class="i-lucide-dumbbell hub-ico" style="width: 14px; height: 14px" />Treino de hoje<span class="i-lucide-arrow-up-right hub-ico" style="width: 12px; height: 12px; opacity: 0.6" /></button>
              <button class="hub-tag" style="height: 36px; padding: 0 14px; font-size: 12px" @click="view = 'pilares'; current = 'treino'"><span class="i-lucide-lightbulb hub-ico" style="width: 14px; height: 14px" />Pilar Treino (métodos)</button>
              <button class="hub-tag" style="height: 36px; padding: 0 14px; font-size: 12px" @click="view = 'ciencia'; topicKey = 'serie'"><span class="i-lucide-atom hub-ico" style="width: 14px; height: 14px" />O que acontece na série</button>
            </div>
          </div>
        </template>
      </template>

      <!-- ═══════════════ CIÊNCIA ═══════════════ -->
      <template v-else-if="view === 'ciencia'">
        <div class="hub-seg hub-seg-wrap mb-6">
          <button v-for="s in SCIENCE" :key="s.key" :class="{ 'is-on': topicKey === s.key }" @click="topicKey = s.key">
            <span :class="s.ico" />{{ s.short }}
          </button>
        </div>

        <div class="hub-sec mb-5">
          <span class="hub-sec-ico"><span :class="topic.ico" /></span>
          <div class="hub-sec-text">
            <p class="hub-h" style="margin: 0">{{ topic.title }}</p>
          </div>
        </div>

        <div class="hub-block p-5 mb-8">
          <p class="hub-label"><span class="i-lucide-clock-3 hub-ico" />Em uma frase</p>
          <div class="hub-edu-lead"><p>{{ topic.lead }}</p></div>
        </div>

        <div class="hub-block p-5 mb-8">
          <div class="hub-sec">
            <span class="hub-sec-ico"><span class="i-lucide-list-ordered" /></span>
            <div class="hub-sec-text">
              <p class="hub-sec-title">Passo a passo</p>
              <p class="hub-sec-sub">o que acontece no corpo, em ordem</p>
            </div>
          </div>
          <div class="hub-edu-steps">
            <div v-for="(st, i) in topic.steps" :key="i" class="hub-edu-step">
              <span class="hub-acc-n" :style="{ background: GRAD_ROYAL }">{{ i + 1 }}</span>
              <div class="min-w-0 flex-1">
                <p class="hub-edu-card-t" style="font-size: 14.5px">{{ st.t }}</p>
                <p class="hub-edu-card-d">{{ st.d }}</p>
              </div>
            </div>
          </div>
        </div>

        <div class="hub-block p-5 mb-8">
          <div class="hub-sec">
            <span class="hub-sec-ico"><span class="i-lucide-check-check" /></span>
            <div class="hub-sec-text">
              <p class="hub-sec-title">Na prática</p>
              <p class="hub-sec-sub">o que isso muda no seu treino e na sua comida</p>
            </div>
          </div>
          <div class="hub-grid-2">
            <div v-for="(p, i) in topic.practice" :key="i" class="hub-crystal t-orange hub-edu-practice">
              <span class="i-lucide-check hub-ico" :style="{ color: LARANJA }" />
              <p>{{ p }}</p>
            </div>
          </div>
          <div class="flex items-center gap-2 flex-wrap mt-5 pt-4" style="border-top: 1px solid rgba(65, 105, 225, 0.16)">
            <span class="text-[11px] text-n-slate-10">Explicação simplificada da fisiologia, em palavras próprias. Não substitui orientação médica.</span>
            <div class="flex-1" />
            <button v-if="nextTopic" class="h-9 px-4 rounded-xl text-xs font-bold text-white inline-flex items-center gap-1.5" :style="{ background: GRAD_ROYAL }" @click="topicKey = nextTopic.key">
              Próximo: {{ nextTopic.short }}
              <span class="i-lucide-arrow-right hub-ico" style="width: 14px; height: 14px" />
            </button>
          </div>
        </div>
      </template>

      <!-- ═══════════════ FILOSOFIA ═══════════════ -->
      <template v-else-if="view === 'filosofia'">
        <div class="hub-block hub-block-solid p-5 mb-8 text-white hub-edu-manifesto">
          <p class="hub-label" style="color: rgba(255,255,255,0.7)"><span class="i-lucide-feather hub-ico" style="color: #ffb25e" />Manifesto</p>
          <p class="hub-edu-manifesto-t">O corpo que buscamos é consequência de um jeito de viver.</p>
          <div class="hub-edu-manifesto-list">
            <div v-for="(m, i) in PHILOSOPHY.manifesto" :key="i" class="hub-edu-manifesto-item">
              <span class="hub-edu-manifesto-n">{{ String(i + 1).padStart(2, '0') }}</span>
              <p>{{ m }}</p>
            </div>
          </div>
        </div>

        <div class="hub-block p-5 mb-8">
          <div class="hub-sec">
            <span class="hub-sec-ico"><span class="i-lucide-sparkles" /></span>
            <div class="hub-sec-text">
              <p class="hub-sec-title">As ideias por trás</p>
              <p class="hub-sec-sub">seis convicções que explicam cada escolha do programa</p>
            </div>
          </div>
          <div class="hub-grid-2">
            <div v-for="(p, i) in PHILOSOPHY.ideas" :key="i" class="hub-crystal hub-edu-card t-royal">
              <span class="hub-edu-card-ico"><span :class="p.ico" /></span>
              <p class="hub-edu-card-t">{{ p.t }}</p>
              <p class="hub-edu-card-d">{{ p.d }}</p>
            </div>
          </div>
        </div>

        <div class="hub-grid-2 mb-8" style="gap: 32px">
          <div class="hub-block p-5" style="margin: 0">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-ban" /></span>
              <div class="hub-sec-text">
                <p class="hub-sec-title">O que o programa não é</p>
                <p class="hub-sec-sub">pra não confundir com o que a academia costuma vender</p>
              </div>
            </div>
            <div class="hub-list">
              <div v-for="(n, i) in PHILOSOPHY.not" :key="i" class="hub-row" style="align-items: flex-start">
                <span class="i-lucide-x hub-ico flex-shrink-0 mt-0.5" style="color: #e5484d; width: 16px; height: 16px" />
                <span class="min-w-0 flex-1">
                  <span class="block text-[13px] font-bold text-n-slate-12">{{ n.t }}</span>
                  <span class="block text-[12px] text-n-slate-10 leading-snug">{{ n.d }}</span>
                </span>
              </div>
            </div>
          </div>
          <div class="hub-block p-5" style="margin: 0">
            <div class="hub-sec">
              <span class="hub-sec-ico"><span class="i-lucide-list-checks" /></span>
              <div class="hub-sec-text">
                <p class="hub-sec-title">Regras de vida</p>
                <p class="hub-sec-sub">o programa inteiro em seis linhas</p>
              </div>
            </div>
            <div class="hub-list">
              <div v-for="(r, i) in PHILOSOPHY.rules" :key="i" class="hub-row">
                <span class="hub-acc-n flex-shrink-0" style="width: 26px; height: 26px; font-size: 11px" :style="{ background: GRAD_LARANJA }">{{ i + 1 }}</span>
                <span class="text-[13px] font-semibold text-n-slate-12 leading-snug min-w-0 flex-1">{{ r }}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="hub-block p-5 mb-8">
          <p class="hub-label"><span class="i-lucide-app-window hub-ico" />Continuar</p>
          <div class="flex gap-2 flex-wrap">
            <button class="hub-tag" style="height: 36px; padding: 0 14px; font-size: 12px" @click="view = 'pilares'; current = 'estilo'"><span class="i-lucide-sunrise hub-ico" style="width: 14px; height: 14px" />Pilar Rotina e mente</button>
            <button class="hub-tag" style="height: 36px; padding: 0 14px; font-size: 12px" @click="view = 'ciencia'; topicKey = 'recomp'"><span class="i-lucide-atom hub-ico" style="width: 14px; height: 14px" />Por que dá pra ficar forte enquanto seca</button>
            <button class="hub-tag" style="height: 36px; padding: 0 14px; font-size: 12px" @click="go('hub_health_rotina')"><span class="i-lucide-calendar-range hub-ico" style="width: 14px; height: 14px" />Minha rotina<span class="i-lucide-arrow-up-right hub-ico" style="width: 12px; height: 12px; opacity: 0.6" /></button>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* busca em pílula de vidro (mesma linguagem da sidebar) */
.hub-edu-search {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 44px;
  padding: 0 14px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.82);
  border: 1px solid rgba(65, 105, 225, 0.28);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.95);
}
.dark .hub-edu-search { background: rgba(255, 255, 255, 0.05); border-color: rgba(143, 169, 245, 0.35); }
.hub-edu-search > .hub-ico { width: 17px; height: 17px; color: #4169e1; flex-shrink: 0; }
.dark .hub-edu-search > .hub-ico { color: #8fa9f5; }
.hub-edu-search-in {
  flex: 1;
  min-width: 0;
  height: 100%;
  background: transparent !important;
  border: 0 !important;
  box-shadow: none !important;
  outline: none !important;
  font-size: 13.5px;
  margin: 0 !important;
  padding: 0 !important;
  color: inherit;
}
.hub-edu-search-in::-webkit-search-cancel-button { display: none; }
.hub-edu-search-x { width: 26px; height: 26px; border-radius: 8px; display: flex; align-items: center; justify-content: center; color: #64748b; }
.hub-edu-search-x > span { width: 14px; height: 14px; }

/* pílulas secundárias: no celular quebram em linhas sem cortar */
.hub-seg-wrap { display: flex; flex-wrap: wrap; width: 100%; justify-content: center; }
.hub-seg-wrap > button { flex: 0 0 auto; }
@media (min-width: 900px) {
  .hub-seg-wrap > button { flex: 1; justify-content: center; }
}

/* texto de abertura */
.hub-edu-lead p {
  font-size: 14.5px;
  line-height: 1.65;
  color: #1e293b;
  margin: 0 0 12px;
  padding-left: 14px;
  border-left: 3px solid rgba(65, 105, 225, 0.35);
}
.hub-edu-lead p:last-child { margin-bottom: 0; }
.dark .hub-edu-lead p { color: rgba(255, 255, 255, 0.88); border-left-color: rgba(143, 169, 245, 0.5); }

/* card de princípio / ideia */
.hub-edu-card { padding: 18px 18px 16px; min-width: 0; }
@media (min-width: 640px) { .hub-edu-card { padding: 22px 22px 20px; } }
.hub-edu-card-ico {
  width: 36px;
  height: 36px;
  border-radius: 11px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(65, 105, 225, 0.12);
  color: #27408b;
  margin-bottom: 12px;
}
.hub-edu-card-ico > span { width: 18px; height: 18px; }
.dark .hub-edu-card-ico { background: rgba(65, 105, 225, 0.3); color: #fff; }
.hub-edu-card-t { font-size: 15px; font-weight: 800; letter-spacing: -0.01em; line-height: 1.2; margin: 0 0 6px; color: #0f172a; }
.dark .hub-edu-card-t { color: #fff; }
.hub-edu-card-d { font-size: 13px; line-height: 1.55; color: #475569; margin: 0; }
.dark .hub-edu-card-d { color: rgba(255, 255, 255, 0.76); }

/* mapa dos ciclos */
.hub-edu-cycle { padding: 18px 16px 16px; min-width: 0; }
.hub-edu-cycle.is-next { opacity: 0.78; }
.hub-edu-weeks { display: grid; grid-template-columns: repeat(8, minmax(0, 1fr)); gap: 4px; margin-top: 4px; }
.hub-edu-weeks i { display: block; height: 7px; border-radius: 4px; background: rgba(148, 163, 184, 0.28); }
.hub-edu-weeks i.is-done { background: #4169e1; }
.hub-edu-weeks i.is-now { background: #ff8a00; box-shadow: 0 0 0 2px rgba(255, 138, 0, 0.25); }

/* termo do glossário */
.hub-edu-term { flex-shrink: 0; width: 9.5rem; font-size: 12px; font-weight: 800; color: #27408b; letter-spacing: 0.01em; }
.dark .hub-edu-term { color: #a9bdf7; }

/* exercício (área Treinos) */
.hub-edu-ex { padding: 18px 16px 16px; min-width: 0; }
@media (min-width: 640px) { .hub-edu-ex { padding: 22px 22px 18px; } }
.hub-edu-ex-n {
  flex-shrink: 0;
  width: 30px;
  height: 30px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 900;
  font-size: 13px;
  color: #27408b;
  background: rgba(65, 105, 225, 0.12);
}
.dark .hub-edu-ex-n { color: #fff; background: rgba(65, 105, 225, 0.32); }
.hub-edu-ex-t { font-size: 16px; font-weight: 800; letter-spacing: -0.01em; line-height: 1.2; margin: 3px 0 0; color: #0f172a; }
.dark .hub-edu-ex-t { color: #fff; }
.hub-edu-ex-m { font-size: 12px; font-weight: 600; color: #3b5bdb; margin: 3px 0 0; }
.dark .hub-edu-ex-m { color: #9db8ff; }
.hub-edu-ex-body { margin-top: 14px; padding-top: 12px; border-top: 1px solid rgba(65, 105, 225, 0.14); display: flex; flex-direction: column; gap: 10px; }
.dark .hub-edu-ex-body { border-top-color: rgba(255, 255, 255, 0.1); }
.hub-edu-ex-row { display: grid; grid-template-columns: minmax(0, 1fr); gap: 4px 14px; }
@media (min-width: 640px) { .hub-edu-ex-row { grid-template-columns: 10.5rem minmax(0, 1fr); } }
.hub-edu-ex-l {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 10.5px;
  font-weight: 800;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: #27408b;
  line-height: 1.3;
}
.hub-edu-ex-l > span { width: 13px; height: 13px; display: inline-block; }
.hub-edu-ex-l.is-orange { color: #b85c00; }
.dark .hub-edu-ex-l { color: #a9bdf7; }
.dark .hub-edu-ex-l.is-orange { color: #ffc17a; }
.hub-edu-ex-v { font-size: 13px; line-height: 1.55; color: #334155; }
.dark .hub-edu-ex-v { color: rgba(255, 255, 255, 0.82); }

/* ciência: passos e prática */
.hub-edu-steps { display: flex; flex-direction: column; gap: 14px; }
.hub-edu-step { display: flex; gap: 14px; align-items: flex-start; padding: 14px 0 0; border-top: 1px solid rgba(65, 105, 225, 0.12); }
.hub-edu-step:first-child { border-top: 0; padding-top: 0; }
.hub-edu-step > .hub-acc-n { flex-shrink: 0; }
.hub-edu-practice { padding: 16px 16px 14px; display: flex; gap: 10px; align-items: flex-start; min-width: 0; }
.hub-edu-practice > .hub-ico { width: 18px; height: 18px; flex-shrink: 0; margin-top: 1px; }
.hub-edu-practice > p { font-size: 13px; line-height: 1.55; color: #334155; margin: 0; }
.dark .hub-edu-practice > p { color: rgba(255, 255, 255, 0.84); }

/* filosofia: manifesto no bloco sólido */
.hub-edu-manifesto-t { font-size: 22px; font-weight: 800; letter-spacing: -0.02em; line-height: 1.2; margin: 4px 0 18px; color: #fff; }
@media (min-width: 640px) { .hub-edu-manifesto-t { font-size: 26px; } }
.hub-edu-manifesto-list { display: grid; gap: 12px; grid-template-columns: minmax(0, 1fr); }
@media (min-width: 640px) { .hub-edu-manifesto-list { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px 24px; } }
.hub-edu-manifesto-item { display: flex; gap: 12px; align-items: flex-start; padding: 12px 14px; border-radius: 14px; background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.12); }
.hub-edu-manifesto-n { font-size: 12px; font-weight: 900; color: #ffb25e; letter-spacing: 0.06em; margin-top: 2px; flex-shrink: 0; }
.hub-edu-manifesto-item > p { font-size: 14px; line-height: 1.5; color: #fff; margin: 0; }
/* ── rodada 40 — MODO CLARO TAMBÉM COM LARANJA (pedido dele 29/09: "no tema
   claro também precisa ter contraste com laranja"). Mesma receita do
   escuro, com os tons escuros do laranja (#b85c00) pra texto legível. */
.hub-edu .hub-seg { border-color: rgba(255, 138, 0, 0.35); background: rgba(255, 138, 0, 0.07); }
.hub-edu .hub-seg > button.is-on {
  background: linear-gradient(135deg, #ff6b1a, #ff8a00);
  color: #1a0e00;
  box-shadow: 0 4px 14px -4px rgba(255, 138, 0, 0.55), inset 0 1px 0 rgba(255, 255, 255, 0.4);
}
.hub-edu .hub-seg > button:not(.is-on):hover { color: #b85c00; }
.hub-edu .hub-seg-wrap > button.is-on {
  background: rgba(255, 138, 0, 0.16);
  color: #8a4500;
  box-shadow: inset 0 0 0 1px rgba(255, 138, 0, 0.75);
}
.hub-edu .hub-edu-search { border-color: rgba(255, 138, 0, 0.5); }
.hub-edu .hub-edu-search:focus-within { border-color: #ff8a00; box-shadow: 0 0 0 3px rgba(255, 138, 0, 0.18); }
.hub-edu .hub-edu-search > .hub-ico { color: #ff8a00; }
.hub-edu .hub-sec-ico { background: rgba(255, 138, 0, 0.16); color: #b85c00; box-shadow: inset 0 0 0 1px rgba(255, 138, 0, 0.35); }
.hub-edu .hub-sec-sub { color: #b85c00; opacity: 1; }
.hub-edu .hub-label > .hub-ico { color: #ff8a00; }
.hub-edu .hub-label::after { background: rgba(255, 138, 0, 0.4); }
.hub-edu .hub-kpi.hub-crystal { border-color: rgba(255, 138, 0, 0.55); }
.hub-edu .hub-kpi-l > span[class^='i-'] { color: #ff8a00; }
.hub-edu .hub-kpi-v.is-royal { color: #b85c00; }
.hub-edu .hub-edu-lead p { border-left-color: #ff8a00; }
.hub-edu .hub-edu-card-ico { background: rgba(255, 138, 0, 0.16); color: #b85c00; }
.hub-edu .hub-edu-ex-n { background: rgba(255, 138, 0, 0.18); color: #8a4500; }
.hub-edu .hub-edu-ex-m { color: #b85c00; }
.hub-edu .hub-edu-term { color: #b85c00; }
.hub-edu .hub-tag.is-on { background: linear-gradient(135deg, #ff6b1a, #ff8a00); color: #1a0e00; border-color: transparent; }
.hub-edu .hub-tag.is-soft { background: rgba(255, 138, 0, 0.14); color: #8a4500; }

/* ── rodada 38 — MODO ESCURO COM MAIS LARANJA (pedido dele 29/09: "no modo
   escuro, quero mais contraste com a cor laranja"). Azul segue como
   estrutura (bordas, fundo dos blocos); laranja vira o destaque: aba
   ativa, números, subtítulos, ícones e fios. Só vale dentro de .hub-edu. */
.dark .hub-edu .hub-seg { border-color: rgba(255, 138, 0, 0.28); }
.dark .hub-edu .hub-seg > button.is-on {
  background: linear-gradient(135deg, #ff6b1a, #ff8a00);
  color: #1a0e00;
  box-shadow: 0 4px 14px -4px rgba(255, 138, 0, 0.6), inset 0 1px 0 rgba(255, 255, 255, 0.35);
}
.dark .hub-edu .hub-seg > button:not(.is-on):hover { color: #ffc17a; }
.dark .hub-edu .hub-seg-wrap > button.is-on {
  background: rgba(255, 138, 0, 0.18);
  color: #ffc17a;
  box-shadow: inset 0 0 0 1px rgba(255, 138, 0, 0.7);
}
.dark .hub-edu .hub-edu-search { border-color: rgba(255, 138, 0, 0.4); }
.dark .hub-edu .hub-edu-search:focus-within { border-color: #ff8a00; box-shadow: 0 0 0 3px rgba(255, 138, 0, 0.2); }
.dark .hub-edu .hub-edu-search > .hub-ico { color: #ffb25e; }
.dark .hub-edu .hub-sec-ico { background: rgba(255, 138, 0, 0.2); color: #ffb25e; box-shadow: inset 0 0 0 1px rgba(255, 138, 0, 0.35); }
.dark .hub-edu .hub-sec-sub { color: #ffc17a; opacity: 0.95; }
.dark .hub-edu .hub-label { color: rgba(255, 255, 255, 0.78); }
.dark .hub-edu .hub-label > .hub-ico { color: #ffb25e; }
.dark .hub-edu .hub-label::after { background: rgba(255, 138, 0, 0.35); }
.dark .hub-edu .hub-kpi.hub-crystal { border-color: rgba(255, 138, 0, 0.5); }
.dark .hub-edu .hub-kpi-l > span[class^='i-'] { color: #ffb25e; }
.dark .hub-edu .hub-kpi-v.is-royal { color: #ffb25e; }
.dark .hub-edu .hub-edu-lead p { border-left-color: #ff8a00; }
.dark .hub-edu .hub-edu-card-ico { background: rgba(255, 138, 0, 0.2); color: #ffb25e; }
.dark .hub-edu .hub-edu-ex-n { background: rgba(255, 138, 0, 0.22); color: #ffc17a; }
.dark .hub-edu .hub-edu-ex-m { color: #ffc17a; }
.dark .hub-edu .hub-edu-term { color: #ffc17a; }
.dark .hub-edu .hub-tag.is-on { background: linear-gradient(135deg, #ff6b1a, #ff8a00); color: #1a0e00; }
.dark .hub-edu .hub-tag.is-soft { background: rgba(255, 138, 0, 0.16); color: #ffc17a; }
.dark .hub-edu .hub-edu-weeks i.is-done { background: #8fa9f5; }
</style>
