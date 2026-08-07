<script setup>
// Dashboard dos MÉDICOS (análise do gestor): quem mais converte consulta em
// cirurgia, indicações, comparecimento, NPS dos pacientes de cada médico e
// o volume de cirurgias por clínica parceira (IOP, Ocular Surgery...).
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import { useCevicoGoals } from 'dashboard/composables/useCevicoGoals';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CrmAPI from 'dashboard/api/crm';
import { DOCTORS } from 'dashboard/helper/cevicoAgenda';

const { isAdmin } = useAdmin();
const isLoading = ref(true);
const data = ref(null);

// ── 🩺 item 104 (20/07): AMBIENTE DO MÉDICO — aba "Gestão do time médico"
// (só admin): perfil de gestão por médico p/ contratações e desenvolvimento —
// status, especialidade, forças, pontos a desenvolver e observações.
// Salva sozinho em agenda_config.doctor_profiles.
const activeTab = ref('desempenho'); // desempenho | gestao
const DOCTOR_STATUS = [
  { key: 'ativo', label: 'Ativo', color: '#047857', bg: 'rgba(16,185,129,0.12)' },
  { key: 'contratacao', label: 'Em contratação', color: '#1D4ED8', bg: 'rgba(59,130,246,0.12)' },
  { key: 'avaliacao', label: 'Em avaliação', color: '#B45309', bg: 'rgba(245,158,11,0.14)' },
  { key: 'pausado', label: 'Pausado', color: '#475569', bg: 'rgba(100,116,139,0.16)' },
];
const profiles = ref({});
const emptyProfile = () => ({ status: 'ativo', specialty: '', strengths: [], weaknesses: [], notes: '', custom: false });
let profilesHydrated = false;
const hydrateProfiles = src => {
  const out = {};
  Object.entries(src || {}).forEach(([name, p]) => {
    out[name] = { ...emptyProfile(), ...p, strengths: [...(p.strengths || [])], weaknesses: [...(p.weaknesses || [])] };
  });
  // médicos oficiais + os que aparecem nos números já nascem com perfil
  [...DOCTORS.map(d => d.name), ...(data.value?.doctors || []).map(r => r.doctor)].forEach(n => {
    if (n && !out[n]) out[n] = emptyProfile();
  });
  return out;
};
const managedDoctors = computed(() =>
  Object.keys(profiles.value).map(name => ({
    name,
    profile: profiles.value[name],
    row: (data.value?.doctors || []).find(r => r.doctor === name) || null,
  }))
);

// autosave com respiro (mesmo padrão do Painel do Empresário)
const profileSaveState = ref('idle');
const profileSavedAt = ref('');
let profileSaveTimer = null;
const persistProfiles = async () => {
  profileSaveState.value = 'saving';
  try {
    await CrmAPI.saveDoctorProfiles(profiles.value);
    profileSaveState.value = 'saved';
    profileSavedAt.value = new Date().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  } catch {
    profileSaveState.value = 'error';
  }
};
watch(profiles, () => {
  if (!profilesHydrated) return;
  clearTimeout(profileSaveTimer);
  profileSaveTimer = setTimeout(persistProfiles, 900);
}, { deep: true });
onBeforeUnmount(() => clearTimeout(profileSaveTimer));

// forças / pontos a desenvolver (chips por médico)
const traitDrafts = ref({});
const draftKey = (name, kind) => `${kind}:${name}`;
const addTrait = (name, kind) => {
  const key = draftKey(name, kind);
  const txt = (traitDrafts.value[key] || '').trim();
  if (!txt) return;
  profiles.value[name][kind].push(txt);
  traitDrafts.value[key] = '';
};
const removeTrait = (name, kind, i) => {
  profiles.value[name][kind].splice(i, 1);
};

