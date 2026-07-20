<script setup>
// PAINEL DE METAS: o histórico dos indicadores (para estipular a meta nova
// com base em dados) + o plano de cada período — alvos, orientações de
// como chegar lá, notas de ajuste por pessoa, MARCOS com check e tarefas
// para o time. Só ADMIN edita; o time inteiro acompanha.
// MULTI-PERÍODO (item 58): ambientes de meta do dia, da semana, do fim de
// semana, do mês (o oficial dos selos), do trimestre e do ano + metas de
// indicadores em % (agendamento, comparecimento, conversão p/ cirurgia).
import { ref, computed, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();
const teamAgents = useMapGetter('agents/getAgents');
const { isAdmin } = useAdmin();

const isLoading = ref(true);
const data = ref(null);
const month = ref(''); // ISO do INÍCIO do período selecionado

// ── ambientes de meta (item 58) ──
const PERIODS = [
  { key: 'day', label: 'Dia' },
  { key: 'week', label: 'Semana' },
  { key: 'weekend', label: 'Fim de semana' },
  { key: 'month', label: 'Mês' },
  { key: 'quarter', label: 'Trimestre' },
  { key: 'year', label: 'Ano' },
];
const period = ref('month');
const HIST_HINTS = {
  day: 'os últimos 14 dias',
  week: 'as últimas 12 semanas',
  weekend: 'os últimos 12 fins de semana',
  month: 'os últimos 12 meses',
  quarter: 'os últimos 8 trimestres',
  year: 'os últimos 5 anos',
};

const monthLabel = iso =>
  new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
// datas sempre no fuso LOCAL (toISOString mudaria o dia depois das 21h)
const fmtIso = d =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const parseIso = iso => new Date(`${iso}T12:00:00`);

// início do período que contém HOJE (mesma regra do backend)
const currentStartIso = () => {
  const d = new Date();
  if (period.value === 'day') return fmtIso(d);
  if (period.value === 'week' || period.value === 'weekend') {
    const start = new Date(d);
    start.setDate(d.getDate() - ((d.getDay() + 6) % 7)); // segunda
    if (period.value === 'weekend') start.setDate(start.getDate() + 5); // sábado
    return fmtIso(start);
  }
  if (period.value === 'quarter')
    return fmtIso(new Date(d.getFullYear(), Math.floor(d.getMonth() / 3) * 3, 1));
  if (period.value === 'year') return fmtIso(new Date(d.getFullYear(), 0, 1));
  return fmtIso(new Date(d.getFullYear(), d.getMonth(), 1));
};
// navega um período para trás/frente a partir do selecionado
const shiftedIso = dir => {
  const d = parseIso(month.value);
  if (period.value === 'day') d.setDate(d.getDate() + dir);
  else if (period.value === 'week' || period.value === 'weekend')
    d.setDate(d.getDate() + dir * 7);
  else if (period.value === 'quarter') d.setMonth(d.getMonth() + dir * 3);
  else if (period.value === 'year') d.setFullYear(d.getFullYear() + dir);
  else d.setMonth(d.getMonth() + dir);
  return fmtIso(d);
};

// nome humano do período selecionado (títulos e alertas)
const periodTitle = computed(() => {
  if (!month.value) return '';
  const d = parseIso(month.value);
  const dm = x => x.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  if (period.value === 'day')
    return d.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: '2-digit' });
  if (period.value === 'week') {
    const end = new Date(d);
    end.setDate(d.getDate() + 6);
    return `semana de ${dm(d)} a ${dm(end)}`;
  }
  if (period.value === 'weekend') {
    const end = new Date(d);
    end.setDate(d.getDate() + 1);
    return `fim de semana ${d.getDate()} e ${dm(end)}`;
  }
  if (period.value === 'quarter')
    return `${Math.floor(d.getMonth() / 3) + 1}º trimestre de ${d.getFullYear()}`;
  if (period.value === 'year') return `${d.getFullYear()}`;
  return monthLabel(month.value);
});

