<script setup>
// Card-resumo do painel da conversa: as informações mais importantes à
// primeira vista — nome/telefone copiáveis, estágio do CRM, etiquetas,
// responsividade e a análise de IA (indicador de interesse).
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import CrmAPI from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import PatientSpaceIcon from 'dashboard/routes/dashboard/patient/PatientSpaceIcon.vue';
import CevicoCallsCard from 'dashboard/components-next/cevico/calls/CevicoCallsCard.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  contact: { type: Object, default: () => ({}) },
});

const route = useRoute();
const router = useRouter();
// Espaço do Paciente: página única com toda a jornada
const openPatientSpace = () => {
  router.push(
    frontendURL(
      `accounts/${route.params.accountId}/patient/${props.contact.id}`
    )
  );
};

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
    const { data } = await CrmAPI.moveConversationStage(
      props.conversationId,
      stageId
    );
    if (summary.value) summary.value.stage = data.stage;
    showStagePicker.value = false;
    useAlert(`Card movido para "${data.stage?.stage_name}"!`);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao mover o card.');
  } finally {
    isMovingStage.value = false;
  }
};

// 🤖 item 212: o liga/desliga do Atendente IA saiu daqui para a CHAVINHA
// no topo da conversa (components-next/cevico/conversas/ResponderSwitch.vue)

// TRAVA do follow-up: a atendente pausa as cutucadas para ESTE paciente
// sem sair da conversa (o robô inteiro se desliga no balão do CRM/Automações)
const isTogglingFollowup = ref(false);
const togglePatientPause = async () => {
  const fu = summary.value?.followup;
  if (isTogglingFollowup.value || !fu) return;
  isTogglingFollowup.value = true;
  try {
    const { data } = await CrmAPI.toggleFollowupPause(
      props.conversationId,
      !fu.paused
    );
    summary.value.followup = data.followup;
    useAlert(
      data.followup.paused
        ? 'Follow-up pausado para este paciente.'
        : 'Follow-up reativado para este paciente.'
    );
  } catch {
    useAlert('Erro ao alterar o follow-up.');
  } finally {
    isTogglingFollowup.value = false;
  }
};

// ⏱ previsão do follow-up (rodada 158): cor por situação + ícone por etapa
const TIMELINE_ICON = {
  enviada: '✅',
  pulada: '⏭️',
  proxima: '🔜',
  aguardando: '⏳',
  pendente: '·',
};
const forecastTone = status =>
  ({
    proxima: 'text-n-brand',
    completa: 'text-green-600',
    pausado: 'text-amber-600',
    desligado: 'text-n-slate-9',
  })[status] || 'text-n-slate-11';

