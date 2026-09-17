<script setup>
// 📞 DASHBOARD DE LIGAÇÕES (item 167) — as chamadas nativas de WhatsApp no
// kit "iMac G3 + vidro" (CevicoHero, PeriodRuler, DashKpi, HBars, ShareBar,
// paleta por bloco). Lê GET crm/calls/dashboard (§5 do contrato):
//   KPIs · por atendente · por dia · por hora (faixa de calor 24 colunas)
//   · motivos de fim · últimas chamadas (com player e link pra conversa).
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CevicoCallsAPI from 'dashboard/api/cevicoCalls';
import {
  callIcon,
  formatTalkTime,
  formatPhoneBR,
  shortDateTime,
  initialsOf,
  STATUS_LABELS,
  END_REASON_LABELS,
} from 'dashboard/helper/cevicoCallsFormat';

const router = useRouter();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const crmSettings = useMapGetter('crm/getSettings');

const pal = useCevicoPalette({
  scope: 'report:calls',
  blocks: [
    { id: 'kpis', label: 'Ligações', icon: 'i-lucide-phone' },
    { id: 'agentes', label: 'Por atendente', icon: 'i-lucide-headset' },
    { id: 'dias', label: 'Por dia', icon: 'i-lucide-calendar-range' },
    { id: 'horas', label: 'Por hora do dia', icon: 'i-lucide-clock' },
    { id: 'motivos', label: 'Como terminaram', icon: 'i-lucide-pie-chart' },
    { id: 'recentes', label: 'Últimas chamadas', icon: 'i-lucide-history' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

const period = ref({ preset: 'month', from: '', to: '' });
const isLoading = ref(true);
const data = ref(null);
const loadError = ref('');

const fetchData = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const p = period.value || {};
    const params = { preset: p.preset };
    if (p.preset === 'custom') {
      Object.assign(params, {
        from: p.from,
        to: p.to,
        since: p.from,
        until: p.to,
      });
    }
    const { data: payload } = await CevicoCallsAPI.dashboard(params);
    data.value = payload;
  } catch (error) {
    data.value = null;
    loadError.value =
      error?.response?.data?.error ||
      'Não consegui carregar as ligações agora.';
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  fetchData();
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});
});
watch(period, fetchData, { deep: true });

const callsEnabled = computed(
  () => crmSettings.value?.calls?.enabled !== false
);
const settingsRoute = computed(() =>
  frontendURL(`accounts/${accountId.value}/settings/integrations/calls`)
);

const kpis = computed(() => data.value?.kpis || {});
const kpiGrad = i => blockFamily('kpis')[i % blockFamily('kpis').length];

// ── por atendente ──
const agentRows = computed(() =>
  (data.value?.by_agent || []).map(a => ({
    key: a.user_id,
    label: a.name || 'Sem nome',
    sub: `${formatTalkTime(a.total_talk_seconds)} em ligação · média ${formatTalkTime(a.avg_talk_seconds)}`,
    values: [Number(a.answered || 0)],
    hint: a.missed_while_ringing
      ? `${a.missed_while_ringing} perdida(s) enquanto tocava`
      : '',
  }))
);

