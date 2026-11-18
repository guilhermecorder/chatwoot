<script setup>
// 🧭 18/11/2026 (LIFE, pedido do Guilherme): ETAPA DA VENDA do cliente, com
// botões para a equipe marcar o que acontece depois do orçamento ("formas
// do Fernando apertar um botão… porque no meu painel ele não está
// registrando"). É a mesma régua da Jornada da venda do Meu Painel
// (app/services/crm/quote_journey.rb): o que se marca aqui aparece lá.
// Marcar = etiqueta no contato; a automação da coluna leva o cartão.
import { ref, computed, watch, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
  // 'side' = painel da conversa; 'block' = Central do cliente
  variant: { type: String, default: 'side' },
  canEdit: { type: Boolean, default: true },
});

const TXT = {
  title: 'Etapa da venda',
  subtitle: 'Marque o que já aconteceu. Aparece na Jornada do Meu Painel.',
  mark: 'Marcar',
  undo: 'Desfazer',
  payment: 'Como vai pagar',
  marked: 'Etapa marcada.',
  undone: 'Marcação desfeita.',
  error: 'Não consegui marcar a etapa agora.',
};

const data = ref(null);
const busy = ref('');

const steps = computed(() => data.value?.steps || []);
const payments = computed(() => data.value?.payments || []);

const load = async () => {
  if (!props.contactId) return;
  try {
    const response = await CrmAPI.getSaleSteps(props.contactId);
    data.value = response.data;
  } catch {
    data.value = null;
  }
};
onMounted(load);
watch(() => props.contactId, load);

const send = async (step, payload, message) => {
  if (busy.value || !props.canEdit) return;
  busy.value = step.key;
  try {
    const response = await CrmAPI.markSaleStep(props.contactId, {
      step: step.key,
      ...payload,
    });
    data.value = response.data;
    useAlert(message);
  } catch (error) {
    useAlert(error?.response?.data?.error || TXT.error);
  } finally {
    busy.value = '';
  }
};
const mark = step => send(step, {}, TXT.marked);
const undo = step => send(step, { undo: true }, TXT.undone);
const pay = (step, payment) => send(step, { payment }, TXT.marked);
const isPayment = step => step.key === 'pagamento';
</script>

<template>
  <div
    v-if="steps.length"
    class="ss"
    :class="variant === 'block' ? 'cv-block p-5 sm:p-6' : 'cv-side-card p-4'"
  >
    <div class="ss-head">
      <span class="ss-icon"><span class="i-lucide-route" /></span>
      <div class="min-w-0">
        <p class="ss-title">{{ TXT.title }}</p>
        <p class="ss-sub">{{ TXT.subtitle }}</p>
      </div>
    </div>
    <ol class="ss-list">
      <li
        v-for="step in steps"
        :key="step.key"
        class="ss-row"
        :class="{
          'ss-done': step.reached,
          'ss-now': step.current,
          'ss-busy': busy === step.key,
        }"
      >
        <span class="ss-dot">
          <span v-if="step.reached" class="i-lucide-check" />
        </span>
        <span class="ss-label" :title="step.hint || ''">
          {{ step.label }}
          <small v-if="isPayment(step) && data.payment" class="ss-value">
            {{ data.payment }}
          </small>
        </span>
        <template v-if="step.markable && canEdit">
          <span
            v-if="isPayment(step) && !step.marked && !step.reached"
            class="ss-choices"
          >
            <button
              v-for="payment in payments"
              :key="payment.key"
              type="button"
              class="ss-btn"
              :title="TXT.payment"
              @click="pay(step, payment.key)"
            >
              {{ payment.label }}
            </button>
          </span>
          <button
            v-else-if="step.marked"
            type="button"
            class="ss-btn ss-btn-undo"
            @click="undo(step)"
          >
            {{ TXT.undo }}
          </button>
          <button
            v-else-if="!step.reached"
            type="button"
            class="ss-btn ss-btn-mark"
            :title="step.hint || ''"
            @click="mark(step)"
          >
            {{ TXT.mark }}
          </button>
        </template>
      </li>
    </ol>
  </div>
