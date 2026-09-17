<script setup>
// 📞 Card "Ligações" do paciente (item 167) — reutilizado no painel da
// conversa (variant="panel", bloco compacto) e no Espaço do Paciente
// (variant="space", card da fileira). Busca `crm/calls?contact_id=&limit=5`:
// total, tempo total falado, última chamada, lista curta com player e link
// pra conversa; botão "Ligar" (se o módulo está ligado) consulta a permissão
// na Meta → liga, ou oferece "Pedir permissão" e mostra o estado. Ligações da
// assistente virtual (handled_by 'ai', item 169) mostram "🤖 assistente
// virtual" no lugar do atendente + o resultado e o resumo.
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CevicoCallsAPI from 'dashboard/api/cevicoCalls';
import { useCevicoCallsStore } from 'dashboard/stores/cevicoCalls';
import {
  callIcon,
  formatTalkTime,
  shortDateTime,
  agoLabel,
  STATUS_LABELS,
} from 'dashboard/helper/cevicoCallsFormat';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
  conversationId: { type: [Number, String], default: null },
  variant: { type: String, default: 'panel' }, // panel | space
  accent: { type: String, default: '' },
});

const router = useRouter();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');
const crmSettings = useMapGetter('crm/getSettings');
const calls = useCevicoCallsStore();

const list = ref([]);
const total = ref(0);
const isLoading = ref(false);
const loaded = ref(false);

const enabled = computed(() => Boolean(crmSettings.value?.calls?.enabled));
const isSpace = computed(() => props.variant === 'space');
const totalTalk = computed(() =>
  list.value.reduce((sum, c) => sum + Number(c.duration || 0), 0)
);
const last = computed(() => list.value[0] || null);
// sem módulo ligado e sem histórico, o bloco nem aparece
const visible = computed(() => enabled.value || list.value.length > 0);

const load = async () => {
  if (!props.contactId) return;
  isLoading.value = true;
  try {
    const { data } = await CevicoCallsAPI.list({
      contact_id: props.contactId,
      limit: 5,
    });
    list.value = data?.calls || [];
    total.value = Number(data?.meta?.total ?? list.value.length);
  } catch {
    list.value = [];
    total.value = 0;
  } finally {
    isLoading.value = false;
    loaded.value = true;
  }
};

onMounted(() => {
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});
  load();
});
watch(() => props.contactId, load);
// uma chamada terminou/entrou nesta aba → refaz a lista (com respiro)
let refreshTimer = null;
watch(
  () => calls.version,
  () => {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(load, 1500);
  }
);

// ── permissão para ligar (Meta exige) ──
const permission = ref(null); // { status, expires_at, can_call, can_request }
const isChecking = ref(false);
const isRequesting = ref(false);

const livePermission = computed(() => calls.permissionFor(props.contactId));
watch(livePermission, p => {
  if (!p) return;
  permission.value = {
    ...(permission.value || {}),
    status: p.status === 'accept' ? 'temporary' : p.status,
    expires_at: p.expires_at,
    can_call: p.status === 'accept' || p.status === 'permanent',
    can_request: p.status !== 'accept' && p.status !== 'permanent',
  };
  if (p.status === 'accept' || p.status === 'permanent') {
    useAlert('O paciente autorizou ligações. Pode ligar!');
  }
});

const permissionLabel = computed(() => {
  const p = permission.value;
  if (!p) return '';
  if (p.error) return p.error;
  if (p.status === 'requested')
    return 'Pedido enviado — aguardando o paciente responder…';
  if (p.status === 'permanent') return 'Permissão permanente para ligar';
  if (p.status === 'temporary' || p.status === 'accept') {
    return p.expires_at
      ? `Pode ligar até ${shortDateTime(p.expires_at)}`
      : 'Paciente autorizou ligações';
  }
  if (p.status === 'reject') return 'O paciente recusou receber ligações';
  if (p.status === 'no_permission')
    return 'O paciente ainda não autorizou ligações';
  return 'Permissão ainda não consultada';
});

const startCall = async () => {
  const result = await calls.startOutbound(props.contactId);
  if (result?.permission) {
    permission.value = result.permission;
  }
};

const call = async () => {
  if (isChecking.value || calls.isBusy) return;
  isChecking.value = true;
  try {
    const { data } = await CevicoCallsAPI.permissionStatus(props.contactId);
    permission.value = data;
    if (data?.can_call) await startCall();
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        'Não consegui consultar a permissão na Meta.'
    );
  } finally {
    isChecking.value = false;
  }
};

const requestPermission = async () => {
  if (isRequesting.value) return;
  isRequesting.value = true;
  try {
    await CevicoCallsAPI.requestPermission(props.contactId);
    permission.value = {
      ...(permission.value || {}),
      status: 'requested',
      can_call: false,
      can_request: false,
    };
    useAlert('Pedido de permissão enviado ao paciente pelo WhatsApp.');
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        'Não consegui enviar o pedido de permissão.'
    );
  } finally {
    isRequesting.value = false;
  }
};