// ── por dia ──
const WEEKDAYS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
const dayLabel = date => {
  const d = new Date(`${date}T12:00:00`);
  if (Number.isNaN(d.getTime())) return date;
  return `${WEEKDAYS[d.getDay()]} ${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
};
const dayRows = computed(() =>
  (data.value?.by_day || []).map(d => ({
    key: d.date,
    label: dayLabel(d.date),
    sub: `${d.received || 0} recebida(s)`,
    values: [Number(d.answered || 0), Number(d.missed || 0)],
  }))
);
const daySeries = computed(() => [
  { label: 'atendidas', color: blockFamily('dias')[1] },
  { label: 'perdidas', color: 'linear-gradient(135deg, #991b1b, #f87171)' },
]);

// ── por hora (faixa de calor de 24 colunas) ──
const hours = computed(() => {
  const list = Array.isArray(data.value?.by_hour) ? data.value.by_hour : [];
  return Array.from({ length: 24 }, (_x, h) => Number(list[h] || 0));
});
const hourMax = computed(() => Math.max(1, ...hours.value));
const hourAlpha = v => (v ? 0.14 + 0.78 * (v / hourMax.value) : 0.05);
const peakHour = computed(() => {
  const max = Math.max(...hours.value);
  if (!max) return null;
  return hours.value.indexOf(max);
});

// ── motivos ──
const reasonItems = computed(() =>
  (data.value?.by_reason || []).map(r => ({
    label: END_REASON_LABELS[r.reason] || r.reason || 'Sem motivo',
    value: Number(r.count || 0),
  }))
);

// ── últimas chamadas ──
const recent = computed(() => data.value?.recent || []);
const playing = ref(null);
const togglePlay = id => {
  playing.value = playing.value === id ? null : id;
};
const openConversation = c => {
  if (!c.conversation_id) return;
  router.push(
    `/app/accounts/${accountId.value}/conversations/${c.conversation_id}`
  );
};
const statusChip = status => {
  if (['completed', 'accepted'].includes(status)) return 'cv-green';
  if (status === 'missed') return 'cv-red';
  if (['rejected', 'failed', 'canceled'].includes(status)) return 'cv-amber';
  return '';
};
const contactName = c => c.contact?.name || c.display_name || 'Paciente';
const contactPhone = c =>
  formatPhoneBR(c.contact?.phone_number || c.wa_id || '');
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Dashboard de Ligações"
        subtitle="chamadas de WhatsApp recebidas e feitas · atendimento · espera · por atendente · por hora"
        icon="i-lucide-phone-call"
      />

      <PeriodRuler v-model="period" glass class="mb-6" />

      <!-- módulo ainda desligado -->
      <div
        v-if="!callsEnabled"
        class="cv-block cv-strip px-4 py-3.5 mb-6 flex items-center gap-3 flex-wrap"
        :style="blockVars('kpis')"
      >
        <span class="cv-icon cv-icon-sm">
          <span class="i-lucide-info text-xs" />
        </span>
        <p class="text-xs text-n-slate-11 flex-1 min-w-0">
          As ligações pelo WhatsApp ainda não estão ativadas nesta conta.
        </p>
        <router-link :to="settingsRoute" class="cv-btn cv-btn-sm">
          Ativar em Integrações →
        </router-link>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <div
        v-else-if="loadError"
        class="cv-block p-6 text-center"
        :style="blockVars('kpis')"
      >
        <p class="text-sm text-n-slate-11">{{ loadError }}</p>
        <button class="cv-btn cv-btn-sm mt-3" @click="fetchData">
          Tentar de novo
        </button>
      </div>

      <template v-else-if="data">
        <!-- KPIs -->
        <div
          class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6"
          :style="blockVars('kpis')"
        >
          <DashKpi
            compact
            glass
            label="Recebidas"
            :value="Number(kpis.received || 0)"
            :sub="`${kpis.outbound || 0} feita(s) pela clínica`"
            :grad="kpiGrad(0)"
          />
          <DashKpi
            compact
            glass
            label="Atendidas"
            :value="Number(kpis.answered || 0)"
            :sub="`${kpis.rejected || 0} recusada(s)`"
            :grad="kpiGrad(1)"
          />
          <DashKpi
            compact
            glass
            label="Perdidas"
            :value="Number(kpis.missed || 0)"
            sub="ninguém atendeu ou fora do horário"
            :grad="kpiGrad(2)"
          />
          <DashKpi
            compact
            glass
            label="Taxa de atendimento"
            :value="`${Math.round(Number(kpis.answer_rate || 0))}%`"
            sub="atendidas ÷ recebidas"
            :grad="kpiGrad(3)"
          />
          <DashKpi
            compact
            glass
            label="Espera média"
            :value="formatTalkTime(kpis.avg_wait_seconds)"
            sub="do toque até atender"
          />
          <DashKpi
            compact
            glass
            label="Conversa média"
            :value="formatTalkTime(kpis.avg_talk_seconds)"
            sub="por chamada atendida"
          />
          <DashKpi
            compact
            glass
            label="Tempo total"
            :value="formatTalkTime(kpis.total_talk_seconds)"
            sub="em ligação no período"
          />
        </div>

        <!-- por atendente + motivos -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
          <div class="cv-block p-5 sm:p-6" :style="blockVars('agentes')">
            <h2
              class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2"
            >
              <span class="cv-icon">
                <span class="i-lucide-headset text-base" />
              </span>
              Por atendente
            </h2>
            <HBars
              :rows="agentRows"
              :series="[
                { label: 'atendidas', color: blockFamily('agentes')[1] },
              ]"
              empty-text="Nenhuma chamada atendida no período."
            />
          </div>

          <div class="cv-block p-5 sm:p-6" :style="blockVars('motivos')">
            <h2
              class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2"
            >
              <span class="cv-icon">
                <span class="i-lucide-pie-chart text-base" />
              </span>
              Como terminaram
            </h2>
            <ShareBar :items="reasonItems" :family="blockFamily('motivos')" />
          </div>
        </div>

        <!-- por hora -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('horas')">
          <h2
            class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2"
          >
            <span class="cv-icon">
              <span class="i-lucide-clock text-base" />
            </span>
            Por hora do dia
            <span v-if="peakHour !== null" class="cv-chip ml-auto">
              pico às {{ peakHour }}h
            </span>
          </h2>
          <p class="text-[11px] text-n-slate-10 mb-3">
            recebidas por hora (fuso de São Paulo) — quanto mais escuro, mais
            chamadas
          </p>
          <div
            class="grid gap-1"
            style="grid-template-columns: repeat(24, minmax(0, 1fr))"
          >
            <div
              v-for="(v, h) in hours"
              :key="h"
              class="h-9 rounded-md transition-colors"
              :style="{ background: `rgb(var(--cv-rgb) / ${hourAlpha(v)})` }"
              :title="`${h}h · ${v} chamada(s)`"
            />
          </div>
          <div
            class="grid gap-1 mt-1"
            style="grid-template-columns: repeat(24, minmax(0, 1fr))"
          >
            <span
              v-for="h in 24"
              :key="'l' + h"
              class="text-[9px] text-n-slate-9 text-center"
            >
              {{ (h - 1) % 3 === 0 ? `${h - 1}h` : '' }}
            </span>
          </div>
        </div>

        <!-- por dia -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('dias')">
          <h2
            class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2"
          >
            <span class="cv-icon">
              <span class="i-lucide-calendar-range text-base" />
            </span>
            Por dia
          </h2>
          <div class="max-h-96 overflow-y-auto pr-1">
            <HBars
              :rows="dayRows"
              :series="daySeries"
              :label-width="8"
              empty-text="Nenhuma chamada no período."
            />
          </div>
        </div>

        <!-- últimas chamadas -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('recentes')">
          <h2
            class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2"
          >
            <span class="cv-icon">
              <span class="i-lucide-history text-base" />
            </span>
            Últimas chamadas
          </h2>
          <p v-if="!recent.length" class="text-xs text-n-slate-9 py-3">
            Nenhuma chamada no período.
          </p>
          <div v-else class="space-y-1.5">
            <div v-for="c in recent" :key="c.id" class="cv-row px-3 py-2">
              <div class="flex items-center gap-3 min-w-0">
                <img
                  v-if="c.contact?.thumbnail"
                  :src="c.contact.thumbnail"
                  alt=""
                  class="w-8 h-8 rounded-full object-cover flex-shrink-0"
                />
                <span
                  v-else
                  class="w-8 h-8 rounded-full flex items-center justify-center text-[11px] font-bold text-white flex-shrink-0"
                  style="background: var(--cv-grad-2)"
                >
                  {{ initialsOf(contactName(c)) }}
                </span>
                <div class="min-w-0 flex-1">
                  <p
                    class="text-xs font-semibold text-n-slate-12 truncate flex items-center gap-1.5"
                  >
                    <span
                      :class="[callIcon(c).icon, callIcon(c).tone]"
                      class="text-xs flex-shrink-0"
                    />
                    {{ contactName(c) }}
                    <span class="text-n-slate-9 font-normal">{{
                      contactPhone(c)
                    }}</span>
                  </p>
                  <p class="text-[11px] text-n-slate-10 truncate">
                    {{ shortDateTime(c.started_at) }}
                    <template v-if="c.user?.name">
                      · {{ c.user.name }}
                    </template>
                    <template v-if="Number(c.duration)">
                      · {{ formatTalkTime(c.duration) }}
                    </template>
                    <template v-if="c.simulated"> · simulação</template>
                  </p>
                </div>
                <span
                  class="cv-chip flex-shrink-0"
                  :class="statusChip(c.status)"
                >
                  {{ STATUS_LABELS[c.status] || c.status }}
                </span>
                <button
                  v-if="c.recording_url"
                  class="cv-btn cv-btn-ghost cv-iconbtn flex-shrink-0"
                  :title="
                    playing === c.id ? 'Fechar o player' : 'Ouvir a gravação'
                  "
                  @click="togglePlay(c.id)"
                >
                  <span
                    :class="playing === c.id ? 'i-lucide-x' : 'i-lucide-play'"
                    class="text-xs"
                  />
                </button>
                <button
                  v-if="c.conversation_id"
                  class="cv-btn cv-btn-ghost cv-btn-sm flex-shrink-0"
                  title="Abrir a conversa"
                  @click="openConversation(c)"
                >
                  Conversa →
                </button>
              </div>
              <audio
                v-if="playing === c.id && c.recording_url"
                controls
                autoplay
                :src="c.recording_url"
                class="w-full h-8 mt-2"
              />
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
