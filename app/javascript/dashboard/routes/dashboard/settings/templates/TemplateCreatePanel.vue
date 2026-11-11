<script setup>
// 📨 item 391 (11/11): CRIAR mensagem modelo daqui do sistema e pedir a
// aprovação à Meta nos números escolhidos. Escreve uma vez, marca os números,
// vê a prévia e envia; o resultado volta número por número. "Copiar para
// outros números" (na prévia de um modelo que já existe) abre este mesmo
// painel já preenchido. Só texto: título, mensagem com {{1}}, rodapé e até 3
// botões de resposta — modelo com foto/vídeo no topo continua nascendo na Meta.
import { computed, reactive, ref } from 'vue';

import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  inboxes: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['created']);

const MAX_BUTTONS = 3;
const PANEL_TITLE = 'Criar mensagem modelo';
const PANEL_DESCRIPTION =
  'Escreva uma vez, escolha os números e o sistema pede a aprovação à Meta.';
// fora do template: "{{1}}" dentro de {{ }} quebra a montagem da tela
const BODY_HINT =
  'Use {{1}} onde entra o nome do paciente. Não cite diagnóstico nem dado de saúde: a Meta recusa e não é bom para o paciente.';
const BODY_PLACEHOLDER = 'Oi, {{1}}! Aqui é o Guilherme, da CEVICO…';
const VARIABLE = /\{\{\s*(\d+)\s*\}\}/g;
const CATEGORIES = [
  {
    value: 'MARKETING',
    label: 'Marketing',
    hint: 'Follow-up, convite, novidade, retorno de quem pediu um tempo.',
  },
  {
    value: 'UTILITY',
    label: 'Utilidade',
    hint: 'Confirmação e lembrete de consulta que a pessoa já marcou.',
  },
];

const panelRef = ref(null);
const isSending = ref(false);
const errors = ref([]);
const results = ref([]);
const copyWarning = ref('');
const form = reactive({
  name: '',
  category: 'MARKETING',
  header: '',
  body: '',
  footer: '',
  buttons: [''],
  examples: [],
  inboxIds: [],
});

// só número ligado direto à Meta aceita pedido de modelo por aqui
const cloudInboxes = computed(() =>
  props.inboxes.filter(inbox => inbox.provider === 'whatsapp_cloud')
);

const variableNumbers = computed(() => {
  const found = [...form.body.matchAll(VARIABLE)].map(match =>
    Number(match[1])
  );
  return [...new Set(found)].sort((a, b) => a - b);
});

const cleanButtons = computed(() =>
  form.buttons.map(text => text.trim()).filter(Boolean)
);

// a mensagem como o paciente lê: os campos {{1}} já trocados pelo exemplo
const previewBody = computed(() => {
  const text = form.body.trim() || 'A sua mensagem aparece aqui.';
  return text.replace(VARIABLE, (field, number) => {
    const index = variableNumbers.value.indexOf(Number(number));
    return form.examples[index] || field;
  });
});

const canSend = computed(
  () =>
    form.name && form.body.trim() && form.inboxIds.length && !isSending.value
);

// o nome que a Meta aceita: minúsculas sem acento, números e _
const cleanName = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+/, '')
    .slice(0, 60);

const onNameInput = value => {
  form.name = cleanName(value);
};

const toggleInbox = id => {
  form.inboxIds = form.inboxIds.includes(id)
    ? form.inboxIds.filter(item => item !== id)
    : [...form.inboxIds, id];
};

const addButton = () => {
  if (form.buttons.length < MAX_BUTTONS) form.buttons.push('');
};

const removeButton = index => {
  form.buttons.splice(index, 1);
  if (!form.buttons.length) form.buttons.push('');
};

const reset = () => {
  Object.assign(form, {
    name: '',
    category: 'MARKETING',
    header: '',
    body: '',
    footer: '',
    buttons: [''],
    examples: [],
    inboxIds: [],
  });
  errors.value = [];
  results.value = [];
  copyWarning.value = '';
};

