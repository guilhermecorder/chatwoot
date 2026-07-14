<script setup>
// Dashboard das campanhas de mensagem modelo — investimento, volume,
// responsividade e conversões, no mesmo visual do Dashboard CEVICO.
import { ref, computed, onMounted, watch } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const data = ref(null);
const error = ref(null);

const PERIOD_PRESETS = [
  { key: 'today', label: 'Hoje' },
  { key: 'yesterday', label: 'Ontem' },
  { key: 'week', label: 'Essa semana' },
  { key: '30', label: '30 dias' },
  { key: '90', label: '90 dias' },
  { key: '365', label: '1 ano' },
];
const selectedPeriodKey = ref('30');

// custo por mensagem modelo (R$) — fica salvo no navegador
const costPerMessage = ref(
  parseFloat(localStorage.getItem('cevico_campaign_msg_cost') || '0.5')
);

const fetchData = async () => {
  isLoading.value = true;
  error.value = null;
  try {
    const preset = selectedPeriodKey.value;
    const params = { cost_per_message: costPerMessage.value || 0 };
    if (['today', 'yesterday', 'week'].includes(preset)) params.preset = preset;
    else params.period = preset;
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
watch(selectedPeriodKey, fetchData);
onMounted(fetchData);

const totals = computed(() => data.value?.totals || {});

const formatCurrency = value =>
  (value || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

const formatDate = iso =>
  iso ? new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit' }) : '—';
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-6xl mx-auto p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-6">
        <h1 class="text-lg font-bold text-n-slate-12 flex items-center gap-2">
          <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
            <span class="i-lucide-megaphone text-white text-base" />
          </span>
          Dashboard — Campanhas
        </h1>
        <p class="text-xs text-n-slate-10 w-full sm:w-auto">
          Resultados das campanhas de mensagem modelo (WhatsApp)
        </p>

        <div class="flex items-center gap-1 ml-auto flex-wrap">
          <button
            v-for="p in PERIOD_PRESETS"
            :key="p.key"
            class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
            :class="selectedPeriodKey === p.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="selectedPeriodKey === p.key ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="selectedPeriodKey = p.key"
          >
            {{ p.label }}
          </button>
        </div>
      </div>

      <!-- Custo por mensagem -->
      <div class="flex items-center gap-2 mb-6 text-xs text-n-slate-11">
        <span class="i-lucide-calculator text-sm text-n-slate-10" />
        Custo por mensagem modelo:
        <span class="font-medium">R$</span>
        <input
          v-model.number="costPerMessage"
          type="number"
          step="0.01"
          min="0"
          class="w-20 border border-n-weak rounded-lg px-2 py-1 text-xs bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
        />
        <span class="text-n-slate-9">(valor cobrado pela Meta por template enviado — usado no cálculo de investimento)</span>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>
      <div v-else-if="error" class="text-center py-16 text-n-slate-10 text-sm">{{ error }}</div>

      <template v-else>
        <!-- KPIs linha 1 -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-5 mb-5">
          <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #0F5FA6, #0B4A82)">
            <p class="text-xs font-medium text-white/80 mb-1">Investimento</p>
            <p class="text-2xl font-bold leading-tight">{{ formatCurrency(totals.investment) }}</p>
            <p class="text-[11px] text-white/70 mt-1">{{ totals.campaigns || 0 }} campanha(s) no período</p>
          </div>
          <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
            <p class="text-xs font-medium text-white/80 mb-1">Volume de mensagens</p>
            <p class="text-3xl font-bold">{{ totals.sent || 0 }}</p>
            <p class="text-[11px] text-white/70 mt-1">mensagens modelo enviadas</p>
          </div>
          <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
            <p class="text-xs font-medium text-white/80 mb-1">Taxa de responsividade</p>
            <p class="text-3xl font-bold">{{ totals.reply_rate || 0 }}%</p>
            <p class="text-[11px] text-white/70 mt-1">{{ totals.replies || 0 }} responderam</p>
          </div>
          <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #65A30D, #84CC16)">
            <p class="text-xs font-medium text-white/80 mb-1">Valor em campanha</p>
            <p class="text-2xl font-bold leading-tight">{{ formatCurrency(totals.potential_value) }}</p>
            <p class="text-[11px] text-white/70 mt-1">$ possível nos cards dos destinatários</p>
          </div>
        </div>

        <!-- KPIs linha 2: conversões -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-5 mb-8">
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <p class="text-xs font-medium text-n-slate-10 mb-1">Avaliações agendadas</p>
            <p class="text-3xl font-bold" style="color: #7C3AED">{{ totals.agendamentos || 0 }}</p>
          </div>
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <p class="text-xs font-medium text-n-slate-10 mb-1">% de consultas agendadas</p>
            <p class="text-3xl font-bold" style="color: #7C3AED">{{ totals.agendamentos_rate || 0 }}%</p>
            <p class="text-[11px] text-n-slate-9 mt-1">dos destinatários</p>
          </div>
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <p class="text-xs font-medium text-n-slate-10 mb-1">Cirurgias realizadas</p>
            <p class="text-3xl font-bold" style="color: #65A30D">{{ totals.cirurgias || 0 }}</p>
          </div>
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <p class="text-xs font-medium text-n-slate-10 mb-1">% cirurgias agendadas</p>
            <p class="text-3xl font-bold" style="color: #65A30D">{{ totals.cirurgias_rate || 0 }}%</p>
            <p class="text-[11px] text-n-slate-9 mt-1">dos destinatários</p>
          </div>
        </div>

        <!-- Tipo de mensagem -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <div class="flex items-center gap-2 mb-5">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-layout-template text-white text-sm" />
            </span>
            <h3 class="text-sm font-bold text-n-slate-12">Tipo de mensagem (modelo)</h3>
          </div>
          <div v-if="!data.by_template?.length" class="text-sm text-n-slate-10 text-center py-6">
            Nenhuma campanha enviada no período.
          </div>
          <div v-else class="space-y-2.5">
            <div v-for="t in data.by_template" :key="t.template" class="flex items-center gap-3">
              <span class="text-sm text-n-slate-12 w-56 truncate font-mono">{{ t.template }}</span>
              <div class="flex-1 h-6 bg-n-alpha-1 rounded-lg overflow-hidden">
                <div
                  class="h-full rounded-lg flex items-center px-2"
                  :style="{
                    width: Math.max((t.sent / (data.by_template[0]?.sent || 1)) * 100, 6) + '%',
                    background: 'linear-gradient(90deg, #0F5FA6, #7C3AED)',
                  }"
                >
                  <span class="text-[10px] text-white font-semibold">{{ t.sent }}</span>
                </div>
              </div>
              <span class="text-xs text-n-slate-10 w-28 text-right">{{ t.reply_rate }}% respostas</span>
            </div>
          </div>
        </div>

        <!-- Tabela por campanha -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <div class="flex items-center gap-2 mb-5">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
              <span class="i-lucide-list text-white text-sm" />
            </span>
            <h3 class="text-sm font-bold text-n-slate-12">Campanha por campanha</h3>
          </div>
          <div v-if="!data.campaigns?.length" class="text-sm text-n-slate-10 text-center py-6">
            Nenhuma campanha no período selecionado.
          </div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left text-[11px] text-n-slate-10 uppercase">
                  <th class="py-2 pr-3 font-medium">Campanha</th>
                  <th class="py-2 pr-3 font-medium">Data</th>
                  <th class="py-2 pr-3 font-medium text-right">Enviadas</th>
                  <th class="py-2 pr-3 font-medium text-right">Respostas</th>
                  <th class="py-2 pr-3 font-medium text-right">Agendamentos</th>
                  <th class="py-2 pr-3 font-medium text-right">Cirurgias</th>
                  <th class="py-2 pr-3 font-medium text-right">Valor possível</th>
                  <th class="py-2 font-medium text-right">Investimento</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="c in data.campaigns" :key="c.id" class="border-t border-n-weak text-n-slate-12">
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
                  <td class="py-2.5 pr-3 text-right" style="color: #7C3AED">
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
