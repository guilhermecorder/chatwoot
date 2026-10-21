<script setup>
// ✍️ ORIENTAR (rodada 191): o admin pega uma resposta do agente (do Testar
// agente ou da tela Sombra), escreve como DEVERIA ter respondido e uma regra
// para o futuro. A orientação fica pendente no painel "Orientações dos
// atendentes"; "Aplicar" escreve a regra na seção escolhida do Roteiro (ou
// nos Passos da etapa do agente), guardando uma versão antes.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CrmAPI from 'dashboard/api/crm';
import { GUIDANCE_SECTIONS, GUIDANCE_AGENT_LABEL } from './guidanceSections';

const props = defineProps({
  // orientação existente (com id) para editar, ou os campos pré-preenchidos
  // (agent_text, patient_excerpt, conversation_id, message_id, agent_key)
  guidance: { type: Object, default: () => ({}) },
  agentKey: { type: String, default: '' },
  agentName: { type: String, default: '' },
});

const emit = defineEmits(['close', 'saved']);

const AGENT_LABEL = GUIDANCE_AGENT_LABEL;

const pal = useCevicoPalette({
  scope: 'report:agentes',
  blocks: [{ id: 'orientar', label: 'Orientar', icon: 'i-lucide-pen-line' }],
});
const { cvVars } = pal;

const form = ref({
  agent_key: '',
  patient_excerpt: '',
  agent_text: '',
  ideal_reply: '',
  rule: '',
  target_section: 'objections',
  conversation_id: null,
  message_id: null,
  source: 'manual',
});
// "Passos do agente" só existe para os atendentes do WhatsApp
const SECTIONS = computed(() =>
  GUIDANCE_SECTIONS.filter(
    s => s.key !== 'stage' || AGENT_LABEL[form.value.agent_key]
  )
);
const saving = ref(false);
const isEdit = computed(() => !!props.guidance?.id);

onMounted(() => {
  const g = props.guidance || {};
  form.value = {
    ...form.value,
    ...g,
    agent_key: g.agent_key || props.agentKey || 'atendente_agendamento',
    agent_text: Array.isArray(g.agent_text)
      ? g.agent_text.join('\n\n')
      : g.agent_text || '',
    target_section: g.target_section || 'objections',
    source: g.source || 'manual',
  };
});

const agentTitle = computed(
  () =>
    props.agentName || AGENT_LABEL[form.value.agent_key] || form.value.agent_key
);
const canSave = computed(
  () => (form.value.ideal_reply || '').trim() || (form.value.rule || '').trim()
);

