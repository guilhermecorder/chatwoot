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

const INTEREST = {
  alto: { label: 'Interesse ALTO', class: 'bg-green-500/15 text-green-600', dot: 'bg-green-500' },
  medio: { label: 'Interesse MÉDIO', class: 'bg-amber-500/15 text-amber-600', dot: 'bg-amber-500' },
  baixo: { label: 'Interesse BAIXO', class: 'bg-orange-500/15 text-orange-600', dot: 'bg-orange-500' },
  perdido: { label: 'PERDIDO', class: 'bg-red-500/15 text-red-600', dot: 'bg-red-500' },
};

const interest = computed(() => INTEREST[summary.value?.ai?.level] || null);

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
      <!-- Estágio do CRM -->
      <div v-if="summary.stage" class="flex items-center gap-1.5 mb-2">
        <span class="i-lucide-kanban text-xs text-n-slate-10" />
        <span
          class="text-[11px] font-medium px-2 py-0.5 rounded-full text-white"
          :style="{ backgroundColor: summary.stage.stage_color || '#6B7280' }"
        >
          {{ summary.stage.stage_name }}
        </span>
        <span class="text-[10px] text-n-slate-9 truncate">{{ summary.stage.pipeline_name }}</span>
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
      </div>
    </template>

    <div v-else-if="isLoading" class="text-[11px] text-n-slate-9">Carregando resumo…</div>
  </div>
</template>
