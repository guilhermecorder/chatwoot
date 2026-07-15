<script setup>
// Card-resumo do painel da conversa: as informações mais importantes à
// primeira vista — nome/telefone copiáveis, estágio do CRM, etiquetas,
// responsividade e a análise de IA (indicador de interesse).
import { ref, computed, watch, onMounted } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  contact: { type: Object, default: () => ({}) },
});

const summary = ref(null);
const isLoading = ref(false);
const isAnalyzing = ref(false);

const load = async () => {
  if (!props.conversationId) return;
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getConversationSummary(props.conversationId);
    summary.value = data;
  } catch {
    summary.value = null;
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
watch(() => props.conversationId, load);

const copy = async (value, label) => {
  if (!value) return;
  try {
    await navigator.clipboard.writeText(value);
    useAlert(`${label} copiado!`);
  } catch {
    useAlert('Não foi possível copiar.');
  }
};

const analyze = async () => {
  if (isAnalyzing.value) return;
  isAnalyzing.value = true;
  try {
    const { data } = await CrmAPI.analyzeConversation(props.conversationId);
    if (summary.value) summary.value.ai = data.ai;
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro na análise de IA.');
  } finally {
    isAnalyzing.value = false;
  }
};

// 💼 Consultor Comercial ao vivo: objeção + respostas prontas
const isCoaching = ref(false);
const salesHelp = ref(null);
const askSalesHelp = async () => {
  if (isCoaching.value) return;
  isCoaching.value = true;
  try {
    const { data } = await CrmAPI.salesHelp(props.conversationId);
    salesHelp.value = data.sales;
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro na ajuda comercial.');
  } finally {
    isCoaching.value = false;
  }
};
const copySalesReply = async text => {
  try {
    await navigator.clipboard.writeText(text);
    useAlert('Resposta copiada — revise antes de enviar.');
  } catch {
    useAlert('Não consegui copiar.');
  }
};
const OBJECTION_LABELS = {
  preco: '💰 Preço/investimento',
  medo_cirurgia: '😨 Medo da cirurgia',
  vou_pensar: '🤔 "Vou pensar"',
  conversar_familia: '👪 Conversar com a família',
  sem_tempo: '⏳ Falta de tempo',
  confianca: '🤝 Confiança',
  distancia: '📍 Distância',
  concorrencia: '⚖️ Comparando com outra clínica',
  sem_objecao: '✅ Sem objeção — hora de avançar',
  outra: '❓ Outra',
};

// mover o card de coluna direto daqui (dispara as automações do board)
const showStagePicker = ref(false);
const isMovingStage = ref(false);

const moveToStage = async stageId => {
  if (isMovingStage.value || stageId === summary.value?.stage?.stage_id) return;
  isMovingStage.value = true;
  try {
    const { data } = await CrmAPI.moveConversationStage(props.conversationId, stageId);
    if (summary.value) summary.value.stage = data.stage;
    showStagePicker.value = false;
    useAlert(`Card movido para "${data.stage?.stage_name}"!`);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao mover o card.');
  } finally {
    isMovingStage.value = false;
  }
};

const INTEREST = {
  alto: { label: 'Interesse ALTO', class: 'bg-green-500/15 text-green-600', dot: 'bg-green-500' },
  medio: { label: 'Interesse MÉDIO', class: 'bg-amber-500/15 text-amber-600', dot: 'bg-amber-500' },
  baixo: { label: 'Interesse BAIXO', class: 'bg-orange-500/15 text-orange-600', dot: 'bg-orange-500' },
  perdido: { label: 'PERDIDO', class: 'bg-red-500/15 text-red-600', dot: 'bg-red-500' },
};

const interest = computed(() => INTEREST[summary.value?.ai?.level] || null);

// etapa do script CEVICO onde a IA entende que a conversa está
const SCRIPT_STAGES = {
  recepcao: 'Recepção',
  sondagem: 'Sondagem',
  autoridade: 'Autoridade',
  orcamento: 'Orçamento',
  objecoes: 'Dúvidas e objeções',
  agendamento: 'Agendamento',
  pos_agendamento: 'Pós-agendamento',
  pos_consulta: 'Pós-consulta',
  pos_cirurgico: 'Pós-cirúrgico',
  reagendamento: 'Reagendamento',
};

const scriptStage = computed(
  () => SCRIPT_STAGES[summary.value?.ai?.script_stage] || null
);

const suggestedPhrases = computed(() => {
  const phrases = summary.value?.ai?.suggested_phrases;
  return Array.isArray(phrases) ? phrases.filter(Boolean) : [];
});

const lastPatientAgo = computed(() => {
  const ts = summary.value?.metrics?.last_patient_message_at;
  if (!ts) return null;
  const mins = Math.floor((Date.now() - new Date(ts).getTime()) / 60000);
  if (mins < 60) return `${mins}min`;
  const hours = Math.floor(mins / 60);
  if (hours < 48) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
});

const analyzedAgo = computed(() => {
  const ts = summary.value?.ai?.analyzed_at;
  if (!ts) return null;
  return new Date(ts).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
});
</script>

<template>
  <div class="mx-4 mb-2 rounded-xl border border-n-weak bg-n-solid-1 p-3">
    <!-- Nome e telefone copiáveis em 1 clique -->
    <div class="flex flex-col gap-1 mb-2">
      <button
        v-if="contact?.name"
        class="flex items-center gap-1.5 text-sm font-semibold text-n-slate-12 hover:text-n-brand text-left"
        title="Copiar nome"
        @click="copy(contact.name, 'Nome')"
      >
        <span class="truncate">{{ contact.name }}</span>
        <span class="i-lucide-copy text-[11px] text-n-slate-9 flex-shrink-0" />
      </button>
      <button
        v-if="contact?.phone_number"
        class="flex items-center gap-1.5 text-xs text-n-slate-11 hover:text-n-brand text-left"
        title="Copiar telefone"
        @click="copy(contact.phone_number, 'Telefone')"
      >
        {{ contact.phone_number }}
        <span class="i-lucide-copy text-[11px] text-n-slate-9 flex-shrink-0" />
      </button>
    </div>

    <template v-if="summary">
      <!-- Estágio do CRM: pílula atual + mover de coluna sem sair da conversa -->
      <div v-if="summary.stage" class="mb-2">
        <div class="flex items-center gap-1.5 min-w-0">
          <span class="i-lucide-kanban text-xs text-n-slate-10 flex-shrink-0" />
          <span
            class="text-[11px] font-medium px-2 py-0.5 rounded-full text-white whitespace-nowrap truncate min-w-0"
            :style="{ backgroundColor: summary.stage.stage_color || '#6B7280' }"
            :title="summary.stage.stage_name"
          >
            {{ summary.stage.stage_name }}
          </span>
          <button
            v-if="summary.stage.stages?.length"
            class="flex items-center gap-0.5 text-[10px] font-medium text-n-slate-10 hover:text-n-brand px-1.5 py-0.5 rounded border border-n-weak hover:border-n-brand/40 flex-shrink-0 transition-colors"
            @click="showStagePicker = !showStagePicker"
          >
            <span :class="showStagePicker ? 'i-lucide-chevron-up' : 'i-lucide-arrow-right-left'" class="text-[10px]" />
            Mover
          </button>
        </div>
        <p class="text-[10px] text-n-slate-9 truncate mt-0.5 pl-[18px]">{{ summary.stage.pipeline_name }}</p>

        <!-- Botões das colunas (mobile-friendly: quebram linha, alvo grande) -->
        <div v-if="showStagePicker" class="flex flex-wrap gap-1 mt-1.5 pl-[18px]">
          <button
            v-for="s in summary.stage.stages"
            :key="s.id"
            class="text-[10px] font-medium px-2 py-1 rounded-lg border transition-colors disabled:opacity-50 max-w-full truncate"
            :class="s.id === summary.stage.stage_id
              ? 'text-white border-transparent cursor-default'
              : 'text-n-slate-11 border-n-weak hover:text-white hover:border-transparent'"
            :style="s.id === summary.stage.stage_id ? { backgroundColor: s.color || '#6B7280' } : {}"
            :disabled="isMovingStage"
            :title="s.id === summary.stage.stage_id ? 'Coluna atual' : `Mover para ${s.name}`"
            @click="moveToStage(s.id)"
            @mouseenter="$event.target.style.backgroundColor = s.color || '#6B7280'"
            @mouseleave="s.id !== summary.stage.stage_id && ($event.target.style.backgroundColor = '')"
          >
            {{ s.name }}
          </button>
        </div>
      </div>

      <!-- Etiquetas -->
      <div v-if="summary.labels?.length" class="flex flex-wrap gap-1 mb-2">
        <span
          v-for="label in summary.labels"
          :key="label"
          class="text-[10px] px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-11"
        >
          {{ label }}
        </span>
      </div>

      <!-- Métricas -->
      <div class="flex items-center gap-3 text-[11px] text-n-slate-10 mb-2">
        <span v-if="summary.metrics?.responsiveness !== null" title="Respostas do paciente ÷ mensagens da clínica">
          <span class="i-lucide-activity text-[10px]" />
          {{ summary.metrics.responsiveness }}% responsivo
        </span>
        <span title="Mensagens do paciente / da clínica">
          💬 {{ summary.metrics?.patient_messages ?? 0 }}/{{ summary.metrics?.clinic_messages ?? 0 }}
        </span>
        <span v-if="lastPatientAgo" title="Última mensagem do paciente">
          <span class="i-lucide-clock text-[10px]" />
          {{ lastPatientAgo }}
        </span>
      </div>

      <!-- Análise de IA -->
      <div class="border-t border-n-weak pt-2">
        <template v-if="summary.ai && !summary.ai.error">
          <div class="flex items-center gap-2 mb-1.5">
            <span
              v-if="interest"
              class="flex items-center gap-1.5 text-[11px] font-semibold px-2 py-0.5 rounded-full"
              :class="interest.class"
            >
              <span class="w-1.5 h-1.5 rounded-full" :class="interest.dot" />
              {{ interest.label }}
            </span>
            <button
              class="ml-auto text-[10px] text-n-slate-9 hover:text-n-brand flex items-center gap-1"
              :disabled="isAnalyzing"
              title="Reanalisar com IA"
              @click="analyze"
            >
              <span :class="isAnalyzing ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-refresh-cw'" class="text-[10px]" />
              {{ analyzedAgo }}
            </button>
          </div>
          <p class="text-xs text-n-slate-11 leading-relaxed mb-1">
            {{ summary.ai.summary }}
          </p>
          <p v-if="summary.ai.next_step" class="text-[11px] text-n-slate-12 font-medium">
            👉 {{ summary.ai.next_step }}
          </p>

          <!-- Etapa do script + frases sugeridas (item 28) -->
          <div v-if="scriptStage" class="flex items-center gap-1.5 mt-2">
            <span class="i-lucide-map-pin text-[10px] text-n-slate-10" />
            <span class="text-[10px] text-n-slate-10">Etapa do script:</span>
            <span class="text-[10px] font-semibold px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-12">
              {{ scriptStage }}
            </span>
          </div>
          <div v-if="suggestedPhrases.length" class="mt-1.5">
            <p class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-10 mb-1">
              <span class="i-lucide-message-square-quote text-[10px]" />
              Frases sugeridas
            </p>
            <button
              v-for="(phrase, index) in suggestedPhrases"
              :key="index"
              class="w-full flex items-start gap-1.5 text-left text-[11px] text-n-slate-11 leading-relaxed rounded-lg border border-n-weak px-2 py-1.5 mb-1 hover:bg-n-alpha-1 hover:text-n-slate-12 hover:border-n-brand/40 transition-colors group"
              title="Copiar frase"
              @click="copy(phrase, 'Frase')"
            >
              <span class="flex-1">{{ phrase }}</span>
              <span class="i-lucide-copy text-[11px] text-n-slate-8 group-hover:text-n-brand flex-shrink-0 mt-0.5" />
            </button>
            <p class="text-[9px] text-n-slate-8 leading-snug">
              Sugestões da IA no tom do script. Revise antes de enviar — quem decide é você.
            </p>
          </div>
        </template>

        <button
          v-else-if="summary.ai_configured"
          class="w-full flex items-center justify-center gap-1.5 text-xs px-2.5 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-brand transition-colors disabled:opacity-50"
          :disabled="isAnalyzing"
          @click="analyze"
        >
          <span :class="isAnalyzing ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-sparkles'" class="text-sm" />
          {{ isAnalyzing ? 'Analisando conversa…' : 'Analisar com IA' }}
        </button>

        <p v-else class="text-[10px] text-n-slate-9">
          <span class="i-lucide-sparkles text-[10px]" />
          Análise de IA disponível — configure em CRM → Integrações → IA
        </p>

        <!-- 💼 Consultor Comercial: ajuda com a OBJEÇÃO durante o atendimento -->
        <button
          v-if="summary.ai_configured"
          class="w-full flex items-center justify-center gap-1.5 text-xs px-2.5 py-1.5 rounded-lg text-white hover:opacity-90 transition-opacity disabled:opacity-50 mt-1.5"
          style="background: linear-gradient(135deg, #065F46, #10B981)"
          :disabled="isCoaching"
          @click="askSalesHelp"
        >
          <span :class="isCoaching ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-handshake'" class="text-sm" />
          {{ isCoaching ? 'Lendo a conversa…' : '💼 Ajuda com objeção (IA)' }}
        </button>
        <div v-if="salesHelp" class="mt-2 rounded-xl border p-2.5 space-y-1.5" style="border-color: rgba(16,185,129,0.4); background: rgba(16,185,129,0.06)">
          <p class="text-[11px] font-bold text-n-slate-12">
            {{ OBJECTION_LABELS[salesHelp.objection] || salesHelp.objection }}
          </p>
          <p class="text-[11px] text-n-slate-11 leading-snug">{{ salesHelp.reading }}</p>
          <div class="space-y-1">
            <button
              v-for="(reply, i) in salesHelp.replies"
              :key="i"
              class="w-full text-left text-[11px] rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 hover:border-green-500/60 transition-colors"
              title="Clique para copiar — revise antes de enviar, quem decide é você"
              @click="copySalesReply(reply)"
            >
              📋 {{ reply }}
            </button>
          </div>
          <p class="text-[10px] text-n-slate-10"><b>Próximo passo:</b> {{ salesHelp.next_step }}</p>
          <p class="text-[9px] text-n-slate-9">Revise antes de enviar — quem decide é você.</p>
        </div>
      </div>
    </template>

    <div v-else-if="isLoading" class="text-[11px] text-n-slate-9">Carregando resumo…</div>
  </div>
</template>