const save = async () => {
  if (!canSave.value || saving.value) return;
  saving.value = true;
  const payload = {
    agent_key: form.value.agent_key,
    patient_excerpt: (form.value.patient_excerpt || '').trim(),
    agent_text: (form.value.agent_text || '').trim(),
    ideal_reply: (form.value.ideal_reply || '').trim(),
    rule: (form.value.rule || '').trim(),
    target_section: form.value.target_section,
    conversation_id: form.value.conversation_id || null,
    message_id: form.value.message_id || null,
    source: form.value.source || 'manual',
  };
  try {
    const { data } = isEdit.value
      ? await CrmAPI.updateAgentGuidance(props.guidance.id, payload)
      : await CrmAPI.createAgentGuidance(payload);
    useAlert(
      isEdit.value
        ? '✍️ Orientação atualizada.'
        : '✍️ Orientação guardada — ela fica pendente no painel "Orientações dos atendentes" até você aplicar.'
    );
    emit('saved', data?.guidance || data || payload);
    emit('close');
  } catch (e) {
    useAlert(
      e?.response?.data?.error ||
        'Não consegui guardar a orientação (o servidor não respondeu).'
    );
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page cv-overlay fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-3 sm:p-6"
      :style="cvVars"
      @click.self="emit('close')"
    >
      <div class="cv-modal w-full max-w-2xl max-h-[92vh] flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-icon cv-icon-lg"><span class="i-lucide-pen-line text-lg"/></span>
          <div class="min-w-0 flex-1">
            <p class="text-base sm:text-lg font-bold leading-tight">
              ✍️ {{ isEdit ? 'Editar orientação' : 'Orientar o agente' }}
            </p>
            <p class="text-[11px] opacity-80">
              {{ agentTitle }} · diga como ele deveria ter respondido e a regra
              para não errar de novo.
            </p>
          </div>
          <button class="cv-iconbtn" title="Fechar" @click="emit('close')">
            <span class="i-lucide-x text-base" />
          </button>
        </div>

        <div class="flex-1 min-h-0 overflow-y-auto px-4 sm:px-6 py-4 space-y-4">
          <!-- o que o paciente disse (editável: dá para resumir) -->
          <div>
            <label class="cv-label block mb-1.5">
              🧑 O paciente disse
              <span class="font-normal opacity-70">(pode resumir)</span>
            </label>
            <textarea
              v-model="form.patient_excerpt"
              rows="2"
              class="cv-input w-full text-sm"
              placeholder="Ex.: minha mãe tem consulta hoje e quer remarcar pra sábado"
            />
          </div>

          <!-- o que o agente respondeu (só leitura) -->
          <div v-if="form.agent_text">
            <label class="cv-label block mb-1.5">🤖 O agente respondeu</label>
            <div
              class="rounded-xl px-3.5 py-2.5 text-sm whitespace-pre-wrap leading-relaxed text-n-slate-12"
              style="
                background: rgb(var(--cv-rgb) / 0.08);
                border: 1px solid rgb(var(--cv-rgb) / 0.22);
              "
            >
              {{ form.agent_text }}
            </div>
          </div>

          <!-- como deveria responder -->
          <div>
            <label class="cv-label block mb-1.5">
              ✅ Como deveria responder
            </label>
            <textarea
              v-model="form.ideal_reply"
              rows="4"
              class="cv-input w-full text-sm"
              placeholder="Escreva a resposta ideal, do jeito que você gostaria de ler no WhatsApp"
            />
          </div>

          <!-- regra para o futuro -->
          <div>
            <label class="cv-label block mb-1.5">
              📌 Regra para o futuro
              <span class="font-normal opacity-70">(1 frase)</span>
            </label>
            <input
              v-model="form.rule"
              type="text"
              class="cv-input w-full text-sm"
              placeholder="Ex.: Consulta de outra pessoa: buscar pelo nome e pelo dia antes de responder"
            />
          </div>

          <!-- onde a regra entra -->
          <div>
            <label class="cv-label block mb-1.5">
              📜 Onde a regra entra quando você aplicar
            </label>
            <div class="cv-seg cv-seg-sm !flex flex-wrap">
              <button
                v-for="sec in SECTIONS"
                :key="sec.key"
                class="cv-seg-item"
                :class="form.target_section === sec.key ? 'cv-seg-on' : ''"
                @click="form.target_section = sec.key"
              >
                <span :class="sec.icon" class="text-xs" /> {{ sec.label }}
              </button>
            </div>
            <p class="text-[11px] text-n-slate-10 mt-1.5 leading-relaxed">
              {{
                form.target_section === 'stage'
                  ? `Entra nos Passos desta etapa — só o ${agentTitle} lê.`
                  : 'Entra no Roteiro CEVICO — vale para todos os atendentes que falam com paciente.'
              }}
            </p>
          </div>
        </div>

        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <span class="text-[11px] text-n-slate-9 flex-1 min-w-0">
            Guardar não muda nada ainda — "Aplicar" no painel escreve a regra no
            lugar escolhido (e guarda uma versão antes).
          </span>
          <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="emit('close')">
            Cancelar
          </button>
          <button
            class="cv-btn cv-btn-sm cv-green"
            :disabled="!canSave || saving"
            @click="save"
          >
            <span
              :class="
                saving ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-save'
              "
              class="text-xs"
            />
            {{
              saving ? 'Guardando…' : isEdit ? 'Salvar' : 'Guardar orientação'
            }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