const INTEREST = {
  alto: {
    label: 'Interesse ALTO',
    class: 'bg-green-500/15 text-green-600',
    dot: 'bg-green-500',
  },
  medio: {
    label: 'Interesse MÉDIO',
    class: 'bg-amber-500/15 text-amber-600',
    dot: 'bg-amber-500',
  },
  baixo: {
    label: 'Interesse BAIXO',
    class: 'bg-orange-500/15 text-orange-600',
    dot: 'bg-orange-500',
  },
  perdido: {
    label: 'PERDIDO',
    class: 'bg-red-500/15 text-red-600',
    dot: 'bg-red-500',
  },
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
  <!-- CEVICO 199 (22/09): o resumo virou TRÊS cartões com divisões claras —
       Jornada (coluna do CRM, etiquetas, indicadores, follow-up),
       Inteligência (análise + ajuda com objeção) e Ligações. -->
  <div class="flex flex-col gap-3">
    <!-- ══ JORNADA NO CRM ══ -->
    <div class="cv-side-card p-4">
      <div class="flex items-center gap-2 mb-3">
        <p class="cv-side-title flex-1 min-w-0">
          <span class="cv-side-icon cv-side-icon-violet"><span class="i-lucide-kanban"/></span>
          Jornada
        </p>
        <button
          v-if="contact?.id"
          class="cv-side-btn"
          title="Abrir o Espaço do Paciente (toda a jornada numa página)"
          @click="openPatientSpace"
        >
          <PatientSpaceIcon :size="14" />
          Espaço do Paciente
        </button>
      </div>

      <template v-if="summary">
        <!-- coluna atual + mover -->
        <div v-if="summary.stage" class="mb-3">
          <div class="flex items-center gap-2 min-w-0 flex-wrap">
            <span
              class="text-[12px] font-bold px-3 h-7 inline-flex items-center rounded-full text-white min-w-0"
              :style="{
                backgroundColor: summary.stage.stage_color || '#6B7280',
              }"
              :title="summary.stage.stage_name"
            >
              {{ summary.stage.stage_name }}
            </span>
            <button
              v-if="summary.stage.stages?.length"
              class="cv-side-btn"
              @click="showStagePicker = !showStagePicker"
            >
              <span
                :class="
                  showStagePicker
                    ? 'i-lucide-chevron-up'
                    : 'i-lucide-arrow-right-left'
                "
                class="text-[11px]"
              />
              Mover
            </button>
          </div>
          <p class="text-[11px] text-n-slate-10 mt-1 m-0">
            Funil {{ summary.stage.pipeline_name }}
          </p>
          <div v-if="showStagePicker" class="flex flex-wrap gap-1 mt-2">
            <button
              v-for="s in summary.stage.stages"
              :key="s.id"
              class="text-[11px] font-medium px-2.5 h-7 rounded-full border transition-colors disabled:opacity-50 max-w-full truncate"
              :class="
                s.id === summary.stage.stage_id
                  ? 'text-white border-transparent cursor-default'
                  : 'text-n-slate-11 border-n-weak hover:text-white hover:border-transparent'
              "
              :style="
                s.id === summary.stage.stage_id
                  ? { backgroundColor: s.color || '#6B7280' }
                  : {}
              "
              :disabled="isMovingStage"
              :title="
                s.id === summary.stage.stage_id
                  ? 'Coluna atual'
                  : `Mover para ${s.name}`
              "
              @click="moveToStage(s.id)"
              @mouseenter="
                $event.target.style.backgroundColor = s.color || '#6B7280'
              "
              @mouseleave="
                s.id !== summary.stage.stage_id &&
                  ($event.target.style.backgroundColor = '')
              "
            >
              {{ s.name }}
            </button>
          </div>
        </div>

        <!-- etiquetas -->
        <div v-if="summary.labels?.length" class="flex flex-wrap gap-1 mb-3">
          <span
            v-for="label in summary.labels"
            :key="label"
            class="text-[10px] font-medium px-2 h-5 inline-flex items-center rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            {{ label }}
          </span>
        </div>

        <!-- indicadores lado a lado -->
        <div class="cv-side-stats mb-3">
          <div
            class="cv-side-stat"
            title="Respostas do paciente ÷ mensagens da clínica"
          >
            <b>{{ summary.metrics?.responsiveness ?? '—'
              }}<template
                v-if="
                  summary.metrics?.responsiveness !== null &&
                  summary.metrics?.responsiveness !== undefined
                "
                >%</template></b>
            <span>responsivo</span>
          </div>
          <div class="cv-side-stat" title="Mensagens do paciente / da clínica">
            <b>{{ summary.metrics?.patient_messages ?? 0
              }}<span class="inline text-n-slate-10 font-normal">/</span>{{ summary.metrics?.clinic_messages ?? 0 }}</b>
            <span>paciente / clínica</span>
          </div>
          <div class="cv-side-stat" title="Última mensagem do paciente">
            <b>{{ lastPatientAgo || '—' }}</b>
            <span>última do paciente</span>
          </div>
        </div>

        <!-- trava do follow-up -->
        <button
          v-if="
            summary.followup &&
            (summary.followup.bots?.length || summary.followup.paused)
          "
          class="w-full flex items-center justify-between gap-2 text-[11px] px-3 py-2 rounded-xl border transition-colors disabled:opacity-50 mb-2"
          :class="
            summary.followup.paused
              ? 'border-amber-400/60 bg-amber-400/10 text-amber-700 dark:text-amber-400 font-semibold'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
          "
          :disabled="isTogglingFollowup"
          :title="
            summary.followup.paused
              ? `Pausado por ${summary.followup.paused_by || '—'}`
              : 'O robô de follow-up para de cutucar este paciente'
          "
          @click="togglePatientPause"
        >
          <span class="flex items-center gap-1.5 min-w-0">
            <span
              :class="
                summary.followup.paused ? 'i-lucide-bell-off' : 'i-lucide-bell'
              "
              class="text-xs flex-shrink-0"
            />
            <span class="truncate">{{
              summary.followup.paused
                ? 'Follow-up pausado para este paciente'
                : 'Pausar follow-up para este paciente'
            }}</span>
          </span>
          <span class="font-bold flex-shrink-0">{{
            summary.followup.paused ? 'Reativar' : 'Pausar'
          }}</span>
        </button>

        <!-- previsão do follow-up, por robô -->
        <div v-if="summary.followup?.bots?.length" class="space-y-1.5">
          <div
            v-for="b in summary.followup.bots"
            :key="`fu-${b.id}`"
            class="rounded-xl bg-n-alpha-1 px-3 py-2 text-[11px]"
          >
            <div class="flex items-center gap-1.5 min-w-0">
              <span
                class="i-lucide-bot text-xs flex-shrink-0"
                :class="forecastTone(b.forecast?.status)"
              />
              <span class="font-semibold text-n-slate-12 truncate">{{
                b.name
              }}</span>
              <span v-if="!b.active"
