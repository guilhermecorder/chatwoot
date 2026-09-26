<script setup>
// 📅 item 253 (26/09, pedido dele: "queria no ambiente dos agentes, mais bonito
// e organizado"): o agente CONFIRMAÇÃO DE CONSULTA como card do kit, no grupo
// "Atendimento ao paciente". Não usa IA: lê a NOSSA Agenda e manda mensagem
// modelo da Meta — QUANTOS lembretes quiser (0 a 7 dias antes), cada um com
// hora, sombra × ao vivo, caixa, modelo por unidade (+ geral), modalidades,
// valor padrão e a última rodada (quem recebeu / receberia / foi pulado).
// Grava em agenda_config.appointment_reminders (chaves dN) e o interruptor
// geral em agenda_config.appointment_confirmation — Crm::AppointmentReminderSendJob.
import { computed, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  view: { type: String, default: 'cards' }, // 'cards' | 'list'
  open: { type: Boolean, default: false },
  opening: { type: Boolean, default: false },
  isAdmin: { type: Boolean, default: false },
});
const emit = defineEmits(['toggle']);

const store = useStore();
const settings = useMapGetter('crm/getSettings');
const inboxes = useMapGetter('inboxes/getInboxes');

const META = {
  title: 'Confirmação de consulta',
  tag: 'WhatsApp · mensagem modelo',
  icon: 'i-lucide-calendar-check',
  color: '#B45309',
  gradient: 'linear-gradient(135deg, #B45309, #F59E0B)',
  description:
    'Lê a NOSSA Agenda e manda a confirmação das consultas pelo WhatsApp com a mensagem modelo da Meta — quantos lembretes você quiser: 2 dias antes com endereço e valor, véspera, no dia. "Sim" do paciente confirma a consulta sozinho; "não" vira aviso no Radar do Meu Painel; remarcar e dúvidas ficam com o Atendente Pós-agendamento. Não usa IA (custo zero). Paciente de parceiro do hub nunca recebe.',
};
const cardVars = {
  '--cv': META.color,
  '--cv-rgb': '180 83 9',
  '--cv-deep': META.color,
  '--cv-deep-rgb': '180 83 9',
  '--cv-grad': META.gradient,
  '--cv-grad-2': META.gradient,
  '--cv-grad-3': META.gradient,
};

const UNITS = [
  { key: 'paulista', label: 'Av. Paulista' },
  { key: 'tatuape', label: 'Tatuapé' },
];
const MODALITIES = [
  { key: 'avaliacao', label: 'Avaliação' },
  { key: 'retorno', label: 'Retorno' },
  { key: 'pos_op', label: 'Pós-operatório' },
  { key: 'teleconsulta', label: 'Teleconsulta' },
  { key: 'exames', label: 'Exames' },
];
const PRESETS = [
  {
    days: 2,
    hour: 10,
    label: '2 dias antes',
    hint: 'confirmação completa (endereço, valor, regras)',
  },
  { days: 1, hour: 10, label: 'Véspera', hint: 'pede o "responde SIM"' },
  { days: 0, hour: 7, label: 'No dia', hint: 'lembrete da manhã' },
];
const DAY_OPTIONS = [0, 1, 2, 3, 4, 5, 6, 7];

const daysLabel = d => {
  if (d === 0) return 'No dia da consulta';
  if (d === 1) return 'Véspera (1 dia antes)';
  return `${d} dias antes`;
};
const ruleIcon = d => {
  if (d === 0) return '☀️';
  if (d === 1) return '📨';
  return '📋';
};

// ── estado ────────────────────────────────────────────────────────────────
const master = ref(true);
const rules = ref([]); // [{ uid, days, enabled, hour, mode, inbox_id, default_value, weekend_bridge, modalities, slots }]
const dirty = ref(false);
const saving = ref(false);
const togglingMaster = ref(false);
const openRule = ref({});
const templatesByInbox = ref({});
let uidSeq = 0;

const whatsappInboxes = computed(() =>
  (inboxes.value || []).filter(i => i.channel_type === 'Channel::Whatsapp')
);
const lastRuns = computed(
  () => settings.value?.appointment_reminders_state || {}
);

// slot = de onde sai o modelo: unidade (paulista/tatuape) ou 'geral'
const blankSlot = () => ({ name: '', vars: {}, saved: null, preview: '' });
// caixas marcadas como "dos parceiros" na integração Oftalmofácil (ex.: caixa 12)
const partnerInboxIds = computed(() =>
  (settings.value?.oftalmofacil?.partner_inbox_ids || []).map(Number)
);
const inboxLabel = i =>
  partnerInboxIds.value.includes(i.id) ? `${i.name} (Oftalmofácil)` : i.name;
const slotFrom = saved => ({
  name: saved?.template_params?.name || '',
  vars: { ...(saved?.template_params?.processed_params?.body || {}) },
  saved: saved?.template_params ? { ...saved } : null,
  preview: saved?.message_preview || '',
});
const partnerFrom = c => ({
  enabled: c?.enabled === true,
  inbox_id: c?.inbox_id || null,
  slot: slotFrom(c?.template_params ? c : null),
});