// "Copiar para outros números": traz o texto de um modelo que já existe
const fillFrom = template => {
  const parts = template.components || [];
  const part = type => parts.find(item => item.type === type) || {};
  const header = part('HEADER');
  const buttons = part('BUTTONS').buttons || [];
  const replies = buttons.filter(button => button.type === 'QUICK_REPLY');
  const notes = [];
  if (header.format && header.format !== 'TEXT')
    notes.push('a foto, vídeo ou arquivo do topo');
  if (replies.length !== buttons.length)
    notes.push('os botões de link ou de telefone');
  if (replies.length > MAX_BUTTONS)
    notes.push(`os botões além dos ${MAX_BUTTONS} primeiros`);

  form.name = cleanName(template.name);
  form.category = template.category === 'UTILITY' ? 'UTILITY' : 'MARKETING';
  form.header = header.format === 'TEXT' ? header.text || '' : '';
  form.body = part('BODY').text || '';
  form.footer = part('FOOTER').text || '';
  form.buttons = replies.slice(0, MAX_BUTTONS).map(button => button.text);
  if (!form.buttons.length) form.buttons = [''];
  form.examples = [...(part('BODY').example?.body_text?.[0] || [])];
  const already = new Set((template.inboxes || []).map(inbox => inbox.id));
  form.inboxIds = cloudInboxes.value
    .filter(inbox => !already.has(inbox.id))
    .map(inbox => inbox.id);
  copyWarning.value = notes.length
    ? `Este modelo tem ${notes.join(' e ')}, que não dá para copiar por aqui. O texto veio; se precisar disso, crie na Meta.`
    : '';
};

const open = (template = null) => {
  reset();
  if (template) fillFrom(template);
  panelRef.value?.open();
};

const close = () => panelRef.value?.close();

