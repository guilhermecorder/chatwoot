<script setup>
// ✉️ ITEM 410 (24/11): a MENSAGEM MODELO da indicação, já preenchida com os
// dados do paciente. Pedido dele: "apertou que tem indicação, aparece a
// mensagem modelo ali, ela aperta, aparece para ela editar e já faz a
// abordagem por ali mesmo… sem IA, só a própria humana".
// Quem manda no formato é o WhatsApp: paciente falou nas últimas 24 h = texto
// livre (edita tudo); passou disso = só o modelo aprovado (edita os campos).
import { ref, computed, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmAPI from 'dashboard/api/crm';
import { openPatientChat } from 'dashboard/composables/useCevicoPatientChat';

const props = defineProps({
  row: { type: Object, required: true },
  pageStyle: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['close', 'sent']);

const data = ref(null);
const isLoading = ref(true);
const loadError = ref('');
const isSending = ref(false);
const modelKey = ref('');
const inboxId = ref(0);
const values = ref({});
const freeText = ref('');

const STATUS = {
  approved: 'aprovado pela Meta',
  pending: 'em análise na Meta',
  rejected: 'recusado pela Meta',
  missing: 'ainda não pedido à Meta',
};

// 📱 o número é escolhido sozinho pelo sistema (onde o paciente já conversa)
const INBOX_REASON = {
  conversa:
    'Escolhido pelo sistema: é o número em que o paciente já conversa com a clínica.',
  ultimo_contato:
    'Escolhido pelo sistema: é o número do último contato com este paciente (ele ainda não respondeu por lá).',
  sem_conversa:
    'Este paciente ainda não tem conversa em nenhum número. Confira por onde enviar.',
};
const INBOX_SWITCH = {
  conversa: 'O paciente conversa com a clínica por outro número.',
  ultimo_contato: 'O último contato com o paciente foi por outro número.',
  sem_conversa: '',
};

const model = computed(
  () => data.value?.models?.find(m => m.key === modelKey.value) || null
);
const inbox = computed(
  () => data.value?.inboxes?.find(i => i.id === inboxId.value) || null
);
const chosenInbox = computed(
  () => data.value?.inboxes?.find(i => i.id === data.value?.inbox_id) || null
);
const switchedNumber = computed(
  () =>
    !!data.value?.inbox_id &&
    data.value.inbox_reason !== 'sem_conversa' &&
    inboxId.value !== data.value.inbox_id
);
const backToChosen = () => {
  inboxId.value = data.value.inbox_id;
};
const template = computed(
  () => inbox.value?.templates?.[modelKey.value] || { status: 'missing' }
);
// text = janela de 24 h aberta · template = modelo aprovado · none = não dá para enviar daqui
const mode = computed(() => {
  if (!inbox.value || !model.value) return 'none';
  if (inbox.value.window_open) return 'text';
  return template.value.status === 'approved' ? 'template' : 'none';
});

const fill = body =>
  String(body || '').replace(/\{\{\s*(\d+)\s*\}\}/g, (_, n) => {
    const v = String(values.value[n] || '').trim();
    return v || '______';
  });
const templateText = computed(() =>
  fill(template.value.body || model.value?.body)
);
const missingField = computed(() =>
  (model.value?.fields || []).some(f => !String(values.value[f.n] || '').trim())
);
// só o que as meninas conferem: paciente, médico, procedimento (a assinatura é fixa)
const openFields = computed(() =>
  (model.value?.fields || []).filter(f => !f.fixed)
);
// médicos da casa + o que veio da consulta (se for alguém de fora)
const doctorOptions = computed(() => {
  const list = [...(data.value?.doctors || [])];
  const fromConsult = (model.value?.fields || []).find(
    f => f.key === 'medico'
  )?.value;
  if (fromConsult && !list.includes(fromConsult)) list.push(fromConsult);
  return list;
});

const resetValues = () => {
  values.value = (model.value?.fields || []).reduce(
    (acc, f) => ({ ...acc, [f.n]: f.value || '' }),
    {}
  );
  freeText.value = fill(model.value?.body);
};

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const res = await CrmAPI.surgeryIndicationMessage(props.row.id);
    data.value = res.data;
    modelKey.value = res.data.models?.[0]?.key || '';
    inboxId.value = res.data.inbox_id || res.data.inboxes?.[0]?.id || 0;
    resetValues();
  } catch (e) {
    loadError.value =
      e?.response?.data?.error || 'Não deu para montar a mensagem agora.';
  } finally {
    isLoading.value = false;
  }
};
watch(() => props.row.id, load, { immediate: true });
watch(modelKey, resetValues);

