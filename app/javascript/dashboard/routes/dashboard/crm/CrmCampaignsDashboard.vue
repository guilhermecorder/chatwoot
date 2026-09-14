<script setup>
// Dashboard das campanhas de mensagem modelo — investimento, volume,
// responsividade e conversões, no mesmo visual do Dashboard CEVICO.
import { ref, computed, onMounted, watch } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const data = ref(null);
const error = ref(null);

// 🍎 formato novo (rodada 163): kit "iMac G3 + vidro" com a paleta desta
// página (o admin escolhe pelo chip do banner; cada bloco pode ter a sua)
const pal = useCevicoPalette({
  scope: 'report:campanhas',
  blocks: [
    { id: 'custo', label: 'Custo por mensagem', icon: 'i-lucide-calculator' },
    { id: 'kpis', label: 'Indicadores', icon: 'i-lucide-gauge' },
    { id: 'modelos', label: 'Tipo de mensagem', icon: 'i-lucide-layout-template' },
    { id: 'campanhas', label: 'Campanha por campanha', icon: 'i-lucide-list' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

// régua de período PADRÃO CEVICO (06/08) — default 'month' (antes: 30 dias)
const period = ref({ preset: 'month', from: '', to: '' });

// custo por mensagem modelo (R$) — fica salvo no navegador
const costPerMessage = ref(
  parseFloat(localStorage.getItem('cevico_campaign_msg_cost') || '0.5')
);

const fetchData = async () => {
  isLoading.value = true;
  error.value = null;
  try {
    const params = {
      cost_per_message: costPerMessage.value || 0,
      preset: period.value.preset,
      ...(period.value.preset === 'custom'
        ? { from: period.value.from, to: period.value.to }
        : {}),
    };
    const { data: payload } = await CrmAPI.getCampaignsDashboard(params);
    data.value = payload;
  } catch {
    error.value = 'Não foi possível carregar o dashboard de campanhas.';
  } finally {
    isLoading.value = false;
  }
};

let costTimer = null;
watch(costPerMessage, value => {
  localStorage.setItem('cevico_campaign_msg_cost', String(value || 0));
  clearTimeout(costTimer);
  costTimer = setTimeout(fetchData, 600);
});
watch(period, fetchData, { deep: true });
onMounted(fetchData);

const totals = computed(() => data.value?.totals || {});

const formatCurrency = value =>
  (value || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

const formatDate = iso =>
  iso ? new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' }) : '—';
</script>

<template>
  <div class="cv-page h-full w-full overflow-y-auto bg-n-surface-1" :style="cvVars">
    <div class="max-w-6xl mx-auto p-4 sm:p-8">
      <!-- banner de vidro na paleta da página (rodada 163) -->
      <CevicoHero
        :pal="pal"
        title="Dashboard — Campanhas"
        subtitle="Resultados das campanhas de mensagem modelo (WhatsApp)"
        icon="i-lucide-megaphone"
      />

      <!-- Régua de período padrão CEVICO -->
      <PeriodRuler v-model="period" glass class="mb-6" />

      <!-- Custo por mensagem (faixa fina de vidro) -->
      <div
        class="cv-block cv-strip flex items-center gap-2 flex-wrap mb-6 px-4 py-3 text-xs text-n-slate-11"
        :style="blockVars('custo')"
      >
        <span class="cv-icon cv-icon-sm"><span class="i-lucide-calculator text-xs" /></span>
        Custo por mensagem modelo:
        <span class="font-medium text-n-slate-12">R$</span>
        <input
          v-model.number="costPerMessage"
          type="number"
          step="0.01"
          min="0"
          class="cv-input !h-8 w-24 text-xs text-n-slate-12"
        />
        <span class="text-n-slate-9">(valor cobrado pela Meta por template enviado — usado no cálculo de investimento)</span>
      </div>

      <SkeletonScreen v-if="isLoading" variant="dashboard" />
      <div v-else-if="error" class="text-center py-16 text-n-slate-10 text-sm">{{ error }}</div>

      <template v-else>
        <div :style="blockVars('kpis')">
          <!-- KPIs linha 1 (padrão CEVICO: DashKpi) nos degraus da família do bloco -->
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-5 mb-5">
            <DashKpi
              glass
              label="Investimento"
              :value="Math.round(totals.investment || 0)"
              prefix="R$ "
              :sub="`${totals.campaigns || 0} campanha(s) no período`"
              :grad="blockFamily('kpis')[0]"
            />
            <DashKpi
              glass
              label="Volume de mensagens"
              :value="totals.sent || 0"
              sub="mensagens modelo enviadas"
              :grad="blockFamily('kpis')[1]"
            />
            <DashKpi
              glass
              label="Taxa de responsividade"
              :value="`${totals.reply_rate || 0}%`"
              :sub="`${totals.replies || 0} responderam`"
              :grad="blockFamily('kpis')[2]"
            />
            <DashKpi
              glass
              label="Valor em campanha"
              :value="Math.round(totals.potential_value || 0)"
              prefix="R$ "
              sub="$ possível nos cards dos destinatários"
              :grad="blockFamily('kpis')[3]"
            />
          </div>

          <!-- KPIs linha 2: conversões (cartões claros de vidro; verde =
               cirurgia realizada, cor com significado) -->
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-5 mb-8">
            <div class="cv-sub p-5">
              <p class="text-xs font-medium text-n-slate-10 mb-1">Avaliações agendadas</p>
              <p class="text-3xl font-bold" style="color: var(--cv)">{{ totals.agendamentos || 0 }}</p>
            </div>
            <div class="cv-sub p-5">
              <p class="text-xs font-medium text-n-slate-10 mb-1">% de consultas agendadas</p>
              <p class="text-3xl font-bold" style="color: var(--cv)">{{ totals.agendamentos_rate || 0 }}%</p>
              <p class="text-[11px] text-n-slate-9 mt-1">dos destinatários</p>
            </div>
            <div class="cv-sub p-5">
              <p class="text-xs font-medium text-n-slate-10 mb-1">Cirurgias realizadas</p>
              <p class="text-3xl font-bold" style="color: #65A30D">{{ totals.cirurgias || 0 }}</p>
            </div>
            <div class="cv-sub p-5">
              <p class="text-xs font-medium text-n-slate-10 mb-1">% cirurgias agendadas</p>
              <p class="text-3xl font-bold" style="color: #65A30D">{{ totals.cirurgias_rate || 0 }}%</p>
              <p class="text-[11px] text-n-slate-9 mt-1">dos destinatários</p>
            </div>
          </div>
        </div>

        <!-- Tipo de mensagem -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('modelos')">
          <div class="flex items-center gap-2 mb-5 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-layout-template text-base" /></span>
            <h2 class="text-sm font-bold text-n-slate-12">Tipo de mensagem (modelo)</h2>
          </div>
          <div v-if="!data.by_template?.length" class="text-sm text-n-slate-10 text-center py-6">
            Nenhuma campanha enviada no período.
          </div>
          <div v-else class="space-y-2.5">
            <div v-for="t in data.by_template" :key="t.template" class="flex items-center gap-3">
              <span class="text-sm text-n-slate-12 w-56 truncate font-mono">{{ t.template }}</span>
              <div class="cv-track !h-6 flex-1">
                <div
                  class="cv-fill flex items-center px-2"
                  :style="{ width: Math.max((t.sent / (data.by_template[0]?.sent || 1)) * 100, 6) + '%' }"
                >
                  <span class="text-[10px] text-white font-semibold">{{ t.sent }}</span>
                </div>
              </div>
              <span class="text-xs text-n-slate-10 w-28 text-right">{{ t.reply_rate }}% respostas</span>
            </div>
          </div>
        </div>

        <!-- Tabela por campanha -->
        <div class="cv-block p-5 sm:p-6" :style="blockVars('campanhas')">
          <div class="flex items-center gap-2 mb-5 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-list text-base" /></span>
            <h2 class="text-sm font-bold text-n-slate-12">Campanha por campanha</h2>
          </div>
          <div v-if="!data.campaigns?.length" class="text-sm text-n-slate-10 text-center py-6">
            Nenhuma campanha no período selecionado.
          </div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left">
                  <th class="py-2 pr-3 cv-label">Campanha</th>
                  <th class="py-2 pr-3 cv-label">Data</th>
                  <th class="py-2 pr-3 cv-label text-right">Enviadas</th>
                  <th class="py-2 pr-3 cv-label text-right">Respostas</th>
                  <th class="py-2 pr-3 cv-label text-right">Agendamentos</th>
                  <th class="py-2 pr-3 cv-label text-right">Cirurgias</th>
                  <th class="py-2 pr-3 cv-label text-right">Valor possível</th>
                  <th class="py-2 cv-label text-right">Investimento</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="c in data.campaigns"
                  :key="c.id"
                  class="border-t text-n-slate-12"
                  style="border-color: rgb(var(--cv-rgb) / 0.18)"
                >
                  <td class="py-2.5 pr-3">
                    <p class="font-medium truncate max-w-[220px]">{{ c.name }}</p>
                    <p class="text-[10px] text-n-slate-9 font-mono truncate max-w-[220px]">{{ c.template || '—' }}</p>
                  </td>
                  <td class="py-2.5 pr-3 text-xs text-n-slate-10 whitespace-nowrap">{{ formatDate(c.started_at) }}</td>
                  <td class="py-2.5 pr-3 text-right font-semibold">{{ c.sent }}</td>
                  <td class="py-2.5 pr-3 text-right">
                    {{ c.replies }}
                    <span class="text-[10px] text-n-slate-9">({{ c.reply_rate }}%)</span>
                  </td>
                  <td class="py-2.5 pr-3 text-right" style="color: var(--cv)">
                    {{ c.agendamentos }}
                    <span class="text-[10px] text-n-slate-9">({{ c.agendamentos_rate }}%)</span>
                  </td>
                  <td class="py-2.5 pr-3 text-right" style="color: #65A30D">
                    {{ c.cirurgias }}
                    <span class="text-[10px] text-n-slate-9">({{ c.cirurgias_rate }}%)</span>
                  </td>
                  <td class="py-2.5 pr-3 text-right whitespace-nowrap">{{ formatCurrency(c.potential_value) }}</td>
                  <td class="py-2.5 text-right whitespace-nowrap">{{ formatCurrency(c.investment) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-[11px] text-n-slate-9 mt-4">
            Agendamentos e cirurgias contam destinatários cujo card ENTROU nas etapas de
            Agendamento/Cirurgia depois do disparo da campanha (via histórico de etapas).
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