const hydrate = s => {
  const cfg = s?.appointment_reminders || {};
  master.value = s?.appointment_confirmation?.enabled !== false;
  rules.value = Object.keys(cfg)
    .filter(k => /^d[0-7]$/.test(k))
    .map(k => {
      const c = cfg[k] || {};
      const days = Number(k.slice(1));
      uidSeq += 1;
      return {
        uid: uidSeq,
        days,
        enabled: !!c.enabled,
        hour: c.hour ?? (days === 0 ? 7 : 10),
        // lembrete antigo sem modo = ao vivo (é como ele roda hoje)
        mode: c.mode === 'shadow' ? 'shadow' : 'live',
        inbox_id: c.inbox_id || null,
        default_value: c.default_value || '150,00',
        weekend_bridge: c.weekend_bridge === true,
        modalities: [...(c.modalities || [])],
        slots: {
          paulista: slotFrom(c.units?.paulista),
          tatuape: slotFrom(c.units?.tatuape),
          geral: slotFrom(c.template_params ? c : null),
        },
        partner: partnerFrom(c.partner),
      };
    })
    .sort((a, b) => b.days - a.days);
  rules.value.forEach(r => {
    if (r.inbox_id) loadTemplates(r.inbox_id);
    if (r.partner.inbox_id) loadTemplates(r.partner.inbox_id);
  });
  dirty.value = false;
};

const loadTemplates = async inboxId => {
  if (!inboxId || templatesByInbox.value[inboxId]) return;
  templatesByInbox.value = { ...templatesByInbox.value, [inboxId]: [] };
  try {
    const data = await store.dispatch('crm/fetchWhatsappTemplates', inboxId);
    templatesByInbox.value = {
      ...templatesByInbox.value,
      [inboxId]: Array.isArray(data) ? data : [],
    };
  } catch {
    // sem modelos: a lista fica vazia e o card avisa
  }
};

watch(
  settings,
  s => {
    if (!dirty.value) hydrate(s);
  },
  { immediate: true }
);

const touch = () => {
  dirty.value = true;
};

// ── modelos ───────────────────────────────────────────────────────────────
const templatesIn = inboxId => templatesByInbox.value[inboxId] || [];
const templatesOf = rule => templatesIn(rule.inbox_id);
const tplIn = (inboxId, slot) =>
  templatesIn(inboxId).find(t => t.name === slot.name) || null;
const bodyIn = (inboxId, slot) =>
  tplIn(inboxId, slot)?.components?.find(c => c.type === 'BODY')?.text ||
  slot.preview ||
  '';
const bodyOf = (rule, slotKey) => bodyIn(rule.inbox_id, rule.slots[slotKey]);
const tokensIn = (inboxId, slot) => {
  const found = new Set();
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  const body = bodyIn(inboxId, slot);
  let m = re.exec(body);
  while (m !== null) {
    found.add(m[1]);
    m = re.exec(body);
  }
  return [...found];
};
const tokensOf = (rule, slotKey) =>
  tokensIn(rule.inbox_id, rule.slots[slotKey]);
// modelos da D-2 do N8N: já sabemos o que cada variável é — preenche sozinho
const SUGGESTED_VARS = {
  1: '{{nome}}',
  2: '{{data}}',
  3: '{{hora}}',
  4: '{{valor}}',
};
const fillVars = (inboxId, slot) => {
  slot.vars = {};
  tokensIn(inboxId, slot).forEach(t => {
    slot.vars[t] = SUGGESTED_VARS[t] || '';
  });
  touch();
};
const onPickTemplate = (rule, slotKey) =>
  fillVars(rule.inbox_id, rule.slots[slotKey]);
const payloadIn = (inboxId, slot) => {
  const tpl = tplIn(inboxId, slot);
  if (tpl) {
    return {
      template_params: {
        name: tpl.name,
        namespace: tpl.namespace ?? '',
        language: tpl.language,
        category: tpl.category,
        processed_params: { body: { ...slot.vars } },
      },
      message_preview: tpl.components?.find(c => c.type === 'BODY')?.text || '',
    };
  }
  if (slot.name && slot.saved?.template_params?.name === slot.name) {
    // mantém a modelo salva (lista da Meta ainda não carregou ou não mudou)
    return {
      template_params: {
        ...slot.saved.template_params,
        processed_params: { body: { ...slot.vars } },
      },
      message_preview: slot.saved.message_preview || slot.preview,
    };
  }
  return null;
};
const slotPayload = (rule, slotKey) =>
  payloadIn(rule.inbox_id, rule.slots[slotKey]);
const hasTemplate = rule =>
  ['paulista', 'tatuape', 'geral'].some(k => rule.slots[k].name);

// ── lembretes ─────────────────────────────────────────────────────────────
const usedDays = computed(() => rules.value.map(r => r.days));
const freeDays = rule =>
  DAY_OPTIONS.filter(d => d === rule.days || !usedDays.value.includes(d));
