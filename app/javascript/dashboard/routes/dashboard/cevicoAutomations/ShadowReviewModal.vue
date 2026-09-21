<script setup>
// 🕶️ TELA SOMBRA (rodada 188): o que o Atendente interno TERIA respondido
// (nota interna de atividade) lado a lado com o que o N8N / a equipe respondeu
// de verdade logo depois, na mesma conversa. É aqui que o admin compara,
// dá 👍/👎 e decide o que afinar no Roteiro antes de ligar o agente ao vivo.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CrmAPI from 'dashboard/api/crm';
import GuidanceModal from './GuidanceModal.vue';

const props = defineProps({
  agentKey: { type: String, default: 'atendente_agendamento' },
  agentName: { type: String, default: 'Atendente de Agendamento' },
});
const emit = defineEmits(['close', 'guided']);
const { accountId } = useAccount();

const pal = useCevicoPalette({
  scope: 'report:agentes',
  blocks: [{ id: 'sombra', label: 'Sombra', icon: 'i-lucide-columns-2' }],
});
const { cvVars, blockFamily } = pal;

const isLoading = ref(true);
const items = ref([]);
const summary = ref({});
const filter = ref('all');
const rating = ref('');

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getAiShadow({
      agent: props.agentKey,
      limit: 80,
    });
    items.value = data.items || [];
    summary.value = data.summary || {};
  } catch {
    useAlert('Não consegui carregar a Sombra.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

const FILTERS = [
  { key: 'all', label: 'Todas' },
  { key: 'book', label: '📅 Agendaria' },
  { key: 'human', label: '🙋 Chamaria humano' },
  { key: 'good', label: '👍 Boas' },
  { key: 'bad', label: '👎 Ruins' },
  { key: 'unrated', label: 'Sem avaliação' },
];
const filtered = computed(() =>
  items.value.filter(it => {
    const sh = it.shadow || {};
    if (filter.value === 'book') return sh.agendar;
    if (filter.value === 'human') return sh.chamar_humano;
    if (filter.value === 'good') return sh.rating === 'good';
    if (filter.value === 'bad') return sh.rating === 'bad';
    if (filter.value === 'unrated') return !sh.rating;
    return true;
  })
);

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

const fmtWhen = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const fmtDay = ymd => {
  if (!ymd) return '';
  const [y, m, d] = String(ymd).split('-');
  return d && m ? `${d}/${m}/${y}` : ymd;
};
const conversationUrl = it =>
  `/app/accounts/${accountId.value}/conversations/${it.conversation_id}`;

const rate = async (it, value) => {
  const next = it.shadow?.rating === value ? null : value;
  rating.value = it.id;
  try {
    const { data } = await CrmAPI.rateAiShadow(it.id, next);
    const idx = items.value.findIndex(x => x.id === it.id);
    if (idx >= 0) items.value[idx] = data;
    summary.value = {
      ...summary.value,
      rated_good: items.value.filter(x => x.shadow?.rating === 'good').length,
      rated_bad: items.value.filter(x => x.shadow?.rating === 'bad').length,
    };
  } catch {
    useAlert('Não consegui salvar a avaliação.');
  } finally {
    rating.value = '';
  }
};

// 🔧 rodada 192: ferramentas usadas na leitura (chips "🔧 …")
const TOOL_LABEL = {
  buscar_consulta: 'buscou consulta',
  remarcar_consulta: 'remarcou',
  cancelar_consulta: 'cancelou',
  confirmar_presenca: 'confirmou presença',
};
const toolChip = a =>
  `🔧 ${a.resumo || TOOL_LABEL[a.ferramenta] || a.ferramenta}`;

// ✍️ rodada 191: Orientar a partir de uma leitura da Sombra
const guiding = ref(null);
const guide = it => {
  guiding.value = {
    agent_key: props.agentKey,
    agent_text: (it.shadow?.mensagens || []).join('\n\n'),
    patient_excerpt: it.patient_said || '',
    conversation_id: it.conversation_id || null,
    message_id: it.id || null,
    rule: it.shadow?.rating_note || '',
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
      <div class="cv-modal w-full max-w-6xl max-h-[92vh] flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-icon cv-icon-lg"
            ><span class="i-lucide-columns-2 text-lg"
          /></span>
          <div class="min-w-0 flex-1">
            <p
              class="text-base sm:text-lg font-bold text-n-slate-12 leading-tight"
            >
              🕶️ Sombra · {{ agentName }}
            </p>
            <p class="text-[11px] text-n-slate-9">
              o que o interno <b>teria respondido</b> × o que foi respondido
              <b>de verdade</b> (N8N ou equipe). Nada disto chegou ao paciente.
            </p>
          </div>
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm"
            :disabled="isLoading"
            @click="load"
          >
            <span
              class="i-lucide-refresh-cw text-xs"
              :class="isLoading ? 'animate-spin' : ''"
            />
            Atualizar
          </button>
          <button class="cv-iconbtn" title="Fechar" @click="emit('close')">
            <span class="i-lucide-x text-base" />
          </button>
        </div>

        <div class="flex-1 min-h-0 overflow-y-auto p-4 sm:p-6">
          <SkeletonScreen
            v-if="isLoading && !items.length"
            variant="dashboard"
          />

          <template v-else>
            <!-- resumo -->
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
              <DashKpi
                compact
                glass
                label="Notas de sombra"
                :value="summary.total || 0"
                sub="mensagens lidas pelo interno"
                :grad="blockFamily('sombra')[0]"
              />
              <DashKpi
                compact
                glass
                label="Agendaria"
                :value="`${summary.would_book || 0}`"
                :sub="`${summary.slot_valid || 0} com vaga válida na Agenda`"
                :grad="blockFamily('sombra')[1]"
              />
              <DashKpi
                compact
                glass
                label="Chamaria humano"
                :value="summary.human || 0"
                sub="urgência, caso clínico, falha"
                :grad="blockFamily('sombra')[2]"
              />
              <DashKpi
                compact
                glass
                label="Sua avaliação"
                :value="`👍 ${summary.rated_good || 0} · 👎 ${summary.rated_bad || 0}`"
                sub="clique nas notas para avaliar"
                :grad="blockFamily('sombra')[3]"
              />
            </div>

            <!-- filtros em linha -->
            <div class="flex flex-wrap gap-1.5 mb-4">
              <button
                v-for="f in FILTERS"
                :key="f.key"
                class="cv-seg-item cv-seg-sm"
                :class="filter === f.key ? 'cv-seg-on' : ''"
                @click="filter = f.key"
              >
                {{ f.label }}
              </button>
              <span class="text-[11px] text-n-slate-9 self-center ml-auto">
                {{ filtered.length }} de {{ items.length }}
              </span>
            </div>

            <div v-if="!filtered.length" class="cv-sub p-8 text-center">
              <p class="text-sm font-bold text-n-slate-12 mb-1">
                Nenhuma nota de sombra ainda
              </p>
              <p class="text-xs text-n-slate-9">
                Ligue o agente, marque a caixa de WhatsApp e as colunas dele. A
                cada mensagem de paciente ele anota aqui o que teria respondido.
              </p>
            </div>

            <!-- uma ficha por leitura: paciente | interno | de verdade -->
            <div v-else class="space-y-3">
              <div v-for="it in filtered" :key="it.id" class="cv-sub p-4">
                <div class="flex items-center gap-2 flex-wrap mb-3">
                  <a
                    :href="conversationUrl(it)"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-sm font-bold text-n-slate-12 hover:underline flex items-center gap-1"
                    title="Abrir a conversa"
                  >
                    {{ it.contact }}
                    <span class="text-[10px] font-normal text-n-slate-9">#{{ it.conversation_id }}</span>
                    <span
                      class="i-lucide-external-link text-[10px] text-n-slate-9"
                    />
                  </a>
                  <span class="cv-chip">{{
                    STAGE_LABEL[it.shadow?.etapa] || it.shadow?.etapa || '—'
                  }}</span>
                  <span
                    v-if="it.shadow?.agendar"
                    class="cv-chip"
                    :class="it.shadow?.slot_valid ? 'cv-green' : 'cv-red'"
                  >
                    📅 agendaria ·
                    {{
                      it.shadow?.slot_valid
                        ? 'vaga válida ✓'
                        : 'vaga NÃO validou ✗'
                    }}
                  </span>
                  <span v-if="it.shadow?.cancelar" class="cv-chip cv-red">
                    🗓️ cancelaria a consulta
                  </span>
                  <span v-if="it.shadow?.chamar_humano"
class="cv-chip cv-amber"
                    >🙋 chamaria humano</span>
                  <span v-if="it.shadow?.pausar"
class="cv-chip cv-slate"
                    >⏸ encerraria</span>
                  <span
                    v-for="(a, ai) in it.shadow?.acoes || []"
                    :key="`acao-${it.id}-${ai}`"
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
                  <span class="text-[10px] text-n-slate-9 ml-auto">{{
                    fmtWhen(it.at)
                  }}</span>
                  <div class="flex items-center gap-1">
                    <button
                      class="cv-btn cv-btn-sm cv-btn-ghost cv-amber"
                      title="Escreva como o agente deveria ter respondido — vira uma orientação para aplicar no Roteiro"
                      @click="guide(it)"
                    >
                      ✍️ Orientar
                    </button>
                    <button
                      class="cv-iconbtn"
                      :class="it.shadow?.rating === 'good' ? 'cv-green' : ''"
                      :disabled="rating === it.id"
                      title="Resposta boa"
                      @click="rate(it, 'good')"
                    >
                      👍
                    </button>
                    <button
                      class="cv-iconbtn"
                      :class="it.shadow?.rating === 'bad' ? 'cv-red' : ''"
                      :disabled="rating === it.id"
                      title="Resposta ruim (para afinar o Roteiro)"
                      @click="rate(it, 'bad')"
                    >
                      👎
                    </button>
                  </div>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-12 gap-3">
                  <!-- paciente disse -->
                  <div
                    class="lg:col-span-3 rounded-xl p-3"
                    style="
                      background: rgb(var(--cv-rgb) / 0.06);
                      border: 1px solid rgb(var(--cv-rgb) / 0.16);
                    "
                  >
                    <p
                      class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-9 mb-1.5"
                    >
                      🧑 Paciente disse
                    </p>
                    <p
                      class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed"
                    >
                      {{ it.patient_said || '(sem texto — áudio ou mídia)' }}
                    </p>
                  </div>
                  <!-- interno teria respondido -->
                  <div
                    class="lg:col-span-5 rounded-xl p-3"
                    style="
                      background: rgba(5, 150, 105, 0.07);
                      border: 1px solid rgba(5, 150, 105, 0.35);
                    "
                  >
                    <p
                      class="text-[10px] font-semibold uppercase tracking-wide mb-1.5"
                      style="color: #059669"
                    >
                      🕶️ Interno teria respondido
                    </p>
                    <ol class="space-y-1.5">
                      <li
                        v-for="(m, i) in it.shadow?.mensagens || []"
                        :key="i"
                        class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed rounded-lg px-2.5 py-1.5 bg-n-solid-2"
                      >
                        <span class="text-[10px] font-bold text-n-slate-9 mr-1">{{ i + 1 }})</span>{{ m }}
                      </li>
                    </ol>
                    <p
                      v-if="it.shadow?.agendar"
                      class="text-[11px] text-n-slate-11 mt-2"
                    >
                      📅 Agendaria:
                      <b>{{ fmtDay(it.shadow?.agendamento?.dia) }}
                        {{ it.shadow?.agendamento?.hora }}</b>
                      ·
                      {{
                        UNIT_LABEL[it.shadow?.agendamento?.unidade] ||
                        it.shadow?.agendamento?.unidade
                      }}
                      · {{ it.shadow?.agendamento?.nome }}
                    </p>
                    <p
                      v-if="it.shadow?.leitura"
                      class="text-[11px] text-n-slate-10 mt-2 italic"
                    >
                      💭 {{ it.shadow.leitura }}
                    </p>
                    <p
                      v-if="it.shadow?.rating_note"
                      class="text-[11px] text-amber-600 mt-1"
                    >
                      📝 {{ it.shadow.rating_note }}
                    </p>
                  </div>
                  <!-- respondido de verdade -->
                  <div
                    class="lg:col-span-4 rounded-xl p-3"
                    style="
                      background: rgba(21, 44, 97, 0.06);
                      border: 1px solid rgba(21, 44, 97, 0.28);
                    "
                  >
                    <p
                      class="text-[10px] font-semibold uppercase tracking-wide mb-1.5"
                      style="color: #2563eb"
                    >
                      ✅ Respondido de verdade
                    </p>
                    <template v-if="it.real_replies?.length">
                      <div
                        v-for="(r, i) in it.real_replies"
                        :key="i"
                        class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed rounded-lg px-2.5 py-1.5 mb-1.5 bg-n-solid-2"
                      >
                        {{ r.content }}
                        <span class="block text-[10px] text-n-slate-9 mt-0.5">{{ r.by }} · {{ fmtWhen(r.at) }}</span>
                      </div>
                    </template>
                    <p v-else class="text-[11px] text-n-slate-9 italic">
                      ainda sem resposta real nos 30 min seguintes
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </template>
        </div>

        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <span class="text-[11px] text-n-slate-9 flex-1 min-w-0">
            💡 Marque 👎 no que o interno erraria e ajuste o Roteiro (ou o bloco
            da etapa). A tela mostra as últimas 80 leituras.
          </span>
          <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="emit('close')">
            Fechar
          </button>
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
