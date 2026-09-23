<script setup>
// 🍎 CEVICO — NOVA CONVERSA em 3 passos (item 199, 22/09).
// Pedido dele: "iniciar uma conversa com um contato que temos no nosso banco
// de dados, através de uma nova caixa de entrada — precisa ser fácil".
// 1) QUEM: busca no cadastro inteiro (nome, telefone do jeito que digita,
//    e-mail) ou cadastra na hora. 2) POR ONDE: todas as caixas em cartões,
//    marcando "já conversou por aqui" × "caixa nova para esta pessoa" e o
//    motivo quando uma não serve. 3) MENSAGEM: no WhatsApp o modelo aprovado
//    (regra da Meta) com as variáveis; nos outros canais, texto livre.
// Montado UMA vez no Dashboard; abre por openNovaConversa() de qualquer lugar.
import {
  ref,
  computed,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import camelcaseKeys from 'camelcase-keys';
import ContactAPI from 'dashboard/api/contacts';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { inboxColorFor } from 'dashboard/helper/cevicoInboxColors';
import { hexToRgb } from 'dashboard/helper/cevicoPalettes';
import {
  NOVA_CONVERSA_EVENT,
  channelLabel,
  channelIcon,
  notContactableReason,
  normalizePhone,
  timeAgoPt,
} from 'dashboard/helper/cevicoNovaConversa';
import {
  createContactSearcher,
  fetchContactableInboxes,
  mergeInboxDetails,
  prepareNewMessagePayload,
  prepareWhatsAppMessagePayload,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const store = useStore();
const router = useRouter();
const currentUser = useMapGetter('getCurrentUser');
const inboxesList = useMapGetter('inboxes/getInboxes');
const getWaTemplates = useMapGetter('inboxes/getFilteredWhatsAppTemplates');

// ── estado geral ──
const open = ref(false);
const step = ref(1); // 1 quem · 2 por onde · 3 mensagem
const presetInboxId = ref(null);
const lockedContact = ref(false); // veio da ficha do contato: não troca a pessoa

// ── passo 1: quem ──
const searchContacts = createContactSearcher();
const searchEl = ref(null);
const query = ref('');
const results = ref([]);
const searching = ref(false);
const searched = ref(false);
const selectedContact = ref(null);
const showCreate = ref(false);
const creating = ref(false);
const newContact = ref({ name: '', phone: '', email: '' });

// ── passo 2: por onde ──
const loadingInboxes = ref(false);
const contactable = ref([]); // [{ id, sourceId, channelType, medium, messageTemplates… }]
const contactConversations = ref([]);
const targetInbox = ref(null);

// ── passo 3: mensagem ──
const templateQuery = ref('');
const selectedTemplate = ref(null);
const message = ref('');
const subject = ref('');
const sending = ref(false);

let searchTimer = null;

const resetAll = () => {
  step.value = 1;
  query.value = '';
  results.value = [];
  searching.value = false;
  searched.value = false;
  selectedContact.value = null;
  showCreate.value = false;
  creating.value = false;
  newContact.value = { name: '', phone: '', email: '' };
  loadingInboxes.value = false;
  contactable.value = [];
  contactConversations.value = [];
  targetInbox.value = null;
  templateQuery.value = '';
  selectedTemplate.value = null;
  message.value = '';
  subject.value = '';
  sending.value = false;
  presetInboxId.value = null;
  lockedContact.value = false;
};

const close = () => {
  open.value = false;
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, false);
  resetAll();
};

// ───────────────────────── passo 1 ─────────────────────────
const runSearch = async () => {
  const q = query.value.trim();
  if (q.length < 2) {
    results.value = [];
    searched.value = false;
    return;
  }
  searching.value = true;
  try {
    // reachableOnly=false: mostra todo mundo; o passo 2 explica o que falta
    const list = await searchContacts(q, { reachableOnly: false });
    if (list === null) return; // busca mais nova em andamento
    results.value = list;
    searched.value = true;
  } catch {
    useAlert('Não consegui buscar no cadastro. Tente de novo.');
  } finally {
    searching.value = false;
  }
};
watch(query, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(runSearch, 320);
});

