<script setup>
// 🏥 LUCRATIVIDADE (item 157): o que sobra de verdade por cirurgia, com os
// dados do OftalmoFácil — receita, custo do prestador, taxa da plataforma,
// resultado CEVICO, margem, ticket; cortes por procedimento/prestador/médico
// e mês; e o marketing do período pra chegar no resultado LÍQUIDO.
import { ref, computed, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const data = ref(null);
const period = ref({ preset: 'month' });
const cut = ref('by_procedure');

const CUTS = [
  { key: 'by_procedure', label: 'Por procedimento', icon: 'i-lucide-scissors' },
  { key: 'by_clinic', label: 'Por prestador', icon: 'i-lucide-building-2' },
  { key: 'by_doctor', label: 'Por médico', icon: 'i-lucide-stethoscope' },
];

const fmtMoney = v =>
  Number(v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const fmtPct = v => (v === null || v === undefined ? '—' : `${Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`);
const fmtMonth = m => {
  const [y, mm] = m.split('-');
  return new Date(Number(y), Number(mm) - 1, 1).toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' });
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getProfitability(period.value);
    data.value = payload;
  } catch {
    data.value = null;
  } finally {
    isLoading.value = false;
  }
};
const onPeriod = p => {
  period.value = p;
  load();
};
onMounted(load);

const s = computed(() => data.value?.summary || {});
// cards principais — dopamine: degradê pleno + fonte branca (padrão do Financeiro)
const kpiCards = computed(() => [
  { key: 'receita', label: 'Receita das cirurgias', value: s.value.receita, grad: 'linear-gradient(135deg, #0F5FA6, #3B82F6)', icon: 'i-lucide-wallet', badge: `${s.value.count || 0} realizada(s)` },
  { key: 'custo', label: 'Custo do prestador', value: s.value.custo, grad: 'linear-gradient(135deg, #B45309, #F59E0B)', icon: 'i-lucide-building-2', badge: 'repasse ao centro cirúrgico' },
  { key: 'taxa', label: 'Taxa da plataforma', value: s.value.taxa, grad: 'linear-gradient(135deg, #6D28D9, #8B5CF6)', icon: 'i-lucide-percent', badge: 'fica no OftalmoFácil' },
  { key: 'resultado', label: 'Resultado CEVICO', value: s.value.resultado, grad: 'linear-gradient(135deg, #065F46, #10B981)', icon: 'i-lucide-trending-up', badge: `margem ${fmtPct(s.value.margem_pct)}` },
]);
const secondCards = computed(() => [
  { key: 'ticket', label: 'Ticket médio', hint: 'receita ÷ cirurgias', value: s.value.ticket, grad: 'linear-gradient(135deg, #1E3A8A, #2563EB)', icon: 'i-lucide-receipt' },
  { key: 'por_cirurgia', label: 'Resultado por cirurgia', hint: 'o que cada cirurgia deixa', value: s.value.resultado_por_cirurgia, grad: 'linear-gradient(135deg, #047857, #34D399)', icon: 'i-lucide-coins' },
  { key: 'marketing', label: 'Marketing no período', hint: 'investimento por caixa, rateado', value: s.value.marketing, grad: 'linear-gradient(135deg, #9D174D, #EC4899)', icon: 'i-lucide-megaphone' },
  { key: 'liquido', label: 'Resultado líquido', hint: 'resultado − marketing', value: s.value.resultado_liquido, grad: 'linear-gradient(135deg, #7C2D12, #EA580C)', icon: 'i-lucide-badge-dollar-sign' },
]);
const rows = computed(() => data.value?.[cut.value] || []);
const maxResultado = computed(() => Math.max(1, ...rows.value.map(r => Math.abs(r.resultado || 0))));
const monthly = computed(() => data.value?.monthly || []);
const maxMonth = computed(() => Math.max(1, ...monthly.value.map(m => m.receita || 0)));
</script>

<template>
  <div>
    <div class="mb-4 flex items-start justify-between gap-3 flex-wrap">
      <div>
        <p class="text-sm font-semibold text-n-slate-12">💰 Lucratividade das cirurgias</p>
        <p class="text-xs text-n-slate-10">
          O que sobra de verdade — receita, custo do prestador, taxa da plataforma e resultado CEVICO, direto do OftalmoFácil
        </p>
      </div>
      <PeriodRuler :model-value="period" @update:model-value="onPeriod" />
    </div>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <div v-else-if="!data || !data.has_data" class="rounded-2xl border border-dashed border-n-weak p-10 text-center">
      <span class="i-lucide-plug-zap text-4xl text-n-slate-9 block mx-auto mb-2" />
      <p class="text-sm font-medium text-n-slate-12">Ainda sem cirurgias sincronizadas</p>
      <p class="text-xs text-n-slate-10 mt-1 max-w-md mx-auto">
        Ligue a conexão em <b>Integrações → OftalmoFácil</b> (usuário só-leitura do banco). Assim que a primeira sincronização rodar, este painel acende sozinho.
      </p>
    </div>

    <template v-else>
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-3">
        <div
          v-for="card in kpiCards"
          :key="card.key"
          class="relative rounded-2xl p-4 text-white shadow-md overflow-hidden"
          :style="{ background: card.grad }"
        >
          <span :class="card.icon" class="absolute -right-2 -bottom-3 text-[64px] text-white/15 pointer-events-none" />
          <p class="text-[11px] font-bold leading-tight relative" style="color: rgba(255,255,255,0.9)">{{ card.label }}</p>
          <p class="text-xl sm:text-2xl font-bold tabular-nums mt-1.5 relative" style="color: #fff">{{ fmtMoney(card.value) }}</p>
          <span v-if="card.badge" class="inline-block mt-1.5 text-[10px] font-semibold px-2 py-0.5 rounded-full bg-black/20 relative" style="color: #fff">{{ card.badge }}</span>
        </div>
      </div>
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <div
          v-for="card in secondCards"
          :key="card.key"
          class="relative rounded-2xl p-4 text-white shadow-md overflow-hidden"
          :style="{ background: card.grad }"
        >
          <span :class="card.icon" class="absolute -right-2 -bottom-3 text-[56px] text-white/15 pointer-events-none" />
          <p class="text-[11px] font-bold leading-tight relative" style="color: rgba(255,255,255,0.9)">{{ card.label }}</p>
          <p class="text-[10px] relative" style="color: rgba(255,255,255,0.65)">{{ card.hint }}</p>
          <p class="text-lg font-bold tabular-nums mt-1 relative" style="color: #fff">{{ fmtMoney(card.value) }}</p>
        </div>
      </div>

      <p v-if="s.agendadas" class="text-xs text-n-slate-10 mb-4">
        📅 Além das realizadas, há <b>{{ s.agendadas }}</b> cirurgia(s) agendada(s) no período somando <b>{{ fmtMoney(s.agendadas_receita) }}</b> — entram no resultado quando acontecerem.
      </p>

      <!-- cortes -->
      <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4">
        <div class="flex items-center gap-1.5 flex-wrap mb-3">
          <button
            v-for="c in CUTS"
            :key="c.key"
            class="h-8 px-3 rounded-lg text-xs font-medium border transition-colors flex items-center gap-1.5"
            :class="cut === c.key ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            :style="cut === c.key ? { background: 'linear-gradient(135deg, #065F46, #10B981)' } : {}"
            @click="cut = c.key"
          >
            <span :class="c.icon" class="text-sm" />{{ c.label }}
          </button>
        </div>
        <p v-if="!rows.length" class="text-xs text-n-slate-10">Sem cirurgias realizadas neste recorte.</p>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr class="text-left text-n-slate-10">
                <th class="py-1.5 pr-3 font-medium">{{ CUTS.find(c => c.key === cut)?.label.replace('Por ', '') }}</th>
                <th class="py-1.5 px-2 font-medium text-right">Cirurgias</th>
                <th class="py-1.5 px-2 font-medium text-right">Receita</th>
                <th class="py-1.5 px-2 font-medium text-right">Custo</th>
                <th class="py-1.5 px-2 font-medium text-right">Taxa</th>
                <th class="py-1.5 px-2 font-medium text-right">Resultado</th>
                <th class="py-1.5 px-2 font-medium text-right">Margem</th>
                <th class="py-1.5 pl-2 font-medium w-40"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in rows" :key="r.key" class="border-t border-n-weak/60">
                <td class="py-2 pr-3 text-n-slate-12 font-medium max-w-[260px] truncate" :title="r.label">{{ r.label }}</td>
                <td class="py-2 px-2 text-right tabular-nums text-n-slate-11">{{ r.count }}</td>
                <td class="py-2 px-2 text-right tabular-nums text-n-slate-11">{{ fmtMoney(r.receita) }}</td>
                <td class="py-2 px-2 text-right tabular-nums text-n-slate-10">{{ fmtMoney(r.custo) }}</td>
                <td class="py-2 px-2 text-right tabular-nums text-n-slate-10">{{ fmtMoney(r.taxa) }}</td>
                <td class="py-2 px-2 text-right tabular-nums font-bold" :class="r.resultado >= 0 ? 'text-emerald-600' : 'text-red-500'">{{ fmtMoney(r.resultado) }}</td>
                <td class="py-2 px-2 text-right tabular-nums text-n-slate-11">{{ fmtPct(r.margem_pct) }}</td>
                <td class="py-2 pl-2">
                  <div class="h-2 rounded-full bg-n-alpha-2 overflow-hidden">
                    <div class="h-full rounded-full" :style="{ width: `${Math.max(3, (Math.abs(r.resultado) / maxResultado) * 100)}%`, background: 'linear-gradient(90deg, #065F46, #10B981)' }" />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- mês a mês -->
      <div v-if="monthly.length" class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
        <p class="text-xs font-semibold text-n-slate-12 mb-3">📈 Mês a mês — receita × resultado</p>
        <div class="space-y-2">
          <div v-for="m in monthly" :key="m.month" class="flex items-center gap-3 text-xs">
            <span class="w-14 text-n-slate-10 capitalize">{{ fmtMonth(m.month) }}</span>
            <div class="flex-1 h-5 rounded-lg bg-n-alpha-1 relative overflow-hidden">
              <div class="absolute inset-y-0 left-0 rounded-lg" :style="{ width: `${(m.receita / maxMonth) * 100}%`, background: 'rgba(15,95,166,0.25)' }" />
              <div class="absolute inset-y-0 left-0 rounded-lg" :style="{ width: `${(Math.max(0, m.resultado) / maxMonth) * 100}%`, background: 'linear-gradient(90deg, #065F46, #10B981)' }" />
            </div>
            <span class="w-24 text-right tabular-nums text-n-slate-11">{{ fmtMoney(m.receita) }}</span>
            <span class="w-24 text-right tabular-nums font-bold text-emerald-600">{{ fmtMoney(m.resultado) }}</span>
            <span class="w-12 text-right tabular-nums text-n-slate-10">{{ m.count }}×</span>
          </div>
        </div>
        <p class="text-[10px] text-n-slate-9 mt-2">barra clara = receita · barra verde = resultado CEVICO</p>
      </div>

      <p class="text-[10px] text-n-slate-9 mt-4 leading-relaxed">ℹ️ {{ data.note }}</p>
    </template>
  </div>
</template>
