<script setup>
// 🚪 item 420 (26/11) — PORTAL DE TERCEIROS · agenda particular de um médico.
// É a ÚNICA tela que um terceiro (ex.: a secretária particular da médica)
// abre: sem menu lateral, sem nada do sistema. Ela vê e marca só as consultas
// particulares do médico dela, nos horários que o administrador liberou.
//   · calendário do mês + os horários do dia escolhido
//   · indicadores dela (hoje, próximos 7 dias, a confirmar, comparecimento)
//   · lista do mês e "faltaram e não remarcaram"
// O administrador abre com ?as=<id> para conferir como a pessoa vê (só leitura).
// As contas da grade moram em helper/cevicoPortal.js; a trava é o servidor.
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Auth from 'dashboard/api/auth';
import CrmAPI from 'dashboard/api/crm';
import {
  spParts,
  dueAtFor,
  dowOf,
  addDays,
  addMonths,
  monthStart,
  monthEnd,
  monthGrid,
  monthLabel,
  dayLabel,
  shortDay,
  dayPlan,
  appointmentStatus,
  maskPhone,
  windowsText,
} from 'dashboard/helper/cevicoPortal';

const route = useRoute();
const router = useRouter();
const previewAs = computed(() => route.query.as || undefined);

const me = ref(null); // { third_party, preview, user, account }
const data = ref(null); // payload do período
const state = ref('loading'); // loading | ready | closed | denied | error
const isFetching = ref(false);
const isSaving = ref(false);

const now = computed(() =>
  data.value?.now ? spParts(data.value.now) : spParts(new Date())
);
const today = computed(() => data.value?.today || now.value.date);
const month = ref(monthStart(spParts(new Date()).date));
const selected = ref(spParts(new Date()).date);

const errorText = e =>
  e?.response?.data?.error ||
  'Não consegui falar com o sistema. Tente de novo.';

const load = async () => {
  isFetching.value = true;
  try {
    const { data: payload } = await CrmAPI.getPortal({
      from: month.value,
      to: monthEnd(month.value),
      as: previewAs.value,
    });
    data.value = payload;
    state.value = 'ready';
  } catch (e) {
    if (state.value !== 'ready') state.value = 'error';
    useAlert(errorText(e));
  } finally {
    isFetching.value = false;
  }
};

const boot = async () => {
  try {
    const { data: who } = await CrmAPI.getPortalMe(previewAs.value);
    me.value = who;
    if (!who.third_party) {
      state.value = 'denied';
      return;
    }
    if (!who.third_party.active) {
      state.value = 'closed';
      return;
    }
    await load();
    // abre no primeiro dia com faixa a partir de hoje
    selected.value = firstOpenDay(today.value) || today.value; // eslint-disable-line no-use-before-define
    if (monthStart(selected.value) !== month.value) {
      month.value = monthStart(selected.value);
    }
  } catch (e) {
    state.value = e?.response?.status === 403 ? 'denied' : 'error';
  }
};
onMounted(boot);
watch(month, () => {
  if (state.value === 'ready') load();
});

const isPreview = computed(() => !!(data.value?.preview || me.value?.preview));
const windows = computed(() => data.value?.windows || []);
const appointments = computed(() => data.value?.appointments || []);
const unitLabel = key =>
  (data.value?.units || []).find(u => u.key === key)?.label || key || '';
const faixasTexto = computed(() => windowsText(windows.value, unitLabel));

const planOf = date =>
  dayPlan({
    date,
    windows: windows.value,
    appointments: appointments.value,
    clinic: data.value?.clinic,
    closed: data.value?.closed,
    now: now.value,
  });
const plans = computed(() => {
  const out = {};
  monthGrid(month.value)
    .flat()
    .filter(Boolean)
    .forEach(date => {
      out[date] = planOf(date);
    });
  return out;
});
const weeks = computed(() => monthGrid(month.value));
const plan = computed(
  () => plans.value[selected.value] || planOf(selected.value)
);

function firstOpenDay(from) {
  const dows = new Set(windows.value.map(w => Number(w.dow)));
  if (!dows.size) return null;
  for (let i = 0, day = from; i < 62; i += 1, day = addDays(day, 1)) {
    if (dows.has(dowOf(day))) return day;
  }
  return null;
}

const pickDay = date => {
  if (!date) return;
  selected.value = date;
};
const goMonth = step => {
  month.value = addMonths(month.value, step);
  const first = monthStart(month.value);
  selected.value =
    monthStart(today.value) === first ? today.value : firstOpenInMonth(first); // eslint-disable-line no-use-before-define
};
function firstOpenInMonth(first) {
  const day = firstOpenDay(first);
  return day && monthStart(day) === first ? day : first;
}
const goToday = () => {
  month.value = monthStart(today.value);
  selected.value = today.value;
};

// ── indicadores ─────────────────────────────────────────────────────────
const ind = computed(() => data.value?.indicators || {});
const cards = computed(() => [
  {
    key: 'today',
    label: 'Hoje',
    value: ind.value.today ?? 0,
    hint: ind.value.today === 1 ? 'paciente marcado' : 'pacientes marcados',
    icon: 'i-lucide-sun',
  },
  {
    key: 'next7',
    label: 'Próximos 7 dias',
    value: ind.value.next7 ?? 0,
    hint: 'consultas na agenda',
    icon: 'i-lucide-calendar-range',
  },
  {
    key: 'to_confirm',
    label: 'A confirmar',
    value: ind.value.to_confirm ?? 0,
    hint: 'dos próximos 7 dias, ainda sem confirmação',
    icon: 'i-lucide-phone-call',
    warn: (ind.value.to_confirm ?? 0) > 0,
  },
  {
    key: 'show',
    label: 'Comparecimento',
    value: ind.value.show_rate30 == null ? '—' : `${ind.value.show_rate30}%`,
    hint: `30 dias · ${ind.value.attended30 ?? 0} vieram · ${ind.value.missed30 ?? 0} faltaram`,
    icon: 'i-lucide-user-check',
  },
]);