const contactLine = c =>
  [c.phoneNumber, c.email].filter(Boolean).join(' · ') ||
  'sem telefone nem e-mail no cadastro';

const loadContactChannels = async contact => {
  loadingInboxes.value = true;
  contactable.value = [];
  contactConversations.value = [];
  try {
    const [inboxes, convs] = await Promise.all([
      fetchContactableInboxes(contact.id),
      ContactAPI.getConversations(contact.id)
        .then(r => r.data?.payload || [])
        .catch(() => []),
    ]);
    contactable.value = mergeInboxDetails(inboxes, inboxesList.value);
    contactConversations.value = convs;
  } catch {
    useAlert('Não consegui ver as caixas desta pessoa. Tente de novo.');
  } finally {
    loadingInboxes.value = false;
  }
};

const pickContact = async contact => {
  selectedContact.value = contact;
  step.value = 2;
  await loadContactChannels(contact);
  // veio de uma caixa aberta em Conversas: já deixa escolhida
  if (presetInboxId.value) {
    const pre = contactable.value.find(i => i.id === presetInboxId.value);
    if (pre) targetInbox.value = pre;
  }
};

const changeContact = () => {
  if (lockedContact.value) return;
  selectedContact.value = null;
  targetInbox.value = null;
  contactable.value = [];
  step.value = 1;
  nextTick(() => searchEl.value?.focus());
};

const openCreate = () => {
  showCreate.value = true;
  const q = query.value.trim();
  const looksPhone = /^[+\d\s()-]{6,}$/.test(q);
  const looksEmail = /@/.test(q);
  newContact.value = {
    name: !looksPhone && !looksEmail ? q : '',
    phone: looksPhone ? q : '',
    email: looksEmail ? q : '',
  };
};

const canCreate = computed(() => {
  const n = newContact.value.name.trim();
  const p = normalizePhone(newContact.value.phone);
  const e = newContact.value.email.trim();
  return n.length >= 2 && (p.length >= 10 || e.includes('@'));
});

const createContact = async () => {
  if (!canCreate.value || creating.value) return;
  creating.value = true;
  try {
    const payload = { name: newContact.value.name.trim() };
    const phone = normalizePhone(newContact.value.phone);
    const email = newContact.value.email.trim();
    if (phone) payload.phone_number = phone;
    if (email) payload.email = email;
    const { data } = await ContactAPI.create(payload);
    const created = camelcaseKeys(
      data?.payload?.contact || data?.payload || {},
      {
        deep: true,
      }
    );
    showCreate.value = false;
    await pickContact(created);
  } catch (e) {
    const msg =
      e?.response?.data?.message ||
      e?.response?.data?.error ||
      'Não consegui cadastrar. Confira o telefone (com DDD) ou o e-mail.';
    useAlert(String(msg));
  } finally {
    creating.value = false;
  }
};

// ───────────────────────── passo 2 ─────────────────────────
const isWhatsappInbox = ib =>
  ib?.channelType === INBOX_TYPES.WHATSAPP ||
  (ib?.channelType === INBOX_TYPES.TWILIO && ib?.medium === 'whatsapp');

const inboxVars = id => {
  const { grad, solid } = inboxColorFor(inboxesList.value, id);
  return {
    '--cv': solid,
    '--cv-rgb': hexToRgb(solid),
    '--cv-deep': solid,
    '--cv-deep-rgb': hexToRgb(solid),
    '--cv-grad': grad,
    '--cv-grad-2': grad,
    '--cv-grad-3': grad,
  };
};

