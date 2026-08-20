<script setup>
// Dashboard dos AGENTES (análise do gestor): desempenho de cada pessoa do
// time — conversas, tempo de 1ª resposta, resoluções, consultas agendadas
// e a responsividade aos avisos do Radar de Oportunidades. Serve de base
// para orientações, feedbacks e treinamentos.
import { ref, computed, watch, onMounted } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const data = ref(null);

// régua padrão CEVICO (06/08): Hoje | Ontem | 7 dias | Este mês | Este ano | Personalizado
const period = ref({ preset: 'month', from: '', to: '' });

const fetchData = async () => {
  isLoading.value = true;
  try {
    const p = period.value;
    const { data: payload } = await CrmAPI.getAgentsDashboard({
      preset: p.preset,
      ...(p.preset === 'custom' ? { from: p.from, to: p.to } : {}),
    });
    data.value = payload;
  } catch {
    data.value = data.value || { agents: [], radar: {} };
  } finally {
    isLoading.value = false;
  }
};

watch(period, fetchData, { deep: true });

const medal = i => ['🥇', '🥈', '🥉'][i] || `${i + 1}º`;

// cores: rápido = verde, ok = dourado, lento = vermelho
const speedColor = min => {
  if (min === null || min === undefined) return '#94A3B8';
  if (min <= 5) return '#059669';
  if (min <= 20) return '#D4A017';
  return '#DC2626';
};
const rateColor = pct => {
  if (pct >= 80) return '#059669';
  if (pct >= 50) return '#D4A017';
  return '#DC2626';
};
const fmtMin = min => {
  if (min === null || min === undefined) return '—';
  if (min < 60) return `${String(min).replace('.', ',')}min`;
  return `${Math.floor(min / 60)}h${String(Math.round(min % 60)).padStart(2, '0')}`;
};
// pausas do expediente: 2h+ vermelho, 1h+ âmbar, resto neutro
const gapColor = min => {
  if (min >= 120) return '#DC2626';
  if (min >= 60) return '#B45309';
  return '#475569';
};

// ⏱ Meta de tempo de atendimento (veio do Meu Painel — pedido 20/08).
// A meta é configurada no agente Radar; horário comercial seg–sex 08–17h.
const responseGoal = computed(() => data.value?.response_goal || null);
const goalMinutes = computed(() => responseGoal.value?.goal_minutes || 15);
const myResponse = computed(() => responseGoal.value?.mine || null);
const teamResponse = computed(() => responseGoal.value?.agents || []);
const respVerdict = row => {
  if (!row || !row.replies) return null;
  if (row.avg_minutes <= goalMinutes.value && row.within_rate >= 70)
    return { label: '🏅 Meta batida', bg: 'rgba(16,185,129,0.14)', color: '#047857' };
  if (row.avg_minutes <= goalMinutes.value)
    return { label: '💪 No ritmo', bg: 'rgba(59,130,246,0.12)', color: '#1D4ED8' };
  return { label: '⏳ Fora da meta', bg: 'rgba(239,68,68,0.12)', color: '#B91C1C' };
};

