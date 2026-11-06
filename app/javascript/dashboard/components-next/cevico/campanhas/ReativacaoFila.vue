<script setup>
// 🎛️ item 382: A FILA INTEIRA — quem recebe hoje, quem recebe amanhã, lote a
// lote, até a base acabar. Lote 1 = o que ainda cabe hoje, lote 2 = próximo
// dia de envio… Os primeiros dias trazem a lista de pessoas.
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import ReativacaoTabelaPessoas from './ReativacaoTabelaPessoas.vue';
import { people, fmtDay, shortWeekday } from './reativacaoHelpers';

const props = defineProps({
  sliceNames: { type: Object, default: () => ({}) }, // key da fatia → nome da coluna
});

const DETAIL_OPTIONS = [1, 3, 7];
const queue = ref(null);
const loading = ref(false);
const detailDays = ref(3);
const open = ref([]); // lotes abertos

const days = computed(() => queue.value?.days || []);
const summary = computed(() => {
  if (!queue.value) return '';
  const q = queue.value;
  const bits = [`${people(q.total)} ao todo`, `${q.lotes || days.value.length} ${(q.lotes || days.value.length) === 1 ? 'lote' : 'lotes'}`];
  bits.push(`ordem: ${q.order === 'oldest' ? 'mais antigos primeiro' : 'mais recentes primeiro'}`);
  bits.push(`fim de semana: ${q.weekdays_only ? 'pula' : 'manda'}`);
  return bits.join(' · ');
});
const sliceName = key => props.sliceNames[key] || key;
const porFatia = day =>
  Object.entries(day.por_fatia || {})
    .map(([k, n]) => `${sliceName(k)} ${n}`)
    .join(' · ');
const isOpen = lote => open.value.includes(lote);
const toggle = lote => {
  open.value = isOpen(lote) ? open.value.filter(x => x !== lote) : [...open.value, lote];
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAPI.getReactivationQueue({ days: 30, detailDays: detailDays.value });
    queue.value = data;
    open.value = (data.days || []).filter(d => d.rows).map(d => d.lote).slice(0, 1);
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para montar a fila.');
  } finally {
    loading.value = false;
  }
};
const setDetail = n => {
  detailDays.value = n;
  if (queue.value) load();
};
</script>

<template>
  <div class="cv-sub p-4 sm:p-6">
    <div class="flex items-center gap-2 mb-3 flex-wrap">
      <span class="cv-icon cv-icon-sm"><span class="i-lucide-list-ordered text-sm" /></span>
      <h3 class="text-sm font-bold text-n-slate-12">A fila inteira</h3>
      <div class="ml-auto flex items-center gap-2 flex-wrap">
        <span class="text-[11px] text-n-slate-10">pessoas nos primeiros</span>
        <button
          v-for="n in DETAIL_OPTIONS"
          :key="n"
          class="cv-chip"
          :class="{ 'cv-chip-on': detailDays === n }"
          :disabled="loading"
          @click="setDetail(n)"
        >
          {{ n }} {{ n === 1 ? 'dia' : 'dias' }}
        </button>
        <button class="cv-btn cv-btn-sm cv-btn-ghost" :disabled="loading" @click="load">
          <span class="i-lucide-eye text-sm" />
          {{ loading ? 'Montando…' : queue ? 'Montar de novo' : 'Ver a fila' }}
        </button>
      </div>
    </div>
    <p class="text-xs text-n-slate-10 leading-relaxed mb-3">
      Lote 1 é o que ainda cabe hoje; lote 2 é o próximo dia de envio, e assim por diante, até a base inteira ter recebido.
    </p>

    <template v-if="queue">
      <p class="text-xs font-semibold text-n-slate-12 mb-2">{{ summary }}</p>
      <p v-if="!days.length" class="text-xs text-n-slate-10 text-center py-3">
        Ninguém na fila agora.
      </p>
      <div v-else class="space-y-2">
        <article v-for="d in days" :key="d.lote" class="lote">
          <button class="w-full flex items-center gap-2 flex-wrap text-left" @click="toggle(d.lote)">
            <span class="lote-num">{{ d.lote }}</span>
            <span class="text-xs font-semibold text-n-slate-12 whitespace-nowrap">
              Lote {{ d.lote }} · {{ shortWeekday(d.weekday) }} {{ fmtDay(d.date) }}
            </span>
            <span class="text-xs text-n-slate-11 whitespace-nowrap">· {{ people(d.total) }}</span>
            <span class="text-[11px] text-n-slate-10 min-w-0 truncate">({{ porFatia(d) }})</span>
            <span class="ml-auto flex items-center gap-1 text-[11px] text-n-slate-10">
              <template v-if="d.rows">{{ isOpen(d.lote) ? 'esconder' : 'ver as pessoas' }}</template>
              <template v-else>só o resumo</template>
              <span v-if="d.rows" :class="isOpen(d.lote) ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="text-sm" />
            </span>
          </button>
          <ReativacaoTabelaPessoas v-if="d.rows && isOpen(d.lote)" :rows="d.rows" class="mt-2" />
        </article>
      </div>
      <p v-if="queue.restam" class="text-[11px] text-n-slate-10 mt-2">
        {{ people(queue.restam) }} ficam depois dos 30 dias mostrados.
      </p>
    </template>
    <p v-else-if="!loading" class="text-xs text-n-slate-10 text-center py-3">
      Clique em “Ver a fila” para enxergar quem recebe em cada dia.
    </p>
  </div>
</template>

<style scoped>
.lote {
  padding: 10px 12px;
  border-radius: 14px;
  background: rgb(var(--cv-rgb) / 0.05);
  border: 1px solid rgb(var(--cv-rgb) / 0.18);
}
.dark .lote {
  background: rgba(255, 255, 255, 0.03);
  border-color: rgb(var(--cv-rgb) / 0.3);
}
.lote-num {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 800;
  color: #fff;
  background: var(--cv-grad);
  border: 1px solid rgba(255, 255, 255, 0.35);
  flex-shrink: 0;
}
</style>
