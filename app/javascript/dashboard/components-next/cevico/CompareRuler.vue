<script setup>
// 📐 BASE DE COMPARAÇÃO PADRÃO do sistema (item 394, 11/11): a chavinha que
// anda ao lado da régua de período (PeriodRuler) e responde "comparar com o
// quê?" — Período anterior | Mês passado | Outro mês (escolhe o mês).
//
// v-model = { mode, month } (helper/cevicoComparison.js). A tela manda
// `compareParams(valor)` para a API; o servidor resolve o intervalo em
// Crm::PeriodComparison e devolve o nome da base ("ontem", "setembro").
import { computed } from 'vue';
import {
  COMPARE_MODES,
  compareMonthOptions,
  normalizeCompare,
} from 'dashboard/helper/cevicoComparison';

const props = defineProps({
  modelValue: {
    type: Object,
    default: () => ({ mode: 'previous', month: '' }),
  },
  // mesmo vidro da régua de período no Meu Painel (kit .cv-seg)
  glass: { type: Boolean, default: false },
  // o que o servidor resolveu: { rotulo: 'setembro', datas: '01/09–30/09' }
  resolved: { type: Object, default: null },
});
const emit = defineEmits(['update:modelValue']);

const valor = computed(() => normalizeCompare(props.modelValue));
const meses = computed(() => compareMonthOptions(12));

const pick = key => {
  if (key === 'pick') {
    emit('update:modelValue', {
      mode: 'pick',
      month: valor.value.month || meses.value[1]?.value || '',
    });
    return;
  }
  emit('update:modelValue', { mode: key, month: '' });
};
const pickMonth = event => {
  emit('update:modelValue', { mode: 'pick', month: event.target.value });
};
const hint = computed(
  () => COMPARE_MODES.find(m => m.key === valor.value.mode)?.hint || ''
);
</script>

<template>
  <div class="cv-compare" :class="{ 'cv-compare--glass': glass }">
    <div
      class="inline-flex items-center gap-0.5 max-w-full flex-nowrap overflow-x-auto"
      :class="
        glass
          ? 'cv-seg'
          : 'min-h-[34px] py-0.5 bg-n-solid-2 border border-n-weak rounded-xl px-0.5'
      "
      :title="hint"
    >
      <span
        class="i-lucide-git-compare-arrows text-sm ml-2 mr-0.5 flex-shrink-0"
        :style="{ color: glass ? 'var(--cv)' : '#7c3aed' }"
      />
      <span class="cv-compare-label">Comparar com</span>
      <button
        v-for="m in COMPARE_MODES"
        :key="m.key"
        type="button"
        class="text-xs font-medium transition-colors whitespace-nowrap flex-shrink-0"
        :class="
          glass
            ? ['cv-seg-item', valor.mode === m.key ? 'cv-seg-on' : '']
            : [
                'h-7 px-2.5 rounded-lg',
                valor.mode === m.key
                  ? 'text-white'
                  : 'text-n-slate-11 hover:bg-n-alpha-1',
              ]
        "
        :style="
          !glass && valor.mode === m.key
            ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' }
            : {}
        "
        :title="m.hint"
        @click="pick(m.key)"
      >
        {{ m.label }}
      </button>
      <select
        v-if="valor.mode === 'pick'"
        class="cv-compare-mes"
        :value="valor.month"
        aria-label="Mês para comparar"
        @change="pickMonth"
      >
        <option v-for="o in meses" :key="o.value" :value="o.value">
          {{ o.label }}
        </option>
      </select>
    </div>
    <span v-if="resolved?.rotulo" class="cv-compare-resolved">
      comparando com <b>{{ resolved.rotulo }}</b>
      <template v-if="resolved.datas"> · {{ resolved.datas }}</template>
    </span>
  </div>
</template>

<style scoped>
.cv-compare {
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 10px;
  max-width: 100%;
}
.cv-compare-label {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.02em;
  white-space: nowrap;
  opacity: 0.7;
  margin-right: 4px;
  flex-shrink: 0;
}
.cv-compare-mes {
  height: 28px;
  margin: 0 2px 0 4px;
  padding: 0 26px 0 10px;
  border-radius: 9999px;
  font-size: 12px;
  font-weight: 600;
  color: inherit;
  background-color: rgb(var(--cv-rgb, 37 99 235) / 0.12);
  border: 1px solid rgb(var(--cv-rgb, 37 99 235) / 0.3);
  flex-shrink: 0;
  cursor: pointer;
}
.cv-compare-resolved {
  font-size: 12px;
  line-height: 16px;
  color: rgb(100 116 139);
  white-space: nowrap;
}
.dark .cv-compare-resolved {
  color: rgb(148 163 184);
}
.cv-compare-resolved b {
  font-weight: 600;
  color: inherit;
}
</style>