onMounted(fetchData);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #7C3AED, #A78BFA)">
          <span class="i-lucide-users text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Dashboard dos Agentes</h1>
          <p class="text-xs text-n-slate-10">desempenho de cada pessoa do time · base para feedbacks e treinamentos</p>
        </div>
      </div>

      <!-- Período (régua padrão CEVICO) -->
      <PeriodRuler v-model="period" class="mb-6" />

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- 📡 Responsividade ao Radar (visão geral) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-radar text-base" style="color: #EA580C" />
            Resposta aos avisos do Radar de Oportunidades
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">
            de cada aviso que o Radar acendeu, a 1ª mensagem enviada ao paciente DEPOIS do aviso conta como a resposta
          </p>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
            <DashKpi
              compact
              label="Avisos no período"
              :value="data.radar?.total_alerts ?? 0"
              from="#EA580C"
              to="#FB923C"
            />
            <DashKpi
              compact
              label="Respondidos"
              :value="data.radar?.responded ?? 0"
              from="#0F5FA6"
              to="#38BDF8"
            />
            <DashKpi
              compact
              label="Taxa de resposta"
              :value="`${data.radar?.response_rate ?? 0}%`"
              :value-color="rateColor(data.radar?.response_rate ?? 0)"
            />
            <DashKpi
              compact
              label="Tempo médio p/ responder"
              :value="fmtMin(data.radar?.avg_response_min)"
              :value-color="speedColor(data.radar?.avg_response_min)"
            />
          </div>

          <!-- por painel de destino -->
          <div v-if="data.radar?.by_target?.length" class="space-y-2">
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">Por painel de destino do aviso</p>
            <div
              v-for="t in data.radar.by_target"
              :key="t.user_id ?? 'geral'"
              class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs flex-wrap"
            >
              <span class="font-medium text-n-slate-12 flex-1 min-w-[120px]">📌 {{ t.user_name || 'Todos os painéis' }}</span>
              <span class="text-n-slate-10">{{ t.responded }} de {{ t.total }} respondidos</span>
              <span class="font-bold" :style="{ color: rateColor(t.response_rate) }">{{ t.response_rate }}%</span>
              <span class="text-n-slate-10">tempo médio <b :style="{ color: speedColor(t.avg_response_min) }">{{ fmtMin(t.avg_response_min) }}</b></span>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-10">Nenhum aviso do Radar no período — ligue o Radar e configure as vigias em Automações → Agentes de IA.</p>
        </div>

        <!-- ⏱ Meta de tempo de atendimento — relatório pessoal (config no
             agente Radar). Atendente vê a própria meta; admin vê o time. -->
        <div
          v-if="responseGoal && (myResponse || teamResponse.length)"
          class="bg-n-card outline outline-1 outline-n-container rounded-2xl p-5 sm:p-6 mb-6"
        >
          <div class="flex items-center gap-2 mb-4 flex-wrap">
            <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #059669, #4ADE80)">
              <span class="i-lucide-target text-white text-base" />
            </span>
            <h2 class="text-sm font-bold text-n-slate-12">Meta de tempo de atendimento</h2>
            <span
              class="text-[10px] px-2 py-0.5 rounded-full font-semibold"
              style="background: rgba(16, 185, 129, 0.12); color: #047857"
            >
              responder em até {{ goalMinutes }} min
            </span>
            <span
              class="text-[10px] px-2 py-0.5 rounded-full font-semibold bg-n-alpha-1 text-n-slate-10"
              title="A meta vale no horário em que a equipe está presente. Noite, madrugada, fim de semana e feriado entram na média 'fora do horário', sem meta."
            >
              vale seg–sex · 08h–17h
            </span>
            <span v-if="!responseGoal.configured" class="text-[10px] text-n-slate-9 ml-auto">
              ajuste a meta em Automações → Radar de Oportunidades
            </span>
          </div>

          <!-- meu resultado no período (4 medidores + selo): a meta julga só
               o horário comercial; "fora do horário" é informativo -->
          <div v-if="myResponse" class="mb-1">
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div class="rounded-xl border border-n-weak bg-n-solid-2 p-3 text-center">
                <p class="text-[10px] text-n-slate-9 mb-0.5">Tempo médio (08–17h)</p>
                <p class="text-xl sm:text-2xl font-bold" :style="{ color: myResponse.avg_minutes === null ? undefined : myResponse.avg_minutes <= goalMinutes ? '#059669' : '#DC2626' }">
                  {{ fmtMin(myResponse.avg_minutes) }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-solid-2 p-3 text-center" title="Mensagens que chegaram de noite, madrugada, fim de semana ou feriado — sem meta, só informação">
                <p class="text-[10px] text-n-slate-9 mb-0.5">🌙 Fora do horário</p>
                <p class="text-xl sm:text-2xl font-bold text-n-slate-11">{{ fmtMin(myResponse.off_avg_minutes) }}</p>
                <p class="text-[9px] text-n-slate-9">{{ myResponse.off_replies }} resposta(s)</p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-solid-2 p-3 text-center">
                <p class="text-[10px] text-n-slate-9 mb-0.5">Dentro da meta</p>
                <p class="text-xl sm:text-2xl font-bold text-n-slate-12">{{ myResponse.within_rate }}%</p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-solid-2 p-3 text-center">
                <p class="text-[10px] text-n-slate-9 mb-0.5">Respostas (08–17h)</p>
                <p class="text-xl sm:text-2xl font-bold text-n-slate-12">{{ myResponse.replies }}</p>
              </div>
            </div>
            <div class="mt-2.5">
              <div class="h-2.5 bg-n-alpha-1 rounded-full overflow-hidden">
                <div
                  class="h-full rounded-full transition-all duration-700"
                  :style="{
                    width: Math.max(myResponse.within_rate, 3) + '%',
                    background: myResponse.within_rate >= 70 ? 'linear-gradient(90deg, #059669, #4ADE80)' : 'linear-gradient(90deg, #D97706, #F59E0B)',
                  }"
                />
              </div>
              <div class="flex items-center justify-between mt-1.5 flex-wrap gap-1">
                <p class="text-[10px] text-n-slate-9">
                  {{ myResponse.within_goal }} de {{ myResponse.replies }} respostas do horário comercial dentro da meta
                </p>
                <span
                  v-if="respVerdict(myResponse)"
                  class="text-[10px] px-2 py-0.5 rounded-full font-bold"
                  :style="{ background: respVerdict(myResponse).bg, color: respVerdict(myResponse).color }"
                >
                  {{ respVerdict(myResponse).label }}
                </span>
              </div>
            </div>
          </div>

          <!-- admin: quebra por atendente -->
          <div v-if="teamResponse.length" class="space-y-1.5" :class="myResponse ? 'mt-4 pt-3 border-t border-n-weak' : ''">
            <p v-if="myResponse" class="text-xs font-medium text-n-slate-11 mb-1.5">Time no período</p>
            <div
              v-for="row in teamResponse"
              :key="row.user_id"
              class="flex items-center gap-2 flex-wrap rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2"
            >
              <span class="text-sm font-semibold text-n-slate-12 truncate">{{ row.name }}</span>
              <span class="text-[10px] text-n-slate-9">{{ row.replies }} resposta(s) 08–17h</span>
              <span class="text-xs font-bold ml-auto" :style="{ color: row.avg_minutes === null ? undefined : row.avg_minutes <= goalMinutes ? '#059669' : '#DC2626' }">
                {{ fmtMin(row.avg_minutes) }}
              </span>
              <span class="text-[10px] text-n-slate-10">{{ row.within_rate }}% na meta</span>
              <span
                v-if="row.off_replies"
                class="text-[10px] text-n-slate-9"
                title="Média das respostas fora do horário comercial (noite, madrugada, fim de semana, feriado) — sem meta"
              >
                🌙 {{ fmtMin(row.off_avg_minutes) }} fora ({{ row.off_replies }})
              </span>
              <span
                v-if="respVerdict(row)"
                class="text-[10px] px-2 py-0.5 rounded-full font-bold"
                :style="{ background: respVerdict(row).bg, color: respVerdict(row).color }"
              >
                {{ respVerdict(row).label }}
              </span>
            </div>
          </div>
        </div>

        <!-- 👥 Métricas por pessoa -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-user-round-check text-base" style="color: #7C3AED" />
            Desempenho por pessoa
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">
            ordenado por volume de mensagens enviadas · "Radar" = avisos em que a pessoa foi quem respondeu ao paciente
          </p>

          <div v-if="!data.agents?.length" class="text-center py-10 text-n-slate-10 text-sm">
            Nenhuma atividade da equipe no período.
          </div>

          <div v-else class="space-y-3">
            <div
              v-for="(row, i) in data.agents"
              :key="row.id"
              class="rounded-2xl border-2 border-violet-400/30 bg-n-solid-1 p-4"
            >
              <div class="flex items-center gap-2 flex-wrap mb-3">
                <span class="text-lg">{{ medal(i) }}</span>
                <p class="text-sm font-bold text-n-slate-12 flex-1 min-w-[140px] break-words">{{ row.name }}</p>
                <span
                  class="text-xs font-bold text-white px-3 py-1 rounded-full"
                  style="background: linear-gradient(135deg, #7C3AED, #A78BFA)"
                >
                  {{ row.messages_sent }} mensagens
                </span>
              </div>
              <div class="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-3 text-center">
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.conversations_assigned }}</p>
                  <p class="text-[10px] text-n-slate-10">conversas atribuídas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold" :style="{ color: speedColor(row.avg_first_response_min) }">
                    {{ fmtMin(row.avg_first_response_min) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10">1ª resposta (média)</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold" :style="{ color: speedColor(row.avg_reply_min) }">
                    {{ fmtMin(row.avg_reply_min) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10">resposta ao lead (média{{ row.replies_count ? ` · ${row.replies_count}` : '' }})</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.conversations_resolved }}</p>
                  <p class="text-[10px] text-n-slate-10">resolvidas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.appointments_created }}</p>
                  <p class="text-[10px] text-n-slate-10">consultas agendadas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.radar_responded }}</p>
                  <p class="text-[10px] text-n-slate-10">avisos do Radar respondidos</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold" :style="{ color: speedColor(row.radar_avg_response_min) }">
                    {{ fmtMin(row.radar_avg_response_min) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10">tempo até responder o Radar</p>
                </div>
              </div>

              <!-- Jornada de atendimento: horários reais + maiores pausas -->
              <div v-if="row.workday" class="mt-3 rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2.5">
                <div class="flex items-center gap-x-4 gap-y-1 flex-wrap text-xs text-n-slate-11">
                  <span class="inline-flex items-center gap-1.5">
                    <span class="i-lucide-sunrise text-sm" style="color: #D97706" />
                    1ª mensagem em média às <b class="text-n-slate-12">{{ row.workday.avg_first_msg }}</b>
                  </span>
                  <span class="inline-flex items-center gap-1.5">
                    <span class="i-lucide-sunset text-sm" style="color: #7C3AED" />
                    última em média às <b class="text-n-slate-12">{{ row.workday.avg_last_msg }}</b>
                  </span>
                  <span class="text-n-slate-9">{{ row.workday.days_active }} dia(s) com atendimento</span>
                </div>
                <div v-if="row.workday.top_gaps?.length" class="flex items-center gap-1.5 flex-wrap mt-2">
                  <span class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">maiores pausas</span>
                  <span
                    v-for="(g, gi) in row.workday.top_gaps"
                    :key="gi"
                    class="text-[11px] px-2 py-0.5 rounded-full bg-n-solid-2 border border-n-weak text-n-slate-11"
                  >
                    {{ g.day }} · {{ g.from }} → {{ g.to }} ·
                    <b :style="{ color: gapColor(g.minutes) }">{{ fmtMin(g.minutes) }}</b>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
