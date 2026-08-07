<script setup>
// Painel do CONSTRUTOR em modo exibição (Meu Painel): renderiza os widgets
// salvos ({key, size}) com a mesma cara do Construtor, sem edição. Os
// templates espelham o BuilderPanel — o catálogo é o mesmo
// (helper/cevicoBuilderCatalog.js).
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  SIZE_CLASS,
  paletteByKey,
  catalogMetaOf,
} from 'dashboard/helper/cevicoBuilderCatalog';

const props = defineProps({
  widgets: { type: Array, default: () => [] }, // [{ key, size }]
  palette: { type: String, default: 'cevico' },
  home: { type: Object, default: null }, // payload do CrmAPI.getHome
  goals: { type: Object, default: null }, // payload do CrmAPI.getGoalPlans
});

const route = useRoute();
const router = useRouter();

const paletteObj = computed(() => paletteByKey(props.palette));
const gradFor = idx =>
  paletteObj.value.grads[idx % paletteObj.value.grads.length];
const metaOf = catalogMetaOf;

const validWidgets = computed(() =>
  props.widgets.filter(w => metaOf(w.key).kind)
);

const kpiValue = key => {
  const meta = metaOf(key);
  let v = props.home?.[key];
  if (v === undefined || v === null) v = props.home?.panel_data?.[key];
  if (key === 'nps_satisfaction') v = props.home?.panel_data?.nps?.satisfaction;
  if (v === undefined || v === null) return meta.pct ? '—' : '0';
  return meta.pct
    ? `${Number(v).toLocaleString('pt-BR')}%`
    : Number(v).toLocaleString('pt-BR');
};

const radarAlerts = computed(
  () => props.home?.opportunity_alerts?.alerts || []
);
const myTasks = computed(() => props.home?.my_tasks?.items || []);
const nextAppointments = computed(() => props.home?.next_appointments || []);
const myResponse = computed(() => props.home?.response_goal?.mine || null);

const goalRows = computed(() => {
  const targets = props.goals?.plan?.targets || {};
  const current =
    (props.goals?.history || []).find(h => h.month === props.goals?.month)
      ?.values || {};
  return Object.entries(targets)
    .filter(([, v]) => Number(v) > 0)
    .slice(0, 4)
    .map(([key, target]) => ({
      key,
      label: props.goals?.indicators?.[key] || key,
      current: current[key] || 0,
      target: Number(target),
      pct: Math.min(
        100,
        Math.round(((current[key] || 0) / Number(target)) * 100)
      ),
    }));
});

const openDash = key => {
  const to = metaOf(key).to;
  if (!to) return;
  router.push(frontendURL(`accounts/${route.params.accountId}/${to}`));
};

const fmtDue = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
</script>

