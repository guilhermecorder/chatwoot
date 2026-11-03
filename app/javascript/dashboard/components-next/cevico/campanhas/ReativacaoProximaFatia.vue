<script setup>
// 🎛️ item 382: QUEM RECEBE NA PRÓXIMA FATIA — a prévia pessoa por pessoa, sem
// mandar nada. No modo "Eu aprovo cada lote" cada linha tem uma caixinha e o
// botão "Aprovar e enviar" manda exatamente quem ficou marcado (digitando
// ENVIAR, como no resto das campanhas). Se o robô já preparou um lote
// (pending_batch), ele aparece sozinho aqui com a hora em que foi preparado.
import { ref, computed, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import ReativacaoTabelaPessoas from './ReativacaoTabelaPessoas.vue';
import { people, fmtTime } from './reativacaoHelpers';

const props = defineProps({
  canEdit: { type: Boolean, default: false },
  isActive: { type: Boolean, default: false },
  approval: { type: String, default: 'manual' }, // 'manual' | 'auto'
  testMode: { type: Boolean, default: false },
  windowNow: { type: String, default: '' },
  pendingBatch: { type: Object, default: null }, // { at, quota, rows }
});
const emit = defineEmits(['sent']);

const preview = ref(null); // { rows, quota, remaining_today, warnings, skip, pending_at }
const loading = ref(false);
const sending = ref(false);
const selected = ref([]);
const confirming = ref(false);
const typed = ref('');

const isManual = computed(() => props.approval !== 'auto');
const rows = computed(() => preview.value?.rows || []);
const warnings = computed(() => (preview.value?.warnings || []).filter(Boolean));
const canApprove = computed(
  () => props.canEdit && isManual.value && props.isActive && selected.value.length > 0 && !sending.value
);
const typedOk = computed(() => typed.value.trim().toUpperCase() === 'ENVIAR');

const setPreview = data => {
  preview.value = data;
  selected.value = (data?.rows || []).map(r => r.contact_id);
  confirming.value = false;
  typed.value = '';
};

// lote já preparado pelo robô (modo manual) aparece sozinho
watch(
  () => props.pendingBatch,
  pb => {
    if (pb?.rows?.length) {
      setPreview({ rows: pb.rows, quota: pb.quota, pending_at: pb.at, warnings: [] });
    } else if (preview.value?.pending_at) {
      preview.value = null;
      selected.value = [];
    }
  },
  { immediate: true }
);

const fail = (err, fallback) => useAlert(err?.response?.data?.error || fallback);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAPI.previewReactivationNext(true);
    setPreview(data);
  } catch (err) {
    fail(err, 'Não deu para montar a próxima fatia.');
  } finally {
    loading.value = false;
  }
};

const send = async () => {
  if (!canApprove.value || !typedOk.value) return;
  sending.value = true;
  try {
    const { data } = await CrmAPI.sendReactivationBatch(selected.value);
    const n = Number(data.sent_now || 0);
    useAlert(n ? `${people(n)} recebendo agora.` : 'Nada saiu — veja os avisos do plano.');
    preview.value = null;
    selected.value = [];
    confirming.value = false;
    typed.value = '';
    emit('sent', data);
  } catch (err) {
    fail(err, 'Não deu para aprovar o lote.');
  } finally {
    sending.value = false;
  }
};

const headline = computed(() => {
  if (!preview.value) return '';
  const bits = [`${people(rows.value.length)} nesta fatia`];
  if (preview.value.remaining_today != null) bits.push(`hoje ainda cabem ${preview.value.remaining_today}`);
  if (props.windowNow) bits.push(`janela: ${props.windowNow}`);
  return bits.join(' · ');
});
</script>