</template>

<style scoped>
.ss {
  --ss-accent: #ea580c;
  --ss-ok: #16a34a;
}
.ss-head {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 10px;
}
.ss-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  flex: none;
  border-radius: 8px;
  font-size: 14px;
  color: #fff;
  background: var(--ss-accent);
}
.ss-title {
  font-size: 13px;
  font-weight: 700;
  line-height: 1.2;
  color: #0f172a;
}
.ss-sub {
  font-size: 11px;
  line-height: 1.3;
  color: #64748b;
}
.ss-list {
  display: flex;
  flex-direction: column;
  margin: 0;
  padding: 0;
  list-style: none;
}
.ss-row {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px 8px;
  min-height: 32px;
  padding: 4px 0;
  border-top: 1px solid rgba(100, 116, 139, 0.16);
}
.ss-row:first-child {
  border-top: 0;
}
.ss-busy {
  opacity: 0.5;
}
.ss-dot {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  flex: none;
  border-radius: 9999px;
  border: 2px solid rgba(100, 116, 139, 0.45);
  font-size: 11px;
  color: #fff;
}
.ss-done .ss-dot {
  border-color: var(--ss-ok);
  background: var(--ss-ok);
}
.ss-now .ss-dot {
  border-color: var(--ss-accent);
  background: var(--ss-accent);
}
.ss-label {
  flex: 1;
  min-width: 0;
  font-size: 12.5px;
  line-height: 1.25;
  color: #64748b;
}
.ss-done .ss-label {
  color: #0f172a;
}
.ss-now .ss-label {
  font-weight: 700;
}
.ss-value {
  display: block;
  font-size: 11px;
  font-weight: 500;
  color: #64748b;
  overflow-wrap: anywhere;
}
.ss-choices {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 4px;
}
.ss-btn {
  padding: 4px 9px;
  border-radius: 8px;
  font-size: 11.5px;
  font-weight: 700;
  line-height: 1.2;
  color: #0f172a;
  background: rgba(100, 116, 139, 0.12);
  border: 1px solid rgba(100, 116, 139, 0.3);
}
.ss-btn:hover {
  border-color: var(--ss-accent);
  color: #c2410c;
}
.ss-btn-mark {
  color: #fff;
  background: var(--ss-accent);
  border-color: var(--ss-accent);
}
.ss-btn-mark:hover {
  color: #fff;
  background: #c2410c;
}
.ss-btn-undo {
  font-weight: 600;
  color: #475569;
  background: transparent;
  border-color: rgba(100, 116, 139, 0.45);
}

/* tema escuro */
:global(.dark .ss-title),
:global(.dark .ss-done .ss-label) {
  color: #fff;
}
:global(.dark .ss-sub),
:global(.dark .ss-label),
:global(.dark .ss-value) {
  color: rgba(255, 255, 255, 0.62);
}
:global(.dark .ss-row) {
  border-top-color: rgba(255, 255, 255, 0.1);
}
:global(.dark .ss-dot) {
  border-color: rgba(255, 255, 255, 0.35);
}
:global(.dark .ss-done .ss-dot) {
  border-color: #22c55e;
  background: #22c55e;
}
:global(.dark .ss-now .ss-dot) {
  border-color: #fb923c;
  background: #ea580c;
}
:global(.dark .ss-btn) {
  color: #fff;
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(255, 255, 255, 0.2);
}
:global(.dark .ss-btn:hover) {
  color: #fdba74;
}
:global(.dark .ss-btn-mark) {
  background: #ea580c;
  border-color: #ea580c;
}
:global(.dark .ss-btn-undo) {
  color: rgba(255, 255, 255, 0.62);
  background: transparent;
}
</style>
