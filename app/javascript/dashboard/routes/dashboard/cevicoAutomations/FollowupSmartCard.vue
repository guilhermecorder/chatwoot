<script setup>
// 🧠 FOLLOW-UP INTELIGENTE (13/10 — "o robô ainda está meio burrinho, não
// entende que a conversa acabou"). Três blocos na aba Robôs:
//   1. Como o robô decide — leitura da conversa, lead frio, fim de semana
//   2. Quem adiou — UMA mensagem modelo N dias depois, modelo por caixa
//   3. Resultado — por coluna do CRM, na régua de período padrão
// Config da conta em agenda_config.followup_smart (Crm::FollowupBotJob#smart).
import { ref, computed, watch, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import TemplatesPicker from 'dashboard/components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import CrmAPI from 'dashboard/api/crm';
import { periodParams } from 'dashboard/helper/cevicoPeriod';

const props = defineProps({
  canEdit: { type: Boolean, default: false },
});

const inboxes = useMapGetter('inboxes/getInboxes');
const whatsappInboxes = computed(() =>
  (inboxes.value || []).filter(i => i.channel_type === 'Channel::Whatsapp')
);

// ── 1 + 2: configuração ──
const cfg = ref(null);
const saving = ref(false);

const load = async () => {
  try {
    const { data } = await CrmAPI.getFollowupSmart();
    cfg.value = data;
  } catch {
    useAlert('Não consegui carregar o follow-up inteligente');
  }
};

const save = async (patch, message) => {
  if (!props.canEdit || saving.value) return;
  saving.value = true;
  try {
    const { data } = await CrmAPI.updateFollowupSmart(patch);
    cfg.value = data;
    if (message) useAlert(message);
  } catch {
    useAlert('Erro ao salvar o follow-up inteligente');
  } finally {
    saving.value = false;
  }
};

const RULES = [
  {
    key: 'leitura',
    icon: 'i-lucide-scan-eye',
    color: '#0F5FA6',
    title: 'Ler a conversa antes de cutucar',
    sub: 'Antes da 1ª cutucada de cada silêncio a IA lê o fim da conversa. Só cutuca quem ficou com uma pergunta ou proposta sem resposta. Despedida, "obrigado", consulta marcada = não cutuca. "Ainda não / vou pensar" = adiou. "Não tenho interesse" = recusou (etiqueta perda_sem_interesse).',
  },
  {
    key: 'lead_frio',
    icon: 'i-lucide-snowflake',
    color: '#0891B2',
    title: 'Lead frio: só 1 cutucada',
    sub: 'Quem nunca escreveu nada (nem nesta conversa, nem em outra) recebe no máximo a 1ª etapa da cadência, e só se ela cair nas primeiras 24h.',
  },
  {
    key: 'fim_de_semana',
    icon: 'i-lucide-calendar-off',
    color: '#7C3AED',
    title: 'Fim de semana só para quem escreveu no dia',
    sub: 'Sábado e domingo a cutucada só sai se o paciente escreveu naquele mesmo dia. Senão, espera a segunda na abertura do horário de envio.',
  },
];

const toggleRule = rule =>
  save(
    { [rule.key]: !cfg.value[rule.key] },
    `${rule.title}: ${cfg.value[rule.key] ? 'desligado' : 'ligado'}`
  );

const react = computed(() => cfg.value?.reativacao || {});
const DAY_OPTIONS = [3, 5, 7, 10, 15, 30];
const modelFor = inboxId => react.value.modelos?.[String(inboxId)] || null;

const saveReactivation = (patch, message) =>
  save({ reativacao: { ...patch } }, message);

// escolher o modelo de UMA caixa (mesmo picker do robô)
const pickerInboxId = ref(null);
const pickerTemplate = ref(null);
const openPicker = inboxId => {
  pickerInboxId.value = inboxId;
  pickerTemplate.value = null;
};
const closePicker = () => {
  pickerInboxId.value = null;
  pickerTemplate.value = null;
};
const useTemplate = payload => {
  const modelos = {
    ...(react.value.modelos || {}),
    [String(pickerInboxId.value)]: {
      message: payload.message,
      template_params: payload.templateParams,
    },
  };
  const name = payload.templateParams?.name;
  closePicker();
  saveReactivation({ modelos }, `Modelo da reativação: ${name}`);
};
const removeModel = inboxId => {
  const modelos = { ...(react.value.modelos || {}) };
  delete modelos[String(inboxId)];
  saveReactivation({ modelos }, 'Modelo removido — essa caixa não reativa');
};
const pickerInboxName = computed(
  () => whatsappInboxes.value.find(i => i.id === pickerInboxId.value)?.name
);

// ── 3: resultado por coluna ──
const period = ref({ preset: 'month', from: '', to: '' });
const results = ref(null);
const loadingResults = ref(false);
const view = ref('lista');

const loadResults = async () => {
  loadingResults.value = true;
  try {
    const { data } = await CrmAPI.getFollowupResults(
      periodParams(period.value)
    );
    results.value = data;
  } catch {
    results.value = null;
  } finally {
    loadingResults.value = false;
  }
};
watch(period, loadResults, { deep: true });

const pct = (part, whole) =>
  whole ? `${Math.round((100 * part) / whole)}%` : '—';
const total = computed(() => results.value?.total || null);
const rows = computed(() => results.value?.rows || []);

onMounted(() => {
  load();
  loadResults();
});
</script>

<template>
  <div class="mb-4 space-y-4">
    <!-- ══ BLOCO 1: como o robô decide ══ -->
    <div class="cv-ag-block p-5 sm:p-6">
      <div class="flex items-center gap-2 flex-wrap">
        <span class="i-lucide-brain text-lg" style="color: #2563eb" />
        <p class="cv-ag-block-title !mb-0">Follow-up inteligente</p>
        <Spinner v-if="saving" :size="14" class="text-n-brand" />
      </div>
      <span class="cv-ag-block-sub block mt-1">
        Vale para todos os robôs. O robô só cutuca quem ainda tem a conversa
        aberta — quem encerrou, adiou ou recusou não recebe mensagem (evita
        denúncia de spam).
      </span>

      <div v-if="!cfg" class="py-6 flex justify-center">
        <Spinner :size="20" class="text-n-brand" />
      </div>
      <div v-else class="mt-4 space-y-3">
        <div
          v-for="rule in RULES"
          :key="rule.key"
          class="flex items-start gap-3 p-3 rounded-xl border border-n-weak"
        >
          <span
            class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
            :style="{ background: `${rule.color}1f` }"
          >
            <span
              :class="rule.icon"
              class="text-base"
              :style="{ color: rule.color }"
            />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-n-slate-12">
              {{ rule.title }}
            </p>
            <p class="text-[11px] text-n-slate-10 leading-relaxed mt-0.5">
              {{ rule.sub }}
            </p>
          </div>
          <button
            class="cv-switch flex-shrink-0 mt-1"
            :class="cfg[rule.key] ? 'cv-switch-on' : ''"
            :disabled="!canEdit || saving"
            :aria-label="rule.title"
            @click="toggleRule(rule)"
          />
        </div>
        <p class="text-[11px] text-n-slate-10 leading-relaxed">
          💡 Os Atendentes de IA (WhatsApp e Instagram) também avisam quando se
          despedem — depois do "é só me chamar aqui", nenhum robô cutuca. O
          gasto da leitura aparece em Agentes de IA como
          <b>Leitor do follow-up</b>.
        </p>
      </div>
    </div>

    <!-- ══ BLOCO 2: quem adiou ══ -->
    <div v-if="cfg" class="cv-ag-block p-5 sm:p-6">
      <div class="flex items-center gap-2 flex-wrap">
        <span class="i-lucide-calendar-clock text-lg" style="color: #d97706" />
        <p class="cv-ag-block-title !mb-0 flex-1">Quem adiou volta depois</p>
        <button
          class="cv-switch cv-switch-lg"
          :class="react.ativa ? 'cv-switch-on' : ''"
          :disabled="!canEdit || saving"
          aria-label="Reativar quem adiou"
          @click="
            saveReactivation(
              { ativa: !react.ativa },
              react.ativa ? 'Reativação desligada' : 'Reativação ligada'
            )
          "
        />
      </div>
      <span class="cv-ag-block-sub block mt-1">
        Paciente que disse "ainda não", "vou pensar", "depois eu vejo" não
        recebe cutucada agora: recebe <b>UMA</b> mensagem modelo dias depois,
        pela caixa em que conversou — só em dia útil, no horário de envio, se
        não voltou a escrever e não tem consulta marcada.
      </span>

      <div class="mt-4 flex items-center gap-2 flex-wrap">
        <span class="cv-ag-row-label !pt-0 !w-auto">Depois de</span>
        <button
          v-for="d in DAY_OPTIONS"
          :key="`rd-${d}`"
          class="text-xs px-3 py-1 rounded-full border transition-colors"
          :class="
            Number(react.dias) === d
              ? 'border-n-brand text-n-brand font-semibold'
              : 'border-n-weak text-n-slate-10 hover:text-n-brand'
          "
          :disabled="!canEdit || saving"
          @click="saveReactivation({ dias: d }, `Reativação em ${d} dias`)"
        >
          {{ d }} dias
        </button>
      </div>

      <!-- escolher modelo de uma caixa -->
      <div
        v-if="pickerInboxId !== null"
        class="mt-4 p-4 rounded-xl border border-n-weak space-y-3"
      >
        <div class="flex items-center justify-between">
          <p class="text-sm font-semibold text-n-slate-12">
            {{
              pickerTemplate
                ? 'Preencher variáveis do modelo'
                : `Mensagem modelo — ${pickerInboxName}`
            }}
          </p>
          <button
            class="text-xs text-n-slate-10 hover:text-n-slate-12 flex items-center gap-1"
            @click="closePicker"
          >
            <span class="i-lucide-arrow-left text-sm" /> Voltar
          </button>
        </div>
        <p class="text-[11px] text-n-slate-10">
          Use [nome] nas variáveis para o primeiro nome do paciente.
        </p>
        <WhatsAppTemplateParser
          v-if="pickerTemplate"
          :template="pickerTemplate"
          @send-message="useTemplate"
          @reset-template="pickerTemplate = null"
        >
          <template #actions="{ sendMessage, resetTemplate, disabled }">
            <footer class="flex gap-2 justify-end">
              <button class="cv-btn cv-btn-sm" @click="resetTemplate">
                Trocar modelo
              </button>
              <button
                class="cv-btn cv-btn-sm cv-blue"
                :disabled="disabled"
                @click="sendMessage"
              >
                Usar este modelo
              </button>
            </footer>
          </template>
        </WhatsAppTemplateParser>
        <TemplatesPicker
          v-else
          :inbox-id="pickerInboxId"
          @on-select="pickerTemplate = $event"
        />
      </div>

      <div v-else class="mt-4 space-y-2">
        <div
          v-for="inbox in whatsappInboxes"
          :key="`ri-${inbox.id}`"
          class="flex items-center gap-3 p-3 rounded-xl border border-n-weak flex-wrap"
        >
          <span
            class="i-lucide-message-circle text-base"
            style="color: #059669"
          />
          <div class="flex-1 min-w-[180px]">
            <p class="text-sm font-semibold text-n-slate-12">
              {{ inbox.name }}
            </p>
            <p v-if="modelFor(inbox.id)" class="text-[11px] text-n-slate-11">
              📋 {{ modelFor(inbox.id).template_params?.name }} —
              <span class="text-n-slate-10">{{
                modelFor(inbox.id).message
              }}</span>
            </p>
            <p v-else class="text-[11px] text-amber-600">
              Sem modelo — quem adiou nesta caixa não recebe a reativação
            </p>
          </div>
          <template v-if="canEdit">
            <button class="cv-btn cv-btn-sm" @click="openPicker(inbox.id)">
              {{ modelFor(inbox.id) ? 'Trocar modelo' : 'Escolher modelo' }}
            </button>
            <button
              v-if="modelFor(inbox.id)"
              class="text-xs text-n-slate-10 hover:text-red-600"
              @click="removeModel(inbox.id)"
            >
              Remover
            </button>
          </template>
        </div>
        <p v-if="!whatsappInboxes.length" class="text-[11px] text-n-slate-9">
          Nenhuma caixa de WhatsApp na conta.
        </p>
        <p class="text-[11px] text-n-slate-10 leading-relaxed">
          Instagram não tem mensagem modelo: quem adiou por lá só volta se
          escrever de novo. Pacientes de parceiros (Oftalmofácil) ficam fora.
        </p>
      </div>
    </div>

    <!-- ══ BLOCO 3: resultado ══ -->
    <div class="cv-ag-block p-5 sm:p-6">
      <div class="flex items-center gap-2 flex-wrap">
        <span class="i-lucide-chart-column text-lg" style="color: #059669" />
        <p class="cv-ag-block-title !mb-0 flex-1">Resultado do follow-up</p>
        <div
          class="flex rounded-lg border border-n-weak overflow-hidden text-xs"
        >
          <button
            v-for="v in ['lista', 'cards']"
            :key="`fv-${v}`"
            class="px-3 py-1"
            :class="
              view === v
                ? 'bg-n-brand text-white font-semibold'
                : 'text-n-slate-10'
            "
            @click="view = v"
          >
            {{ v === 'lista' ? 'Lista' : 'Cards' }}
          </button>
        </div>
      </div>
      <span class="cv-ag-block-sub block mt-1">
        Por coluna do CRM (a do card na hora da cutucada). Respondeu = o
        paciente escreveu até 48h depois de uma cutucada.
      </span>
      <div class="mt-3">
        <PeriodRuler v-model="period" />
      </div>

      <div v-if="loadingResults" class="py-6 flex justify-center">
        <Spinner :size="20" class="text-n-brand" />
      </div>
      <template v-else-if="total">
        <!-- a ponte entre os números (de onde vem, pra onde vai) -->
        <p class="mt-4 text-sm text-n-slate-12 leading-relaxed">
          <b>{{ total.cutucados }}</b> conversas receberam
          <b>{{ total.cutucadas }}</b> cutucadas →
          <b class="text-emerald-600">{{ total.responderam }}</b> responderam
          ({{ pct(total.responderam, total.cutucados) }}),
          <b class="text-red-600">{{ total.pararam }}</b> pediram para parar ou
          recusaram e <b>{{ total.nao_entregues }}</b> cutucadas não foram
          entregues. A leitura
          <b>segurou {{ total.seguradas_total }}</b> conversas ({{
            total.seguradas.encerrada
          }}
          encerradas, {{ total.seguradas.adiada }} adiadas,
          {{ total.seguradas.recusou }} recusas) e liberou
          {{ total.abertas }} que estavam abertas.
          <template v-if="total.reativacoes">
            Reativações: <b>{{ total.reativacoes }}</b> enviadas,
            {{ total.reativacoes_responderam }} responderam.
          </template>
        </p>

        <p v-if="!rows.length" class="mt-4 text-sm text-n-slate-10">
          Nada no período.
        </p>

        <div v-else-if="view === 'lista'" class="mt-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr
                class="text-[10px] uppercase tracking-wider text-n-slate-10 text-left"
              >
                <th class="py-2 pr-3 font-semibold">Coluna</th>
                <th class="py-2 px-2 font-semibold text-right">Cutucados</th>
                <th class="py-2 px-2 font-semibold text-right">Responderam</th>
                <th class="py-2 px-2 font-semibold text-right">Pararam</th>
                <th class="py-2 px-2 font-semibold text-right">
                  Não entregues
                </th>
                <th class="py-2 px-2 font-semibold text-right">Seguradas</th>
                <th class="py-2 pl-2 font-semibold text-right">Reativações</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="r in rows"
                :key="`fr-${r.stage_id}`"
                class="border-t border-n-weak"
              >
                <td class="py-2 pr-3">
                  <span class="flex items-center gap-2">
                    <span
                      class="w-2 h-2 rounded-full flex-shrink-0"
                      :style="{ background: r.stage_color }"
                    />
                    <span class="text-n-slate-12">{{ r.stage_name }}</span>
                    <span
                      v-if="r.pipeline_name"
                      class="text-[10px] text-n-slate-9"
                      >{{ r.pipeline_name }}</span
                    >
                  </span>
                </td>
                <td class="py-2 px-2 text-right whitespace-nowrap">
                  {{ r.cutucados }}
                  <span class="text-[10px] text-n-slate-9"
                    >({{ r.cutucadas }} msg)</span
                  >
                </td>
                <td class="py-2 px-2 text-right whitespace-nowrap">
                  {{ r.responderam }}
                  <span class="text-[10px] text-emerald-600">{{
                    pct(r.responderam, r.cutucados)
                  }}</span>
                </td>
                <td class="py-2 px-2 text-right text-red-600">
                  {{ r.pararam }}
                </td>
                <td class="py-2 px-2 text-right">{{ r.nao_entregues }}</td>
                <td
                  class="py-2 px-2 text-right whitespace-nowrap"
                  :title="`${r.seguradas.encerrada} encerradas · ${r.seguradas.adiada} adiadas · ${r.seguradas.recusou} recusas`"
                >
                  {{ r.seguradas_total }}
                </td>
                <td class="py-2 pl-2 text-right whitespace-nowrap">
                  {{ r.reativacoes }}
                  <span
                    v-if="r.reativacoes"
                    class="text-[10px] text-emerald-600"
                    >{{ r.reativacoes_responderam }} resp.</span
                  >
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-else
          class="mt-4 grid gap-3"
          style="grid-template-columns: repeat(auto-fit, minmax(220px, 1fr))"
        >
          <div
            v-for="r in rows"
            :key="`fc-${r.stage_id}`"
            class="p-4 rounded-xl border border-n-weak"
            :style="{ borderTop: `3px solid ${r.stage_color}` }"
          >
            <p class="text-sm font-semibold text-n-slate-12">
              {{ r.stage_name }}
            </p>
            <p v-if="r.pipeline_name" class="text-[10px] text-n-slate-9">
              {{ r.pipeline_name }}
            </p>
            <p class="mt-2 text-2xl font-bold text-n-slate-12">
              {{ pct(r.responderam, r.cutucados) }}
              <span class="text-xs font-medium text-n-slate-10"
                >responderam</span
              >
            </p>
            <p class="text-[11px] text-n-slate-11 leading-relaxed mt-1">
              {{ r.cutucados }} cutucados ({{ r.cutucadas }} msg) ·
              {{ r.responderam }} responderam · {{ r.pararam }} pararam ·
              {{ r.nao_entregues }} não entregues
            </p>
            <p class="text-[11px] text-n-slate-10 mt-1">
              Leitura segurou {{ r.seguradas_total }}:
              {{ r.seguradas.encerrada }} encerradas,
              {{ r.seguradas.adiada }} adiadas,
              {{ r.seguradas.recusou }} recusas
            </p>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