const currentText = computed(() =>
  mode.value === 'text' ? freeText.value : templateText.value
);
const canSend = computed(() => {
  if (isSending.value || data.value?.blocked) return false;
  if (mode.value === 'text') return freeText.value.trim().length > 0;
  return mode.value === 'template' && !missingField.value;
});

// "preencher automático": volta tudo para os dados que o sistema já tem
const autofill = () => {
  resetValues();
  useAlert('Preenchido com os dados da consulta.');
};

const copy = async () => {
  await copyTextToClipboard(currentText.value);
  useAlert('Texto copiado.');
};
const openChat = () =>
  openPatientChat({ contactId: props.row.contact_id, phone: props.row.phone });

const send = async () => {
  if (!canSend.value) return;
  isSending.value = true;
  try {
    const res = await CrmAPI.sendSurgeryIndicationMessage(props.row.id, {
      model: modelKey.value,
      inbox_id: inboxId.value,
      mode: mode.value,
      text: freeText.value,
      values: values.value,
    });
    useAlert(`Mensagem enviada para ${data.value.first_name || 'o paciente'}.`);
    emit('sent', res.data.row);
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não deu para enviar. Tente de novo.');
  } finally {
    isSending.value = false;
  }
};

const sentWhen = iso =>
  new Date(iso)
    .toLocaleString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'America/Sao_Paulo',
    })
    .replace(',', ' às');
