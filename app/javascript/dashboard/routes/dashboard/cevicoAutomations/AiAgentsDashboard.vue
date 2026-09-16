<script setup>
// DASHBOARD DOS AGENTES DE IA (item 85, só admin): um card por agente —
// quem está ligado, o que cada um faz, quantas vezes trabalhou no
// período, custo, última atividade e o ritmo diário (14 dias).
// 14/09: formato novo do kit (paleta do admin, vidros DashKpi, gráficos
// MiniBars/HBars/ShareBar): ritmo do time dia a dia, ranking de quem mais
// trabalhou (cada agente com a SUA cor — identidade), fatia do custo e os
// cards com o mini-gráfico de verdade.
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import CevicoPalettePicker from 'dashboard/components-next/cevico/CevicoPalettePicker.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const data = ref(null);
// régua de período PADRÃO CEVICO (06/08) — default 'last7' (antes: 7 dias)
const period = ref({ preset: 'last7', from: '', to: '' });

// 🍎 paleta desta tela (o admin escolhe pelo chip de paleta; cada bloco pode ter a sua)
const pal = useCevicoPalette({
  scope: 'report:agentes',
  blocks: [
    { id: 'totais', label: 'Totais do período', icon: 'i-lucide-gauge' },
    { id: 'ritmo', label: 'Ritmo do time', icon: 'i-lucide-activity' },
    { id: 'ranking', label: 'Quem mais trabalhou', icon: 'i-lucide-trophy' },
    { id: 'custo', label: 'Fatia do custo', icon: 'i-lucide-coins' },
    { id: 'agentes', label: 'Um card por agente', icon: 'i-lucide-bot' },
  ],
});
const { cvVars, blockVars, blockFamily, openPalettePicker } = pal;

const load = async () => {
  isLoading.value = true;
  try {
    const params = {
      preset: period.value.preset,
      ...(period.value.preset === 'custom'
        ? { from: period.value.from, to: period.value.to }
        : {}),
    };
    const { data: payload } = await CrmAPI.getAiDashboard(params);
    data.value = payload;
  } catch {
    useAlert('Não consegui carregar o painel dos agentes.');
  } finally {
    isLoading.value = false;
  }
};
watch(period, load, { deep: true });
onMounted(load);

const totals = computed(() => data.value?.totals || {});
const agents = computed(() => data.value?.agents || []);

const MODEL_LABEL = {
  'claude-opus-4-8': 'Opus',
  'claude-sonnet-5': 'Sonnet',
  'claude-haiku-4-5': 'Haiku',
};

const fmtNum = v => Number(v || 0).toLocaleString('pt-BR');
const fmtCost = v => {
  const n = Number(v || 0);
  if (n === 0) return 'US$ 0';
  if (n < 0.01) return '< US$ 0,01';
  return `US$ ${n.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}`;
};

// "há 2h", "há 3d" — atividade recente sem precisar ler data
const ago = iso => {
  if (!iso) return 'nunca rodou';
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return 'agora mesmo';
  if (mins < 60) return `há ${mins} min`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `há ${hours}h`;
  return `há ${Math.floor(hours / 24)}d`;
};

// ── ritmo do time: soma dos 14 dias de todos os agentes ──
const DAYS = 14;
const dayLabels = computed(() =>
  Array.from({ length: DAYS }, (_, i) => {
    const d = new Date();
    d.setDate(d.getDate() - (DAYS - 1 - i));
    return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  })
);
const teamDaily = computed(() =>
  Array.from({ length: DAYS }, (_, i) =>
    agents.value.reduce((s, a) => s + (Number(a.daily?.[i]) || 0), 0)
  )
);
const teamDailyTotal = computed(() =>
  teamDaily.value.reduce((s, v) => s + v, 0)
);
const busiestDay = computed(() => {
  const max = Math.max(0, ...teamDaily.value);
  if (!max) return null;
  return { label: dayLabels.value[teamDaily.value.indexOf(max)], value: max };
});

// ── ranking: quem mais trabalhou (cor = identidade do agente) ──
const rankingRows = computed(() =>
  [...agents.value]
    .filter(a => a.calls > 0)
    .sort((a, b) => b.calls - a.calls)
    .slice(0, 8)
    .map((a, i) => ({
      key: a.key,
      label: a.name,
      sub: `${fmtCost(a.cost_usd)} · ${MODEL_LABEL[a.model] || a.model}`,
      values: [a.calls],
      color: a.color,
      badge: ['🥇', '🥈', '🥉'][i] || null,
    }))
);
// ── fatia do custo por agente ──
const costSlices = computed(() =>
  agents.value
    .filter(a => a.cost_usd > 0)
    .map(a => ({ label: a.name, value: a.cost_usd, color: a.color }))
);
// nos cards o gráfico é pequeno: só 3 datas (início, meio, fim) para não colidir
const cardLabels = computed(() =>
  dayLabels.value.map((l, i) => ([0, 7, DAYS - 1].includes(i) ? l : ''))
);
const agentsOn = computed(() => agents.value.filter(a => a.enabled));
const agentsOff = computed(() => agents.value.filter(a => !a.enabled));
</script>