const addRule = (days, hour) => {
  if (usedDays.value.includes(days)) {
    useAlert(`Já existe um lembrete de "${daysLabel(days).toLowerCase()}".`);
    return;
  }
  uidSeq += 1;
  const fromOther = rules.value.find(r => r.inbox_id)?.inbox_id || null;
  const rule = {
    uid: uidSeq,
    days,
    enabled: false,
    hour,
    mode: 'shadow',
    inbox_id: fromOther,
    default_value: '150,00',
    weekend_bridge: days >= 1 && days <= 2,
    modalities: ['avaliacao', 'retorno'],
    slots: { paulista: blankSlot(), tatuape: blankSlot(), geral: blankSlot() },
    partner: {
      enabled: false,
      inbox_id: partnerInboxIds.value[0] || null,
      slot: blankSlot(),
    },
  };
  if (rule.partner.inbox_id) loadTemplates(rule.partner.inbox_id);
  rules.value = [...rules.value, rule].sort((a, b) => b.days - a.days);
  openRule.value = { ...openRule.value, [rule.uid]: true };
  touch();
};
const removeRule = rule => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Apagar o lembrete "${daysLabel(rule.days)}"?`)) return;
  rules.value = rules.value.filter(r => r.uid !== rule.uid);
  touch();
};
const toggleModality = (rule, key) => {
  rule.modalities = rule.modalities.includes(key)
    ? rule.modalities.filter(m => m !== key)
    : [...rule.modalities, key];
  touch();
};
const onInbox = rule => {
  ['paulista', 'tatuape', 'geral'].forEach(k => {
    rule.slots[k] = blankSlot();
  });
  loadTemplates(rule.inbox_id);
  touch();
};
// ── pacientes do Oftalmofácil (cerca dos parceiros liberada só por aqui) ──
const togglePartner = rule => {
  rule.partner.enabled = !rule.partner.enabled;
  if (rule.partner.enabled && !rule.partner.inbox_id) {
    rule.partner.inbox_id = partnerInboxIds.value[0] || null;
  }
  if (rule.partner.inbox_id) loadTemplates(rule.partner.inbox_id);
  touch();
};
const onPartnerInbox = rule => {
  rule.partner.slot = blankSlot();
  loadTemplates(rule.partner.inbox_id);
  touch();
};

// ── salvar ────────────────────────────────────────────────────────────────
const buildPayload = () => {
  const out = {};
  rules.value.forEach(rule => {
    const units = {};
    UNITS.forEach(u => {
      const p = slotPayload(rule, u.key);
      if (p) units[u.key] = p;
    });
    const geral = slotPayload(rule, 'geral');
    out[`d${rule.days}`] = {
      enabled: rule.enabled,
      hour: rule.hour,
      inbox_id: rule.inbox_id,
      mode: rule.mode,
      default_value: rule.default_value || '150,00',
      weekend_bridge: rule.weekend_bridge,
      modalities: rule.modalities,
      units,
      partner: {
        enabled: rule.partner.enabled,
        inbox_id: rule.partner.inbox_id,
        ...(payloadIn(rule.partner.inbox_id, rule.partner.slot) || {}),
      },
      ...(geral || {}),
    };
  });
  return out;
};
const problemOf = rule => {
  if (!rule.enabled) return '';
  if (!rule.inbox_id) return 'escolha a caixa do WhatsApp';
  if (!hasTemplate(rule)) return 'escolha pelo menos um modelo';
  if (rule.partner.enabled && !rule.partner.inbox_id)
    return 'escolha a caixa que fala com os pacientes do Oftalmofácil';
  if (rule.partner.enabled && !rule.partner.slot.name)
    return 'escolha o modelo dos pacientes do Oftalmofácil';
  return '';
};
const save = async () => {
  const bad = rules.value.find(r => problemOf(r));
  if (bad) {
    useAlert(`"${daysLabel(bad.days)}": ${problemOf(bad)} antes de ligar.`);
    openRule.value = { ...openRule.value, [bad.uid]: true };
    return;
  }
  saving.value = true;
  try {
    await CrmAPI.saveAppointmentConfirmation({ reminders: buildPayload() });
    dirty.value = false;
    await store.dispatch('crm/fetchSettings');
    useAlert('Confirmação de consulta salva ✓');
  } catch {
    useAlert('Não consegui salvar os lembretes. Tente de novo.');
  } finally {
    saving.value = false;
  }
};
const discard = () => {
  dirty.value = false;
  hydrate(settings.value);
};
const toggleMaster = async () => {
  togglingMaster.value = true;
  const next = !master.value;
  try {
    await CrmAPI.saveAppointmentConfirmation({ enabled: next });
    master.value = next;
    await store.dispatch('crm/fetchSettings');
    useAlert(
      next
        ? '✅ Confirmação de consulta LIGADA.'
        : '⏹ Confirmação de consulta DESLIGADA — nenhum lembrete sai.'
    );
  } catch {
    useAlert('Não consegui mudar o interruptor.');
  } finally {
    togglingMaster.value = false;
  }
};

// ── números do card ───────────────────────────────────────────────────────
const onCount = computed(() => rules.value.filter(r => r.enabled).length);
const liveCount = computed(
  () => rules.value.filter(r => r.enabled && r.mode === 'live').length
);
const statusChip = computed(() => {
  if (!master.value) return { label: 'Desligado', tone: 'cv-slate' };
  if (!onCount.value)
    return { label: 'Nenhum lembrete ligado', tone: 'cv-slate' };
  if (liveCount.value)
    return { label: `${liveCount.value} ao vivo`, tone: 'cv-green' };
  return { label: 'Em sombra', tone: 'cv-slate' };
});
const runOf = rule => lastRuns.value[`d${rule.days}`] || null;
const fmtRunDate = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '';
const fmtDates = list =>
  (list || [])
    .map(d =>
      new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR', {
        weekday: 'short',
        day: '2-digit',
        month: '2-digit',
      })
    )
    .join(' e ');
const ruleSummary = rule => {
  const parts = [
    `${String(rule.hour).padStart(2, '0')}h`,
    rule.mode === 'live' ? 'ao vivo' : 'sombra',
  ];
  const models = ['paulista', 'tatuape', 'geral'].filter(
    k => rule.slots[k].name
  ).length;
  parts.push(models ? `${models} modelo(s)` : 'sem modelo');
  if (rule.partner.enabled) parts.push('+ Oftalmofácil');
  return parts.join(' · ');
};
const isOpen = computed(() => props.open);
const compact = computed(() => props.view === 'cards' && !isOpen.value);
</script>

<template>
  <div
    id="cv-agent-confirmacao"
    class="cv-block flex flex-col"
    :class="[
      view === 'cards' && open ? 'cv-agent-open' : '',
      opening ? 'cv-agent-opening' : '',
    ]"
    :style="cardVars"
  >
    <div
      class="h-1 w-full flex-shrink-0"
      :style="{ background: META.gradient }"
    />
    <div :class="compact ? 'p-4 flex-1 flex flex-col' : 'p-5 sm:p-6'">
      <!-- 🃏 card compacto -->
      <div
        v-if="compact"
        class="flex-1 flex flex-col gap-2.5 cursor-pointer select-none"
        @click="emit('toggle')"
      >
        <div class="flex items-start justify-between gap-2">
          <span class="cv-icon cv-icon-xl"
            ><span :class="META.icon" class="text-lg"
          /></span>
          <div class="flex flex-col items-end gap-1" @click.stop>
            <button
              class="cv-switch cv-switch-lg"
              :class="master ? 'cv-switch-on' : ''"
              :disabled="togglingMaster || !isAdmin"
              :title="
                master
                  ? 'Desligar todos os lembretes agora'
                  : 'Ligar os lembretes'
              "
              :aria-pressed="master"
              @click="toggleMaster"
            />
            <span class="text-[10px] text-n-slate-9">{{
              togglingMaster ? 'salvando…' : master ? 'Ligado' : 'Desligado'
            }}</span>
          </div>
        </div>
        <div>
          <p class="text-base font-bold text-n-slate-12 leading-tight">
            {{ META.title }}
          </p>
          <div class="flex items-center gap-1.5 flex-wrap mt-1.5">
            <span class="cv-chip">{{ META.tag }}</span>
            <span class="cv-chip" :class="statusChip.tone"
              >● {{ statusChip.label }}</span
            >
          </div>
        </div>
        <p class="text-xs text-n-slate-10 leading-relaxed line-clamp-3">
          {{ META.description }}
        </p>
        <div class="mt-auto flex items-center gap-2 flex-wrap pt-1">
          <span class="cv-chip cv-slate"
            >{{ rules.length }} lembrete(s) · {{ onCount }} ligado(s)</span
          >
          <button class="cv-btn cv-btn-sm ml-auto" @click.stop="emit('toggle')">
            <span class="i-lucide-maximize-2 text-xs" /> Abrir
          </button>
        </div>
      </div>

      <!-- cabeçalho completo (Lista ou card aberto) -->
      <div
        v-else
        class="flex items-start gap-3 cursor-pointer select-none"
        :class="open ? 'mb-4' : ''"
        @click="emit('toggle')"
      >
        <span class="cv-icon cv-icon-xl"
          ><span :class="META.icon" class="text-lg"
        /></span>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <p class="text-base font-bold text-n-slate-12 leading-tight">
              {{ META.title }}
            </p>
            <span class="cv-chip">{{ META.tag }}</span>
            <span class="cv-chip" :class="statusChip.tone"
              >● {{ statusChip.label }}</span
            >
            <span v-if="dirty" class="cv-chip cv-amber"
              >📝 alterações não salvas</span
            >
          </div>
          <p
            class="text-xs text-n-slate-10 mt-1 leading-relaxed"
            :class="open ? '' : 'line-clamp-2'"
          >
            {{ META.description }}
          </p>
        </div>
        <div class="flex flex-col items-end gap-1 flex-shrink-0" @click.stop>
          <button
            class="cv-switch cv-switch-lg"
            :class="master ? 'cv-switch-on' : ''"
            :disabled="togglingMaster || !isAdmin"
            :title="
              master
                ? 'Desligar todos os lembretes agora'
                : 'Ligar os lembretes'
            "
            :aria-pressed="master"
            @click="toggleMaster"
          />
          <span class="text-[10px] text-n-slate-9">{{
            togglingMaster ? 'salvando…' : master ? 'Ligado' : 'Desligado'
          }}</span>
        </div>
        <span
          class="i-lucide-chevron-down text-n-slate-9 text-lg mt-2 flex-shrink-0 transition-transform duration-200"
          :class="open ? 'rotate-180' : ''"
        />
      </div>

      <!-- corpo -->
      <div v-if="open" class="cevico-agent-body space-y-4">
        <!-- situação -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <div class="cv-stat px-3 py-2" :class="master ? 'cv-green' : ''">
            <p class="text-[10px] text-n-slate-10">Situação</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ master ? 'Ligado' : 'Desligado' }}
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Lembretes</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ rules.length }}
              <span class="text-[10px] font-normal text-n-slate-9"
                >· {{ onCount }} ligado(s)</span
              >
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Ao vivo</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ liveCount }}
              <span class="text-[10px] font-normal text-n-slate-9"
                >· o resto em sombra</span
              >
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Custo</p>
            <p class="text-sm font-bold text-n-slate-12">
              sem IA
              <span class="text-[10px] font-normal text-n-slate-9"
                >· só o modelo da Meta</span
              >
            </p>
          </div>
        </div>

        <!-- como funciona -->
        <div
          class="cv-sub p-3.5 text-[11px] text-n-slate-11 leading-relaxed space-y-1.5"
        >
          <p>
            <b>📅 De onde vem:</b> as consultas da <b>nossa Agenda</b> (não
            confirmadas, sem presença marcada, com telefone). Consulta que só
            está no Google Agenda não recebe — ela precisa estar na Agenda do
            sistema.
          </p>
          <p>
            <b>🕶️ Sombra:</b> o lembrete não manda nada; só lista abaixo quem
            receberia. Use por uns dias para comparar com o N8N.
            <b>🟢 Ao vivo:</b> manda de verdade — desligue o fluxo do N8N no
            mesmo dia (nunca os dois juntos).
          </p>
          <p>
            <b>✅ Resposta:</b> "sim", "confirmo" ou 👍 marca a consulta como
            confirmada (e ela não recebe os próximos lembretes); "não" vira
            aviso no Radar do Meu Painel para ligar.
          </p>
        </div>

        <!-- novo lembrete -->
        <div v-if="isAdmin" class="flex items-center gap-2 flex-wrap">
          <span class="cv-label !mb-0">Novo lembrete</span>
          <button
            v-for="p in PRESETS"
            :key="'pre' + p.days"
            class="cv-chip cv-chip-lg"
            :disabled="usedDays.includes(p.days)"
            :class="usedDays.includes(p.days) ? 'opacity-40' : ''"
            :title="p.hint"
            @click="addRule(p.days, p.hour)"
          >
            <span class="i-lucide-plus text-[10px]" /> {{ p.label }}
          </button>
          <select
            class="cv-input !h-8 text-xs"
            style="width: auto; margin-bottom: 0"
            @change="
              e => {
                const d = Number(e.target.value);
                if (e.target.value !== '') addRule(d, d === 0 ? 7 : 10);
                e.target.value = '';
              }
            "
          >
            <option value="">outro: quantos dias antes…</option>
            <option
              v-for="d in DAY_OPTIONS.filter(x => !usedDays.includes(x))"
              :key="'opt' + d"
              :value="d"
            >
              {{ daysLabel(d) }}
            </option>
          </select>
        </div>

        <div
          v-if="!rules.length"
          class="cv-sub p-8 text-center text-sm text-n-slate-10"
        >
          Nenhum lembrete ainda. Comece por <b>2 dias antes</b> (a confirmação
          completa do N8N) e, se quiser, <b>No dia</b>.
        </div>

        <!-- lembretes -->
        <div
          v-for="rule in rules"
          :key="rule.uid"
          class="cv-sub p-4"
          :class="rule.enabled ? '' : 'opacity-90'"
        >
          <div
            class="flex items-center gap-2 flex-wrap cursor-pointer select-none"
            @click="openRule = { ...openRule, [rule.uid]: !openRule[rule.uid] }"
          >
            <button
              class="cv-switch"
              :class="rule.enabled ? 'cv-switch-on' : ''"
              :disabled="!isAdmin"
              :title="
                rule.enabled ? 'Desligar este lembrete' : 'Ligar este lembrete'
              "
              @click.stop="
                rule.enabled = !rule.enabled;
                touch();
              "
            />
            <span class="text-base">{{ ruleIcon(rule.days) }}</span>
            <p class="text-sm font-bold text-n-slate-12">
              {{ daysLabel(rule.days) }}
            </p>
            <span
              class="cv-chip"
              :class="rule.mode === 'live' ? 'cv-green' : 'cv-slate'"
              >{{ rule.mode === 'live' ? '🟢 ao vivo' : '🕶️ sombra' }}</span
            >
            <span class="text-[11px] text-n-slate-10">{{
              ruleSummary(rule)
            }}</span>
            <span v-if="problemOf(rule)" class="cv-chip cv-amber"
              >⚠️ {{ problemOf(rule) }}</span
            >
            <span
              v-if="runOf(rule)"
              class="text-[11px] text-n-slate-10 ml-auto"
            >
              última rodada {{ fmtRunDate(runOf(rule).last_run_at) }}:
              <b>{{ (runOf(rule).sent || []).length }}</b>
              {{ runOf(rule).mode === 'live' ? 'enviada(s)' : 'receberia(m)' }}
            </span>
            <span
              class="i-lucide-chevron-down text-n-slate-9 transition-transform duration-200"
              :class="[
                openRule[rule.uid] ? 'rotate-180' : '',
                runOf(rule) ? '' : 'ml-auto',
              ]"
            />
          </div>

          <div
            v-if="openRule[rule.uid]"
            class="mt-3 space-y-3"
            :class="!isAdmin ? 'pointer-events-none opacity-80' : ''"
          >
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1"
                  >Quando</label
                >
                <select
                  v-model.number="rule.days"
                  class="cv-input w-full text-sm"
                  style="margin-bottom: 0"
                  @change="touch"
                >
                  <option v-for="d in freeDays(rule)" :key="'d' + d" :value="d">
                    {{ daysLabel(d) }}
                  </option>
                </select>
              </div>
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1"
                  >Hora do envio</label
                >
                <select
                  v-model.number="rule.hour"
                  class="cv-input w-full text-sm"
                  style="margin-bottom: 0"
                  @change="touch"
                >
                  <option v-for="h in 24" :key="'h' + h" :value="h - 1">
                    {{ String(h - 1).padStart(2, '0') }}h
                  </option>
                </select>
              </div>
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1"
                  >Modo</label
                >
                <div class="cv-seg cv-seg-sm cv-green">
                  <button
                    class="cv-seg-item"
                    :class="rule.mode !== 'live' ? 'cv-seg-on' : ''"
                    title="Só lista quem receberia. Nada chega ao paciente."
                    @click="
                      rule.mode = 'shadow';
                      touch();
                    "
                  >
                    🕶️ Sombra
                  </button>
                  <button
                    class="cv-seg-item"
                    :class="rule.mode === 'live' ? 'cv-seg-on' : ''"
                    title="Manda de verdade. Desligue o N8N antes."
                    @click="
                      rule.mode = 'live';
                      touch();
                    "
                  >
                    🟢 Ao vivo
                  </button>
                </div>
              </div>
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1"
                  >Valor padrão (R$)</label
                >
                <input
                  v-model="rule.default_value"
                  class="cv-input w-full text-sm"
                  style="margin-bottom: 0"
                  placeholder="150,00"
                  @input="touch"
                />
              </div>
            </div>

            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-xs font-medium text-n-slate-11"
                >Quem recebe</span
              >
              <button
                v-for="m in MODALITIES"
                :key="rule.uid + m.key"
                class="cv-chip"
                :class="rule.modalities.includes(m.key) ? 'cv-chip-on' : ''"
                @click="toggleModality(rule, m.key)"
              >
                {{ m.label }}
              </button>
              <span class="text-[10px] text-n-slate-9">{{
                rule.modalities.length ? '' : '(nenhuma marcada = todas)'
              }}</span>
              <label
                v-if="rule.days >= 1 && rule.days <= 2"
                class="flex items-center gap-1.5 text-[11px] text-n-slate-11 cursor-pointer ml-auto"
                title="Na sexta manda também o da consulta de segunda (o envio normal cairia no fim de semana)"
              >
                <input
                  v-model="rule.weekend_bridge"
                  type="checkbox"
                  style="margin: 0"
                  @change="touch"
                />
                sexta adianta a de segunda
              </label>
            </div>

            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Caixa do WhatsApp que envia</label
              >
              <select
                v-model.number="rule.inbox_id"
                class="cv-input w-full sm:w-80 text-sm"
                style="margin-bottom: 0"
                @change="onInbox(rule)"
              >
                <option :value="null">Escolha a caixa…</option>
                <option
                  v-for="i in whatsappInboxes"
                  :key="rule.uid + 'ib' + i.id"
                  :value="i.id"
                >
                  {{ i.name }}
                </option>
              </select>
            </div>

            <!-- modelos: por unidade + geral -->
            <div
              v-if="rule.inbox_id"
              class="grid grid-cols-1 lg:grid-cols-3 gap-2"
            >
              <div
                v-for="slotKey in ['paulista', 'tatuape', 'geral']"
                :key="rule.uid + slotKey"
                class="cv-stat p-3 space-y-1.5"
              >
                <p class="text-[11px] font-bold text-n-slate-12">
                  {{
                    slotKey === 'geral'
                      ? 'Modelo geral'
                      : `Modelo da ${UNITS.find(u => u.key === slotKey).label}`
                  }}
                  <span class="font-normal text-n-slate-9">{{
                    slotKey === 'geral' ? '(outros locais / reserva)' : ''
                  }}</span>
                </p>
                <select
                  v-model="rule.slots[slotKey].name"
                  class="cv-input w-full !h-8 text-xs"
                  style="margin-bottom: 0"
                  @change="onPickTemplate(rule, slotKey)"
                >
                  <option value="">— nenhum —</option>
                  <option
                    v-if="
                      rule.slots[slotKey].name &&
                      !templatesOf(rule).some(
                        t => t.name === rule.slots[slotKey].name
                      )
                    "
                    :value="rule.slots[slotKey].name"
                  >
                    {{ rule.slots[slotKey].name }} (salva)
                  </option>
                  <option
                    v-for="t in templatesOf(rule)"
                    :key="rule.uid + slotKey + t.name + t.language"
                    :value="t.name"
                  >
                    {{ t.name }} ({{ t.language }})
                  </option>
                </select>
                <template v-if="rule.slots[slotKey].name">
                  <p
                    class="text-[10px] text-n-slate-10 whitespace-pre-wrap max-h-28 overflow-auto bg-n-alpha-1 rounded-lg px-2 py-1.5"
                  >
                    {{ bodyOf(rule, slotKey) || 'prévia indisponível' }}
                  </p>
                  <input
                    v-for="token in tokensOf(rule, slotKey)"
                    :key="rule.uid + slotKey + 'v' + token"
                    v-model="rule.slots[slotKey].vars[token]"
                    class="cv-input w-full !h-7 text-[11px] font-mono"
                    style="margin-bottom: 0"
                    :placeholder="`{{${token}}} — ex.: {{nome}}`"
                    @input="touch"
                  />
                </template>
              </div>
            </div>
            <p v-if="rule.inbox_id" class="text-[10px] text-n-slate-9">
              Variáveis: <code v-pre>{{ nome }}</code> paciente ·
              <code v-pre>{{ data }}</code> dd/mm/aaaa ·
              <code v-pre>{{ hora }}</code> horário ·
              <code v-pre>{{ valor }}</code> "Valor: X" da observação ou o
              padrão · <code v-pre>{{ unidade }}</code> Av. Paulista/Tatuapé ·
              <code v-pre>{{ contact.name }}</code> nome do cadastro. A consulta
              usa o modelo da unidade dela; sem modelo da unidade, o geral.
            </p>

            <!-- pacientes do Oftalmofácil: só a caixa escolhida fala com eles -->
            <div
              class="rounded-xl border p-3 space-y-2"
              :class="
                rule.partner.enabled
                  ? 'border-amber-300 bg-amber-50/60 dark:border-amber-700 dark:bg-amber-900/10'
                  : 'border-n-weak'
              "
            >
              <div class="flex items-center gap-2 flex-wrap">
                <span class="i-lucide-shield-check text-sm text-amber-600" />
                <p class="text-xs font-bold text-n-slate-12">
                  Pacientes do Oftalmofácil
                </p>
                <label
                  class="flex items-center gap-1.5 text-[11px] text-n-slate-11 cursor-pointer ml-auto"
                >
                  <input
                    :checked="rule.partner.enabled"
                    type="checkbox"
                    style="margin: 0"
                    @change="togglePartner(rule)"
                  />
                  enviar para eles também
                </label>
              </div>
              <p class="text-[11px] text-n-slate-10">
                {{
                  rule.partner.enabled
                    ? 'Recebem só pela caixa abaixo, com o modelo dela. Sem IA: a resposta "sim/não" é lida por palavra e o resto fica com a equipe.'
                    : 'Desligado: pacientes dos parceiros do hub são pulados (cerca).'
                }}
              </p>
              <template v-if="rule.partner.enabled">
                <select
                  v-model.number="rule.partner.inbox_id"
                  class="cv-input w-full sm:w-80 text-sm"
                  style="margin-bottom: 0"
                  @change="onPartnerInbox(rule)"
                >
                  <option :value="null">Escolha a caixa…</option>
                  <option
                    v-for="i in whatsappInboxes"
                    :key="rule.uid + 'pib' + i.id"
                    :value="i.id"
                  >
                    {{ inboxLabel(i) }}
                  </option>
                </select>
                <div
                  v-if="rule.partner.inbox_id"
                  class="cv-stat p-3 space-y-1.5 lg:w-1/2"
                >
                  <p class="text-[11px] font-bold text-n-slate-12">
                    Modelo para os pacientes do Oftalmofácil
                  </p>
                  <select
                    v-model="rule.partner.slot.name"
                    class="cv-input w-full !h-8 text-xs"
                    style="margin-bottom: 0"
                    @change="fillVars(rule.partner.inbox_id, rule.partner.slot)"
                  >
                    <option value="">— nenhum —</option>
                    <option
                      v-if="
                        rule.partner.slot.name &&
                        !templatesIn(rule.partner.inbox_id).some(
                          t => t.name === rule.partner.slot.name
                        )
                      "
                      :value="rule.partner.slot.name"
                    >
                      {{ rule.partner.slot.name }} (salva)
                    </option>
                    <option
                      v-for="t in templatesIn(rule.partner.inbox_id)"
                      :key="rule.uid + 'pt' + t.name + t.language"
                      :value="t.name"
                    >
                      {{ t.name }} ({{ t.language }})
                    </option>
                  </select>
                  <template v-if="rule.partner.slot.name">
                    <p
                      class="text-[10px] text-n-slate-10 whitespace-pre-wrap max-h-28 overflow-auto bg-n-alpha-1 rounded-lg px-2 py-1.5"
                    >
                      {{
                        bodyIn(rule.partner.inbox_id, rule.partner.slot) ||
                        'prévia indisponível'
                      }}
                    </p>
                    <input
                      v-for="token in tokensIn(
                        rule.partner.inbox_id,
                        rule.partner.slot
                      )"
                      :key="rule.uid + 'pv' + token"
                      v-model="rule.partner.slot.vars[token]"
                      class="cv-input w-full !h-7 text-[11px] font-mono"
                      style="margin-bottom: 0"
                      :placeholder="`{{${token}}} — ex.: {{nome}}`"
                      @input="touch"
                    />
                  </template>
                </div>
                <p class="text-[10px] text-n-slate-9">
                  Mesmas variáveis de cima, mais
                  <code v-pre>{{ parceiro }}</code> = nome do parceiro do hub.
                  Hora, sombra/ao vivo e "Quem recebe" são os deste lembrete.
                </p>
              </template>
            </div>

            <!-- última rodada -->
            <div
              v-if="runOf(rule)"
              class="rounded-lg bg-n-alpha-1 p-2.5 text-[11px] text-n-slate-11 space-y-0.5"
            >
              <p class="font-semibold">
                Última rodada ({{
                  runOf(rule).mode === 'live' ? 'ao vivo' : 'sombra'
                }}) · {{ fmtRunDate(runOf(rule).last_run_at) }} · consultas de
                {{ fmtDates(runOf(rule).dates) }}:
                <b>{{ (runOf(rule).sent || []).length }}</b>
                {{
                  runOf(rule).mode === 'live' ? 'enviada(s)' : 'receberia(m)'
                }}
                · <b>{{ (runOf(rule).skipped || []).length }}</b> pulada(s)
              </p>
              <p
                v-for="e in (runOf(rule).sent || []).slice(0, 40)"
                :key="rule.uid + 's' + e.task_id"
              >
                ✓ {{ e.when }} · {{ e.name }} · {{ e.unit }} · …{{
                  e.phone_tail
                }}
                <span
                  v-if="e.partner"
                  class="text-amber-700 dark:text-amber-400"
                  >· Oftalmofácil ({{ e.partner }})</span
                >
                <span class="text-n-slate-9">{{
                  e.template ? `(${e.template})` : ''
                }}</span>
              </p>
              <p
                v-for="e in (runOf(rule).skipped || []).slice(0, 40)"
                :key="rule.uid + 'k' + e.task_id"
                class="text-amber-700 dark:text-amber-400"
              >
                ↷ {{ e.when }} · {{ e.name }} · {{ e.unit }} — {{ e.why }}
              </p>
            </div>
            <p v-else class="text-[11px] text-n-slate-9">
              Ainda não rodou: a primeira rodada acontece na hora escolhida, com
              o lembrete ligado.
            </p>

            <div v-if="isAdmin" class="flex justify-end">
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm cv-btn-danger"
                @click="removeRule(rule)"
              >
                <span class="i-lucide-trash-2 text-xs" /> Apagar lembrete
              </button>
            </div>
          </div>
        </div>

        <!-- salvar -->
        <div v-if="isAdmin" class="flex items-center gap-2 flex-wrap pt-1">
          <button class="cv-btn" :disabled="saving || !dirty" @click="save">
            <Spinner v-if="saving" :size="14" />
            <span v-else class="i-lucide-save text-sm" /> Salvar lembretes
          </button>
          <button
            v-if="dirty"
            class="cv-btn cv-btn-ghost"
            :disabled="saving"
            @click="discard"
          >
            Descartar
          </button>
          <span class="text-[11px] text-n-slate-10"
            >1 envio por consulta em cada lembrete — reprocessar não
            duplica.</span
          >
        </div>
        <p v-else class="text-[11px] text-n-slate-10">
          Só administradores alteram os lembretes.
        </p>
      </div>
    </div>
  </div>
</template>
