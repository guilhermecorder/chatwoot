<script setup>
// 🎛️ item 382: a TABELA DE PESSOAS do controle do lote — a mesma para a
// próxima fatia (com caixinha de marcar) e para a fila (só leitura).
// Colunas: nome, telefone, coluna do CRM, frente, caixa, modelo.
import { computed } from 'vue';
import { fmtPhone, frenteLabel } from './reativacaoHelpers';

const props = defineProps({
  rows: { type: Array, default: () => [] },
  selectable: { type: Boolean, default: false },
  selected: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:selected']);

const isOn = id => props.selected.includes(id);
const allOn = computed(
  () => props.rows.length > 0 && props.rows.every(r => isOn(r.contact_id))
);
const toggle = id => {
  const next = isOn(id) ? props.selected.filter(x => x !== id) : [...props.selected, id];
  emit('update:selected', next);
};
const toggleAll = () => {
  emit('update:selected', allOn.value ? [] : props.rows.map(r => r.contact_id));
};
</script>

<template>
  <div class="overflow-x-auto -mx-1 px-1">
    <table class="w-full text-xs tabela">
      <thead>
        <tr class="text-left">
          <th v-if="selectable" class="py-2 pr-2 w-6">
            <input
              type="checkbox"
              class="rounded border-n-weak"
              :checked="allOn"
              title="Marcar ou desmarcar todo mundo"
              @change="toggleAll"
            />
          </th>
          <th class="py-2 pr-3 cv-label">Nome</th>
          <th class="py-2 pr-3 cv-label">Telefone</th>
          <th class="py-2 pr-3 cv-label">Coluna</th>
          <th class="py-2 pr-3 cv-label">Frente</th>
          <th class="py-2 pr-3 cv-label">Caixa</th>
          <th class="py-2 cv-label">Modelo</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="r in rows"
          :key="r.contact_id"
          class="border-t text-n-slate-12"
          :class="{ 'opacity-50': selectable && !isOn(r.contact_id) }"
        >
          <td v-if="selectable" class="py-2 pr-2">
            <input
              type="checkbox"
              class="rounded border-n-weak"
              :checked="isOn(r.contact_id)"
              @change="toggle(r.contact_id)"
            />
          </td>
          <td class="py-2 pr-3 font-medium whitespace-nowrap max-w-[180px] truncate">{{ r.name || 'Sem nome' }}</td>
          <td class="py-2 pr-3 tabular-nums whitespace-nowrap text-n-slate-11">{{ fmtPhone(r.phone) }}</td>
          <td class="py-2 pr-3 whitespace-nowrap text-n-slate-11">{{ r.stage_name || '—' }}</td>
          <td class="py-2 pr-3 whitespace-nowrap text-n-slate-11">{{ frenteLabel(r.frente) }}</td>
          <td class="py-2 pr-3 whitespace-nowrap">
            <template v-if="r.fallback">
              <span class="text-amber-700 dark:text-amber-300">
                {{ r.inbox_name }} <span class="opacity-80">· via padrão (origem: {{ r.origin_inbox }})</span>
              </span>
            </template>
            <span v-else class="text-n-slate-11">{{ r.inbox_name || '—' }}</span>
          </td>
          <td class="py-2 font-mono text-[11px] text-n-slate-10 whitespace-nowrap">{{ r.template || '—' }}</td>
        </tr>
      </tbody>
    </table>
    <p v-if="!rows.length" class="text-xs text-n-slate-10 text-center py-3">Ninguém nesta lista.</p>
  </div>
</template>

<style scoped>
.tabela tbody tr {
  border-color: rgb(var(--cv-rgb) / 0.18);
}
</style>
