<script setup>
// 🧪 TESTAR AGENTE (rodada 188): bate-papo estilo WhatsApp em que VOCÊ é o
// paciente e o agente responde com a IA de verdade e o Roteiro atual. Roda
// numa caixa interna sem canal de envio — ambiente seguro, controlado e
// dedicado a testar agentes, local ou em produção. As respostas ficam como
// notas de sombra (mesmo formato da tela Sombra).
import { ref, computed, nextTick, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CrmAPI from 'dashboard/api/crm';
import GuidanceModal from './GuidanceModal.vue';

const props = defineProps({
  agentKey: { type: String, default: 'atendente_agendamento' },
  agentName: { type: String, default: 'Atendente de Agendamento' },
  // ✍️ rodada 191: "Testar de novo" no painel de Orientações abre o teste
  // com a fala do paciente já digitada no campo
  prefill: { type: String, default: '' },
});
const emit = defineEmits(['close', 'edit-script', 'guided']);

const pal = useCevicoPalette({
  scope: 'report:agentes',
  blocks: [
    { id: 'teste', label: 'Testar agente', icon: 'i-lucide-flask-conical' },
  ],
});
const { cvVars } = pal;

const conversationId = ref(null);
const displayId = ref(null);
const turns = ref([]);
const draft = ref('');
const isSending = ref(false);
const isStarting = ref(false);
const errorText = ref('');
const bodyEl = ref(null);
const inputEl = ref(null);

const STAGE_LABEL = {
  recepcao: 'recepção',
  sondagem: 'sondagem',
  autoridade: 'autoridade',
  orcamento: 'orçamento',
  objecoes: 'objeções',
  agendamento: 'agendamento',
  pos_agendamento: 'pós-agendamento',
  reagendamento: 'reagendamento',
  pos_consulta: 'pós-consulta',
  pos_cirurgico: 'pós-cirúrgico',
  encerramento: 'encerramento',
};
const UNIT_LABEL = { tatuape: 'Tatuapé', paulista: 'Av. Paulista' };
const SUGGESTIONS = [
  'oi, quero saber sobre cirurgia refrativa, uso grau 3',
  'minha mãe tem catarata, quanto fica?',
  'tenho convênio unimed',
  'achei caro',
  'pode ser terça de manhã?',
  'preciso remarcar minha consulta',
  'você é um robô?',
  'fiz a cirurgia ontem e meu olho tá doendo muito',
];

const scrollToEnd = async () => {
  await nextTick();
  if (bodyEl.value) bodyEl.value.scrollTop = bodyEl.value.scrollHeight;
};

const start = async () => {
  isStarting.value = true;
  errorText.value = '';
  try {
    const { data } = await CrmAPI.simulateAgent({ agent: props.agentKey });
    conversationId.value = data.conversation_id;
    displayId.value = data.display_id;
    turns.value = data.turns || [];
    if (props.prefill && !draft.value) draft.value = props.prefill;
  } catch {
    useAlert('Não consegui abrir a conversa de teste.');
  } finally {
    isStarting.value = false;
    await scrollToEnd();
    inputEl.value?.focus();
  }
};
onMounted(start);

const send = async text => {
  const content = (text ?? draft.value).trim();
  if (!content || isSending.value) return;
  draft.value = '';
  errorText.value = '';
  // otimista: o balão do paciente aparece na hora, o agente "digita"
  turns.value.push({
    role: 'patient',
    text: content,
    at: new Date().toISOString(),
    id: `tmp-${Date.now()}`,
  });
  isSending.value = true;
  await scrollToEnd();
  try {
    const { data } = await CrmAPI.simulateAgent({
      agent: props.agentKey,
      conversation_id: conversationId.value,
      text: content,
    });
    conversationId.value = data.conversation_id;
    turns.value = data.turns || [];
    if (data.error) errorText.value = data.error;
  } catch {
    errorText.value = 'Falha ao falar com a IA. Tente de novo.';
  } finally {
    isSending.value = false;
    await scrollToEnd();
    inputEl.value?.focus();
  }
};

const fmtTime = iso =>
  iso
    ? new Date(iso).toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const fmtDay = ymd => {
  if (!ymd) return '';
  const [y, m, d] = String(ymd).split('-');
  return d && m ? `${d}/${m}/${y}` : ymd;
};
const lastAgent = computed(() =>
  [...turns.value].reverse().find(t => t.role === 'agent')
);
const ended = computed(() => !!lastAgent.value?.meta?.pausar);

// 🔧 rodada 192: ferramentas que o agente usou nesta resposta (buscar,
// remarcar, cancelar, confirmar) — montadas pelo serviço, viram chips
const TOOL_LABEL = {
  buscar_consulta: 'buscou consulta',
  remarcar_consulta: 'remarcou',
  cancelar_consulta: 'cancelou',
  confirmar_presenca: 'confirmou presença',
};
const toolChip = a =>
  `🔧 ${a.resumo || TOOL_LABEL[a.ferramenta] || a.ferramenta}`;

// ✍️ rodada 191: Orientar a partir de um balão do agente — leva as
// mensagens dele e a última fala do paciente antes dele
const guiding = ref(null);
const lastPatientBefore = turn => {
  const idx = turns.value.indexOf(turn);
  for (let i = idx - 1; i >= 0; i -= 1) {
    if (turns.value[i].role === 'patient') return turns.value[i].text || '';
  }
  return '';
};
const guide = turn => {
  guiding.value = {
    agent_key: props.agentKey,
    agent_text: (turn.messages || []).join('\n\n'),
    patient_excerpt: lastPatientBefore(turn),
    conversation_id: displayId.value || null,
    message_id: typeof turn.id === 'number' ? turn.id : null,
    source: 'manual',
  };
};
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-3 sm:p-6"
      :style="cvVars"
      @click.self="emit('close')"
    >
      <div class="cv-modal w-full max-w-3xl max-h-[92vh] flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-icon cv-icon-lg"><span class="i-lucide-flask-conical text-lg"/></span>
          <div class="min-w-0 flex-1">
            <p class="text-base sm:text-lg font-bold leading-tight">
              🧪 Testar agente · {{ agentName }}
            </p>
            <p class="text-[11px] opacity-80">
              Você é o paciente. O agente responde com a IA de verdade e o
              Roteiro de agora. Caixa interna, sem canal de envio: nada vai para
              telefone nenhum.
            </p>
          </div>
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm"
            :disabled="isStarting || isSending"
            title="Começar uma conversa do zero"
            @click="start"
          >
            <span class="i-lucide-rotate-ccw text-xs" /> Nova conversa
          </button>
          <button class="cv-iconbtn" title="Fechar" @click="emit('close')">
            <span class="i-lucide-x text-base" />
          </button>
        </div>

        <!-- corpo do bate-papo -->
        <div
          ref="bodyEl"
          class="flex-1 min-h-0 overflow-y-auto px-4 sm:px-6 py-4 space-y-3 cv-chat-bg"
        >
          <p v-if="displayId" class="text-center text-[10px] text-n-slate-9">
            conversa de teste #{{ displayId }} · paciente de teste ·
            {{ new Date().toLocaleDateString('pt-BR') }}
          </p>

          <template v-for="t in turns" :key="t.id">
            <!-- paciente (você) à direita -->
            <div v-if="t.role === 'patient'" class="flex justify-end">
              <div class="cv-bubble cv-bubble-me">
                <p class="whitespace-pre-wrap">{{ t.text }}</p>
                <span class="cv-bubble-time">{{ fmtTime(t.at) }} · você (paciente)</span>
              </div>
            </div>
            <!-- agente à esquerda: um balão por mensagem -->
            <div v-else class="flex flex-col items-start gap-1.5">
              <div
                v-for="(m, i) in t.messages"
                :key="`${t.id}-${i}`"
                class="cv-bubble cv-bubble-agent"
              >
                <p class="whitespace-pre-wrap">{{ m }}</p>
                <span class="cv-bubble-time">{{ fmtTime(t.at) }} · {{ agentName }}</span>
              </div>
              <div class="flex flex-wrap items-center gap-1.5 pl-1">
                <span class="cv-chip">{{
                  STAGE_LABEL[t.meta?.etapa] || t.meta?.etapa || '—'
                }}</span>
                <span
                  v-if="t.meta?.agendar"
                  class="cv-chip"
                  :class="t.meta?.slot_valid ? 'cv-green' : 'cv-red'"
                >
                  📅 agendaria {{ fmtDay(t.meta?.agendamento?.dia) }}
                  {{ t.meta?.agendamento?.hora }} ·
                  {{
                    UNIT_LABEL[t.meta?.agendamento?.unidade] ||
                    t.meta?.agendamento?.unidade
                  }}
                  ·
                  {{
                    t.meta?.slot_valid ? 'vaga válida ✓' : 'vaga NÃO validou ✗'
                  }}
                </span>
                <span v-if="t.meta?.chamar_humano"
class="cv-chip cv-amber"
                  >🙋 chamaria humano</span>
                <span v-if="t.meta?.pausar"
class="cv-chip cv-slate"
                  >⏸ encerraria</span>
                <span
                  v-for="(a, ai) in t.meta?.acoes || []"
                  :key="`acao-${t.id}-${ai}`"
                  class="cv-chip cv-chip-wrap"
                  :class="a.ok === false ? 'cv-red' : 'cv-green'"
                  :title="
                    a.ok === false
                      ? 'a ferramenta não conseguiu'
                      : 'ferramenta usada'
                  "
                >
                  {{ toolChip(a) }}
                </span>
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost cv-amber"
                  title="Escreva como o agente deveria ter respondido — vira uma orientação para aplicar no Roteiro"
                  @click="guide(t)"
                >
                  ✍️ Orientar
                </button>
              </div>
              <p
                v-if="t.meta?.leitura"
                class="text-[11px] text-n-slate-10 italic pl-1 max-w-[85%]"
              >
                💭 {{ t.meta.leitura }}
              </p>
            </div>
          </template>

          <div v-if="isSending" class="flex items-start">
            <div class="cv-bubble cv-bubble-agent">
              <span class="i-lucide-loader-2 animate-spin text-sm" />
              <span class="text-[11px]">o agente está lendo o Roteiro e a conversa…</span>
            </div>
          </div>
          <p v-if="errorText" class="cv-strip text-[11px]">
            ⚠️ {{ errorText }}
          </p>
          <p v-if="ended" class="text-center text-[11px] text-n-slate-10">
            ⏸ O agente encerrou a função nesta conversa. Comece uma nova para
            testar outro caso.
          </p>
        </div>

        <!-- sugestões + entrada -->
        <div class="cv-modal-foot flex flex-col gap-2">
          <div class="flex gap-1.5 overflow-x-auto pb-1">
            <button
              v-for="s in SUGGESTIONS"
              :key="s"
              class="cv-chip whitespace-nowrap hover:opacity-80"
              :disabled="isSending"
              @click="send(s)"
            >
              {{ s }}
            </button>
          </div>
          <div class="flex items-end gap-2">
            <textarea
              ref="inputEl"
              v-model="draft"
              rows="2"
              class="cv-input flex-1 min-w-0 resize-none"
              placeholder="Escreva como o paciente… (Enter envia, Shift+Enter quebra linha)"
              :disabled="isSending || isStarting"
              @keydown.enter.exact.prevent="send()"
            />
            <button
              class="cv-btn cv-btn-lg"
              :disabled="isSending || isStarting || !draft.trim()"
              @click="send()"
            >
              <span class="i-lucide-send text-sm" /> Enviar
            </button>
          </div>
          <div
            class="flex items-center gap-2 flex-wrap text-[10px] text-n-slate-9"
          >
            <span class="flex-1 min-w-0">Cada resposta custa centavos de dólar e aparece também na tela
              Sombra. Ajuste o Roteiro e teste de novo até ficar do seu
              jeito.</span>
            <button
              class="cv-btn cv-btn-ghost cv-btn-sm"
              @click="emit('edit-script')"
            >
              <span class="i-lucide-scroll-text text-xs" /> Editar Roteiro
            </button>
          </div>
        </div>
      </div>
    </div>
    <GuidanceModal
      v-if="guiding"
      :guidance="guiding"
      :agent-key="agentKey"
      :agent-name="agentName"
      @close="guiding = null"
      @saved="emit('guided', $event)"
    />
  </Teleport>
</template>

<style scoped>
.cv-chat-bg {
  background: radial-gradient(
      circle at 20% 10%,
      rgb(var(--cv-rgb) / 0.08),
      transparent 45%
    ),
    radial-gradient(
      circle at 85% 90%,
      rgb(var(--cv-rgb) / 0.06),
      transparent 40%
    );
}
.cv-bubble {
  max-width: 85%;
  border-radius: 18px;
  padding: 10px 14px;
  font-size: 13px;
  line-height: 1.45;
  box-shadow: 0 1px 2px rgb(0 0 0 / 0.08);
}
.cv-bubble-agent {
  background: linear-gradient(135deg, #0f5fa6, #1d4ed8);
  color: #fff;
  border-bottom-left-radius: 6px;
}
.cv-bubble-me {
  background: rgb(var(--cv-rgb) / 0.14);
  color: inherit;
  border: 1px solid rgb(var(--cv-rgb) / 0.25);
  border-bottom-right-radius: 6px;
}
.cv-bubble-time {
  display: block;
  margin-top: 4px;
  font-size: 10px;
  opacity: 0.7;
}
</style>