class="text-n-slate-9 flex-shrink-0"
                >desligado</span>
            </div>
            <p
              v-if="b.forecast?.text"
              class="mt-0.5 leading-snug m-0"
              :class="forecastTone(b.forecast.status)"
            >
              {{ b.forecast.text }}
            </p>
            <div
              v-if="b.forecast?.timeline?.length"
              class="mt-1 flex flex-wrap gap-1"
            >
              <span
                v-for="(t, i) in b.forecast.timeline"
                :key="`fu-${b.id}-${i}`"
                class="rounded-full px-1.5 py-0.5 bg-n-alpha-2 text-n-slate-11"
                :title="t.note || ''"
                >{{ TIMELINE_ICON[t.status] || '·' }} {{ t.label
                }}<template v-if="t.when"> · {{ t.when }}</template></span>
            </div>
          </div>
        </div>
      </template>
      <p v-else-if="isLoading" class="text-[11px] text-n-slate-9 m-0">
        Carregando a jornada…
      </p>
      <p v-else class="text-[11px] text-n-slate-9 m-0">
        Esta conversa ainda não tem card no CRM.
      </p>
    </div>

    <!-- ══ INTELIGÊNCIA (IA) ══ -->
    <div v-if="summary" class="cv-side-card p-4">
      <div class="flex items-center gap-2 mb-3">
        <p class="cv-side-title flex-1 min-w-0">
          <span class="cv-side-icon cv-side-icon-green"><span class="i-lucide-sparkles"/></span>
          Inteligência
        </p>
        <button
          v-if="summary.ai && !summary.ai.error"
          class="text-[10px] text-n-slate-10 hover:text-n-slate-12 flex items-center gap-1"
          :disabled="isAnalyzing"
          title="Reanalisar com IA"
          @click="analyze"
        >
          <span
            :class="
              isAnalyzing
                ? 'i-lucide-loader-2 animate-spin'
                : 'i-lucide-refresh-cw'
            "
            class="text-[10px]"
          />
          {{ analyzedAgo }}
        </button>
      </div>

      <template v-if="summary.ai && !summary.ai.error">
        <div class="flex items-center gap-2 mb-2 flex-wrap">
          <span
            v-if="interest"
            class="flex items-center gap-1.5 text-[11px] font-bold px-2.5 h-6 rounded-full"
            :class="interest.class"
          >
            <span class="w-1.5 h-1.5 rounded-full" :class="interest.dot" />
            {{ interest.label }}
          </span>
          <span
            v-if="scriptStage"
            class="text-[10px] font-semibold px-2 h-6 inline-flex items-center gap-1 rounded-full bg-n-alpha-2 text-n-slate-12"
            title="Etapa do script onde a IA entende que a conversa está"
          >
            <span class="i-lucide-map-pin text-[10px] text-n-slate-10" />
            {{ scriptStage }}
          </span>
        </div>
        <p class="text-xs text-n-slate-11 leading-relaxed mb-1.5">
          {{ summary.ai.summary }}
        </p>
        <p
          v-if="summary.ai.next_step"
          class="text-[12px] text-n-slate-12 font-semibold rounded-xl bg-n-alpha-1 px-3 py-2 m-0"
        >
          👉 {{ summary.ai.next_step }}
        </p>

        <div v-if="suggestedPhrases.length" class="mt-3">
          <p
            class="text-[10px] font-bold uppercase tracking-wide text-n-slate-10 mb-1.5"
          >
            <span class="i-lucide-message-square-quote text-[10px]" />
            Frases sugeridas
          </p>
          <button
            v-for="(phrase, index) in suggestedPhrases"
            :key="index"
            class="w-full flex items-start gap-1.5 text-left text-[11px] text-n-slate-11 leading-relaxed rounded-xl border border-n-weak px-3 py-2 mb-1 hover:bg-n-alpha-1 hover:text-n-slate-12 transition-colors group"
            title="Copiar frase"
            @click="copy(phrase, 'Frase')"
          >
            <span class="flex-1">{{ phrase }}</span>
            <span
              class="i-lucide-copy text-[11px] text-n-slate-8 group-hover:text-n-slate-12 flex-shrink-0 mt-0.5"
            />
          </button>
          <p class="text-[10px] text-n-slate-9 leading-snug m-0">
            Sugestões da IA no tom do script. Revise antes de enviar — quem
            decide é você.
          </p>
        </div>
      </template>

      <button
        v-else-if="summary.ai_configured"
        class="cv-side-btn w-full"
        :disabled="isAnalyzing"
        @click="analyze"
      >
        <span
          :class="
            isAnalyzing ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-sparkles'
          "
          class="text-sm"
        />
        {{ isAnalyzing ? 'Analisando conversa…' : 'Analisar com IA' }}
      </button>

      <p v-else class="text-[11px] text-n-slate-9 m-0">
        Análise de IA disponível — configure em CRM → Integrações → IA
      </p>

      <!-- 💼 ajuda com a OBJEÇÃO durante o atendimento -->
      <button
        v-if="summary.ai_configured"
        class="cv-side-btn cv-side-btn-green w-full mt-2"
        :disabled="isCoaching"
        @click="askSalesHelp"
      >
        <span
          :class="
            isCoaching ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-handshake'
          "
          class="text-sm"
        />
        {{ isCoaching ? 'Lendo a conversa…' : 'Ajuda com objeção (IA)' }}
      </button>
      <div
        v-if="salesHelp"
        class="mt-2 rounded-xl border p-3 space-y-1.5"
        style="
          border-color: rgba(16, 185, 129, 0.4);
          background: rgba(16, 185, 129, 0.06);
        "
      >
        <p class="text-[12px] font-bold text-n-slate-12 m-0">
          {{ OBJECTION_LABELS[salesHelp.objection] || salesHelp.objection }}
        </p>
        <p class="text-[11px] text-n-slate-11 leading-snug m-0">
          {{ salesHelp.reading }}
        </p>
        <div class="space-y-1">
          <button
            v-for="(reply, i) in salesHelp.replies"
            :key="i"
            class="w-full text-left text-[11px] rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 hover:border-green-500/60 transition-colors"
            title="Clique para copiar — revise antes de enviar, quem decide é você"
            @click="copySalesReply(reply)"
          >
            📋 {{ reply }}
          </button>
        </div>
        <p class="text-[10px] text-n-slate-10 m-0">
          <b>Próximo passo:</b> {{ salesHelp.next_step }}
        </p>
        <p class="text-[10px] text-n-slate-9 m-0">
          Revise antes de enviar — quem decide é você.
        </p>
      </div>
    </div>

    <!-- ══ LIGAÇÕES (item 167) ══ -->
    <div v-if="contact?.id" class="cv-side-card cv-side-calls p-4">
      <CevicoCallsCard
        :contact-id="contact.id"
        :conversation-id="conversationId"
        variant="panel"
      />
    </div>
  </div>
</template>