// ── lista do mês ────────────────────────────────────────────────────────
const timeOf = a => spParts(a.due_at).time;
const dateOf = a => spParts(a.due_at).date;
const statusOf = a => appointmentStatus(a, now.value);
const monthList = computed(() =>
  appointments.value
    .filter(a => !a.canceled_at)
    .slice()
    .sort((a, b) => new Date(a.due_at) - new Date(b.due_at))
);
const canceledList = computed(() =>
  appointments.value.filter(a => a.canceled_at)
);
const showCanceled = ref(false);
const isPast = a => {
  const p = spParts(a.due_at);
  return (
    p.date < now.value.date ||
    (p.date === now.value.date && p.time <= now.value.time)
  );
};

// ── formulário (marcar / editar / remarcar) ─────────────────────────────
const form = ref(null); // { id?, name, phone, description, date, time, unit, title }
const freeTimes = computed(() => {
  if (!form.value?.date) return [];
  const p = planOf(form.value.date);
  const list = p.groups.flatMap(g =>
    g.slots
      .filter(
        s =>
          s.state === 'free' ||
          (form.value.id && s.appointment?.id === form.value.id)
      )
      .map(s => ({ time: s.time, unit: s.unit }))
  );
  return list;
});
const formDayNote = computed(() => {
  if (!form.value?.date) return '';
  const p = planOf(form.value.date);
  if (!p.hasWindow)
    return 'Este dia da semana não está liberado para o seu acesso.';
  if (p.closed) return p.groups[0]?.reason || 'A clínica fechou esse dia.';
  if (!freeTimes.value.length) return 'Não há horário livre neste dia.';
  return '';
});
const needsMonth = date => monthStart(date) !== month.value;
watch(
  () => form.value?.date,
  date => {
    if (!date || !form.value) return;
    // o formulário pode escolher um dia de outro mês: a grade acompanha
    if (needsMonth(date)) month.value = monthStart(date);
    if (!freeTimes.value.some(t => t.time === form.value.time)) {
      form.value.time = freeTimes.value[0]?.time || '';
    }
  }
);
watch(freeTimes, list => {
  if (form.value && !list.some(t => t.time === form.value.time)) {
    form.value.time = list[0]?.time || '';
  }
});

const openNew = (date, time, preset = {}) => {
  if (isPreview.value) return;
  form.value = {
    id: null,
    name: preset.name || '',
    phone: maskPhone(preset.phone || ''),
    description: '',
    date: date || selected.value,
    time: time || '',
    title: 'Marcar consulta',
  };
};
const openEdit = a => {
  if (isPreview.value) return;
  form.value = {
    id: a.id,
    name: a.name || '',
    phone: maskPhone(a.phone || ''),
    description: a.description || '',
    date: dateOf(a),
    time: timeOf(a),
    title: 'Editar ou remarcar',
    history: a.history || [],
  };
};
const closeForm = () => {
  form.value = null;
};

const replaceAppointment = saved => {
  if (!data.value) return;
  const list = data.value.appointments || [];
  const at = list.findIndex(a => a.id === saved.id);
  if (at >= 0) list.splice(at, 1, saved);
  else list.push(saved);
  data.value = { ...data.value, appointments: [...list] };
};

const save = async () => {
  const f = form.value;
  if (!f || isSaving.value) return;
  if (f.name.trim().length < 2) {
    useAlert('Escreva o nome do paciente.');
    return;
  }
  if (!f.date || !f.time) {
    useAlert('Escolha o dia e o horário.');
    return;
  }
  const unit = freeTimes.value.find(t => t.time === f.time)?.unit;
  const body = {
    name: f.name.trim(),
    phone: f.phone.trim(),
    description: f.description.trim(),
    due_at: dueAtFor(f.date, f.time),
    unit,
  };
  isSaving.value = true;
  try {
    if (f.id) await CrmAPI.updatePortalAppointment(f.id, body);
    else await CrmAPI.createPortalAppointment(body);
    useAlert(f.id ? 'Consulta atualizada.' : 'Consulta marcada.');
    selected.value = f.date;
    form.value = null;
    await load(); // traz também os indicadores novos
  } catch (e) {
    useAlert(errorText(e));
  } finally {
    isSaving.value = false;
  }
};

const patch = async (a, body, done) => {
  if (isPreview.value || isSaving.value) return;
  isSaving.value = true;
  try {
    const { data: saved } = await CrmAPI.updatePortalAppointment(a.id, body);
    replaceAppointment(saved);
    if (done) useAlert(done);
    load();
  } catch (e) {
    useAlert(errorText(e));
  } finally {
    isSaving.value = false;
  }
};
const toggleConfirm = a =>
  patch(
    a,
    { confirmed: !a.confirmed_at },
    a.confirmed_at ? 'Confirmação desfeita.' : 'Consulta confirmada.'
  );
const setAttendance = (a, value) =>
  patch(a, { attendance: a.attendance === value ? '' : value });
const cancelAsk = ref(null);
const cancel = async a => {
  cancelAsk.value = null;
  await patch(a, { canceled: true }, 'Consulta cancelada.');
};
const restore = a => patch(a, { canceled: false }, 'Consulta reativada.');

const logout = () => Auth.logout();
const backToAccess = () =>
  router.push(`/app/accounts/${route.params.accountId}/settings/acessos`);