// ── formulário do plano (rascunho local → Salvar) ──
const form = ref({ targets: {}, guidance: '', milestones: [], indicator_meta: {} });
const hydrateForm = () => {
  const plan = data.value?.plan;
  form.value = {
    targets: { ...(plan?.targets || {}) },
    guidance: plan?.guidance || '',
    milestones: (plan?.milestones || []).map(m => ({ ...m })),
    indicator_meta: Object.fromEntries(
      Object.entries(plan?.indicator_meta || {}).map(([k, v]) => [k, { ...v }])
    ),
  };
};

const load = async targetDate => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getGoalPlans(targetDate, period.value);
    data.value = payload;
    month.value = payload.month;
    hydrateForm();
  } catch {
    useAlert('Não consegui carregar o Painel de Metas.');
  } finally {
    isLoading.value = false;
  }
};
const switchPeriod = async p => {
  if (period.value === p) return;
  period.value = p;
  await load(currentStartIso());
};

// responsável + "o que é preciso" por indicador (admin prepara, time vê)
const metaOf = key => form.value.indicator_meta[key] || {};
const setMeta = (key, field, value) => {
  const meta = { ...metaOf(key), [field]: value };
  if (!meta.owner_id) delete meta.owner_id;
  if (!meta.how) delete meta.how;
  if (Object.keys(meta).length) form.value.indicator_meta[key] = meta;
  else delete form.value.indicator_meta[key];
};
const ownerName = key => {
  const id = metaOf(key).owner_id;
  if (!id) return null;
  return (teamAgents.value || []).find(a => a.id === id)?.name || null;
};
const saving = ref(false);
const savePlan = async () => {
  saving.value = true;
  try {
    const { data: plan } = await CrmAPI.upsertGoalPlan({
      month: month.value,
      period: period.value,
      ...form.value,
    });
    data.value.plan = plan;
    useAlert(`Meta (${periodTitle.value}) salva! 🎯`);
  } catch {
    useAlert('Não consegui salvar a meta.');
  } finally {
    saving.value = false;
  }
};

// ── histórico: mini-gráfico de barras por indicador ──
const INDICATOR_COLORS = {
  new_leads: '#0F5FA6',
  appointments_booked: '#7C3AED',
  consultations_attended: '#0D9488',
  surgeries_booked: '#B8860B',
  surgeries_done: '#047857',
  revenue_closed: '#BE185D',
  rate_scheduling: '#6366F1',
  rate_attendance: '#0891B2',
  rate_surgery: '#EA580C',
};
const history = computed(() => data.value?.history || []);
const maxOf = key => Math.max(1, ...history.value.map(h => h.values[key] || 0));
const monthShort = iso =>
  new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { month: 'short' }).replace('.', '');
// rótulo curto de cada barra, conforme o ambiente de meta
const barShort = iso => {
  if (period.value === 'month') return monthShort(iso);
  const d = parseIso(iso);
  if (period.value === 'quarter')
    return `T${Math.floor(d.getMonth() / 3) + 1}·${String(d.getFullYear()).slice(2)}`;
  if (period.value === 'year') return `${d.getFullYear()}`;
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
};
const isRate = key => (data.value?.rate_keys || []).includes(key);
const fmtVal = (key, v) => {
  if (isRate(key)) return `${Number(v || 0).toLocaleString('pt-BR')}%`;
  return key === 'revenue_closed'
    ? `R$ ${Number(v || 0).toLocaleString('pt-BR')}`
    : Number(v || 0).toLocaleString('pt-BR');
};

// progresso do mês selecionado (valores atuais × alvo)
const selectedHistory = computed(() => history.value.find(h => h.month === month.value));
const progressOf = key => {
  const target = Number(form.value.targets[key] || 0);
  if (!target) return null;
  const current = selectedHistory.value?.values?.[key] || 0;
  return { current, target, pct: Math.min(999, Math.round((current / target) * 100)) };
};

// ── marcos ──
const newMilestone = ref('');
const addMilestone = () => {
  if (!newMilestone.value.trim()) return;
  form.value.milestones.push({ title: newMilestone.value.trim(), due_on: null, done: false });
  newMilestone.value = '';
};
const toggleMilestone = async m => {
  m.done = !m.done;
  if (isAdmin.value) await savePlan();
};