<template>
  <div class="cv-sub p-4 sm:p-6">
    <div class="flex items-center gap-2 mb-3 flex-wrap">
      <span class="cv-icon cv-icon-sm"><span class="i-lucide-users text-sm" /></span>
      <h3 class="text-sm font-bold text-n-slate-12">Quem recebe na próxima fatia</h3>
      <span v-if="testMode" class="cv-chip cv-amber">
        <span class="i-lucide-flask-conical text-xs" />
        MODO DE TESTE
      </span>
      <span v-if="preview?.pending_at" class="cv-chip">
        <span class="i-lucide-clock text-xs" />
        preparado às {{ fmtTime(preview.pending_at) }}
      </span>
      <div class="ml-auto flex gap-2 flex-wrap">
        <button class="cv-btn cv-btn-sm cv-btn-ghost" :disabled="loading || sending" @click="load">
          <span class="i-lucide-eye text-sm" />
          {{ loading ? 'Montando…' : preview ? 'Montar de novo' : 'Ver a próxima fatia' }}
        </button>
      </div>
    </div>
    <p class="text-xs text-n-slate-10 leading-relaxed mb-3">
      Mostra, pessoa por pessoa, quem entra na próxima fatia e por qual caixa e modelo cada uma vai — sem mandar nada.
      <template v-if="isManual">Você marca quem fica e aprova.</template>
      <template v-else>No automático o robô manda sozinho dentro do horário; aqui você só confere.</template>
    </p>

    <template v-if="preview">
      <p v-if="preview.skip" class="nota nota-amber">
        <span class="i-lucide-info text-sm flex-shrink-0" />
        Nada para mandar agora: {{ preview.skip }}.
      </p>
      <template v-else>
        <p class="text-xs font-semibold text-n-slate-12 mb-2">{{ headline }}</p>
        <p v-for="(w, i) in warnings" :key="i" class="nota nota-amber mb-1">
          <span class="i-lucide-info text-sm flex-shrink-0" />
          {{ w }}
        </p>
        <ReativacaoTabelaPessoas
          v-model:selected="selected"
          :rows="rows"
          :selectable="canEdit && isManual"
          class="mt-2"
        />

        <!-- aprovar (só quem edita, só no modo manual) -->
        <div v-if="canEdit && isManual && rows.length" class="mt-4">
          <p v-if="!isActive" class="text-[11px] text-n-slate-10">
            Ative o plano para poder aprovar um lote.
          </p>
          <template v-else-if="confirming">
            <div class="nota nota-amber flex-col items-stretch gap-2">
              <span>
                Vai sair agora para <b>{{ people(selected.length) }}</b>. A Meta cobra por mensagem e não dá para
                desfazer. Para continuar, digite <span class="font-mono font-bold">ENVIAR</span>:
              </span>
              <div class="flex items-center gap-2 flex-wrap">
                <input
                  v-model="typed"
                  class="cv-input !h-8 w-36 text-xs font-mono uppercase"
                  placeholder="ENVIAR"
                  @keyup.enter="send"
                />
                <button class="cv-btn cv-btn-sm cv-green" :disabled="!canApprove || !typedOk" @click="send">
                  <span class="i-lucide-send text-sm" />
                  {{ sending ? 'Mandando…' : 'Confirmar' }}
                </button>
                <button class="cv-btn cv-btn-sm cv-btn-ghost" :disabled="sending" @click="confirming = false; typed = ''">
                  Voltar
                </button>
              </div>
            </div>
          </template>
          <div v-else class="flex items-center gap-2 flex-wrap">
            <button class="cv-btn cv-green" :disabled="!canApprove" @click="confirming = true">
              <span class="i-lucide-check-check text-sm" />
              Aprovar e enviar {{ people(selected.length) }}
            </button>
            <span v-if="selected.length < rows.length" class="text-[11px] text-n-slate-10">
              {{ rows.length - selected.length }} desmarcada(s) ficam para a próxima fatia
            </span>
          </div>
        </div>
      </template>
    </template>
    <p v-else-if="!loading" class="text-xs text-n-slate-10 text-center py-3">
      Clique em “Ver a próxima fatia” para conferir quem recebe.
    </p>
  </div>
</template>

<style scoped>
.nota {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  padding: 6px 10px;
  border-radius: 10px;
  font-size: 11px;
  line-height: 1.4;
}
.nota-amber {
  color: #92400e;
  background: rgba(245, 158, 11, 0.12);
  border: 1px solid rgba(245, 158, 11, 0.35);
}
.dark .nota-amber {
  color: #fcd34d;
}
</style>