// ── lista ──
const playing = ref(null);
const togglePlay = id => {
  playing.value = playing.value === id ? null : id;
};
const openConversation = c => {
  const id = c.conversation_id || props.conversationId;
  if (!id) return;
  router.push(`/app/accounts/${accountId.value}/conversations/${id}`);
};
const rowLabel = c => {
  const dir = c.direction === 'outbound' ? 'Ligação' : 'Recebida';
  const st = STATUS_LABELS[c.status] || c.status;
  // ligação da assistente virtual: não tem atendente, é a IA
  let who = '';
  if (c.handled_by === 'ai') who = ' · 🤖 assistente virtual';
  else if (c.user?.name) who = ` · ${c.user.name.split(' ')[0]}`;
  const talk = Number(c.duration) ? ` · ${formatTalkTime(c.duration)}` : '';
  return `${dir} · ${st}${who}${talk}`;
};
</script>

<template>
  <div
    v-if="visible"
    :class="
      isSpace
        ? 'rounded-xl px-4 py-3 bg-n-solid-1 border border-n-weak'
        : 'border-t border-n-weak pt-2 mt-2'
    "
  >
    <p
      class="font-semibold text-n-slate-10 flex items-center gap-1.5"
      :class="
        isSpace
          ? 'text-[11px] mb-1.5'
          : 'text-[10px] uppercase tracking-wide mb-1'
      "
    >
      <span
        class="i-lucide-phone text-xs"
        :style="accent ? { color: accent } : {}"
      />
      Ligações<template v-if="total"> · {{ total }}</template>
      <button
        v-if="enabled"
        class="ml-auto text-[10px] font-bold px-2 py-0.5 rounded-full text-white flex items-center gap-1 disabled:opacity-50 normal-case tracking-normal"
        style="background: linear-gradient(135deg, #059669, #34d399)"
        :disabled="isChecking || calls.isBusy || Boolean(calls.active)"
        :title="
          calls.active
            ? 'Você já está em uma chamada'
            : 'Ligar para o paciente pelo WhatsApp'
        "
        @click="call"
      >
        <span
          :class="
            isChecking
              ? 'i-lucide-loader-2 animate-spin'
              : 'i-lucide-phone-outgoing'
          "
          class="text-[10px]"
        />
        {{ isChecking ? 'Consultando…' : 'Ligar' }}
      </button>
    </p>

    <!-- estado da permissão (só depois de consultar) -->
    <div
      v-if="permission"
      class="text-[10px] rounded-lg px-2 py-1.5 mb-1.5 flex items-center gap-2 flex-wrap"
      :class="
        permission.can_call
          ? 'bg-green-500/10 text-green-700'
          : 'bg-amber-500/10 text-amber-700'
      "
    >
      <span class="flex-1 min-w-0">{{ permissionLabel }}</span>
      <button
        v-if="permission.can_request"
        class="font-bold underline disabled:opacity-50"
        :disabled="isRequesting"
        @click="requestPermission"
      >
        {{ isRequesting ? 'Enviando…' : 'Pedir permissão' }}
      </button>
    </div>

    <p v-if="isLoading && !loaded" class="text-[11px] text-n-slate-9">
      Carregando ligações…
    </p>
    <p v-else-if="!list.length" class="text-[11px] text-n-slate-9 py-1">
      Nenhuma ligação com este paciente ainda.
    </p>
    <template v-else>
      <p class="text-[11px] text-n-slate-10 mb-1">
        <b class="text-n-slate-12">{{ formatTalkTime(totalTalk) }}</b> falados
        <template v-if="last?.started_at">
          · última {{ agoLabel(last.started_at) }}
        </template>
      </p>
      <div class="space-y-1" :class="isSpace ? 'max-h-32 overflow-y-auto' : ''">
        <div
          v-for="c in list"
          :key="c.id"
          class="rounded-lg bg-n-alpha-1 px-2 py-1"
        >
          <div class="flex items-center gap-1.5 min-w-0">
            <span
              :class="[callIcon(c).icon, callIcon(c).tone]"
              class="text-xs flex-shrink-0"
            />
            <button
              class="text-[11px] text-n-slate-11 truncate text-left flex-1 min-w-0 hover:text-n-brand"
              :title="`${shortDateTime(c.started_at)} · abrir a conversa`"
              @click="openConversation(c)"
            >
              <span class="text-n-slate-9">{{
                shortDateTime(c.started_at)
              }}</span>
              · {{ rowLabel(c) }}
            </button>
            <button
              v-if="c.recording_url"
              class="w-5 h-5 rounded-full flex items-center justify-center text-n-slate-10 hover:text-n-brand flex-shrink-0"
              :title="playing === c.id ? 'Fechar o player' : 'Ouvir a gravação'"
              @click="togglePlay(c.id)"
            >
              <span
                :class="playing === c.id ? 'i-lucide-x' : 'i-lucide-play'"
                class="text-[11px]"
              />
            </button>
          </div>
          <!-- resultado + resumo das ligações da assistente virtual -->
          <p
            v-if="c.handled_by === 'ai' && (c.outcome_label || c.summary)"
            class="text-[10px] text-n-slate-10 mt-0.5 pl-5 flex items-center gap-1.5 min-w-0"
          >
            <span
              v-if="c.outcome_label"
              class="px-1.5 py-0.5 rounded-full bg-purple-500/10 text-purple-700 flex-shrink-0"
            >
              {{ c.outcome_label }}
            </span>
            <span v-if="c.summary" class="truncate" :title="c.summary">
              {{ c.summary }}
            </span>
          </p>
          <audio
            v-if="playing === c.id && c.recording_url"
            controls
            autoplay
            :src="c.recording_url"
            class="w-full h-8 mt-1"
          />
        </div>
      </div>
    </template>
  </div>
</template>
