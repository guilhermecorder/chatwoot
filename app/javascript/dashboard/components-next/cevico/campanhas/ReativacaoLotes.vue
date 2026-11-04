<script setup>
// 🎛️ item 382: LOTES QUE JÁ SAÍRAM — um cartão por lote (dia × caixa), com
// o status de entrega de cada pessoa e o atalho para a conversa.
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import CrmAPI from 'dashboard/api/crm';
import { people, fmtDay, fmtTime, fmtPhone, frenteLabel, statusMeta } from './reativacaoHelpers';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  refreshKey: { type: Number, default: 0 }, // o pai incrementa depois de um envio
});

const router = useRouter();
const batches = ref([]);
const loading = ref(false);
const loaded = ref(false);
const open = ref([]);

const ORDER = ['delivered', 'read', 'sent', 'failed'];
const statusChips = b =>
  Object.entries(b.por_status || {})
    .sort(([a], [c]) => ORDER.indexOf(a) - ORDER.indexOf(c))
    .map(([key, n]) => ({ key, n, ...statusMeta(key) }));
const isOpen = id => open.value.includes(id);
const toggle = id => {
  open.value = isOpen(id) ? open.value.filter(x => x !== id) : [...open.value, id];
};
const openConversation = id => {
  if (!id) return;
  router.push(frontendURL(`accounts/${props.accountId}/conversations/${id}`));
};
const total = computed(() => batches.value.reduce((acc, b) => acc + Number(b.total || 0), 0));

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAPI.getReactivationBatches({ days: 14 });
    batches.value = data.batches || [];
    loaded.value = true;
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para carregar os lotes.');
  } finally {
    loading.value = false;
  }
};
onMounted(load);
watch(() => props.refreshKey, load);
</script>

<template>
  <div class="cv-sub p-4 sm:p-6">
    <div class="flex items-center gap-2 mb-3 flex-wrap">
      <span class="cv-icon cv-icon-sm"><span class="i-lucide-package-check text-sm" /></span>
      <h3 class="text-sm font-bold text-n-slate-12">Lotes que já saíram</h3>
      <span v-if="loaded" class="text-[11px] text-n-slate-10">
        últimos 14 dias · {{ people(total) }}
      </span>
      <button class="ml-auto cv-btn cv-btn-sm cv-btn-ghost" :disabled="loading" @click="load">
        <span class="i-lucide-refresh-cw text-sm" :class="{ 'animate-spin': loading }" />
        Atualizar
      </button>
    </div>

    <p v-if="loaded && !batches.length" class="text-xs text-n-slate-10 text-center py-3">
      Nenhum lote saiu ainda.
    </p>
    <div v-else class="space-y-2">
      <article v-for="b in batches" :key="b.id" class="lote">
        <button class="w-full flex items-center gap-2 flex-wrap text-left" @click="toggle(b.id)">
          <span class="text-xs font-semibold text-n-slate-12 whitespace-nowrap">{{ fmtDay(b.day) }}</span>
          <span class="text-xs text-n-slate-11 whitespace-nowrap">· {{ b.inbox_name || 'caixa removida' }}</span>
          <span v-if="b.test" class="cv-chip cv-amber">
            <span class="i-lucide-flask-conical text-xs" />
            TESTE
          </span>
          <span class="text-xs text-n-slate-11 whitespace-nowrap">· {{ people(b.total) }}</span>
          <span v-for="s in statusChips(b)" :key="s.key" class="cv-chip tabular-nums" :class="s.tone">
            {{ s.n }} {{ s.label }}
          </span>
          <span class="ml-auto flex items-center gap-1 text-[11px] text-n-slate-10">
            {{ isOpen(b.id) ? 'esconder' : 'ver as pessoas' }}
            <span :class="isOpen(b.id) ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="text-sm" />
          </span>
        </button>

        <div v-if="isOpen(b.id)" class="overflow-x-auto -mx-1 px-1 mt-2">
          <table class="w-full text-xs tabela">
            <thead>
              <tr class="text-left">
                <th class="py-2 pr-3 cv-label">Nome</th>
                <th class="py-2 pr-3 cv-label">Telefone</th>
                <th class="py-2 pr-3 cv-label">Hora</th>
                <th class="py-2 pr-3 cv-label">Status</th>
                <th class="py-2 pr-3 cv-label">Frente</th>
                <th class="py-2 pr-3 cv-label">Modelo</th>
                <th class="py-2 cv-label" />
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in b.rows" :key="`${b.id}-${r.contact_id}`" class="border-t text-n-slate-12">
                <td class="py-2 pr-3 font-medium whitespace-nowrap max-w-[180px] truncate">{{ r.name || 'Sem nome' }}</td>
                <td class="py-2 pr-3 tabular-nums whitespace-nowrap text-n-slate-11">{{ fmtPhone(r.phone) }}</td>
                <td class="py-2 pr-3 tabular-nums whitespace-nowrap text-n-slate-11">{{ fmtTime(r.sent_at) }}</td>
                <td class="py-2 pr-3 whitespace-nowrap">
                  <span class="cv-chip" :class="statusMeta(r.status).tone">{{ statusMeta(r.status).label }}</span>
                  <p v-if="r.error" class="text-[10px] text-red-700 dark:text-red-300 mt-1 max-w-[260px] whitespace-normal">
                    {{ r.error }}
                  </p>
                </td>
                <td class="py-2 pr-3 whitespace-nowrap text-n-slate-11">{{ frenteLabel(r.frente) }}</td>
                <td class="py-2 pr-3 font-mono text-[11px] text-n-slate-10 whitespace-nowrap">{{ r.template || '—' }}</td>
                <td class="py-2 whitespace-nowrap">
                  <button
                    v-if="r.conversation_id"
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    @click="openConversation(r.conversation_id)"
                  >
                    <span class="i-lucide-message-square text-sm" />
                    Abrir conversa
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>
    </div>
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
.tabela tbody tr {
  border-color: rgb(var(--cv-rgb) / 0.18);
}
</style>