const send = async () => {
  if (!canSend.value) return;
  isSending.value = true;
  errors.value = [];
  results.value = [];
  try {
    const { data } = await CrmAPI.createWhatsappTemplate({
      inbox_ids: form.inboxIds,
      name: form.name,
      category: form.category,
      header: form.header,
      body: form.body,
      footer: form.footer,
      buttons: cleanButtons.value,
      examples: variableNumbers.value.map((_, i) => form.examples[i] || ''),
    });
    results.value = data.results || [];
    if (data.ok) {
      useAlert(
        'Modelo enviado para a Meta. A análise costuma levar de minutos a algumas horas.'
      );
    }
    if (results.value.some(row => row.ok)) emit('created');
  } catch (error) {
    errors.value = error.response?.data?.errors || [
      error.response?.data?.error ||
        'Não consegui enviar agora. Tente de novo em alguns minutos.',
    ];
  } finally {
    isSending.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <SidePanel
    ref="panelRef"
    width="2xl"
    :title="PANEL_TITLE"
    :description="PANEL_DESCRIPTION"
    :close-on-click-outside="false"
  >
    <div class="flex flex-col gap-6">
      <p
        v-if="copyWarning"
        class="px-3 py-2 text-sm border rounded-lg border-n-amber-6 bg-n-amber-2 text-n-amber-11"
      >
        {{ copyWarning }}
      </p>

      <section>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ '1. Para quais números' }}
        </h3>
        <p v-if="!cloudInboxes.length" class="mt-2 text-sm text-n-slate-11">
          {{ 'Nenhum número de WhatsApp ligado direto à Meta nesta conta.' }}
        </p>
        <div class="grid gap-2 mt-3 sm:grid-cols-2">
          <label
            v-for="inbox in cloudInboxes"
            :key="inbox.id"
            class="flex items-center gap-3 px-3 py-2 border rounded-lg cursor-pointer border-n-weak hover:bg-n-alpha-1"
          >
            <Checkbox
              :model-value="form.inboxIds.includes(inbox.id)"
              @change="toggleInbox(inbox.id)"
            />
            <span class="min-w-0">
              <span class="block text-sm truncate text-n-slate-12">
                {{ inbox.name }}
              </span>
              <span class="block text-xs text-n-slate-10">
                {{ inbox.phone_number }}
              </span>
            </span>
          </label>
        </div>
      </section>

      <section class="flex flex-col gap-4">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ '2. O modelo' }}
        </h3>
        <Input
          :model-value="form.name"
          label="Nome do modelo"
          placeholder="retorno_combinado"
          message="Só letras minúsculas, números e _. É o nome que aparece na lista e nos robôs."
          @update:model-value="onNameInput"
        />
        <div>
          <span class="block mb-2 text-sm font-medium text-n-slate-12">
            {{ 'Tipo' }}
          </span>
          <div class="grid gap-2 sm:grid-cols-2">
            <button
              v-for="option in CATEGORIES"
              :key="option.value"
              type="button"
              class="px-3 py-2 text-left border rounded-lg"
              :class="
                form.category === option.value
                  ? 'border-n-brand bg-n-alpha-2'
                  : 'border-n-weak hover:bg-n-alpha-1'
              "
              @click="form.category = option.value"
            >
              <span class="block text-sm font-medium text-n-slate-12">
                {{ option.label }}
              </span>
              <span class="block text-xs text-n-slate-11">
                {{ option.hint }}
              </span>
            </button>
          </div>
        </div>
        <Input
          v-model="form.header"
          label="Título (opcional)"
          placeholder="Combinado é combinado"
          message="Até 60 letras, sem emoji e sem negrito."
        />
        <TextArea
          v-model="form.body"
          label="Mensagem"
          :placeholder="BODY_PLACEHOLDER"
          :max-length="1024"
          show-character-count
          auto-height
          min-height="8rem"
        />
        <p class="-mt-2 text-xs text-n-slate-10">{{ BODY_HINT }}</p>
        <div v-if="variableNumbers.length" class="grid gap-3 sm:grid-cols-2">
          <Input
            v-for="(number, index) in variableNumbers"
            :key="number"
            v-model="form.examples[index]"
            :label="`Exemplo para {{${number}}}`"
            :placeholder="index === 0 ? 'Maria' : 'exemplo'"
            message="A Meta pede um exemplo para analisar."
          />
        </div>
        <Input
          v-model="form.footer"
          label="Rodapé (opcional)"
          placeholder="CEVICO - Centro da Visão e Cuidados Oculares"
        />
        <div>
          <span class="block mb-2 text-sm font-medium text-n-slate-12">
            {{ 'Botões de resposta (até 3, opcional)' }}
          </span>
          <div class="flex flex-col gap-2">
            <div
              v-for="(_, index) in form.buttons"
              :key="index"
              class="flex items-center gap-2"
            >
              <Input
                v-model="form.buttons[index]"
                class="flex-1"
                placeholder="Ver horários"
                max="25"
              />
              <Button
                icon="i-lucide-trash-2"
                color="slate"
                variant="ghost"
                size="sm"
                @click="removeButton(index)"
              />
            </div>
          </div>
          <Button
            v-if="form.buttons.length < MAX_BUTTONS"
            class="mt-2"
            label="Mais um botão"
            icon="i-lucide-plus"
            color="slate"
            variant="link"
            size="sm"
            @click="addButton"
          />
        </div>
      </section>

      <section>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ '3. Como o paciente vai ver' }}
        </h3>
        <div
          class="flex items-center justify-center px-6 py-8 mt-3 border rounded-xl border-n-weak bg-n-alpha-1"
        >
          <div class="w-full max-w-sm">
            <div
              class="px-3 py-2 text-sm border rounded-xl border-n-weak bg-n-solid-2 text-n-slate-12"
            >
              <p v-if="form.header.trim()" class="mb-1 font-semibold">
                {{ form.header.trim() }}
              </p>
              <p class="whitespace-pre-line">{{ previewBody }}</p>
              <p v-if="form.footer.trim()" class="mt-1 text-xs text-n-slate-10">
                {{ form.footer.trim() }}
              </p>
            </div>
            <div
              v-for="text in cleanButtons"
              :key="text"
              class="px-3 py-2 mt-1 text-sm font-medium text-center border rounded-xl border-n-weak bg-n-solid-2 text-n-blue-11"
            >
              {{ text }}
            </div>
          </div>
        </div>
      </section>

      <ul
        v-if="errors.length"
        class="px-4 py-3 text-sm list-disc list-inside border rounded-lg border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11"
      >
        <li v-for="message in errors" :key="message">{{ message }}</li>
      </ul>

      <section v-if="results.length">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ 'Resposta da Meta' }}
        </h3>
        <ul class="mt-3 border divide-y rounded-lg divide-n-weak border-n-weak">
          <li
            v-for="row in results"
            :key="row.inbox_id"
            class="flex items-start justify-between gap-4 px-3 py-2 text-sm"
          >
            <span class="text-n-slate-12">{{ row.inbox_name }}</span>
            <span v-if="row.ok" class="text-right text-n-teal-11">
              {{
                row.status === 'APPROVED'
                  ? 'Aprovado'
                  : 'Enviado, em análise na Meta'
              }}
            </span>
            <span v-else class="text-right text-n-ruby-11">
              {{ row.error }}
            </span>
          </li>
        </ul>
      </section>
    </div>

    <template #footer>
      <div class="flex flex-col gap-2">
        <Button
          class="w-full"
          label="Enviar para aprovação da Meta"
          icon="i-lucide-send"
          :is-loading="isSending"
          :disabled="!canSend"
          @click="send"
        />
        <p class="text-xs text-center text-n-slate-10">
          {{
            'Nada é enviado a paciente agora: a Meta só analisa o texto. Mensagem modelo aprovada é cobrada a cada envio.'
          }}
        </p>
      </div>
    </template>
  </SidePanel>
</template>