// TODAS as caixas da clínica, na ordem do menu; cada uma diz se serve
const inboxCards = computed(() => {
  const all = [...(inboxesList.value || [])].sort((a, b) =>
    String(a.name).localeCompare(String(b.name))
  );
  const contact = selectedContact.value || {};
  return all.map(raw => {
    const ok = contactable.value.find(c => c.id === raw.id) || null;
    const channelType = raw.channel_type;
    const medium = raw.medium;
    const convs = contactConversations.value.filter(
      c => Number(c.inbox_id) === Number(raw.id)
    );
    const last = convs.reduce(
      (m, c) => Math.max(m, Number(c.last_activity_at || c.timestamp || 0)),
      0
    );
    const openCount = convs.filter(c => c.status === 'open').length;
    // caixa "trancada em uma conversa só" reaproveita a conversa existente;
    // as outras abrem uma conversa nova (ConversationBuilder)
    const singleConversation = !!raw.lock_to_single_conversation;
    return {
      id: raw.id,
      name: raw.name,
      channelType,
      medium,
      singleConversation,
      label: channelLabel(channelType, medium),
      icon: channelIcon(channelType, medium),
      ok,
      reason: ok ? '' : notContactableReason(channelType, contact),
      convCount: convs.length,
      openCount,
      lastLabel: last ? timeAgoPt(last) : '',
      vars: inboxVars(raw.id),
    };
  });
});

const pickInbox = card => {
  if (!card.ok) return;
  targetInbox.value = card.ok;
  selectedTemplate.value = null;
  templateQuery.value = '';
  step.value = 3;
  // modelos do WhatsApp podem ter sido sincronizados agora há pouco
  if (isWhatsappInbox(card.ok)) store.dispatch('inboxes/get');
};

// ───────────────────────── passo 3 ─────────────────────────
const targetIsWhatsapp = computed(
  () => targetInbox.value?.channelType === INBOX_TYPES.WHATSAPP
);
const targetIsEmail = computed(
  () => targetInbox.value?.channelType === INBOX_TYPES.EMAIL
);
const targetCard = computed(
  () => inboxCards.value.find(c => c.id === targetInbox.value?.id) || null
);

const waTemplates = computed(() =>
  targetIsWhatsapp.value ? getWaTemplates.value(targetInbox.value.id) || [] : []
);
const templateBody = t =>
  (t.components || []).find(c => c.type === 'BODY')?.text || '';
const filteredTemplates = computed(() => {
  const q = templateQuery.value.trim().toLowerCase();
  if (!q) return waTemplates.value;
  return waTemplates.value.filter(
    t =>
      t.name.toLowerCase().includes(q) ||
      templateBody(t).toLowerCase().includes(q)
  );
});
const prettyTemplateName = name =>
  String(name || '')
    .replace(/[_-]+/g, ' ')
    .replace(/^\w/, c => c.toUpperCase());

const canSendText = computed(() => {
  if (!targetInbox.value || sending.value) return false;
  if (!message.value.trim()) return false;
  if (targetIsEmail.value && !subject.value.trim()) return false;
  return true;
});

const goToConversation = data => {
  const to = `/app/accounts/${data.account_id}/conversations/${data.id}`;
  close();
  useAlert('Conversa iniciada. Abrindo…');
  router.push(to);
};

const sendText = async () => {
  if (!canSendText.value) return;
  sending.value = true;
  try {
    const payload = prepareNewMessagePayload({
      targetInbox: targetInbox.value,
      selectedContact: selectedContact.value,
      message: message.value.trim(),
      subject: subject.value.trim(),
      ccEmails: '',
      bccEmails: '',
      currentUser: currentUser.value,
      attachedFiles: [],
      directUploadsEnabled: false,
    });
    const data = await store.dispatch('contactConversations/create', {
      params: payload,
      isFromWhatsApp: false,
    });
    goToConversation(data);
  } catch {
    useAlert('Não consegui iniciar a conversa. Tente de novo.');
  } finally {
    sending.value = false;
  }
};