<template>
  <div class="cv-page cv-overlay max-w-5xl" :style="cvVars">
    <!-- linha de cima: o que é este painel + a paleta (admin) -->
    <div class="mb-2 flex items-center gap-2 flex-wrap">
      <p class="text-[11px] text-n-slate-9 flex-1 min-w-0">
        O que cada agente de IA fez no período, quanto custou e o ritmo do time.
      </p>
      <button
        class="cv-btn cv-btn-ghost cv-btn-sm flex-shrink-0"
        title="Paleta deste painel (cor do dia, iMac G3, frutas ou salada) e a cor de cada bloco"
        @click="openPalettePicker('panel')"
      >
        <span class="i-lucide-palette text-xs" />
        Paleta
      </button>
    </div>
    <!-- período — régua padrão CEVICO -->
    <PeriodRuler v-model="period" glass class="mb-4" />

    <!-- popup da paleta (nos relatórios ele mora no banner; aqui não há banner) -->
    <CevicoPalettePicker
      :pal="pal"
      title="Paleta de cores · Painel dos agentes"
    />

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- totais do período: 4 vidros -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('totais')">
        <div class="flex items-center gap-2 mb-4 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-gauge text-base" /></span>
          <h2 class="text-sm font-bold text-n-slate-12">Totais do período</h2>
          <span class="text-[11px] text-n-slate-9 ml-auto">custo estimado pelos tokens de cada chamada</span>
        </div>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
          <DashKpi
            compact
            glass
            label="Trabalhos no período"
            :value="totals.calls || 0"
            sub="chamadas de IA"
            :grad="blockFamily('totais')[0]"
          />
          <DashKpi
            compact
            glass
            label="Custo do período"
            :value="fmtCost(totals.cost_usd)"
            sub="estimado (tokens)"
            :grad="blockFamily('totais')[1]"
          />
          <DashKpi
            compact
            glass
            label="Agentes ligados"
            :value="`${totals.active_agents || 0} / ${agents.length}`"
            sub="interruptor definitivo"
            :grad="blockFamily('totais')[2]"
          />
          <div
            class="cv-tile rounded-2xl px-4 py-3 text-white shadow-lg"
            :style="{ background: blockFamily('totais')[3] }"
          >
            <p class="text-[11px] font-medium text-white/80 mb-1.5">
              Mais ativo
            </p>
            <p class="text-base font-bold leading-tight">
              {{ totals.top_agent || '—' }}
            </p>
            <p class="text-[10px] text-white/70 mt-1">no período</p>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-5 gap-4 mb-4">
        <!-- ritmo do time, 14 dias -->
        <div
          class="xl:col-span-3 cv-block p-5 sm:p-6"
          :style="blockVars('ritmo')"
        >
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-activity text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Ritmo do time, dia a dia
            </h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-3">
            últimos 14 dias, todos os agentes somados ·
            {{ fmtNum(teamDailyTotal) }} trabalho(s)
            <template v-if="busiestDay">
              · dia mais cheio:
              <b class="text-n-slate-11">{{ busiestDay.label }}</b> ({{
                fmtNum(busiestDay.value)
              }})
            </template>
          </p>
          <div class="cv-sub p-4 pb-2">
            <MiniBars
              :values="teamDaily"
              :labels="dayLabels"
              :color="hexFromGrad(blockFamily('ritmo')[1]) || '#0F5FA6'"
              :height="140"
              :format="v => `${fmtNum(v)} trabalho(s)`"
            />
          </div>
        </div>

        <!-- fatia do custo -->
        <div
          class="xl:col-span-2 cv-block p-5 sm:p-6"
          :style="blockVars('custo')"
        >
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-coins text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">Fatia do custo</h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-3">
            quem gasta mais no período · {{ fmtCost(totals.cost_usd) }}
          </p>
          <ShareBar :items="costSlices" :format="fmtCost" :height="16" />
        </div>
      </div>

      <!-- ranking -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('ranking')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-trophy text-base"/></span>
          <h2 class="text-sm font-bold text-n-slate-12">Quem mais trabalhou</h2>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-3">
          trabalhos no período, cada agente na sua cor
        </p>
        <HBars
          :rows="rankingRows"
          :series="[{ label: 'trabalhos', format: fmtNum }]"
          :label-width="14"
          empty-text="nenhum agente trabalhou no período"
        />
      </div>

      <!-- um card por agente -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('agentes')">
        <div class="flex items-center gap-2 mb-4 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-bot text-base" /></span>
          <h2 class="text-sm font-bold text-n-slate-12">Um card por agente</h2>
          <span class="text-[11px] text-n-slate-9 ml-auto">{{ agentsOn.length }} ligado(s) ·
            {{ agentsOff.length }} desligado(s)</span>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div
            v-for="agent in agents"
            :key="agent.key"
            class="cv-sub cv-sub-hover p-4"
            :class="agent.enabled ? '' : 'opacity-60'"
          >
            <div class="flex items-center gap-2.5 mb-2">
              <span
                class="cv-icon flex-shrink-0"
                :style="{ background: agent.color }"
              >
                <span :class="agent.icon" class="text-base" />
              </span>
              <div class="min-w-0 flex-1">
                <p
                  class="text-sm font-bold text-n-slate-12 leading-tight flex items-center gap-1.5 flex-wrap"
                >
                  {{ agent.name }}
                  <span
                    v-if="agent.responder"
                    class="text-[8px] font-black uppercase px-1.5 py-0.5 rounded-full"
                    style="background: rgba(219, 39, 119, 0.12); color: #db2777"
                    title="Este agente FALA com o paciente"
                    >fala c/ paciente</span>
                </p>
                <p class="text-[10px] text-n-slate-9 leading-snug">
                  {{ agent.what }}
                </p>
              </div>
              <span
                class="flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                :style="
                  agent.enabled
                    ? {
                        background: 'rgba(5, 150, 105, 0.12)',
                        color: '#059669',
                      }
                    : {
                        background: 'rgba(100, 116, 139, 0.14)',
                        color: '#64748B',
                      }
                "
              >
                <span
                  class="w-1.5 h-1.5 rounded-full"
                  :style="{ background: agent.enabled ? '#059669' : '#94A3B8' }"
                />
                {{ agent.enabled ? 'ligado' : 'desligado' }}
              </span>
            </div>

            <div
              class="grid items-end gap-3"
              style="
                grid-template-columns: max-content max-content minmax(0, 1fr);
              "
            >
              <div>
                <p class="text-xl font-bold leading-none text-n-slate-12">
                  {{ fmtNum(agent.calls) }}
                </p>
                <p class="text-[9px] text-n-slate-9 mt-1">trabalhos</p>
              </div>
              <div>
                <p
                  class="text-sm font-bold tabular-nums text-n-slate-11 leading-none"
                >
                  {{ fmtCost(agent.cost_usd) }}
                </p>
                <p class="text-[9px] text-n-slate-9 mt-1">custo</p>
              </div>
              <!-- ritmo diário (14 dias) — mini-gráfico de verdade -->
              <div
                class="min-w-0"
                :title="`ritmo diário (14 dias): ${(agent.daily || []).join(', ')}`"
              >
                <MiniBars
                  :values="
                    agent.daily?.length ? agent.daily : Array(14).fill(0)
                  "
                  :labels="cardLabels"
                  :color="agent.color"
                  :height="56"
                  :axis="false"
                  :show-values="false"
                  :format="v => `${fmtNum(v)} trabalho(s)`"
                />
              </div>
            </div>

            <div
              class="flex items-center gap-2 mt-2 pt-2"
              style="border-top: 1px solid rgb(var(--cv-rgb) / 0.16)"
            >
              <span class="cv-chip">{{
                MODEL_LABEL[agent.model] || agent.model
              }}</span>
              <span class="text-[10px] text-n-slate-9 ml-auto">
                <span class="i-lucide-clock text-[9px]" />
                última atividade:
                <b class="text-n-slate-11">{{ ago(agent.last_call_at) }}</b>
              </span>
            </div>
          </div>
        </div>
      </div>

      <p class="text-[11px] text-n-slate-9 mb-6">
        💡 Custo estimado pelos tokens de cada chamada. Para ligar/desligar um
        agente ou editar o prompt, use a aba <b>Agentes de IA</b> aqui do lado.
        <template v-if="data.extras?.mentor_feedbacks_30d">
          · Mentor escreveu
          <b>{{ data.extras.mentor_feedbacks_30d }}</b> feedback(s) nos últimos
          30 dias.
        </template>
      </p>
    </template>
  </div>
</template>