// contratações futuras: adicionar/remover médico manual
const newDoctorName = ref('');
const addDoctor = () => {
  const n = newDoctorName.value.trim();
  if (!n || profiles.value[n]) return;
  profiles.value[n] = { ...emptyProfile(), status: 'contratacao', custom: true };
  newDoctorName.value = '';
};
const removeDoctor = name => {
  if (!profiles.value[name]?.custom) return;
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Remover "${name}" da gestão? Os números dele não são afetados.`)) return;
  delete profiles.value[name];
};
const initialsOf = name =>
  name.replace(/^Dra?\.?\s*/i, '').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase();

// régua padrão CEVICO (06/08): Hoje | Ontem | 7 dias | Este mês | Este ano | Personalizado
const period = ref({ preset: 'month', from: '', to: '' });

const fetchData = async () => {
  isLoading.value = true;
  try {
    const p = period.value;
    const { data: payload } = await CrmAPI.getDoctorsDashboard({
      preset: p.preset,
      ...(p.preset === 'custom' ? { from: p.from, to: p.to } : {}),
    });
    data.value = payload;
    // perfis de gestão (item 104): hidrata uma vez, sem atropelar edição em curso
    if (payload.profiles !== null && payload.profiles !== undefined && !profilesHydrated) {
      profiles.value = hydrateProfiles(payload.profiles);
      setTimeout(() => { profilesHydrated = true; }, 300);
    }
  } catch {
    data.value = data.value || { doctors: [], surgeries_by_clinic: [] };
  } finally {
    isLoading.value = false;
  }
};

watch(period, fetchData, { deep: true });

const doctorColor = name => DOCTORS.find(d => d.name === name)?.color || '#64748B';
const medal = i => ['🥇', '🥈', '🥉'][i] || `${i + 1}º`;
const fmtBRL = v =>
  Number(v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

const npsColor = avg => {
  if (avg === null || avg === undefined) return '#94A3B8';
  if (avg >= 9) return '#059669';
  if (avg >= 7) return '#D4A017';
  return '#DC2626';
};

// resumo geral do período (soma dos médicos) c/ metas oficiais do mês
const goals = useCevicoGoals();
const totals = computed(() => {
  const rows = data.value?.doctors || [];
  const sum = key => rows.reduce((s, r) => s + Number(r[key] || 0), 0);
  return {
    consultations: sum('consultations'),
    conversions: sum('conversions'),
    surgeriesDone: sum('surgeries_done'),
    revenue: sum('revenue'),
  };
});

onMounted(() => {
  fetchData();
  goals.load();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #0369A1, #38BDF8)">
          <span class="i-lucide-stethoscope text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Dashboard dos Médicos</h1>
          <p class="text-xs text-n-slate-10">quem mais converte consulta em cirurgia · indicações · NPS · cirurgias por clínica</p>
        </div>
      </div>

      <!-- Abas: Desempenho | 🩺 Gestão do time médico (item 104, só admin) -->
      <div v-if="isAdmin" class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full mb-3">
        <button
          class="px-3 h-8 rounded-lg text-xs font-medium transition-colors flex items-center gap-1.5"
          :class="activeTab === 'desempenho' ? 'text-white font-bold' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'desempenho' ? 'background: linear-gradient(135deg, #0369A1, #38BDF8)' : ''"
          @click="activeTab = 'desempenho'"
        >
          <span class="i-lucide-trending-up text-sm" /> Desempenho
        </button>
        <button
          class="px-3 h-8 rounded-lg text-xs font-medium transition-colors flex items-center gap-1.5"
          :class="activeTab === 'gestao' ? 'text-white font-bold' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'gestao' ? 'background: linear-gradient(135deg, #0F766E, #2DD4BF)' : ''"
          @click="activeTab = 'gestao'"
        >
          <span class="i-lucide-clipboard-list text-sm" /> Gestão do time médico
        </button>
      </div>

      <!-- Período (régua padrão CEVICO) -->
      <PeriodRuler v-if="activeTab === 'desempenho'" v-model="period" class="mb-6" />

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <!-- ══ 🩺 GESTÃO DO TIME MÉDICO (item 104 — só admin) ══ -->
      <div v-else-if="activeTab === 'gestao' && isAdmin" class="space-y-4">
        <div class="flex items-center gap-2 flex-wrap">
          <p class="text-xs text-n-slate-10">
            O raio-X de gestão de cada médico — status, forças, pontos a desenvolver e as suas anotações.
            Só administradores veem esta aba.
          </p>
          <span
            class="ml-auto text-[11px] font-medium px-2.5 py-1 rounded-full flex items-center gap-1.5"
            :class="profileSaveState === 'error' ? 'text-red-600 bg-red-500/10' : 'text-n-slate-10 bg-n-alpha-1'"
          >
            <span v-if="profileSaveState === 'saving'" class="i-lucide-loader-2 animate-spin text-xs" />
            <span v-else-if="profileSaveState === 'saved'" class="i-lucide-check text-xs" style="color: #059669" />
            <span v-else-if="profileSaveState === 'error'" class="i-lucide-alert-triangle text-xs" />
            {{ profileSaveState === 'saving' ? 'Salvando…'
              : profileSaveState === 'saved' ? `Salvo às ${profileSavedAt}`
                : profileSaveState === 'error' ? 'Não consegui salvar — tento na próxima mudança'
                  : 'Alterações salvam sozinhas' }}
          </span>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div
            v-for="d in managedDoctors"
            :key="d.name"
            class="bg-n-solid-2 border border-n-weak rounded-2xl p-4"
          >
            <!-- cabeçalho: medalhão + nome + status -->
            <div class="flex items-center gap-2.5 mb-3">
              <span
                class="w-10 h-10 rounded-full flex items-center justify-center text-white text-sm font-bold flex-shrink-0 shadow-sm"
                :style="{ background: `linear-gradient(135deg, ${doctorColor(d.name)}, ${doctorColor(d.name)}99)` }"
              >
                {{ initialsOf(d.name) }}
              </span>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-bold text-n-slate-12 truncate">{{ d.name }}</p>
                <input
                  v-model="d.profile.specialty"
                  class="w-full text-[11px] bg-transparent border-b border-transparent hover:border-n-weak focus:border-n-brand focus:outline-none text-n-slate-10"
                  placeholder="Especialidade (ex.: catarata, refrativa, córnea…)"
                />
              </div>
              <button
                v-if="d.profile.custom"
                class="text-n-slate-9 hover:text-red-500 flex-shrink-0"
                title="Remover da gestão"
                @click="removeDoctor(d.name)"
              >
                <span class="i-lucide-trash-2 text-sm" />
              </button>
            </div>

            <!-- status em botões em linha -->
            <div class="flex items-center gap-1 flex-wrap mb-3">
              <button
                v-for="s in DOCTOR_STATUS"
                :key="s.key"
                class="px-2 h-6 rounded-full text-[10px] font-semibold border transition-colors"
                :style="d.profile.status === s.key
                  ? { background: s.bg, color: s.color, borderColor: s.color }
                  : { borderColor: 'transparent' }"
                :class="d.profile.status === s.key ? '' : 'text-n-slate-10 hover:bg-n-alpha-1'"
                @click="d.profile.status = s.key"
              >
                {{ s.label }}
              </button>
            </div>

            <!-- números reais do período (quando existem) -->
            <div v-if="d.row" class="grid grid-cols-3 gap-1.5 mb-3">
              <div class="rounded-lg bg-n-alpha-1 px-2 py-1.5 text-center">
                <p class="text-sm font-bold text-n-slate-12">{{ d.row.consultations }}</p>
                <p class="text-[9px] text-n-slate-10 uppercase tracking-wide">consultas</p>
              </div>
              <div class="rounded-lg bg-n-alpha-1 px-2 py-1.5 text-center">
                <p class="text-sm font-bold" :style="{ color: d.row.conversion_rate >= 50 ? '#059669' : '#B45309' }">
                  {{ d.row.conversion_rate }}%
                </p>
                <p class="text-[9px] text-n-slate-10 uppercase tracking-wide">conversão</p>
              </div>
              <div class="rounded-lg bg-n-alpha-1 px-2 py-1.5 text-center">
                <p class="text-sm font-bold" :style="{ color: npsColor(d.row.nps_avg) }">
                  {{ d.row.nps_avg ?? '—' }}
                </p>
                <p class="text-[9px] text-n-slate-10 uppercase tracking-wide">NPS</p>
              </div>
            </div>
            <p v-else class="text-[10px] text-n-slate-9 mb-3">
              sem números no período selecionado — os indicadores aparecem na aba Desempenho
            </p>

            <!-- 💪 forças -->
            <p class="text-[11px] font-bold mb-1" style="color: #047857">💪 Forças</p>
            <div class="flex flex-wrap gap-1 mb-2">
              <span
                v-for="(f, i) in d.profile.strengths"
                :key="`f-${i}`"
                class="group inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full"
                style="background: rgba(16, 185, 129, 0.1); color: #047857; border: 1px solid rgba(16, 185, 129, 0.35)"
              >
                {{ f }}
                <button class="opacity-0 group-hover:opacity-100" @click="removeTrait(d.name, 'strengths', i)">
                  <span class="i-lucide-x text-[9px]" />
                </button>
              </span>
              <input
                v-model="traitDrafts[draftKey(d.name, 'strengths')]"
                class="text-[11px] bg-transparent border-b border-dashed border-n-weak focus:outline-none focus:border-n-brand min-w-[90px] py-0.5 text-n-slate-12"
                placeholder="+ força (Enter)"
                @keydown.enter.prevent="addTrait(d.name, 'strengths')"
              />
            </div>

            <!-- 🧗 pontos a desenvolver -->
            <p class="text-[11px] font-bold mb-1" style="color: #B45309">🧗 Pontos a desenvolver</p>
            <div class="flex flex-wrap gap-1 mb-2">
              <span
                v-for="(f, i) in d.profile.weaknesses"
                :key="`w-${i}`"
                class="group inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full"
                style="background: rgba(245, 158, 11, 0.1); color: #B45309; border: 1px solid rgba(245, 158, 11, 0.4)"
              >
                {{ f }}
                <button class="opacity-0 group-hover:opacity-100" @click="removeTrait(d.name, 'weaknesses', i)">
                  <span class="i-lucide-x text-[9px]" />
                </button>
              </span>
              <input
                v-model="traitDrafts[draftKey(d.name, 'weaknesses')]"
                class="text-[11px] bg-transparent border-b border-dashed border-n-weak focus:outline-none focus:border-n-brand min-w-[90px] py-0.5 text-n-slate-12"
                placeholder="+ ponto (Enter)"
                @keydown.enter.prevent="addTrait(d.name, 'weaknesses')"
              />
            </div>

            <!-- 📝 observações do gestor -->
            <textarea
              v-model="d.profile.notes"
              rows="2"
              class="w-full text-[11px] leading-snug rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-2 resize-none focus:outline-none focus:border-n-brand text-n-slate-12"
              placeholder="Observações do gestor: acordos, plano de desenvolvimento, próxima conversa…"
            />
          </div>

          <!-- ➕ contratação futura -->
          <div class="border-2 border-dashed border-n-weak rounded-2xl p-4 flex flex-col items-center justify-center gap-2.5 min-h-[180px]">
            <span class="i-lucide-user-round-plus text-2xl text-n-slate-9" />
            <p class="text-xs text-n-slate-10 text-center">
              Contratando? Adicione o candidato aqui e acompanhe a avaliação.
            </p>
            <div class="flex gap-1.5 w-full max-w-[260px]">
              <input
                v-model="newDoctorName"
                class="flex-1 text-xs border border-n-weak rounded-lg px-2.5 py-1.5 bg-n-solid-1 focus:outline-none focus:border-n-brand text-n-slate-12"
                placeholder="Dr(a). Nome"
                @keydown.enter.prevent="addDoctor"
              />
              <button
                class="text-xs font-semibold text-white px-3 rounded-lg disabled:opacity-40"
                style="background: linear-gradient(135deg, #0F766E, #2DD4BF)"
                :disabled="!newDoctorName.trim()"
                @click="addDoctor"
              >
                <span class="i-lucide-plus text-sm" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <template v-else>
        <!-- 📈 Resumo do período (c/ selos de recorde/meta do mês) -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
          <DashKpi
            compact
            label="Consultas realizadas"
            :value="totals.consultations"
            from="#0369A1"
            to="#38BDF8"
            :state="goals.stateFor('consultations_attended')"
            :goal="goals.goalFor('consultations_attended')"
          />
          <DashKpi
            compact
            label="Viraram cirurgia"
            :value="totals.conversions"
            from="#5B21B6"
            to="#7C3AED"
          />
          <DashKpi
            compact
            label="Cirurgias realizadas"
            :value="totals.surgeriesDone"
            from="#059669"
            to="#34D399"
            :state="goals.stateFor('surgeries_done')"
            :goal="goals.goalFor('surgeries_done')"
          />
          <DashKpi
            compact
            label="Faturamento gerado"
            :value="Math.round(totals.revenue)"
            prefix="R$ "
            from="#065F46"
            to="#10B981"
            :state="goals.stateFor('revenue_closed')"
            :goal="goals.goalFor('revenue_closed')"
          />
        </div>

        <!-- 🏆 Ranking de conversão -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-trophy text-base" style="color: #D4A017" />
            Conversão de consulta em cirurgia — ranking
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">
            conversão = pacientes que o médico INDICOU e que têm cirurgia marcada (rastreado pelo telefone do contato)
          </p>

          <div v-if="!data.doctors?.length" class="text-center py-10 text-n-slate-10 text-sm">
            Nenhuma consulta com médico no período — os dados vêm da conferência do dia na Agenda.
          </div>

          <div v-else class="space-y-3">
            <div
              v-for="(row, i) in data.doctors"
              :key="row.doctor"
              class="rounded-2xl border-2 bg-n-solid-1 p-4"
              :style="{ borderColor: doctorColor(row.doctor) + '40' }"
            >
              <!-- nome nunca vira "Dr. …": quebra linha no celular em vez de truncar -->
              <div class="flex items-center gap-2 flex-wrap mb-3">
                <span class="text-lg">{{ medal(i) }}</span>
                <span class="w-2.5 h-2.5 rounded-full flex-shrink-0" :style="{ backgroundColor: doctorColor(row.doctor) }" />
                <p class="text-sm font-bold text-n-slate-12 flex-1 min-w-[140px] break-words">{{ row.doctor }}</p>
                <span
                  class="text-xs font-bold text-white px-3 py-1 rounded-full whitespace-nowrap"
                  :style="{ background: `linear-gradient(135deg, ${doctorColor(row.doctor)}, ${doctorColor(row.doctor)}99)` }"
                >
                  {{ row.conversion_rate }}% de conversão
                </span>
              </div>
              <div class="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-3 text-center">
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.consultations }}</p>
                  <p class="text-[10px] text-n-slate-10">consultas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.show_rate }}%</p>
                  <p class="text-[10px] text-n-slate-10">comparecimento</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.indications }}</p>
                  <p class="text-[10px] text-n-slate-10">indicações ({{ row.indication_rate }}%)</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.conversions }}</p>
                  <p class="text-[10px] text-n-slate-10">viraram cirurgia</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.surgeries_done }}</p>
                  <p class="text-[10px] text-n-slate-10">cirurgias realizadas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold" :style="{ color: npsColor(row.nps_avg) }">
                    {{ row.nps_avg === null ? '—' : row.nps_avg }}
                  </p>
                  <p class="text-[10px] text-n-slate-10">NPS médio ({{ row.nps_count }})</p>
                </div>
                <div class="rounded-xl px-2 py-2 text-white" style="background: linear-gradient(135deg, #065F46, #10B981)">
                  <p class="text-sm font-bold leading-tight">{{ fmtBRL(row.revenue) }}</p>
                  <p class="text-[10px] text-white/80">faturamento gerado</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- 🏥 Cirurgias por clínica parceira -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-building-2 text-base" style="color: #0284C7" />
            Volume de cirurgias por clínica
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">IOP (geralmente PRK) · Ocular Surgery (geralmente Lasik) — no período selecionado</p>

          <div v-if="!data.surgeries_by_clinic?.length" class="text-center py-8 text-n-slate-10 text-sm">
            Nenhuma cirurgia agendada no período.
          </div>
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div
              v-for="c in data.surgeries_by_clinic"
              :key="c.key"
              class="rounded-2xl p-5 text-white shadow-lg"
              style="background: linear-gradient(135deg, #0284C7, #38BDF8)"
            >
              <p class="text-xs font-medium text-white/80 mb-1">{{ c.label }}</p>
              <p class="text-3xl font-bold">{{ c.count }}</p>
              <p class="text-[11px] text-white/70 mt-1">
                {{ c.done }} realizada(s)
                <template v-if="c.nps_avg !== null && c.nps_avg !== undefined">
                  · NPS {{ c.nps_avg }} ({{ c.nps_count }})
                </template>
              </p>
            </div>
          </div>
          <p class="text-[10px] text-n-slate-9 mt-4 flex items-center gap-1.5">
            <span class="i-lucide-info text-xs" />
            A ocupação da sala cirúrgica (dia/semana/mês) fica na Agenda → trilho Cirurgias, seguindo as janelas configuradas.
          </p>
        </div>

        <!-- 🏢 Consultas por UNIDADE (Tatuapé / Av. Paulista) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-map-pin text-base" style="color: #EA580C" />
            Consultas por unidade
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">volume e taxa de comparecimento em cada unidade da clínica</p>

          <div v-if="!data.consultations_by_unit?.length" class="text-center py-6 text-n-slate-10 text-sm">
            Nenhuma consulta no período.
          </div>
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div
              v-for="u in data.consultations_by_unit"
              :key="u.key"
              class="rounded-2xl border border-n-weak bg-n-solid-1 p-4"
            >
              <div class="flex items-center gap-2 mb-2">
                <p class="text-sm font-bold text-n-slate-12 flex-1">{{ u.label }}</p>
                <span class="text-xl font-bold text-n-slate-12">{{ u.count }}</span>
                <span class="text-[10px] text-n-slate-9">consultas</span>
              </div>
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">Comparecimento</span>
                <span class="font-bold text-n-slate-12">{{ u.show_rate }}%</span>
              </div>
              <div class="h-3 bg-n-alpha-1 rounded-full overflow-hidden">
                <div
                  class="h-full rounded-full"
                  :style="{ width: Math.max(u.show_rate, 3) + '%', background: 'linear-gradient(90deg, #059669, #34D399)' }"
                />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-1">{{ u.attended }} compareceram · {{ u.missed }} faltaram</p>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