<template>
  <div class="grid grid-cols-1 sm:grid-cols-12 gap-4">
    <div
      v-for="(w, wi) in validWidgets"
      :key="w.key"
      class="relative rounded-2xl overflow-hidden"
      :class="SIZE_CLASS[w.size] || SIZE_CLASS.sm"
      style="min-height: 96px"
    >
      <!-- KPI -->
      <div
        v-if="metaOf(w.key).kind === 'kpi'"
        class="h-full p-4 text-white"
        :style="{ background: gradFor(wi) }"
      >
        <span :class="metaOf(w.key).icon" class="text-lg opacity-90" />
        <p class="text-3xl font-black leading-tight mt-1.5">
          {{ kpiValue(w.key) }}
        </p>
        <p class="text-[11px] opacity-90">{{ metaOf(w.key).label }}</p>
      </div>

      <!-- Atalho de DASHBOARD -->
      <button
        v-else-if="metaOf(w.key).kind === 'dash'"
        class="h-full w-full p-4 text-white text-left relative overflow-hidden"
        :style="{ background: gradFor(wi) }"
        @click="openDash(w.key)"
      >
        <span
          :class="metaOf(w.key).icon"
          class="absolute -right-2 -bottom-3 text-[56px] text-white/15 pointer-events-none"
        />
        <span :class="metaOf(w.key).icon" class="text-lg opacity-90" />
        <p class="text-sm font-bold leading-tight mt-1.5">
          {{ metaOf(w.key).label }}
        </p>
        <p class="text-[11px] opacity-90 mt-0.5 flex items-center gap-1">
          abrir dashboard <span class="i-lucide-arrow-right text-[10px]" />
        </p>
      </button>

      <!-- Metas do mês -->
      <div
        v-else-if="metaOf(w.key).kind === 'goals'"
        class="h-full bg-n-solid-2 border border-n-weak rounded-2xl p-4"
      >
        <p
          class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5"
        >
          <span class="i-lucide-target text-sm" style="color: #b8860b" /> Metas
          do mês
        </p>
        <div v-if="goalRows.length" class="space-y-2">
          <div v-for="g in goalRows" :key="g.key">
            <div class="flex items-center justify-between text-[11px] mb-0.5">
              <span class="text-n-slate-11 truncate">{{ g.label }}</span>
              <b class="text-n-slate-12">{{ g.current.toLocaleString('pt-BR') }}/{{
                  g.target.toLocaleString('pt-BR')
                }}</b>
            </div>
            <div class="h-2 bg-n-alpha-1 rounded-full overflow-hidden">
              <div
                class="h-full rounded-full transition-all duration-700"
                :style="{ width: `${g.pct}%`, background: gradFor(wi) }"
              />
            </div>
          </div>
        </div>
        <p v-else class="text-[11px] text-n-slate-9">
          defina as metas no Painel de Metas.
        </p>
      </div>

      <!-- Radar -->
      <div
        v-else-if="metaOf(w.key).kind === 'radar'"
        class="h-full bg-n-solid-2 border border-n-weak rounded-2xl p-4"
      >
        <p
          class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5"
        >
          <span class="i-lucide-radar text-sm" style="color: #059669" /> Radar
          de Oportunidades
        </p>
        <p v-if="!radarAlerts.length" class="text-[11px] text-n-slate-9">
          nenhum paciente quente esperando. 🎉
        </p>
        <div v-else class="space-y-1.5">
          <p class="text-2xl font-black" style="color: #059669">
            {{ radarAlerts.length }}
          </p>
          <p class="text-[11px] text-n-slate-10 -mt-1 mb-1">
            paciente(s) quente(s) sem atendimento
          </p>
          <div
            v-for="a in radarAlerts.slice(0, 3)"
            :key="a.conversation_id"
            class="text-[11px] text-n-slate-11 truncate"
          >
            • {{ a.contact_name }}
          </div>
        </div>
      </div>

      <!-- Tarefas -->
      <div
        v-else-if="metaOf(w.key).kind === 'tasks'"
        class="h-full bg-n-solid-2 border border-n-weak rounded-2xl p-4"
      >
        <p
          class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5"
        >
          <span class="i-lucide-list-checks text-sm" style="color: #b8860b" />
          Tarefas esperando você
        </p>
        <p v-if="!myTasks.length" class="text-[11px] text-n-slate-9">
          nada pendente. ✨
        </p>
        <div v-else class="space-y-1">
          <p
            v-for="t in myTasks.slice(0, 4)"
            :key="t.id"
            class="text-[11px] text-n-slate-11 truncate"
          >
            • {{ t.title }}
          </p>
        </div>
      </div>

      <!-- Próximas consultas -->
      <div
        v-else-if="metaOf(w.key).kind === 'appointments'"
        class="h-full bg-n-solid-2 border border-n-weak rounded-2xl p-4"
      >
        <p
          class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5"
        >
          <span
            class="i-lucide-calendar-range text-sm"
            style="color: #0369a1"
          />
          Próximas consultas
        </p>
        <p v-if="!nextAppointments.length" class="text-[11px] text-n-slate-9">
          nenhuma consulta futura marcada.
        </p>
        <div v-else class="space-y-1">
          <p
            v-for="a in nextAppointments.slice(0, 4)"
            :key="a.id"
            class="text-[11px] text-n-slate-11 truncate"
          >
            <b style="color: #0369a1">{{ fmtDue(a.due_at) }}</b> ·
            {{ (a.title || '').replace(/^Consulta:\s*/i, '') }}
          </p>
        </div>
      </div>

      <!-- Meta de tempo -->
      <div
        v-else-if="metaOf(w.key).kind === 'response'"
        class="h-full p-4 text-white"
        :style="{ background: gradFor(wi) }"
      >
        <span class="i-lucide-timer text-lg opacity-90" />
        <template v-if="myResponse && myResponse.replies">
          <p class="text-3xl font-black leading-tight mt-1.5">
            {{ String(myResponse.avg_minutes).replace('.', ',') }} min
          </p>
          <p class="text-[11px] opacity-90">
            meu tempo médio · {{ myResponse.within_rate }}% dentro da meta
          </p>
        </template>
        <template v-else>
          <p class="text-sm font-bold mt-1.5">Sem respostas no período</p>
          <p class="text-[11px] opacity-90">minha meta de tempo</p>
        </template>
      </div>
    </div>
  </div>
</template>
