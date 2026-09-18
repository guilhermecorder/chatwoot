<script setup>
// 📞 Botão "Ligar" do CEVICO (item 167, rodada 2): fica no cabeçalho da
// conversa e no painel do contato. Usa o NOSSO fluxo (Graph API + WebRTC do
// item 167), não o módulo Enterprise. Ao clicar: consulta a permissão na
// Meta → se pode, liga na hora; senão abre um balãozinho com o estado e o
// botão "Pedir permissão" (mensagem interativa no WhatsApp). Quando o
// paciente responde, o cable `cevico_call.permission` atualiza sozinho.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CevicoCallsAPI from 'dashboard/api/cevicoCalls';
import { useCevicoCallsStore } from 'dashboard/stores/cevicoCalls';
import { shortDateTime } from 'dashboard/helper/cevicoCallsFormat';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
  // caixa da conversa aberta: com várias caixas de ligação, liga por ela
  inboxId: { type: [Number, String], default: null },
  phone: { type: String, default: '' },
  // sm | md — tamanho do NextButton
  size: { type: String, default: 'sm' },
  // faded = fundo suave (painel do contato); ghost = sem fundo (cabeçalho)
  ghost: { type: Boolean, default: true },
  faded: { type: Boolean, default: false },
});

const store = useStore();
const crmSettings = useMapGetter('crm/getSettings');
const calls = useCevicoCallsStore();

const enabled = computed(() => Boolean(crmSettings.value?.calls?.enabled));
const digits = computed(() => String(props.phone || '').replace(/\D/g, ''));
const visible = computed(
  () => enabled.value && Boolean(props.contactId) && digits.value.length >= 8
);

const isChecking = ref(false);
const isRequesting = ref(false);
const open = ref(false);
const permission = ref(null); // { status, expires_at, can_call, can_request, error }
const root = ref(null);

// clique fora fecha o balão
const onDocClick = e => {
  if (open.value && root.value && !root.value.contains(e.target))
    open.value = false;
};
onMounted(() => {
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});
  document.addEventListener('click', onDocClick, true);
});
onBeforeUnmount(() => document.removeEventListener('click', onDocClick, true));
watch(
  () => props.contactId,
  () => {
    permission.value = null;
    open.value = false;
  }
);

// resposta do paciente chegou pelo cable → atualiza o balão
const livePermission = computed(() => calls.permissionFor(props.contactId));
watch(livePermission, p => {
  if (!p) return;
  const granted = p.status === 'accept' || p.status === 'permanent';
  permission.value = {
    ...(permission.value || {}),
    status: granted ? 'temporary' : p.status,
    expires_at: p.expires_at,
    can_call: granted,
    can_request: !granted,
  };
  if (granted) useAlert('O paciente autorizou ligações. Pode ligar!');
});

const label = computed(() => {
  const p = permission.value;
  if (!p) return '';
  if (p.error) return p.error;
  if (p.status === 'requested')
    return 'Pedido enviado — aguardando o paciente responder…';
  if (p.status === 'permanent') return 'Permissão permanente para ligar.';
  if (p.status === 'temporary' || p.status === 'accept')
    return p.expires_at
      ? `Pode ligar até ${shortDateTime(p.expires_at)}.`
      : 'O paciente autorizou ligações.';
  if (p.status === 'reject') return 'O paciente recusou receber ligações.';
  if (p.status === 'no_permission')
    return 'A Meta exige que o paciente autorize antes da primeira ligação.';
  return 'Permissão ainda não consultada.';
});

const tooltip = computed(() => {
  if (calls.active) return 'Você já está em uma chamada';
  return 'Ligar para o paciente pelo WhatsApp';
});

const startCall = async () => {
  const result = await calls.startOutbound(props.contactId, props.inboxId);
  if (result?.permission) {
    permission.value = result.permission;
    open.value = true;
  } else if (result?.id) {
    open.value = false;
  }
};

const onClick = async () => {
  if (isChecking.value || calls.isBusy || calls.active) return;
  isChecking.value = true;
  try {
    const { data } = await CevicoCallsAPI.permissionStatus(
      props.contactId,
      props.inboxId
    );
    permission.value = data;
    if (data?.can_call) await startCall();
    else open.value = true;
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
    await CevicoCallsAPI.requestPermission(props.contactId, props.inboxId);
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
</script>

<template>
  <div v-if="visible" ref="root" class="relative inline-flex">
    <NextButton
      v-tooltip.bottom="tooltip"
      :sm="size === 'sm'"
      :md="size === 'md'"
      :ghost="ghost && !faded"
      :faded="faded"
      slate
      :icon="isChecking ? 'i-lucide-loader-2' : 'i-lucide-phone-outgoing'"
      :is-loading="isChecking"
      :disabled="isChecking || calls.isBusy || Boolean(calls.active)"
      @click="onClick"
    />
    <!-- balão da permissão -->
    <div
      v-if="open && permission"
      class="absolute right-0 top-full mt-1.5 z-40 w-72 rounded-xl border border-n-weak bg-n-solid-1 shadow-lg p-3 text-xs"
    >
      <p class="font-semibold text-n-slate-12 flex items-center gap-1.5 mb-1">
        <span class="i-lucide-phone-outgoing text-n-brand" />
        Ligar pelo WhatsApp
      </p>
      <p
        class="rounded-lg px-2 py-1.5 leading-relaxed"
        :class="
          permission.can_call
            ? 'bg-green-500/10 text-green-700'
            : 'bg-amber-500/10 text-amber-700'
        "
      >
        {{ label }}
      </p>
      <div class="flex items-center justify-end gap-2 mt-2">
        <button
          class="text-n-slate-10 hover:text-n-slate-12"
          @click="open = false"
        >
          Fechar
        </button>
        <button
          v-if="permission.can_request"
          class="font-bold px-2.5 py-1 rounded-full text-white disabled:opacity-50"
          style="background: linear-gradient(135deg, #059669, #34d399)"
          :disabled="isRequesting"
          @click="requestPermission"
        >
          {{ isRequesting ? 'Enviando…' : 'Pedir permissão' }}
        </button>
        <button
          v-else-if="permission.can_call"
          class="font-bold px-2.5 py-1 rounded-full text-white disabled:opacity-50"
          style="background: linear-gradient(135deg, #059669, #34d399)"
          :disabled="calls.isBusy || Boolean(calls.active)"
          @click="startCall"
        >
          Ligar agora
        </button>
      </div>
    </div>
  </div>
</template>
