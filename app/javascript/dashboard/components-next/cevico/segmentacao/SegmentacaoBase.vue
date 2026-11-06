<script setup>
// 🧪 item 383: SUA BASE — cada coluna da casa com quantas pessoas têm
// telefone, quantas já estão em algum segmento (já testadas ou reservadas) e
// quantas podem receber hoje pelas regras padrão. Clicar numa coluna já a
// escolhe no formulário de segmento novo.
import { computed } from 'vue';
import { fmtInt, pct } from './segmentacaoHelpers';

const props = defineProps({
  stages: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  selected: { type: Array, default: () => [] }, // stage_ids escolhidos no formulário
});
const emit = defineEmits(['pick']);

const totals = computed(() =>
  props.stages.reduce(
    (acc, s) => ({
      cards: acc.cards + Number(s.cards || 0),
      with_phone: acc.with_phone + Number(s.with_phone || 0),
      in_segment: acc.in_segment + Number(s.in_segment || 0),
      eligible: acc.eligible + Number(s.eligible || 0),
    }),
    { cards: 0, with_phone: 0, in_segment: 0, eligible: 0 }
  )
);
const isOn = id => props.selected.includes(id);
</script>

<template>
  <div>
    <div class="flex items-start gap-4 mb-6 flex-wrap">
      <span class="cv-icon cv-icon-lg"><span class="i-lucide-database text-xl" /></span>
      <div class="min-w-0 flex-1">
        <h2 class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight">1. Sua base</h2>
        <p class="text-sm text-n-slate-11 mt-1">
          Quem está em cada coluna do CRM, quem já entrou em algum segmento (reservado ou testado) e quem ainda pode receber hoje.
          Clique numa coluna para começar um segmento com ela.
        </p>
      </div>
    </div>

    <p v-if="loading" class="text-sm text-n-slate-10">Contando a base…</p>
    <template v-else>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
        <div class="base-num"><b>{{ fmtInt(totals.with_phone) }}</b><span>pessoas com telefone</span></div>
        <div class="base-num"><b>{{ fmtInt(totals.in_segment) }}</b><span>já em algum segmento</span></div>
        <div class="base-num"><b>{{ fmtInt(totals.eligible) }}</b><span>podem receber hoje</span></div>
        <div class="base-num"><b>{{ pct(totals.in_segment, totals.with_phone) }}%</b><span>da base já trabalhada</span></div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        <button
          v-for="s in stages"
          :key="s.stage_id"
          class="base-col text-left"
          :class="{ 'base-col-on': isOn(s.stage_id) }"
          :title="isOn(s.stage_id) ? 'Esta coluna já está escolhida no segmento novo' : 'Escolher esta coluna no segmento novo'"
          @click="emit('pick', s.stage_id)"
        >
          <div class="flex items-center justify-between gap-2 mb-2">
            <span class="font-bold text-n-slate-12 text-sm">{{ s.name }}</span>
            <span class="cv-chip" :class="isOn(s.stage_id) ? 'cv-chip-on' : ''">
              <span :class="isOn(s.stage_id) ? 'i-lucide-check' : 'i-lucide-plus'" class="text-xs" />
              {{ isOn(s.stage_id) ? 'escolhida' : 'escolher' }}
            </span>
          </div>
          <div class="base-bar mb-2">
            <span :style="{ width: `${pct(s.in_segment, s.with_phone)}%` }" />
          </div>
          <div class="flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-n-slate-11">
            <span><b class="text-n-slate-12 tabular-nums">{{ fmtInt(s.with_phone) }}</b> com telefone</span>
            <span><b class="text-n-slate-12 tabular-nums">{{ fmtInt(s.in_segment) }}</b> em segmento</span>
            <span><b class="text-n-slate-12 tabular-nums">{{ fmtInt(s.eligible) }}</b> podem receber</span>
          </div>
        </button>
      </div>
      <p v-if="!stages.length" class="text-sm text-n-slate-10">Nenhuma coluna encontrada no funil da casa.</p>
      <p class="text-[11px] text-n-slate-10 mt-4">
        “Podem receber” já tira: não perturbe e pacientes de parceiro, quem conversou nas últimas 24 h, quem tem consulta ou cirurgia marcada,
        quem chegou há menos de 3 dias, quem está em outro segmento e quem recebeu campanha nos últimos 30 dias. Essas regras você ajusta no segmento novo.
      </p>
    </template>
  </div>
</template>

<style scoped>
.base-num {
  padding: 12px 14px;
  border-radius: 14px;
  background: rgb(var(--cv-rgb) / 0.08);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.base-num b {
  font-size: 20px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
  line-height: 1.1;
  white-space: nowrap;
}
.base-num span {
  font-size: 11px;
  opacity: 0.75;
}
.base-col {
  padding: 14px 16px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.5);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
  transition: border-color 0.15s ease, transform 0.15s ease;
}
.base-col:hover {
  border-color: rgb(var(--cv-rgb) / 0.5);
  transform: translateY(-1px);
}
.base-col-on {
  border-color: rgb(var(--cv-rgb) / 0.6);
  background: rgb(var(--cv-rgb) / 0.08);
}
.dark .base-col {
  background: rgba(255, 255, 255, 0.03);
}
.base-bar {
  height: 6px;
  border-radius: 9999px;
  background: rgb(var(--cv-rgb) / 0.14);
  overflow: hidden;
}
.base-bar > span {
  display: block;
  height: 100%;
  border-radius: 9999px;
  background: var(--cv-grad);
}
</style>