const sendTemplate = async ({ message: body, templateParams }) => {
  if (sending.value) return;
  sending.value = true;
  try {
    const payload = prepareWhatsAppMessagePayload({
      targetInbox: targetInbox.value,
      selectedContact: selectedContact.value,
      message: body,
      templateParams,
      currentUser: currentUser.value,
    });
    const data = await store.dispatch('contactConversations/create', {
      params: payload,
      isFromWhatsApp: true,
    });
    goToConversation(data);
  } catch {
    useAlert('Não consegui enviar o modelo. Tente de novo.');
  } finally {
    sending.value = false;
  }
};

// ───────────────────────── abrir / fechar ─────────────────────────
const openWith = async ({ contactId, inboxId } = {}) => {
  resetAll();
  open.value = true;
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, true);
  presetInboxId.value = inboxId ? Number(inboxId) : null;
  if (!inboxesList.value?.length) store.dispatch('inboxes/get');
  if (contactId) {
    lockedContact.value = true;
    try {
      const { data } = await ContactAPI.show(contactId);
      const contact = camelcaseKeys(data?.payload || {}, { deep: true });
      if (contact?.id) await pickContact(contact);
      else lockedContact.value = false;
    } catch {
      lockedContact.value = false;
    }
  }
  await nextTick();
  if (step.value === 1) searchEl.value?.focus();
};

const onKey = e => {
  if (!open.value) return;
  if (e.key === 'Escape') close();
};

onMounted(() => {
  emitter.on(NOVA_CONVERSA_EVENT, openWith);
  window.addEventListener('keydown', onKey);
});
onBeforeUnmount(() => {
  emitter.off(NOVA_CONVERSA_EVENT, openWith);
  window.removeEventListener('keydown', onKey);
  clearTimeout(searchTimer);
});