const firstName = computed(
  () => String(me.value?.user?.name || '').split(' ')[0]
);
const telHref = phone => `tel:${String(phone || '').replace(/[^\d+]/g, '')}`;
const STATUS_CLASS = {
  confirmed: 'pt-chip-ok',
  attended: 'pt-chip-ok',
  pending: 'pt-chip-warn',
  unmarked: 'pt-chip-mute',
  missed: 'pt-chip-bad',
  canceled: 'pt-chip-mute',
};
</script>

<template>
  <div class="pt-root h-full w-full overflow-y-auto bg-n-background">
    <div class="mx-auto w-full max-w-5xl px-4 pb-16 pt-5 sm:px-8 sm:pt-8">
      <!-- barra do topo: marca + quem está logado -->
      <header class="flex items-center justify-between gap-3">
        <div class="flex min-w-0 items-center gap-3">
          <span class="pt-logo"><span class="i-lucide-calendar-heart" /></span>
          <div class="min-w-0">
            <p class="truncate text-sm font-bold leading-tight text-n-slate-12">
              {{ me?.account?.name || 'Portal' }}
            </p>
            <p class="text-xs leading-tight text-n-slate-11">
              Portal de acesso restrito
            </p>
          </div>
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <span
            v-if="firstName"
            class="hidden text-sm text-n-slate-11 sm:inline"
          >
            Olá, {{ firstName }}
          </span>
          <!-- conferindo o portal de alguém: "Sair" encerraria a sessão do próprio administrador -->
          <button
            v-if="previewAs"
            type="button"
            class="pt-btn pt-btn-ghost"
            @click="backToAccess"
          >
            <span class="i-lucide-arrow-left" />Voltar
          </button>
          <button
            v-else
            type="button"
            class="pt-btn pt-btn-ghost"
            @click="logout"
          >
            <span class="i-lucide-log-out" />Sair
          </button>
        </div>
      </header>

      <!-- estados de entrada -->
      <div v-if="state === 'loading'" class="pt-empty">
        <span class="i-lucide-loader-circle animate-spin text-2xl" />
        <p>Abrindo a sua agenda…</p>
      </div>
      <div v-else-if="state === 'closed'" class="pt-empty">
        <span class="i-lucide-lock text-3xl" />
        <h1 class="text-xl font-bold text-n-slate-12">Acesso encerrado</h1>
        <p>
          Este acesso foi encerrado pela clínica. Fale com a clínica para
          reabrir.
        </p>
      </div>
      <div v-else-if="state === 'denied'" class="pt-empty">
        <span class="i-lucide-shield-alert text-3xl" />
        <h1 class="text-xl font-bold text-n-slate-12">Área restrita</h1>
        <p>Esta página é só para acessos de terceiros.</p>
      </div>
      <div v-else-if="state === 'error'" class="pt-empty">
        <span class="i-lucide-cloud-off text-3xl" />
        <p>Não consegui abrir a agenda agora.</p>
        <button type="button" class="pt-btn pt-btn-main" @click="boot">
          Tentar de novo
        </button>
      </div>

      <template v-else>
        <!-- título em duas cores, uma frase por linha -->
        <section class="mt-8 sm:mt-10">
          <h1 class="pt-title">
            <span class="block text-n-slate-12">Agenda particular</span>
            <span class="block pt-blue">{{ data.doctor }}</span>
          </h1>
          <p class="mt-3 text-sm leading-relaxed text-n-slate-11">
            {{ data.label || 'Acesso de terceiros' }} · você vê e marca só as
            consultas particulares deste médico.
          </p>
          <ul v-if="faixasTexto.length" class="mt-3 flex flex-wrap gap-2">
            <li v-for="txt in faixasTexto" :key="txt" class="pt-pill">
              <span class="i-lucide-clock-3" />{{ txt }}
            </li>
          </ul>
          <p v-else class="pt-strip pt-strip-warn mt-4">
            <span class="i-lucide-triangle-alert" />
            A clínica ainda não liberou horários para o seu acesso. Fale com a
            clínica.
          </p>
          <p v-if="isPreview" class="pt-strip pt-strip-info mt-4">
            <span class="i-lucide-eye" />
            Você está conferindo como esta pessoa vê o portal. Aqui é só
            leitura: quem marca é a própria pessoa.
          </p>
        </section>

        <!-- indicadores -->
        <section class="pt-cards mt-8">
          <article
            v-for="c in cards"
            :key="c.key"
            class="pt-card"
            :class="c.warn ? 'pt-card-warn' : ''"
          >
            <div
              class="flex items-center gap-2 text-xs font-semibold text-n-slate-11"
            >
              <span :class="c.icon" class="pt-blue text-sm" />{{ c.label }}
            </div>
            <p class="pt-card-num">{{ c.value }}</p>
            <p class="text-xs leading-snug text-n-slate-11">{{ c.hint }}</p>
          </article>
        </section>

        <!-- calendário + dia -->
        <section
          class="mt-10 grid gap-6 lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]"
        >
          <div class="pt-panel">
            <div class="flex items-center justify-between gap-2">
              <h2 class="pt-h2 first-letter:uppercase">
                {{ monthLabel(month) }}
              </h2>
              <div class="flex items-center gap-1.5">
                <button
                  type="button"
                  class="pt-btn pt-btn-ghost"
                  @click="goToday"
                >
                  Hoje
                </button>
                <button
                  type="button"
                  class="pt-icon"
                  aria-label="Mês anterior"
                  @click="goMonth(-1)"
                >
                  <span class="i-lucide-chevron-left" />
                </button>
                <button
                  type="button"
                  class="pt-icon"
                  aria-label="Próximo mês"
                  @click="goMonth(1)"
                >
                  <span class="i-lucide-chevron-right" />
                </button>
              </div>
            </div>
            <div
              class="pt-week mt-4 text-[11px] font-semibold uppercase text-n-slate-10"
            >
              <span
                v-for="d in ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb']"
                :key="d"
              >
                {{ d }}
              </span>
            </div>
            <div class="mt-1 space-y-1" :class="isFetching ? 'opacity-60' : ''">
              <div v-for="(week, wi) in weeks" :key="wi" class="pt-week">
                <template v-for="(day, di) in week" :key="`${wi}-${di}`">
                  <span v-if="!day" />
                  <button
                    v-else
                    type="button"
                    class="pt-day"
                    :class="{
                      'pt-day-on': day === selected,
                      'pt-day-open':
                        day >= today &&
                        plans[day]?.hasWindow &&
                        !plans[day]?.closed,
                      'pt-day-today': day === today,
                    }"
                    @click="pickDay(day)"
                  >
                    <span class="pt-day-num">{{ Number(day.slice(8)) }}</span>
                    <span
                      v-if="plans[day]?.mine"
                      class="pt-day-badge"
                      :title="`${plans[day].mine} marcada(s)`"
                    >
                      {{ plans[day].mine }}
                    </span>
                    <span
                      v-else-if="plans[day]?.closed"
                      class="i-lucide-lock text-[10px] text-n-slate-10"
                    />
                    <span v-else-if="plans[day]?.free" class="pt-day-free">
                      {{ plans[day].free }} livre{{
                        plans[day].free > 1 ? 's' : ''
                      }}
                    </span>
                  </button>
                </template>
              </div>
            </div>
            <p
              class="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-n-slate-11"
            >
              <span class="pt-leg">
                <i class="pt-dot pt-dot-blue" />
                dia com horário liberado
              </span>
              <span class="pt-leg">
                <i class="pt-dot pt-dot-badge" />
                consultas marcadas por aqui
              </span>
            </p>
          </div>

          <div class="pt-panel">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h2 class="pt-h2 first-letter:uppercase">
                  {{ dayLabel(selected) }}
                </h2>
                <p class="mt-0.5 text-xs text-n-slate-11">
                  <template v-if="!plan.hasWindow">
                    sem horário liberado neste dia
                  </template>
                  <template v-else-if="plan.closed">
                    agenda fechada pela clínica
                  </template>
                  <template v-else>
                    {{ plan.mine }} marcada{{ plan.mine === 1 ? '' : 's' }} ·
                    {{ plan.free }} livre{{ plan.free === 1 ? '' : 's' }}
                  </template>
                </p>
              </div>
              <button
                v-if="!isPreview && plan.free > 0"
                type="button"
                class="pt-btn pt-btn-main shrink-0"
                @click="openNew(selected, '')"
              >
                <span class="i-lucide-plus" />Marcar
              </button>
            </div>

            <div
              v-if="!plan.hasWindow && !plan.extras.length"
              class="pt-empty-sm"
            >
              <span class="i-lucide-calendar-off text-xl" />
              <p>Escolha no calendário um dia em azul.</p>
            </div>

            <div
              v-for="group in plan.groups"
              :key="`${group.unit}-${group.win.start}`"
              class="mt-5"
            >
              <p
                class="flex items-center gap-1.5 text-xs font-semibold text-n-slate-11"
              >
                <span class="i-lucide-map-pin text-sm" />{{
                  unitLabel(group.unit)
                }}
                · {{ group.win.start }} às {{ group.win.end }}
              </p>
              <p v-if="group.reason" class="pt-strip pt-strip-warn mt-2">
                <span class="i-lucide-lock" />{{ group.reason }}
              </p>
              <ul class="mt-2 space-y-2">
                <li
                  v-for="slot in group.slots"
                  :key="slot.time"
                  class="pt-slot"
                  :class="`pt-slot-${slot.state}`"
                >
                  <span class="pt-slot-time">{{ slot.time }}</span>

                  <!-- consulta do portal -->
                  <div v-if="slot.state === 'mine'" class="min-w-0 flex-1">
                    <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                      <b class="break-words text-sm text-n-slate-12">
                        {{ slot.appointment.name }}
                      </b>
                      <span
                        class="pt-chip"
                        :class="STATUS_CLASS[statusOf(slot.appointment).key]"
                      >
                        {{ statusOf(slot.appointment).label }}
                      </span>
                    </div>
                    <a
                      v-if="slot.appointment.phone"
                      :href="telHref(slot.appointment.phone)"
                      class="mt-0.5 inline-flex items-center gap-1 text-xs text-n-slate-11 hover:underline"
                    >
                      <span class="i-lucide-phone text-[11px]" />{{
                        maskPhone(slot.appointment.phone)
                      }}
                    </a>
                    <p
                      v-if="slot.appointment.description"
                      class="mt-1 whitespace-pre-line break-words text-xs leading-snug text-n-slate-11"
                    >
                      {{ slot.appointment.description }}
                    </p>
                    <div v-if="!isPreview" class="mt-2 flex flex-wrap gap-1.5">
                      <template v-if="isPast(slot.appointment)">
                        <button
                          type="button"
                          class="pt-mini"
                          :class="
                            slot.appointment.attendance === 'attended'
                              ? 'pt-mini-on'
                              : ''
                          "
                          @click="setAttendance(slot.appointment, 'attended')"
                        >
                          <span class="i-lucide-check" />Compareceu
                        </button>
                        <button
                          type="button"
                          class="pt-mini"
                          :class="
                            slot.appointment.attendance === 'missed'
                              ? 'pt-mini-bad'
                              : ''
                          "
                          @click="setAttendance(slot.appointment, 'missed')"
                        >
                          <span class="i-lucide-user-x" />Faltou
                        </button>
                      </template>
                      <button
                        v-else
                        type="button"
                        class="pt-mini"
                        :class="
                          slot.appointment.confirmed_at ? 'pt-mini-on' : ''
                        "
                        @click="toggleConfirm(slot.appointment)"
                      >
                        <span class="i-lucide-check-check" />
                        {{
                          slot.appointment.confirmed_at
                            ? 'Confirmada'
                            : 'Confirmar'
                        }}
                      </button>
                      <button
                        type="button"
                        class="pt-mini"
                        @click="openEdit(slot.appointment)"
                      >
                        <span class="i-lucide-pencil" />Editar ou remarcar
                      </button>
                      <button
                        v-if="cancelAsk !== slot.appointment.id"
                        type="button"
                        class="pt-mini"
                        @click="cancelAsk = slot.appointment.id"
                      >
                        <span class="i-lucide-x" />Cancelar
                      </button>
                      <template v-else>
                        <button
                          type="button"
                          class="pt-mini pt-mini-bad"
                          @click="cancel(slot.appointment)"
                        >
                          Sim, cancelar
                        </button>
                        <button
                          type="button"
                          class="pt-mini"
                          @click="cancelAsk = null"
                        >
                          Não
                        </button>
                      </template>
                    </div>
                  </div>

                  <!-- particular marcada pela clínica: só o nome -->
                  <div
                    v-else-if="slot.state === 'private'"
                    class="min-w-0 flex-1"
                  >
                    <b class="break-words text-sm text-n-slate-12">{{
                      slot.clinic.name
                    }}</b>
                    <p class="text-xs text-n-slate-11">
                      particular marcada pela clínica · para mudar, fale com a
                      clínica
                    </p>
                  </div>
                  <p
                    v-else-if="slot.state === 'busy'"
                    class="flex-1 text-sm text-n-slate-11"
                  >
                    Ocupado · paciente da clínica
                  </p>
                  <p
                    v-else-if="slot.state === 'locked'"
                    class="flex-1 text-sm text-n-slate-11"
                  >
                    Fechado pela clínica
                  </p>
                  <p
                    v-else-if="slot.state === 'past'"
                    class="flex-1 text-sm text-n-slate-10"
                  >
                    —
                  </p>
                  <template v-else>
                    <p class="flex-1 text-sm text-n-slate-11">Livre</p>
                    <button
                      v-if="!isPreview"
                      type="button"
                      class="pt-btn pt-btn-soft shrink-0"
                      @click="openNew(selected, slot.time)"
                    >
                      Marcar
                    </button>
                  </template>
                </li>
              </ul>
            </div>

            <!-- consultas do portal fora das faixas de hoje -->
            <div v-if="plan.extras.length" class="mt-5">
              <p class="text-xs font-semibold text-n-slate-11">
                Fora das faixas liberadas
              </p>
              <ul class="mt-2 space-y-2">
                <li
                  v-for="a in plan.extras"
                  :key="a.id"
                  class="pt-slot pt-slot-mine"
                >
                  <span class="pt-slot-time">{{ timeOf(a) }}</span>
                  <div class="min-w-0 flex-1">
                    <b class="break-words text-sm text-n-slate-12">{{
                      a.name
                    }}</b>
                    <p class="text-xs text-n-slate-11">
                      {{ unitLabel(a.unit) }} · {{ statusOf(a).label }}
                    </p>
                    <div v-if="!isPreview" class="mt-2 flex flex-wrap gap-1.5">
                      <button
                        type="button"
                        class="pt-mini"
                        @click="openEdit(a)"
                      >
                        <span class="i-lucide-pencil" />Editar ou remarcar
                      </button>
                    </div>
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </section>

        <!-- lista do mês -->
        <section class="pt-panel mt-10">
          <h2 class="pt-h2">
            Consultas de <span class="pt-blue">{{ monthLabel(month) }}</span>
          </h2>
          <p class="mt-0.5 text-xs text-n-slate-11">
            tudo o que foi marcado por este portal neste mês, na ordem do
            calendário
          </p>
          <div v-if="!monthList.length" class="pt-empty-sm">
            <span class="i-lucide-calendar-plus text-xl" />
            <p>Nenhuma consulta marcada neste mês.</p>
          </div>
          <ul v-else class="mt-4 divide-y divide-n-weak">
            <li
              v-for="a in monthList"
              :key="a.id"
              class="flex flex-wrap items-center gap-x-4 gap-y-1 py-3"
            >
              <button
                type="button"
                class="pt-when"
                :title="dayLabel(dateOf(a))"
                @click="pickDay(dateOf(a))"
              >
                <b>{{ shortDay(dateOf(a)) }}</b>
                <span>{{ timeOf(a) }}</span>
              </button>
              <div class="min-w-0 flex-1">
                <p class="break-words text-sm font-semibold text-n-slate-12">
                  {{ a.name }}
                </p>
                <p class="text-xs text-n-slate-11">
                  {{ unitLabel(a.unit) }}
                  <span v-if="a.phone" class="whitespace-nowrap">
                    · {{ maskPhone(a.phone) }}
                  </span>
                </p>
              </div>
              <span class="pt-chip" :class="STATUS_CLASS[statusOf(a).key]">
                {{ statusOf(a).label }}
              </span>
            </li>
          </ul>

          <div v-if="canceledList.length" class="mt-4">
            <button
              type="button"
              class="text-xs font-semibold text-n-slate-11 hover:underline"
              @click="showCanceled = !showCanceled"
            >
              {{ showCanceled ? 'Esconder' : 'Ver' }} canceladas ({{
                canceledList.length
              }})
            </button>
            <ul v-if="showCanceled" class="mt-2 divide-y divide-n-weak">
              <li
                v-for="a in canceledList"
                :key="a.id"
                class="flex flex-wrap items-center gap-x-4 gap-y-1 py-2.5"
              >
                <span class="pt-when opacity-60">
                  <b>{{ shortDay(dateOf(a)) }}</b>
                  <span>{{ timeOf(a) }}</span>
                </span>
                <p
                  class="min-w-0 flex-1 break-words text-sm text-n-slate-11 line-through"
                >
                  {{ a.name }}
                </p>
                <button
                  v-if="!isPreview"
                  type="button"
                  class="pt-mini"
                  @click="restore(a)"
                >
                  <span class="i-lucide-undo-2" />Reativar
                </button>
              </li>
            </ul>
          </div>
        </section>

        <!-- faltaram e não remarcaram -->
        <section
          v-if="(ind.missed_no_return || []).length"
          class="pt-panel mt-10"
        >
          <h2 class="pt-h2">
            Faltaram e <span class="pt-blue">não remarcaram</span>
          </h2>
          <p class="mt-0.5 text-xs text-n-slate-11">
            faltas dos últimos 60 dias sem uma nova consulta marcada: vale uma
            ligação
          </p>
          <ul class="mt-4 divide-y divide-n-weak">
            <li
              v-for="row in ind.missed_no_return"
              :key="row.id"
              class="flex flex-wrap items-center gap-x-4 gap-y-1 py-3"
            >
              <div class="min-w-0 flex-1">
                <p class="break-words text-sm font-semibold text-n-slate-12">
                  {{ row.name }}
                </p>
                <p class="text-xs text-n-slate-11">
                  faltou em {{ shortDay(spParts(row.due_at).date) }}
                  <template v-if="row.phone">
                    · {{ maskPhone(row.phone) }}
                  </template>
                </p>
              </div>
              <a v-if="row.phone" :href="telHref(row.phone)" class="pt-mini">
                <span class="i-lucide-phone" />Ligar
              </a>
              <button
                v-if="!isPreview"
                type="button"
                class="pt-mini"
                @click="openNew(firstOpenDay(today) || today, '', row)"
              >
                <span class="i-lucide-calendar-plus" />Remarcar
              </button>
            </li>
          </ul>
        </section>

        <p
          class="mt-10 text-center text-[11px] leading-relaxed text-n-slate-10"
        >
          Acesso restrito e registrado: cada consulta guarda quem marcou, mudou
          ou cancelou.
        </p>
      </template>
    </div>

    <!-- formulário -->
    <div v-if="form" class="pt-overlay" @click.self="closeForm">
      <form class="pt-modal" @submit.prevent="save">
        <div class="pt-modal-bar" />
        <div
          class="flex items-start justify-between gap-3 px-5 pt-5 sm:px-7 sm:pt-6"
        >
          <div>
            <h2 class="text-lg font-bold text-n-slate-12">{{ form.title }}</h2>
            <p class="text-xs text-n-slate-11">
              consulta particular · {{ data.doctor }}
            </p>
          </div>
          <button
            type="button"
            class="pt-icon"
            aria-label="Fechar"
            @click="closeForm"
          >
            <span class="i-lucide-x" />
          </button>
        </div>
        <div class="space-y-4 overflow-y-auto px-5 py-5 sm:px-7">
          <label class="block">
            <span class="pt-label">Nome do paciente</span>
            <input
              v-model="form.name"
              type="text"
              class="pt-input"
              maxlength="120"
              autocomplete="off"
              placeholder="Nome completo"
            />
          </label>
          <label class="block">
            <span class="pt-label">Telefone (com DDD)</span>
            <input
              :value="form.phone"
              type="tel"
              inputmode="tel"
              class="pt-input"
              autocomplete="off"
              placeholder="(11) 90000-0000"
              @input="form.phone = maskPhone($event.target.value)"
            />
          </label>
          <div class="grid gap-4 sm:grid-cols-2">
            <label class="block">
              <span class="pt-label">Dia</span>
              <input
                v-model="form.date"
                type="date"
                class="pt-input"
                :min="today"
              />
            </label>
            <label class="block">
              <span class="pt-label">Horário</span>
              <select
                v-model="form.time"
                class="pt-input"
                :disabled="!freeTimes.length"
              >
                <option v-if="!freeTimes.length" value="">sem horário</option>
                <option
                  v-for="t in freeTimes"
                  :key="`${t.unit}-${t.time}`"
                  :value="t.time"
                >
                  {{ t.time }} · {{ unitLabel(t.unit) }}
                </option>
              </select>
            </label>
          </div>
          <p v-if="formDayNote" class="pt-strip pt-strip-warn">
            <span class="i-lucide-triangle-alert" />{{ formDayNote }}
          </p>
          <label class="block">
            <span class="pt-label">Observação (opcional)</span>
            <textarea
              v-model="form.description"
              rows="3"
              maxlength="1000"
              class="pt-input"
              placeholder="Ex.: primeira consulta, retorno, traz exames"
            />
          </label>
          <div
            v-if="form.history?.length"
            class="rounded-xl border border-n-weak p-3"
          >
            <p class="pt-label">Histórico</p>
            <ul class="mt-1 space-y-1 text-xs leading-snug text-n-slate-11">
              <li v-for="(h, i) in form.history" :key="i">
                {{
                  h.at
                    ? `${shortDay(spParts(h.at).date)} ${spParts(h.at).time} · `
                    : ''
                }}{{ h.text }}
              </li>
            </ul>
          </div>
        </div>
        <div
          class="flex justify-end gap-2 border-t border-n-weak px-5 py-4 sm:px-7"
        >
          <button type="button" class="pt-btn pt-btn-ghost" @click="closeForm">
            Voltar
          </button>
          <button
            type="submit"
            class="pt-btn pt-btn-main"
            :disabled="isSaving || !form.time"
          >
            <span v-if="isSaving" class="i-lucide-loader-circle animate-spin" />
            {{ form.id ? 'Salvar' : 'Marcar consulta' }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>

<style scoped>
/* portal de terceiros: azul royal nas ações (regra da casa para tela nova),
   bastante respiro, cantos redondos; as cores neutras seguem o tema (claro/escuro) */
.pt-root {
  --pt: #2563eb;
  --pt-deep: #1d4ed8;
  --pt-rgb: 37 99 235;
}
.pt-blue {
  color: var(--pt);
}
.pt-logo {
  display: grid;
  place-items: center;
  width: 2.75rem;
  height: 2.75rem;
  flex-shrink: 0;
  border-radius: 0.9rem;
  background: linear-gradient(135deg, var(--pt-deep), #3b82f6);
  color: #fff;
  font-size: 1.25rem;
  box-shadow: 0 6px 16px rgb(var(--pt-rgb) / 0.28);
}
.pt-title {
  font-size: clamp(1.75rem, 5.2vw, 2.6rem);
  font-weight: 800;
  line-height: 1.08;
  letter-spacing: -0.02em;
}
.pt-h2 {
  font-size: 1.125rem;
  font-weight: 700;
  letter-spacing: -0.01em;
  color: rgb(var(--slate-12));
}
.pt-pill {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
  border-radius: 999px;
  border: 1px solid rgb(var(--pt-rgb) / 0.25);
  background: rgb(var(--pt-rgb) / 0.07);
  padding: 0.3rem 0.75rem;
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--pt);
}
.pt-panel {
  border-radius: 1.25rem;
  border: 1px solid rgb(var(--slate-6) / 0.6);
  background: rgb(var(--solid-1, 255 255 255) / 0.6);
  padding: 1.25rem;
}
@media (min-width: 640px) {
  .pt-panel {
    padding: 1.75rem;
  }
}
.pt-cards {
  display: grid;
  gap: 0.75rem;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
}
.pt-card {
  border-radius: 1.1rem;
  border: 1px solid rgb(var(--slate-6) / 0.6);
  background: rgb(var(--solid-1, 255 255 255) / 0.6);
  padding: 1rem 1.1rem;
}
.pt-card-warn {
  border-color: rgb(217 119 6 / 0.45);
  background: rgb(217 119 6 / 0.06);
}
.pt-card-num {
  margin: 0.35rem 0 0.15rem;
  font-size: 2rem;
  font-weight: 800;
  line-height: 1;
  letter-spacing: -0.02em;
  white-space: nowrap;
  color: rgb(var(--slate-12));
}
.pt-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.375rem;
  border-radius: 0.75rem;
  padding: 0.5rem 0.9rem;
  font-size: 0.8125rem;
  font-weight: 600;
  line-height: 1.2;
  transition:
    background 0.15s,
    opacity 0.15s;
}
.pt-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.pt-btn-main {
  background: linear-gradient(135deg, var(--pt-deep), #3b82f6);
  color: #fff;
  box-shadow: 0 4px 12px rgb(var(--pt-rgb) / 0.25);
}
.pt-btn-soft {
  background: rgb(var(--pt-rgb) / 0.1);
  color: var(--pt);
}
.pt-btn-soft:hover {
  background: rgb(var(--pt-rgb) / 0.18);
}
.pt-btn-ghost {
  border: 1px solid rgb(var(--slate-6) / 0.8);
  color: rgb(var(--slate-12));
}
.pt-btn-ghost:hover {
  background: rgb(var(--slate-4) / 0.6);
}
.pt-icon {
  display: grid;
  place-items: center;
  width: 2.1rem;
  height: 2.1rem;
  border-radius: 0.7rem;
  border: 1px solid rgb(var(--slate-6) / 0.8);
  color: rgb(var(--slate-12));
}
.pt-icon:hover {
  background: rgb(var(--slate-4) / 0.6);
}
.pt-week {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  gap: 0.25rem;
  text-align: center;
}
.pt-day {
  display: flex;
  min-height: 3.4rem;
  flex-direction: column;
  align-items: center;
  justify-content: flex-start;
  gap: 0.15rem;
  border-radius: 0.8rem;
  border: 1px solid transparent;
  padding: 0.35rem 0.1rem;
  color: rgb(var(--slate-10));
}
.pt-day:hover {
  background: rgb(var(--slate-4) / 0.5);
}
.pt-day-num {
  font-size: 0.875rem;
  font-weight: 600;
  line-height: 1.2;
}
.pt-day-open {
  background: rgb(var(--pt-rgb) / 0.07);
  color: rgb(var(--slate-12));
}
.pt-day-open:hover {
  background: rgb(var(--pt-rgb) / 0.14);
}
.pt-day-today .pt-day-num {
  text-decoration: underline;
  text-decoration-thickness: 2px;
  text-underline-offset: 3px;
  text-decoration-color: var(--pt);
}
.pt-day-on {
  border-color: var(--pt);
  background: rgb(var(--pt-rgb) / 0.16);
  color: rgb(var(--slate-12));
}
.pt-day-badge {
  min-width: 1.25rem;
  border-radius: 999px;
  background: var(--pt);
  padding: 0 0.3rem;
  font-size: 0.6875rem;
  font-weight: 700;
  line-height: 1.25rem;
  color: #fff;
}
.pt-day-free {
  font-size: 0.625rem;
  font-weight: 600;
  line-height: 1.1;
  color: var(--pt);
}
.pt-leg {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}
.pt-dot {
  display: inline-block;
  width: 0.6rem;
  height: 0.6rem;
  flex-shrink: 0;
  border-radius: 999px;
}
.pt-dot-blue {
  background: rgb(var(--pt-rgb) / 0.25);
}
.pt-dot-badge {
  background: var(--pt);
}
.pt-slot {
  display: flex;
  align-items: flex-start;
  gap: 0.85rem;
  border-radius: 0.9rem;
  border: 1px solid rgb(var(--slate-6) / 0.6);
  padding: 0.7rem 0.85rem;
}
.pt-slot-time {
  min-width: 2.9rem;
  font-size: 0.9375rem;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-12));
}
.pt-slot-free {
  align-items: center;
  border-style: dashed;
  border-color: rgb(var(--pt-rgb) / 0.4);
}
.pt-slot-mine {
  border-color: rgb(var(--pt-rgb) / 0.45);
  background: rgb(var(--pt-rgb) / 0.06);
}
.pt-slot-busy,
.pt-slot-locked,
.pt-slot-past {
  align-items: center;
  background: rgb(var(--slate-4) / 0.35);
}
.pt-slot-past .pt-slot-time {
  color: rgb(var(--slate-10));
}
.pt-chip {
  display: inline-flex;
  align-items: center;
  border-radius: 999px;
  padding: 0.1rem 0.55rem;
  font-size: 0.6875rem;
  font-weight: 700;
  white-space: nowrap;
}
.pt-chip-ok {
  background: rgb(5 150 105 / 0.14);
  color: #059669;
}
.pt-chip-warn {
  background: rgb(217 119 6 / 0.14);
  color: #b45309;
}
.pt-chip-bad {
  background: rgb(220 38 38 / 0.12);
  color: #dc2626;
}
.pt-chip-mute {
  background: rgb(var(--slate-5) / 0.8);
  color: rgb(var(--slate-11));
}
.pt-mini {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  border-radius: 0.6rem;
  border: 1px solid rgb(var(--slate-6) / 0.9);
  padding: 0.3rem 0.6rem;
  font-size: 0.75rem;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.pt-mini:hover {
  background: rgb(var(--slate-4) / 0.6);
}
.pt-mini-on {
  border-color: rgb(5 150 105 / 0.5);
  background: rgb(5 150 105 / 0.12);
  color: #059669;
}
.pt-mini-bad {
  border-color: rgb(220 38 38 / 0.5);
  background: rgb(220 38 38 / 0.1);
  color: #dc2626;
}
.pt-when {
  display: flex;
  min-width: 3.4rem;
  flex-direction: column;
  align-items: flex-start;
  font-size: 0.75rem;
  font-variant-numeric: tabular-nums;
  line-height: 1.25;
  color: rgb(var(--slate-11));
}
.pt-when b {
  font-size: 0.9375rem;
  color: rgb(var(--slate-12));
}
.pt-strip {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  border-radius: 0.8rem;
  padding: 0.6rem 0.8rem;
  font-size: 0.75rem;
  line-height: 1.4;
}
.pt-strip > span:first-child {
  margin-top: 0.1rem;
  flex-shrink: 0;
}
.pt-strip-warn {
  border: 1px solid rgb(217 119 6 / 0.35);
  background: rgb(217 119 6 / 0.08);
  color: rgb(var(--slate-12));
}
.pt-strip-info {
  border: 1px solid rgb(var(--pt-rgb) / 0.3);
  background: rgb(var(--pt-rgb) / 0.07);
  color: rgb(var(--slate-12));
}
.pt-empty {
  display: flex;
  min-height: 50vh;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  text-align: center;
  font-size: 0.875rem;
  color: rgb(var(--slate-11));
}
.pt-empty-sm {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.4rem;
  padding: 2rem 0 1rem;
  text-align: center;
  font-size: 0.8125rem;
  color: rgb(var(--slate-11));
}
.pt-overlay {
  position: fixed;
  inset: 0;
  z-index: 50;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  background: rgb(0 0 0 / 0.45);
  backdrop-filter: blur(3px);
}
@media (min-width: 640px) {
  .pt-overlay {
    align-items: center;
    padding: 1.5rem;
  }
}
.pt-modal {
  position: relative;
  display: flex;
  max-height: 92vh;
  width: 100%;
  max-width: 32rem;
  flex-direction: column;
  overflow: hidden;
  border-radius: 1.25rem 1.25rem 0 0;
  background: rgb(var(--background-color, 255 255 255));
  box-shadow: 0 24px 60px rgb(0 0 0 / 0.3);
}
@media (min-width: 640px) {
  .pt-modal {
    border-radius: 1.25rem;
  }
}
.pt-modal-bar {
  height: 0.375rem;
  flex-shrink: 0;
  background: linear-gradient(135deg, var(--pt-deep), #3b82f6);
}
.pt-label {
  display: block;
  margin-bottom: 0.3rem;
  font-size: 0.75rem;
  font-weight: 600;
  color: rgb(var(--slate-11));
}
.pt-input {
  width: 100%;
  border-radius: 0.75rem;
  border: 1px solid rgb(var(--slate-7));
  background: transparent;
  padding: 0.6rem 0.8rem;
  font-size: 0.9375rem;
  color: rgb(var(--slate-12));
  margin: 0;
}
.pt-input:focus {
  border-color: var(--pt);
  outline: 2px solid rgb(var(--pt-rgb) / 0.25);
}
</style>
