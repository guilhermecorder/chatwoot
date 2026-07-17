<script setup>
// PAINEL DE METAS: o histórico dos indicadores mês a mês (para estipular a
// meta nova com base em dados) + o plano do mês — alvos, orientações de
// como chegar lá, notas de ajuste por pessoa, MARCOS com check e tarefas
// para o time. Só ADMIN edita; o time inteiro acompanha.
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();
const teamAgents = useMapGetter('agents/getAgents');
const { isAdmin } = useAdmin();

const isLoading = ref(true);
const data = ref(null);
const month = ref(''); // ISO do dia 1 do mês selecionado

const monthLabel = iso =>
  new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
const nextMonthIso = () => {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth() + 1, 1).toISOString().slice(0, 10);
};
const thisMonthIso = () => {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().slice(0, 10);
};

const load = async targetMonth => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getGoalPlans(targetMonth);
    data.value = payload;
    month.value = payload.month;
    hydrateForm();
  } catch {
    useAlert('Não consegui carregar o Painel de Metas.');
  } finally {
    isLoading.value = false;
  }
};

// ── formulário do plano (rascunho local → Salvar) ──
const form = ref({ targets: {}, guidance: '', milestones: [] });
const hydrateForm = () => {
  const plan = data.value?.plan;
  form.value = {
    targets: { ...(plan?.targets || {}) },
    guidance: plan?.guidance || '',
    milestones: (plan?.milestones || []).map(m => ({ ...m })),
  };
};
const saving = ref(false);
const savePlan = async () => {
  saving.value = true;
  try {
    const { data: plan } = await CrmAPI.upsertGoalPlan({ month: month.value, ...form.value });
    data.value.plan = plan;
    useAlert(`Meta de ${monthLabel(month.value)} salva! 🎯`);
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
};
const history = computed(() => data.value?.history || []);
const maxOf = key => Math.max(1, ...history.value.map(h => h.values[key] || 0));
const monthShort = iso =>
  new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { month: 'short' }).replace('.', '');
const fmtVal = (key, v) =>
  key === 'revenue_closed' ? `R$ ${Number(v || 0).toLocaleString('pt-BR')}` : Number(v || 0).toLocaleString('pt-BR');

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
    const { data: plan } = await CrmAPI.addGoalNote(month.value, noteText.value.trim(), noteAbout.value || null);
    data.value.plan = plan;
    hydrateForm();
    noteText.value = '';
  } catch {
    useAlert('Não consegui salvar a nota.');
  }
};
const removeNote = async note => {
  const { data: plan } = await CrmAPI.deleteGoalNote(month.value, note.id).catch(() => ({}));
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
      description: `Atividade da meta de ${monthLabel(month.value)} (Painel de Metas).`,
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
  await load(thisMonthIso());
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
          <p class="text-xs text-n-slate-10">analise o histórico, defina a meta do mês e acompanhe o caminho — marcos, ajustes e tarefas</p>
        </div>
        <div class="flex items-center gap-1.5">
          <button
            class="px-3 h-8 rounded-lg text-xs font-medium border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            :class="month === thisMonthIso() ? 'bg-n-alpha-2 font-bold' : ''"
            @click="load(thisMonthIso())"
          >
            Mês atual
          </button>
          <button
            class="px-3 h-8 rounded-lg text-xs font-medium border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            :class="month === nextMonthIso() ? 'bg-n-alpha-2 font-bold' : ''"
            @click="load(nextMonthIso())"
          >
            Próximo mês
          </button>
          <input
            :value="month ? month.slice(0, 7) : ''"
            type="month"
            class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
            style="width: 10rem"
            @change="load(`${$event.target.value}-01`)"
          />
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- ── histórico + meta por indicador ── -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1">
            Meta de {{ monthLabel(month) }}
            <span class="text-[11px] font-normal text-n-slate-9">— cada indicador mostra os últimos 12 meses pra você calibrar o alvo</span>
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
                <span class="text-[10px] text-n-slate-9">alvo:</span>
                <input
                  v-model.number="form.targets[key]"
                  type="number"
                  min="0"
                  :disabled="!isAdmin"
                  class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs font-bold text-n-slate-12 disabled:opacity-60"
                  style="width: 6rem"
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
                  :title="`${monthShort(h.month)}: ${fmtVal(key, h.values[key])}${h.targets[key] ? ` · meta ${fmtVal(key, h.targets[key])}` : ''}`"
                />
              </div>
              <div class="flex items-center justify-between mt-1">
                <span class="text-[9px] text-n-slate-9">{{ monthShort(history[0]?.month) }}</span>
                <span class="text-[9px] text-n-slate-9">{{ monthShort(history[history.length - 1]?.month) }}</span>
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
              {{ saving ? 'Salvando…' : `Salvar meta de ${monthLabel(month)}` }}
            </button>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-5">
          <!-- marcos -->
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3 flex items-center gap-2">
              <span class="i-lucide-flag text-base" style="color: #B8860B" /> Marcos do mês
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

        <!-- rotinas + ferramentas (vão pro Meu Painel do time) -->
        <div v-if="isAdmin" class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
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