// ── notas de ajuste por pessoa ──
const noteText = ref('');
const noteAbout = ref('');
const sendNote = async () => {
  if (!noteText.value.trim()) return;
  try {
    const { data: plan } = await CrmAPI.addGoalNote(month.value, noteText.value.trim(), noteAbout.value || null, period.value);
    data.value.plan = plan;
    hydrateForm();
    noteText.value = '';
  } catch {
    useAlert('Não consegui salvar a nota.');
  }
};
const removeNote = async note => {
  const { data: plan } = await CrmAPI.deleteGoalNote(month.value, note.id, period.value).catch(() => ({}));
  if (plan) data.value.plan = plan;
};

// ── tarefas para o time (usa o ambiente Tarefas) ──
const taskDraft = ref({ title: '', assignee_id: '' });
const creatingTask = ref(false);
const createTeamTask = async () => {
  if (!taskDraft.value.title.trim()) return;
  creatingTask.value = true;
  try {
    await store.dispatch('tasks/create', {
      title: `🎯 ${taskDraft.value.title.trim()}`,
      description: `Atividade da meta (${periodTitle.value}) — Painel de Metas.`,
      assignee_id: taskDraft.value.assignee_id || null,
      priority: 'high',
    });
    useAlert('Tarefa criada no ambiente Tarefas! A pessoa recebe o aviso no Meu Painel.');
    taskDraft.value = { title: '', assignee_id: '' };
  } catch {
    useAlert('Não consegui criar a tarefa.');
  } finally {
    creatingTask.value = false;
  }
};

// ── rotinas + ferramentas (admin edita; aparecem no Meu Painel) ──
const routinesText = ref('');
const tools = ref([]);
const savingRoutines = ref(false);
const hydrateRoutines = () => {
  routinesText.value = (data.value?.routines || []).join('\n');
  tools.value = (data.value?.tools || []).map(t => ({ ...t }));
};
const saveRoutinesTools = async () => {
  savingRoutines.value = true;
  try {
    const { data: res } = await CrmAPI.updateRoutinesTools({
      routines: routinesText.value.split('\n').map(r => r.trim()).filter(Boolean),
      tools: tools.value.filter(t => t.label),
    });
    data.value.routines = res.routines;
    data.value.tools = res.tools;
    useAlert('Rotinas e ferramentas atualizadas — já aparecem no Meu Painel do time.');
  } catch {
    useAlert('Não consegui salvar.');
  } finally {
    savingRoutines.value = false;
  }
};