const lastSent = computed(() => {
  const list = data.value?.history || [];
  return list.length ? list[list.length - 1] : null;
});
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page cv-overlay fixed inset-0 z-[80] flex items-end sm:items-center justify-center bg-black/50 p-0 sm:p-4"
      :style="pageStyle"
      @click.self="emit('close')"
    >
      <div
        class="cv-modal w-full sm:max-w-xl max-h-[92vh] flex flex-col !rounded-b-none sm:!rounded-b-3xl"
      >
        <div class="cv-modal-head !p-5">
          <div class="flex items-center gap-2 text-white/90">
            <span class="i-lucide-send text-base" />
            <p class="text-sm font-bold flex-1 truncate">
              Mensagem para {{ row.name }}
            </p>
            <button
              class="cv-glass-btn cv-iconbtn"
              aria-label="Fechar"
              @click="emit('close')"
            >
              <span class="i-lucide-x text-sm" />
            </button>
          </div>
          <p class="text-xs text-white/85 mt-1">
            <template v-if="row.status === 'indicado'">
              🎯 Indicação: {{ row.indicated_procedure }}
            </template>
            <template v-else>Sem indicação cirúrgica</template>
            <template v-if="row.doctor"> · {{ row.doctor }}</template>
          </p>
        </div>

        <div class="p-4 sm:p-5 overflow-y-auto flex flex-col gap-4">
          <p v-if="isLoading" class="text-xs text-n-slate-10 py-6 text-center">
            Montando a mensagem…
          </p>

          <div
            v-else-if="loadError"
            class="cv-block cv-strip cv-red px-4 py-3 text-xs text-n-slate-11"
          >
            {{ loadError }}
          </div>

          <template v-else-if="data">
            <div
              v-if="data.blocked"
              class="cv-block cv-strip cv-amber px-4 py-3 flex items-center gap-3"
            >
              <p class="text-xs text-n-slate-11 flex-1">{{ data.blocked }}</p>
              <button class="cv-btn cv-btn-sm" @click="openChat">
                Abrir conversa
              </button>
            </div>

            <div
              v-if="lastSent"
              class="cv-block cv-strip cv-green px-4 py-2.5 text-xs text-n-slate-11"
            >
              Já enviada em {{ sentWhen(lastSent.at) }} por
              {{ lastSent.name }} ({{ lastSent.model_label }}). Enviar de novo
              manda outra mensagem.
            </div>

            <!-- 1 · por onde sai (o sistema escolhe o número da conversa) -->
            <section v-if="data.inboxes.length" class="cv-sub cv-ind-step">
              <header class="cv-ind-step-head">
                <span class="cv-ind-step-n">1</span>
                <span class="cv-ind-step-t">Por onde sai</span>
              </header>
              <select v-model="inboxId" class="cv-input w-full">
                <option v-for="i in data.inboxes" :key="i.id" :value="i.id">
                  {{ i.name }}
                  {{ i.talks ? '· conversa do paciente' : '' }}
                  {{
                    i.window_open
                      ? '· falou nas últimas 24 h'
                      : `· modelo ${STATUS[i.templates?.[modelKey]?.status || 'missing']}`
                  }}
                </option>
              </select>
              <p
                v-if="switchedNumber"
                class="text-[11px] mt-2 text-amber-600 dark:text-amber-400"
              >
                Você trocou o número. {{ INBOX_SWITCH[data.inbox_reason] }}
                <button class="underline font-semibold" @click="backToChosen">
                  Voltar para {{ chosenInbox?.name }}
                </button>
              </p>
              <p v-else class="text-[11px] text-n-slate-10 mt-2">
                {{ INBOX_REASON[data.inbox_reason] }}
              </p>
            </section>

            <!-- 2 · a mensagem (texto livre dentro das 24 h; modelo aprovado fora) -->
            <section v-if="model" class="cv-sub cv-ind-step">
              <header class="cv-ind-step-head">
                <span class="cv-ind-step-n">2</span>
                <span class="cv-ind-step-t">
                  {{
                    mode === 'text' ? 'A mensagem (pode editar)' : 'A mensagem'
                  }}
                </span>
                <div
                  v-if="data.models.length > 1"
                  class="cv-seg cv-seg-sm flex-wrap ml-auto"
                >
                  <button
                    v-for="m in data.models"
                    :key="m.key"
                    class="cv-seg-item"
                    :class="modelKey === m.key ? 'cv-seg-on' : ''"
                    @click="modelKey = m.key"
                  >
                    {{ m.label }}
                  </button>
                </div>
              </header>

              <template v-if="mode === 'text'">
                <textarea
                  v-model="freeText"
                  rows="10"
                  class="cv-input w-full resize-y text-sm leading-relaxed"
                />
                <p class="text-[11px] text-n-slate-10 mt-2">
                  O paciente falou com a clínica nas últimas 24 horas: o texto
                  sai do jeito que você deixar aqui.
                </p>
              </template>

              <template v-else>
                <div
                  v-if="mode === 'none'"
                  class="cv-block cv-strip cv-amber px-4 py-3 mb-3 text-xs text-n-slate-11"
                >
                  Passaram as 24 horas desde a última mensagem do paciente, e
                  neste número o modelo “{{ model.label }}” está
                  {{ STATUS[template.status] }}. Sem o modelo aprovado o
                  WhatsApp não deixa enviar. Dá para copiar o texto ou abrir a
                  conversa.
                </div>
                <div class="cv-ind-bubble">
                  <p
                    class="whitespace-pre-wrap text-sm leading-relaxed text-n-slate-12"
                  >
                    {{ templateText }}
                  </p>
                  <p
                    v-if="model.footer"
                    class="text-[11px] text-n-slate-10 mt-2"
                  >
                    {{ model.footer }}
                  </p>
                  <div
                    v-if="model.buttons?.length"
                    class="flex flex-wrap gap-1.5 mt-3 pt-3 border-t border-black/10 dark:border-white/10"
                  >
                    <span
                      v-for="b in model.buttons"
                      :key="b"
                      class="cv-ind-reply"
                    >
                      {{ b }}
                    </span>
                  </div>
                </div>
              </template>
            </section>

            <!-- 3 · os dados que entram no modelo (já vêm da consulta) -->
            <section v-if="mode === 'template'" class="cv-sub cv-ind-step">
              <header class="cv-ind-step-head">
                <span class="cv-ind-step-n">3</span>
                <span class="cv-ind-step-t">Confira os dados</span>
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost ml-auto"
                  title="Volta o nome, o médico e o procedimento para o que está na consulta"
                  @click="autofill"
                >
                  <span class="i-lucide-wand-sparkles text-xs" />
                  Preencher automático
                </button>
              </header>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <label v-for="f in openFields" :key="f.n" class="block">
                  <span class="cv-label block mb-1">{{ f.label }}</span>
                  <select
                    v-if="f.key === 'medico'"
                    v-model="values[f.n]"
                    class="cv-input w-full"
                  >
                    <option v-for="d in doctorOptions" :key="d" :value="d">
                      {{ d }}
                    </option>
                  </select>
                  <input
                    v-else
                    v-model="values[f.n]"
                    class="cv-input w-full"
                    maxlength="120"
                  />
                </label>
              </div>
              <p class="text-[11px] text-n-slate-10 mt-3">
                Já veio preenchido com os dados da consulta; quem assina é
                sempre {{ data.signature }}. Fora das 24 horas o WhatsApp só
                aceita o modelo aprovado: o resto do texto é fixo.
              </p>
            </section>

            <p
              class="text-[11px] text-n-slate-10 flex items-start gap-1.5 px-1"
            >
              <span class="i-lucide-user-round-check text-xs mt-0.5 shrink-0" />
              Sem IA: depois do envio, o Atendente IA fica desligado nesta
              conversa por {{ data.human_only_days }} dias. Quem responde é
              você.
            </p>
          </template>
        </div>

        <div
          class="cv-modal-foot flex flex-wrap items-center gap-2 !px-4 sm:!px-5 !py-3.5"
        >
          <button
            v-if="data && model"
            class="cv-btn cv-btn-sm cv-btn-ghost"
            @click="copy"
          >
            <span class="i-lucide-copy text-xs" /> Copiar texto
          </button>
          <button
            v-if="data && model && mode === 'text'"
            class="cv-btn cv-btn-sm cv-btn-ghost"
            title="Volta o nome, o médico e o procedimento para o que está na consulta"
            @click="autofill"
          >
            <span class="i-lucide-wand-sparkles text-xs" /> Preencher automático
          </button>
          <div class="flex items-center gap-2 ml-auto">
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost"
              @click="emit('close')"
            >
              Agora não
            </button>
            <button
              class="cv-btn cv-btn-sm"
              :disabled="!canSend"
              :class="!canSend ? 'opacity-50 cursor-not-allowed' : ''"
              @click="send"
            >
              <span class="i-ri-whatsapp-line text-sm" />
              {{ isSending ? 'Enviando…' : 'Enviar pelo WhatsApp' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.cv-ind-bubble {
  border-radius: 6px 18px 18px 18px;
  padding: 14px 16px;
  background: rgba(37, 211, 102, 0.1);
  border: 1px solid rgba(37, 211, 102, 0.28);
}
.cv-ind-step {
  padding: 14px 16px 16px;
}
.cv-ind-step-head {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 12px;
}
.cv-ind-step-n {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 800;
  color: #fff;
  background: var(--cv-grad);
}
.cv-ind-step-t {
  font-size: 13px;
  font-weight: 700;
}
.cv-ind-reply {
  font-size: 11px;
  font-weight: 600;
  padding: 4px 10px;
  border-radius: 999px;
  background: rgba(37, 99, 235, 0.1);
  color: #2563eb;
}
</style>
