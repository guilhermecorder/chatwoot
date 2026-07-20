<script setup>
// AMBIENTE PESSOAS (RH e desenvolvimento): cada pessoa tem seu espaço —
// diagnóstico DISC / 4 temperamentos com dashboard individual, objetivos
// e metas de desenvolvimento pessoal com progresso, e a linha do tempo
// dos feedbacks do Mentor (semanais e mensais). Admin vê o time inteiro
// para combinar perfis e montar times fortes e entrosados.
import { ref, computed, watch, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import TestsTab from './TestsTab.vue';
import LifeTab from './LifeTab.vue';
import { DISC_PROFILES, discRanking } from './discQuiz';

const isLoading = ref(true);
const data = ref({ me: null, admin: false, people: [] });
const selectedUserId = ref(null);

const load = async () => {
  try {
    const { data: payload } = await CrmAPI.getPeople();
    data.value = payload;
    if (!selectedUserId.value) selectedUserId.value = payload.me;
  } catch {
    useAlert('Não consegui carregar o ambiente Pessoas.');
  } finally {
    isLoading.value = false;
  }
};

const person = computed(() => data.value.people.find(p => p.user_id === selectedUserId.value) || null);
const isMe = computed(() => person.value?.user_id === data.value.me);
const canEditGoals = computed(() => isMe.value || data.value.admin);
const firstName = name => (name || '').split(' ')[0];

// ── abas do espaço da pessoa (Vida é privada: só no próprio espaço) ──
const TABS = computed(() => [
  { key: 'perfil', label: 'Perfil', icon: 'i-lucide-fingerprint' },
  ...(isMe.value ? [{ key: 'vida', label: 'Vida', icon: 'i-lucide-loader-pinwheel' }] : []),
  { key: 'desenvolvimento', label: 'Desenvolvimento', icon: 'i-lucide-trending-up' },
  { key: 'feedbacks', label: 'Feedbacks', icon: 'i-lucide-graduation-cap' },
]);
const tab = ref('perfil');
watch(selectedUserId, () => {
  if (tab.value === 'vida' && !isMe.value) tab.value = 'perfil';
});

// resumo pro card do time — a ORDEM dos 4 importa
const discOf = p => {
  const scores = p?.disc?.scores;
  if (!scores) return null;
  const norm = { d: scores.d || 0, i: scores.i || 0, s: scores.s || 0, c: scores.c || 0 };
  const ranking = discRanking(norm);
  return { ranking, profile: DISC_PROFILES[ranking[0]] };
};

// ── Desenvolvimento pessoal: objetivos e metas ──
const goals = computed(() => person.value?.goals || []);
const newGoal = ref({ title: '', why: '', due_on: '' });
const newMetaText = ref({});
const savingGoals = ref(false);

const persistGoals = async list => {
  savingGoals.value = true;
  try {
    const { data: res } = await CrmAPI.savePersonGoals(person.value.user_id, list);
    person.value.goals = res.goals;
  } catch {
    useAlert('Não consegui salvar.');
  } finally {
    savingGoals.value = false;
  }
};
const addGoal = async () => {
  if (!newGoal.value.title.trim()) return;
  const list = [...goals.value, {
    title: newGoal.value.title.trim(),
    why: newGoal.value.why,
    due_on: newGoal.value.due_on || null,
    status: 'andamento',
    metas: [],
    updates: [],
  }];
  await persistGoals(list);
  newGoal.value = { title: '', why: '', due_on: '' };
};
const addMeta = async goal => {
  const text = (newMetaText.value[goal.id] || '').trim();
  if (!text) return;
  goal.metas.push({ text, done: false });
  newMetaText.value[goal.id] = '';
  await persistGoals(goals.value);
};
const toggleMeta = async (goal, meta) => {
  meta.done = !meta.done;
  await persistGoals(goals.value);
};
const setGoalStatus = async (goal, status) => {
  goal.status = status;
  await persistGoals(goals.value);
};
const removeGoal = async goal => {
  if (!window.confirm(`Excluir o objetivo "${goal.title}"?`)) return;
  await persistGoals(goals.value.filter(g => g.id !== goal.id));
};
const goalProgress = goal => {
  if (goal.status === 'concluido') return 100;
  if (!goal.metas?.length) return 0;
  return Math.round((goal.metas.filter(m => m.done).length / goal.metas.length) * 100);
};
const GOAL_STATUS = [
  { key: 'andamento', label: 'Em andamento', color: '#1D4ED8', bg: 'rgba(59,130,246,0.1)' },
  { key: 'concluido', label: 'Concluído', color: '#047857', bg: 'rgba(16,185,129,0.12)' },
  { key: 'pausado', label: 'Pausado', color: '#64748B', bg: 'rgba(100,116,139,0.14)' },
];
const goalStatusOf = goal => GOAL_STATUS.find(s => s.key === goal.status) || GOAL_STATUS[0];

// ── GESTÃO DOS TESTES (item 81, só admin): quem fez o quê, quando, e
// quando cada pessoa pode refazer (trava de 90 dias = 1x por trimestre) ──
const showTestsPanel = ref(false);
const RETAKE_DAYS = 90;
const testStatusOf = (p, kind) => {
  const latest = [...(p.assessments || [])].reverse().find(a => a.kind === kind);
  if (!latest) return { done: false };
  const takenAt = new Date(latest.taken_at);
  const retakeDate = new Date(takenAt);
  retakeDate.setDate(retakeDate.getDate() + RETAKE_DAYS);
  const ranking = latest.ranking || discRanking(latest.scores);
  return {
    done: true,
    takenAt,
    retakeDate,
    locked: retakeDate > new Date(),
    dominant: DISC_PROFILES[ranking[0]],
    answers: (latest.answers || []).length,
  };
};
const fmtShort = d => d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' });

// ── Feedbacks do Mentor (semanais e mensais) ──
const feedbacks = computed(() => person.value?.feedbacks || []);
const fbPeriodLabel = fb => {
  const d = new Date(`${fb.week_start}T12:00:00`);
  if (fb.cadence === 'monthly') {
    return d.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
  }
  const end = new Date(d);
  end.setDate(d.getDate() + 6);
  const f = x => x.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  return `semana de ${f(d)} a ${f(end)}`;
};

const fmtDue = d => (d ? new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' }) : null);

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #0F766E, #2DD4BF)">
          <span class="i-lucide-heart-handshake text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Pessoas</h1>
          <p class="text-xs text-n-slate-10">perfil, desenvolvimento e feedbacks — para crescer e montar times fortes e entrosados</p>
        </div>
      </div>

      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <template v-else>
        <!-- admin: visão do time (perfil dominante de cada um, lado a lado) -->
        <div v-if="data.admin && data.people.length > 1" class="bg-n-solid-2 border border-n-weak rounded-2xl p-4 mb-5">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2">O time num relance — clique para abrir o espaço de cada pessoa</p>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
            <button
              v-for="p in data.people"
              :key="p.user_id"
              class="rounded-xl border p-3 text-left transition-all"
              :class="selectedUserId === p.user_id ? 'border-teal-500 bg-teal-500/5' : 'border-n-weak bg-n-solid-1 hover:border-teal-500/50'"
              @click="selectedUserId = p.user_id"
            >
              <p class="text-xs font-bold text-n-slate-12 truncate">{{ p.name }}</p>
              <template v-if="discOf(p)">
                <span
                  class="inline-flex items-center gap-1 text-[10px] font-bold px-1.5 py-0.5 rounded-full text-white mt-1"
                  :style="{ background: discOf(p).profile.grad }"
                >
                  <span :class="discOf(p).profile.icon" class="text-[10px]" />
                  {{ discOf(p).profile.temperament }}
                </span>
                <!-- a ORDEM dos 4 (importa!) -->
                <p class="text-[10px] font-black tracking-widest mt-1">
                  <span
                    v-for="(dim, di) in discOf(p).ranking"
                    :key="dim"
                    :style="{ color: DISC_PROFILES[dim].color, opacity: 1 - di * 0.18 }"
                  >{{ DISC_PROFILES[dim].letter }}<span v-if="di < 3" class="text-n-slate-8"> › </span></span>
                </p>
              </template>
              <p v-else class="text-[10px] text-n-slate-9 mt-1">DISC pendente</p>
            </button>
          </div>
        </div>

        <!-- admin: GESTÃO DOS TESTES (item 81) — quem fez, quando, trava -->
        <div v-if="data.admin && data.people.length > 1" class="bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden mb-5">
          <button
            class="w-full flex items-center gap-2 px-4 py-3 text-left hover:bg-n-alpha-1 transition-colors"
            @click="showTestsPanel = !showTestsPanel"
          >
            <span class="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #0F766E, #2DD4BF)">
              <span class="i-lucide-clipboard-check text-white text-sm" />
            </span>
            <div class="flex-1 min-w-0">
              <p class="text-xs font-bold text-n-slate-12">Gestão dos testes do time</p>
              <p class="text-[10px] text-n-slate-9">quem já fez DISC e Temperamentos, quando, e quando cada um pode refazer (1x por trimestre)</p>
            </div>
            <span class="text-n-slate-10 flex-shrink-0" :class="showTestsPanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" />
          </button>

          <div v-if="showTestsPanel" class="border-t border-n-weak divide-y divide-n-weak">
            <div class="hidden sm:grid items-center px-4 py-2 text-[10px] font-bold text-n-slate-9 uppercase tracking-wide" style="grid-template-columns: 1.2fr 1fr 1fr">
              <span>Pessoa</span>
              <span>DISC (trabalho)</span>
              <span>4 Temperamentos (vida)</span>
            </div>
            <div
              v-for="p in data.people"
              :key="`tests-${p.user_id}`"
              class="grid items-center gap-2 px-4 py-2.5 sm:gap-0"
              style="grid-template-columns: 1.2fr 1fr 1fr"
            >
              <button class="text-xs font-semibold text-n-slate-12 text-left truncate hover:text-teal-600" @click="selectedUserId = p.user_id">
                {{ p.name }}
              </button>
              <template v-for="kind in ['disc', 'temperamentos']" :key="kind">
                <div v-if="testStatusOf(p, kind).done" class="min-w-0">
                  <p class="text-[11px] font-bold truncate" :style="{ color: testStatusOf(p, kind).dominant?.color }">
                    {{ kind === 'disc' ? `${testStatusOf(p, kind).dominant?.letter} — ${testStatusOf(p, kind).dominant?.name}` : testStatusOf(p, kind).dominant?.temperament }}
                  </p>
                  <p class="text-[10px] text-n-slate-9">
                    {{ fmtShort(testStatusOf(p, kind).takenAt) }}
                    <template v-if="testStatusOf(p, kind).locked"> · 🔒 refaz {{ fmtShort(testStatusOf(p, kind).retakeDate) }}</template>
                    <template v-else> · ✅ pode refazer</template>
                    <template v-if="testStatusOf(p, kind).answers"> · {{ testStatusOf(p, kind).answers }} respostas</template>
                  </p>
                </div>
                <p v-else class="text-[11px] text-n-slate-9">— pendente</p>
              </template>
            </div>
          </div>
        </div>

        <div v-if="person" class="bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #0F766E, #2DD4BF)" />
          <div class="p-4 sm:p-6">
            <!-- identidade + abas -->
            <div class="flex items-center gap-3 flex-wrap mb-4">
              <span class="w-10 h-10 rounded-full flex items-center justify-center text-white text-sm font-bold" style="background: linear-gradient(135deg, #0F766E, #2DD4BF)">
                {{ (person.name || '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase() }}
              </span>
              <div class="flex-1 min-w-0">
                <h2 class="text-sm font-bold text-n-slate-12">{{ person.name }}</h2>
                <p class="text-[11px] text-n-slate-9 truncate">{{ isMe ? 'este é o seu espaço de desenvolvimento' : person.email }}</p>
              </div>
              <div class="flex items-center bg-n-solid-1 border border-n-weak rounded-xl p-0.5 gap-0.5">
                <button
                  v-for="t in TABS"
                  :key="t.key"
                  class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex items-center gap-1.5"
                  :class="tab === t.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                  :style="tab === t.key ? { background: 'linear-gradient(135deg, #0F766E, #2DD4BF)' } : {}"
                  @click="tab = t.key"
                >
                  <span :class="t.icon" class="text-sm" />
                  {{ t.label }}
                </button>
              </div>
            </div>

            <!-- ═══ ABA PERFIL: testes, radar, ordem dos 4 e arquivo ═══ -->
            <TestsTab v-if="tab === 'perfil'" :person="person" :is-me="isMe" :is-admin="data.admin" />

            <!-- ═══ ABA VIDA (privada): Roda da Vida, objetivos, hábitos ═══ -->
            <LifeTab v-else-if="tab === 'vida' && isMe" :person="person" />

            <!-- ═══ ABA DESENVOLVIMENTO ═══ -->
            <template v-else-if="tab === 'desenvolvimento'">
              <div v-for="goal in goals" :key="goal.id" class="rounded-xl border border-n-weak bg-n-solid-1 p-4 mb-3">
                <div class="flex items-center gap-2 flex-wrap mb-1">
                  <p class="text-sm font-bold text-n-slate-12 flex-1 min-w-[160px]" :class="goal.status === 'concluido' ? 'line-through opacity-60' : ''">
                    {{ goal.title }}
                  </p>
                  <span v-if="goal.due_on" class="text-[10px] text-n-slate-9">até {{ fmtDue(goal.due_on) }}</span>
                  <button
                    v-if="canEditGoals"
                    class="text-[10px] font-bold px-2 py-0.5 rounded-full"
                    :style="{ background: goalStatusOf(goal).bg, color: goalStatusOf(goal).color }"
                    title="Clique para mudar"
                    @click="setGoalStatus(goal, goal.status === 'andamento' ? 'concluido' : goal.status === 'concluido' ? 'pausado' : 'andamento')"
                  >
                    {{ goalStatusOf(goal).label }}
                  </button>
                  <button v-if="canEditGoals" class="i-lucide-trash-2 text-n-slate-9 hover:text-red-500 text-sm" @click="removeGoal(goal)" />
                </div>
                <p v-if="goal.why" class="text-xs text-n-slate-10 italic mb-2">{{ goal.why }}</p>

                <div class="h-2.5 bg-n-alpha-1 rounded-full overflow-hidden mb-1">
                  <div class="h-full rounded-full transition-all duration-700" :style="{ width: `${Math.max(goalProgress(goal), 2)}%`, background: 'linear-gradient(90deg, #0F766E, #2DD4BF)' }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mb-2">{{ goalProgress(goal) }}% do caminho</p>

                <div v-for="(meta, mi) in goal.metas" :key="mi" class="flex items-center gap-2 mb-1">
                  <button
                    class="w-4 h-4 rounded border flex items-center justify-center flex-shrink-0 transition-colors"
                    :class="meta.done ? 'bg-teal-600 border-teal-600' : 'border-n-strong'"
                    :disabled="!canEditGoals"
                    @click="toggleMeta(goal, meta)"
                  >
                    <span v-if="meta.done" class="i-lucide-check text-white text-[10px]" />
                  </button>
                  <span class="text-xs" :class="meta.done ? 'line-through text-n-slate-9' : 'text-n-slate-11'">{{ meta.text }}</span>
                </div>
                <div v-if="canEditGoals" class="flex items-center gap-1.5 mt-1.5">
                  <input
                    v-model="newMetaText[goal.id]"
                    type="text"
                    placeholder="Nova meta deste objetivo…"
                    class="flex-1 min-w-0 h-7 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-12"
                    @keyup.enter="addMeta(goal)"
                  />
                  <button class="w-7 h-7 rounded-lg border border-n-weak text-n-slate-10 hover:text-teal-600 flex items-center justify-center" @click="addMeta(goal)">
                    <span class="i-lucide-plus text-xs" />
                  </button>
                </div>
              </div>

              <div v-if="!goals.length" class="text-center py-6 text-xs text-n-slate-10">
                {{ canEditGoals ? 'Nenhum objetivo ainda — escreva o primeiro aqui embaixo.' : 'Nenhum objetivo definido ainda.' }}
              </div>

              <!-- novo objetivo -->
              <div v-if="canEditGoals" class="rounded-xl border border-dashed border-n-weak p-3">
                <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2">Novo objetivo</p>
                <input
                  v-model="newGoal.title"
                  type="text"
                  placeholder="O que você quer conquistar? (ex.: dominar o fechamento de cirurgias)"
                  class="w-full h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[12px] text-n-slate-12 mb-1.5"
                />
                <div class="flex items-center gap-1.5 flex-wrap">
                  <input
                    v-model="newGoal.why"
                    type="text"
                    placeholder="Por que isso importa pra você?"
                    class="flex-1 min-w-[160px] h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12"
                  />
                  <input v-model="newGoal.due_on" type="date" class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12" style="width: 9rem" />
                  <button
                    class="px-3 h-8 rounded-lg text-[11px] font-bold text-white disabled:opacity-50"
                    style="background: linear-gradient(135deg, #0F766E, #2DD4BF)"
                    :disabled="savingGoals || !newGoal.title.trim()"
                    @click="addGoal"
                  >
                    Criar objetivo
                  </button>
                </div>
              </div>
            </template>

            <!-- ═══ ABA FEEDBACKS ═══ -->
            <template v-else>
              <div v-if="!feedbacks.length" class="text-center py-8 text-xs text-n-slate-10">
                Nenhum feedback do Mentor ainda — eles chegam toda segunda (semanal) e todo dia 1º (mensal), com o agente ligado.
              </div>
              <div v-for="fb in feedbacks" :key="`${fb.cadence}-${fb.week_start}`" class="rounded-xl border border-n-weak bg-n-solid-1 p-4 mb-3">
                <div class="flex items-center gap-2 flex-wrap mb-2">
                  <span
                    class="text-[10px] font-bold px-2 py-0.5 rounded-full text-white"
                    :style="{ background: fb.cadence === 'monthly' ? 'linear-gradient(135deg, #5B21B6, #7C3AED)' : 'linear-gradient(135deg, #C2410C, #FB923C)' }"
                  >
                    {{ fb.cadence === 'monthly' ? 'MENSAL' : 'SEMANAL' }}
                  </span>
                  <span class="text-[11px] text-n-slate-9">{{ fbPeriodLabel(fb) }}</span>
                </div>
                <p class="text-xs text-n-slate-11 leading-relaxed mb-2">{{ fb.feedback.resumo }}</p>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  <div class="rounded-lg px-2.5 py-1.5" style="background: rgba(16,185,129,0.08)">
                    <p class="text-[9px] font-bold uppercase" style="color: #047857">Ponto forte</p>
                    <p class="text-[11px] text-n-slate-11">{{ fb.feedback.ponto_forte }}</p>
                  </div>
                  <div class="rounded-lg px-2.5 py-1.5" style="background: rgba(245,158,11,0.08)">
                    <p class="text-[9px] font-bold uppercase" style="color: #B45309">Ponto a corrigir</p>
                    <p class="text-[11px] text-n-slate-11">{{ fb.feedback.ponto_fraco }}</p>
                  </div>
                </div>
              </div>
            </template>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