onMounted(async () => {
  if (!teamAgents.value.length) store.dispatch('agents/get');
  await load(currentStartIso());
  hydrateRoutines();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <div class="flex items-center gap-3 flex-wrap mb-4">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
          <span class="i-lucide-target text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Painel de Metas</h1>
          <p class="text-xs text-n-slate-10">analise o histórico, defina metas por período — dia, semana, fim de semana, mês, trimestre e ano — e acompanhe o caminho</p>
        </div>
      </div>

      <!-- ambientes de meta + navegação do período -->
      <div class="flex items-center gap-2 flex-wrap mb-4">
        <div class="flex items-center gap-1 flex-wrap">
          <button
            v-for="p in PERIODS"
            :key="p.key"
            class="px-3 h-8 rounded-full text-xs font-medium border transition-colors"
            :class="period === p.key
              ? 'text-white border-transparent font-bold shadow-sm'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            :style="period === p.key ? 'background: linear-gradient(135deg, #B8860B, #D4A017)' : ''"
            @click="switchPeriod(p.key)"
          >
            {{ p.label }}
          </button>
        </div>
        <div class="flex items-center gap-1.5 ml-auto">
          <button
            class="w-8 h-8 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center justify-center"
            title="Período anterior"
            @click="load(shiftedIso(-1))"
          >
            <span class="i-lucide-chevron-left text-sm" />
          </button>
          <button
            class="px-3 h-8 rounded-lg text-xs font-medium border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            :class="month === currentStartIso() ? 'bg-n-alpha-2 font-bold' : ''"
            @click="load(currentStartIso())"
          >
            Atual
          </button>
          <button
            class="w-8 h-8 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center justify-center"
            title="Próximo período"
            @click="load(shiftedIso(1))"
          >
            <span class="i-lucide-chevron-right text-sm" />
          </button>
          <input
            v-if="period === 'month'"
            :value="month ? month.slice(0, 7) : ''"
            type="month"
            class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
            style="width: 10rem; margin-bottom: 0"
            @change="load(`${$event.target.value}-01`)"
          />
        </div>
      </div>

      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <template v-else>
        <!-- ── histórico + meta por indicador ── -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1">
            Meta — {{ periodTitle }}
            <span class="text-[11px] font-normal text-n-slate-9">— cada indicador mostra {{ HIST_HINTS[period] }} pra você calibrar o alvo</span>
          </h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-3">
            <div
              v-for="(label, key) in data.indicators"
              :key="key"
              class="rounded-xl border border-n-weak bg-n-solid-1 p-3"
            >
              <div class="flex items-center gap-2 flex-wrap mb-2">
                <span class="w-2.5 h-2.5 rounded-full" :style="{ background: INDICATOR_COLORS[key] }" />
                <p class="text-xs font-bold text-n-slate-12 flex-1">{{ label }}</p>
                <span class="text-[10px] text-n-slate-9">{{ isRate(key) ? 'alvo (%):' : 'alvo:' }}</span>
                <input
                  v-model.number="form.targets[key]"
                  type="number"
                  min="0"
                  :disabled="!isAdmin"
                  class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs font-bold text-n-slate-12 disabled:opacity-60"
                  style="width: 6rem; margin-bottom: 0"
                />
              </div>
              <!-- 12 meses em barras; o mês selecionado destacado -->
              <div class="flex items-end gap-[3px] h-14">
                <div
                  v-for="h in history"
                  :key="h.month"
                  class="flex-1 rounded-t-sm transition-all"
                  :style="{
                    height: `${Math.max(((h.values[key] || 0) / maxOf(key)) * 100, h.values[key] ? 8 : 2)}%`,
                    background: h.month === month ? INDICATOR_COLORS[key] : `${INDICATOR_COLORS[key]}55`,
                  }"
                  :title="`${barShort(h.month)}: ${fmtVal(key, h.values[key])}${h.targets[key] ? ` · meta ${fmtVal(key, h.targets[key])}` : ''}`"
                />
              </div>
              <div class="flex items-center justify-between mt-1">
                <span class="text-[9px] text-n-slate-9">{{ history.length ? barShort(history[0].month) : '' }}</span>
                <span class="text-[9px] text-n-slate-9">{{ history.length ? barShort(history[history.length - 1].month) : '' }}</span>
              </div>
              <!-- progresso do mês contra a meta -->
              <div v-if="progressOf(key)" class="mt-2">
                <div class="h-2 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all duration-700"
                    :style="{ width: `${Math.min(progressOf(key).pct, 100)}%`, background: INDICATOR_COLORS[key] }"
                  />
                </div>
                <p class="text-[10px] text-n-slate-10 mt-0.5">
                  {{ fmtVal(key, progressOf(key).current) }} de {{ fmtVal(key, progressOf(key).target) }}
                  · <b :style="{ color: progressOf(key).pct >= 100 ? '#047857' : undefined }">{{ progressOf(key).pct }}%</b>
                </p>
              </div>

              <!-- responsável + o que é preciso para alcançar -->
              <div v-if="isAdmin" class="mt-2 pt-2 border-t border-n-weak space-y-1.5">
                <div class="flex items-center gap-2">
                  <span class="text-[10px] text-n-slate-9 flex-shrink-0">responsável:</span>
                  <select
                    :value="metaOf(key).owner_id || ''"
                    class="h-7 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-1.5 text-[11px] text-n-slate-12"
                    style="margin-bottom: 0"
                    @change="setMeta(key, 'owner_id', Number($event.target.value) || null)"
                  >
                    <option value="">— ninguém ainda —</option>
                    <option v-for="a in teamAgents" :key="a.id" :value="a.id">{{ a.name }}</option>
                  </select>
                </div>
                <textarea
                  :value="metaOf(key).how || ''"
                  rows="2"
                  placeholder="O que é preciso para alcançar essa meta?"
                  class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 text-[11px] text-n-slate-12 resize-y"
                  style="margin-bottom: 0"
                  @input="setMeta(key, 'how', $event.target.value)"
                />
              </div>
              <div
                v-else-if="ownerName(key) || metaOf(key).how"
                class="mt-2 pt-2 border-t border-n-weak"
              >
                <p v-if="ownerName(key)" class="text-[10px] font-semibold text-n-slate-11 flex items-center gap-1">
                  <span class="i-lucide-user-round text-[11px]" :style="{ color: INDICATOR_COLORS[key] }" />
                  {{ ownerName(key) }} puxa essa meta
                </p>
                <p v-if="metaOf(key).how" class="text-[11px] text-n-slate-10 mt-0.5 whitespace-pre-line">
                  {{ metaOf(key).how }}
                </p>
              </div>
            </div>
          </div>

          <!-- orientações -->
          <div class="mt-4">
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">Como vamos chegar lá (orientações pro time)</p>
            <textarea
              v-model="form.guidance"
              rows="3"
              :disabled="!isAdmin"
              placeholder="Ex.: foco em reativar os sem-resposta na 1ª quinzena; toda indicação de cirurgia recebe follow-up em 24h; usar o mapa de objeções no fechamento…"
              class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12 resize-y disabled:opacity-70"
            />
          </div>

          <div v-if="isAdmin" class="flex justify-end mt-2">
            <button
              class="px-4 h-9 rounded-xl text-xs font-bold text-white shadow-sm disabled:opacity-60"
              style="background: linear-gradient(135deg, #B8860B, #D4A017)"
              :disabled="saving"
              @click="savePlan"
            >
              {{ saving ? 'Salvando…' : `Salvar meta (${periodTitle})` }}
            </button>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-5">
          <!-- marcos -->
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3 flex items-center gap-2">
              <span class="i-lucide-flag text-base" style="color: #B8860B" /> {{ period === 'month' ? 'Marcos do mês' : 'Marcos do período' }}
            </h2>
            <div v-for="(m, mi) in form.milestones" :key="m.id || mi" class="flex items-center gap-2 mb-1.5">
              <button
                class="w-4 h-4 rounded border flex items-center justify-center flex-shrink-0"
                :class="m.done ? 'bg-amber-600 border-amber-600' : 'border-n-strong'"
                @click="toggleMilestone(m)"
              >
                <span v-if="m.done" class="i-lucide-check text-white text-[10px]" />
              </button>
              <span class="text-xs flex-1" :class="m.done ? 'line-through text-n-slate-9' : 'text-n-slate-11'">{{ m.title }}</span>
              <input
                v-model="m.due_on"
                type="date"
                :disabled="!isAdmin"
                class="h-7 rounded-lg border border-n-weak bg-n-solid-1 px-1 text-[10px] text-n-slate-11 disabled:opacity-50"
                style="width: 8rem"
              />
              <button v-if="isAdmin" class="i-lucide-x text-n-slate-9 hover:text-red-500 text-xs" @click="form.milestones.splice(mi, 1)" />
            </div>
            <div v-if="isAdmin" class="flex items-center gap-1.5 mt-2">
              <input
                v-model="newMilestone"
                type="text"
                placeholder="Novo marco (ex.: 10 cirurgias fechadas até dia 15)"
                class="flex-1 min-w-0 h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
                @keyup.enter="addMilestone"
              />
              <button class="w-8 h-8 rounded-lg text-white flex items-center justify-center" style="background: linear-gradient(135deg, #B8860B, #D4A017)" @click="addMilestone">
                <span class="i-lucide-plus text-xs" />
              </button>
            </div>
            <p v-if="isAdmin" class="text-[10px] text-n-slate-9 mt-1.5">marque/desmarque e clique em salvar — o Mentor usa os marcos pendentes nos feedbacks.</p>
          </div>

          <!-- tarefas + notas -->
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3 flex items-center gap-2">
              <span class="i-lucide-list-checks text-base" style="color: #7C3AED" /> Atividades e ajustes do time
            </h2>
            <!-- criar tarefa -->
            <div v-if="isAdmin" class="flex items-center gap-1.5 flex-wrap mb-3">
              <input
                v-model="taskDraft.title"
                type="text"
                placeholder="Atividade rumo à meta (vira tarefa de verdade)…"
                class="flex-1 min-w-[160px] h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
              />
              <select v-model="taskDraft.assignee_id" class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-1 text-[11px] text-n-slate-12" style="width: 8.5rem">
                <option value="">Sem dono</option>
                <option v-for="a in teamAgents" :key="a.id" :value="a.id">{{ a.available_name || a.name }}</option>
              </select>
              <button
                class="px-3 h-8 rounded-lg text-[11px] font-bold text-white disabled:opacity-50"
                style="background: linear-gradient(135deg, #5B21B6, #7C3AED)"
                :disabled="creatingTask || !taskDraft.title.trim()"
                @click="createTeamTask"
              >
                Criar tarefa
              </button>
            </div>
            <!-- notas de ajuste -->
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">Ajustes de processo (por pessoa)</p>
            <div v-if="data.plan?.process_notes?.length" class="space-y-1.5 mb-2 max-h-48 overflow-y-auto">
              <div v-for="n in data.plan.process_notes" :key="n.id" class="rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5">
                <div class="flex items-center gap-2">
                  <span class="text-[10px] font-bold px-1.5 py-0.5 rounded-full" style="background: rgba(124,58,237,0.12); color: #6D28D9">{{ n.name }}</span>
                  <span class="text-[10px] text-n-slate-9">por {{ n.author }}</span>
                  <button v-if="isAdmin" class="ml-auto i-lucide-x text-n-slate-9 hover:text-red-500 text-xs" @click="removeNote(n)" />
                </div>
                <p class="text-[11px] text-n-slate-11 mt-0.5">{{ n.text }}</p>
              </div>
            </div>
            <div v-if="isAdmin" class="flex items-center gap-1.5 flex-wrap">
              <select v-model="noteAbout" class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-1 text-[11px] text-n-slate-12" style="width: 8.5rem">
                <option value="">Processo geral</option>
                <option v-for="a in teamAgents" :key="a.id" :value="a.id">{{ a.available_name || a.name }}</option>
              </select>
              <input
                v-model="noteText"
                type="text"
                placeholder="O ajuste combinado (ex.: priorizar fila do sem-resposta às 14h)…"
                class="flex-1 min-w-[160px] h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
                @keyup.enter="sendNote"
              />
              <button class="px-3 h-8 rounded-lg text-[11px] font-bold text-white" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)" @click="sendNote">
                Anotar
              </button>
            </div>
          </div>
        </div>

        <!-- rotinas + ferramentas (vão pro Meu Painel do time; são globais, só no ambiente do mês) -->
        <div v-if="isAdmin && period === 'month'" class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-repeat text-base" style="color: #0D9488" /> Rotinas e ferramentas do time
            <span class="text-[11px] font-normal text-n-slate-9">— aparecem no Meu Painel de todo mundo</span>
          </h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
            <div>
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">Rotinas (uma por linha)</p>
              <textarea
                v-model="routinesText"
                rows="5"
                placeholder="08h — limpar a fila do sem-resposta&#10;14h — conferência da agenda de amanhã&#10;17h — follow-up dos orçamentos do dia"
                class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12 resize-y"
              />
            </div>
            <div>
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">Ferramentas importantes (nome + link)</p>
              <div v-for="(t, ti) in tools" :key="ti" class="flex items-center gap-1.5 mb-1.5">
                <input v-model="t.label" type="text" placeholder="Nome" class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12" style="width: 11rem" />
                <input v-model="t.url" type="text" placeholder="https://…" class="flex-1 min-w-0 h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12" />
                <button class="i-lucide-x text-n-slate-9 hover:text-red-500 text-xs" @click="tools.splice(ti, 1)" />
              </div>
              <button class="text-[11px] text-n-slate-10 hover:text-teal-600 flex items-center gap-1" @click="tools.push({ label: '', url: '' })">
                <span class="i-lucide-plus text-xs" /> adicionar ferramenta
              </button>
              <p class="text-[10px] text-n-slate-9 mt-1.5">as Ferramentas de Fechamento (script + mapa de objeções) já aparecem sozinhas.</p>
            </div>
          </div>
          <div class="flex justify-end mt-2">
            <button
              class="px-4 h-8 rounded-lg text-xs font-bold text-white disabled:opacity-60"
              style="background: linear-gradient(135deg, #0F766E, #2DD4BF)"
              :disabled="savingRoutines"
              @click="saveRoutinesTools"
            >
              Salvar rotinas & ferramentas
            </button>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