const steps = [
  { n: 1, label: 'Quem' },
  { n: 2, label: 'Por onde' },
  { n: 3, label: 'Mensagem' },
];
const goStep = n => {
  if (n >= step.value) return;
  if (n === 1 && lockedContact.value) return;
  if (n === 1) changeContact();
  else step.value = n;
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="cv-page cv-overlay fixed inset-0 z-[70] flex items-end sm:items-center justify-center bg-black/55 p-0 sm:p-6"
      @click.self="close"
    >
      <div
        class="cv-blue cv-modal w-full sm:max-w-3xl max-h-[96vh] sm:max-h-[90vh] flex flex-col !rounded-b-none sm:!rounded-b-[24px]"
      >
        <!-- cabeçalho dourado + trilho dos 3 passos -->
        <div class="cv-modal-head flex flex-col gap-3">
          <div class="flex items-center gap-3">
            <span
              class="cv-glass w-11 h-11 flex items-center justify-center flex-shrink-0"
            >
              <span class="i-lucide-message-square-plus text-xl" />
            </span>
            <div class="min-w-0 flex-1">
              <p
                class="text-lg sm:text-xl font-bold leading-tight"
                style="color: #fff"
              >
                Nova conversa
              </p>
              <p
                class="text-[12px] leading-snug"
                style="color: rgba(255, 255, 255, 0.86)"
              >
                Escolha a pessoa, por onde falar e o que dizer. Em três passos.
              </p>
            </div>
            <button
              class="cv-glass w-9 h-9 flex items-center justify-center flex-shrink-0 hover:bg-white/20 transition-colors"
              title="Fechar (Esc)"
              @click="close"
            >
              <span class="i-lucide-x text-lg" style="color: #fff" />
            </button>
          </div>
          <div class="flex items-center gap-1.5 flex-wrap">
            <button
              v-for="s in steps"
              :key="s.n"
              class="cv-glass-chip transition-opacity"
              :class="[
                s.n === step ? '!bg-white/90 !text-[#1e3a8a] font-bold' : '',
                s.n > step ? 'opacity-60' : 'cursor-pointer',
              ]"
              :disabled="s.n > step"
              @click="goStep(s.n)"
            >
              <span
                class="w-4 h-4 rounded-full inline-flex items-center justify-center text-[10px] font-bold"
                :class="
                  s.n === step ? 'bg-[#2563eb] text-white' : 'bg-white/25'
                "
              >
                <span v-if="s.n < step" class="i-lucide-check text-[10px]" />
                <template v-else>{{ s.n }}</template>
              </span>
              {{ s.label }}
              <template v-if="s.n === 1 && selectedContact && step > 1">
                · {{ selectedContact.name }}
              </template>
              <template v-if="s.n === 2 && targetCard && step > 2">
                · {{ targetCard.name }}
              </template>
            </button>
          </div>
        </div>

        <!-- corpo -->
        <div class="flex-1 min-h-0 overflow-y-auto p-5 sm:p-7 text-n-slate-12">
          <!-- ══ PASSO 1 · QUEM ══ -->
          <div v-if="step === 1" class="flex flex-col gap-5">
            <div>
              <p class="cv-label mb-1.5">1 · Quem</p>
              <h2
                class="text-xl sm:text-2xl font-bold tracking-tight leading-tight"
              >
                Com quem você quer falar?
              </h2>
              <p class="text-sm text-n-slate-11 mt-1">
                Busca no cadastro inteiro da CEVICO. Pode digitar o nome, o
                telefone do jeito que lembra (com ou sem DDD) ou o e-mail.
              </p>
            </div>

            <div class="relative">
              <span
                class="i-lucide-search absolute left-3.5 top-1/2 -translate-y-1/2 text-base text-n-slate-10 pointer-events-none"
              />
              <input
                ref="searchEl"
                v-model="query"
                type="text"
                class="cv-input w-full !h-12 !pl-10 !text-base"
                placeholder="Nome, telefone ou e-mail…"
                autocomplete="off"
              />
              <span
                v-if="searching"
                class="i-lucide-loader-circle animate-spin absolute right-3.5 top-1/2 -translate-y-1/2 text-n-slate-10"
              />
            </div>

            <!-- resultados -->
            <div v-if="results.length" class="flex flex-col gap-2">
              <button
                v-for="c in results"
                :key="c.id"
                class="cv-sub cv-sub-hover flex items-center gap-3 p-3 text-left w-full"
                @click="pickContact(c)"
              >
                <Avatar
                  :src="c.thumbnail || ''"
                  :name="c.name || '?'"
                  :size="40"
                  rounded-full
                />
                <div class="min-w-0 flex-1">
                  <p class="font-semibold leading-tight">
                    {{ c.name || 'Sem nome' }}
                  </p>
                  <p class="text-xs text-n-slate-11 mt-0.5 break-words">
                    {{ contactLine(c) }}
                  </p>
                </div>
                <span class="cv-chip flex-shrink-0">Escolher</span>
              </button>
            </div>

            <!-- ninguém / cadastrar -->
            <div
              v-if="searched && !results.length && !searching && !showCreate"
              class="cv-sub p-5 flex flex-col sm:flex-row sm:items-center gap-3"
            >
              <span class="cv-icon cv-icon-lg">
                <span class="i-lucide-user-round-search text-lg" />
              </span>
              <div class="flex-1 min-w-0">
                <p class="font-semibold">
                  Ninguém no cadastro com "{{ query.trim() }}".
                </p>
                <p class="text-xs text-n-slate-11 mt-0.5">
                  Confira o nome ou cadastre a pessoa agora — leva 10 segundos.
                </p>
              </div>
              <button class="cv-btn" @click="openCreate">
                <span class="i-lucide-user-round-plus text-sm" /> Cadastrar
              </button>
            </div>
            <div
              v-else-if="!searched && !showCreate"
              class="flex items-center justify-between flex-wrap gap-2"
            >
              <p class="text-xs text-n-slate-10">
                Dica: dois caracteres já bastam para começar a busca.
              </p>
              <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="openCreate">
                <span class="i-lucide-user-round-plus text-xs" /> Pessoa nova?
                Cadastrar
              </button>
            </div>

            <!-- cadastro rápido -->
            <div v-if="showCreate" class="cv-sub p-5 flex flex-col gap-4">
              <div class="flex items-center gap-3">
                <span class="cv-icon">
                  <span class="i-lucide-user-round-plus text-base" />
                </span>
                <div>
                  <p class="font-semibold leading-tight">Cadastro rápido</p>
                  <p class="text-xs text-n-slate-11">
                    Nome e pelo menos um jeito de falar: telefone ou e-mail.
                  </p>
                </div>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <label class="flex flex-col gap-1">
                  <span class="cv-label">Nome</span>
                  <input
                    v-model="newContact.name"
                    type="text"
                    class="cv-input"
                    placeholder="Maria da Silva"
                  />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="cv-label">Telefone (WhatsApp)</span>
                  <input
                    v-model="newContact.phone"
                    type="tel"
                    class="cv-input"
                    placeholder="11 99999-9999"
                  />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="cv-label">E-mail</span>
                  <input
                    v-model="newContact.email"
                    type="email"
                    class="cv-input"
                    placeholder="maria@email.com"
                  />
                </label>
              </div>
              <div class="flex items-center gap-2 flex-wrap">
                <button
                  class="cv-btn"
                  :disabled="!canCreate || creating"
                  @click="createContact"
                >
                  <span
                    :class="
                      creating
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-check'
                    "
                    class="text-sm"
                  />
                  Cadastrar e continuar
                </button>
                <button class="cv-btn cv-btn-ghost" @click="showCreate = false">
                  Voltar à busca
                </button>
                <span class="text-[11px] text-n-slate-10">
                  Telefone sem +55 vira +55 sozinho.
                </span>
              </div>
            </div>
          </div>

          <!-- ══ PASSO 2 · POR ONDE ══ -->
          <div v-else-if="step === 2" class="flex flex-col gap-5">
            <div class="flex items-start justify-between gap-3 flex-wrap">
              <div class="min-w-0">
                <p class="cv-label mb-1.5">2 · Por onde</p>
                <h2
                  class="text-xl sm:text-2xl font-bold tracking-tight leading-tight"
                >
                  Por qual caixa você quer falar com
                  {{ selectedContact?.name || 'esta pessoa' }}?
                </h2>
                <p class="text-sm text-n-slate-11 mt-1">
                  Todas as caixas da clínica. Uma caixa nova para a pessoa
                  funciona normalmente — o sistema cria o vínculo na hora.
                </p>
              </div>
              <div
                class="cv-sub flex items-center gap-3 p-2.5 pr-3 flex-shrink-0"
              >
                <Avatar
                  :src="selectedContact?.thumbnail || ''"
                  :name="selectedContact?.name || '?'"
                  :size="34"
                  rounded-full
                />
                <div class="min-w-0">
                  <p class="text-sm font-semibold leading-tight">
                    {{ selectedContact?.name }}
                  </p>
                  <p class="text-[11px] text-n-slate-11 break-words">
                    {{ contactLine(selectedContact || {}) }}
                  </p>
                </div>
                <button
                  v-if="!lockedContact"
                  class="cv-btn cv-btn-ghost cv-btn-sm"
                  title="Escolher outra pessoa"
                  @click="changeContact"
                >
                  Trocar
                </button>
              </div>
            </div>

            <div
              v-if="loadingInboxes"
              class="flex items-center gap-2 text-sm text-n-slate-11 py-6 justify-center"
            >
              <span class="i-lucide-loader-circle animate-spin" /> Vendo por
              onde dá para falar…
            </div>

            <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <button
                v-for="card in inboxCards"
                :key="card.id"
                class="cv-choice p-4"
                :class="[
                  targetInbox?.id === card.id ? 'cv-choice-on' : '',
                  !card.ok
                    ? 'opacity-55 !cursor-not-allowed hover:!translate-y-0'
                    : '',
                ]"
                :style="card.vars"
                :disabled="!card.ok"
                @click="pickInbox(card)"
              >
                <!-- .cv-choice é display:block no kit — o flex fica num filho -->
                <div class="flex items-start gap-3">
                  <span class="cv-icon cv-icon-lg">
                    <span :class="card.icon" class="text-lg" />
                  </span>
                  <div class="min-w-0 flex-1 pr-6">
                    <p class="font-bold leading-tight break-words">
                      {{ card.name }}
                    </p>
                    <p class="text-[11px] text-n-slate-11 mt-0.5">
                      {{ card.label }}
                    </p>
                    <div class="mt-2 flex flex-col gap-1">
                      <template v-if="card.ok">
                        <span
                          v-if="card.convCount"
                          class="cv-chip cv-chip-wrap self-start"
                        >
                          <span class="i-lucide-history text-[10px]" />
                          Já conversou por aqui · {{ card.convCount }}
                          {{ card.convCount === 1 ? 'conversa' : 'conversas'
                          }}<template v-if="card.lastLabel">, última {{ card.lastLabel }}</template>
                        </span>
                        <span v-else class="cv-chip cv-chip-wrap self-start">
                          <span class="i-lucide-sparkles text-[10px]" />
                          Caixa nova para esta pessoa
                        </span>
                        <span
                          v-if="card.openCount"
                          class="text-[11px] text-n-slate-11"
                        >
                          {{
                            card.openCount === 1
                              ? '1 conversa aberta'
                              : `${card.openCount} conversas abertas`
                          }}
                          <template v-if="card.singleConversation">
                            — esta caixa junta tudo numa conversa só: a mensagem
                            entra na existente.</template>
                          <template v-else>
                            — a mensagem abre uma conversa nova (a aberta
                            continua).</template>
                        </span>
                      </template>
                      <span
                        v-else
                        class="text-[11px] text-n-slate-11 leading-snug"
                      >
                        <span class="i-lucide-lock text-[10px]" />
                        {{ card.reason }}
                      </span>
                    </div>
                  </div>
                </div>
                <span v-if="card.ok" class="cv-choice-mark">
                  <span class="i-lucide-check" />
                </span>
              </button>
              <p
                v-if="!inboxCards.length"
                class="text-sm text-n-slate-11 col-span-full py-6 text-center"
              >
                Nenhuma caixa de entrada cadastrada ainda.
              </p>
            </div>
          </div>

          <!-- ══ PASSO 3 · MENSAGEM ══ -->
          <div v-else class="flex flex-col gap-5" :style="targetCard?.vars">
            <div class="flex items-start justify-between gap-3 flex-wrap">
              <div class="min-w-0">
                <p class="cv-label mb-1.5">3 · Mensagem</p>
                <h2
                  class="text-xl sm:text-2xl font-bold tracking-tight leading-tight"
                >
                  O que você quer dizer?
                </h2>
                <p class="text-sm text-n-slate-11 mt-1">
                  Para <b>{{ selectedContact?.name }}</b>, pela caixa <b>{{ targetCard?.name }}</b> ({{
                    targetCard?.label
                  }}).
                </p>
              </div>
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm flex-shrink-0"
                @click="step = 2"
              >
                <span class="i-lucide-arrow-left text-xs" /> Trocar a caixa
              </button>
            </div>

            <!-- WhatsApp: modelo aprovado -->
            <template v-if="targetIsWhatsapp">
              <div class="cv-block cv-strip p-4 flex items-start gap-3">
                <span class="cv-icon"><span class="i-ri-whatsapp-line text-base"/></span>
                <p class="text-sm leading-snug">
                  <b>No WhatsApp, a primeira mensagem precisa ser um modelo
                    aprovado pela Meta.</b>
                  É regra do WhatsApp, não nossa. Depois que a pessoa responder,
                  a conversa fica livre por 24 horas.
                </p>
              </div>

              <div v-if="!selectedTemplate" class="flex flex-col gap-3">
                <div class="relative">
                  <span
                    class="i-lucide-search absolute left-3.5 top-1/2 -translate-y-1/2 text-n-slate-10 pointer-events-none"
                  />
                  <input
                    v-model="templateQuery"
                    type="text"
                    class="cv-input w-full !pl-10"
                    placeholder="Buscar modelo pelo nome ou pelo texto…"
                  />
                </div>
                <div
                  v-if="filteredTemplates.length"
                  class="grid grid-cols-1 gap-3"
                >
                  <button
                    v-for="t in filteredTemplates"
                    :key="t.id || t.name"
                    class="cv-choice p-4 text-left"
                    @click="selectedTemplate = t"
                  >
                    <p class="font-bold leading-tight pr-8">
                      {{ prettyTemplateName(t.name) }}
                    </p>
                    <p class="text-[11px] text-n-slate-10 mt-0.5">
                      {{ t.language }} · {{ t.category }}
                    </p>
                    <p
                      class="text-sm text-n-slate-11 mt-2 whitespace-pre-wrap leading-relaxed"
                    >
                      {{ templateBody(t) }}
                    </p>
                    <span class="cv-choice-mark"><span class="i-lucide-arrow-right"/></span>
                  </button>
                </div>
                <div v-else class="cv-sub p-5 text-sm text-n-slate-11">
                  <template v-if="waTemplates.length">
                    Nenhum modelo com "{{ templateQuery }}".
                  </template>
                  <template v-else>
                    Esta caixa ainda não tem modelos aprovados sincronizados. Vá
                    em
                    <b>Configurações → Caixas de entrada →
                      {{ targetCard?.name }}</b>
                    e sincronize os modelos, ou escolha outra caixa.
                  </template>
                </div>
              </div>

              <div v-else class="cv-sub p-5 flex flex-col gap-3">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="cv-chip">Modelo</span>
                  <p class="font-bold">
                    {{ prettyTemplateName(selectedTemplate.name) }}
                  </p>
                </div>
                <WhatsAppTemplateParser
                  :template="selectedTemplate"
                  @send-message="sendTemplate"
                  @back="selectedTemplate = null"
                >
                  <template #actions="{ sendMessage, goBack, disabled }">
                    <div class="flex items-center gap-2 flex-wrap pt-2">
                      <button
                        class="cv-btn cv-btn-lg"
                        :disabled="disabled || sending"
                        @click="sendMessage"
                      >
                        <span
                          :class="
                            sending
                              ? 'i-lucide-loader-circle animate-spin'
                              : 'i-lucide-send'
                          "
                          class="text-sm"
                        />
                        Enviar e abrir a conversa
                      </button>
                      <button
                        class="cv-btn cv-btn-ghost"
                        :disabled="sending"
                        @click="goBack"
                      >
                        Outro modelo
                      </button>
                    </div>
                  </template>
                </WhatsAppTemplateParser>
              </div>
            </template>

            <!-- outros canais: texto livre -->
            <template v-else>
              <label v-if="targetIsEmail" class="flex flex-col gap-1">
                <span class="cv-label">Assunto</span>
                <input
                  v-model="subject"
                  type="text"
                  class="cv-input"
                  placeholder="Assunto do e-mail"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="cv-label">Mensagem</span>
                <textarea
                  v-model="message"
                  rows="6"
                  class="cv-input w-full"
                  placeholder="Escreva aqui. A conversa abre assim que enviar."
                />
              </label>
              <div class="flex items-center gap-2 flex-wrap">
                <button
                  class="cv-btn cv-btn-lg"
                  :disabled="!canSendText"
                  @click="sendText"
                >
                  <span
                    :class="
                      sending
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-send'
                    "
                    class="text-sm"
                  />
                  Enviar e abrir a conversa
                </button>
                <span class="text-[11px] text-n-slate-10">
                  A conversa fica atribuída a você.
                </span>
              </div>
            </template>
          </div>
        </div>

        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <span class="text-[11px] text-n-slate-10 flex-1 min-w-0">
            <template v-if="step === 1">Passo 1 de 3 · escolha a pessoa</template>
            <template v-else-if="step === 2">Passo 2 de 3 · escolha a caixa</template>
            <template v-else>Passo 3 de 3 · escreva e envie</template>
          </span>
          <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="close">
            Cancelar
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
