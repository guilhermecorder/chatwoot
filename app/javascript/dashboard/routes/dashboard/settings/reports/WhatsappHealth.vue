<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import InboxesAPI from 'dashboard/api/inboxes';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');

const healthByInbox = ref({});
const isLoading = ref(false);
const lastRefresh = ref(null);

const whatsappInboxes = computed(() =>
  inboxes.value.filter(i => i.channel_type === 'Channel::Whatsapp')
);

const QUALITY_META = {
  GREEN:   { label: 'Alta',      cls: 'bg-green-500/15 text-green-600', dot: '#22C55E' },
  YELLOW:  { label: 'Média',     cls: 'bg-amber-500/15 text-amber-600', dot: '#F59E0B' },
  RED:     { label: 'Baixa',     cls: 'bg-red-500/15 text-red-600',     dot: '#EF4444' },
  UNKNOWN: { label: 'Sem dados', cls: 'bg-n-alpha-2 text-n-slate-10',   dot: '#9CA3AF' },
};

const TIER_LABELS = {
  TIER_50: '50 conversas/24h',
  TIER_250: '250 conversas/24h',
  TIER_1K: '1.000 conversas/24h',
  TIER_10K: '10.000 conversas/24h',
  TIER_100K: '100.000 conversas/24h',
  TIER_UNLIMITED: 'Ilimitado',
};

const qualityMeta = h =>
  QUALITY_META[h?.quality_rating?.toUpperCase?.()] ?? QUALITY_META.UNKNOWN;

const tierLabel = h =>
  TIER_LABELS[h?.messaging_limit_tier] ?? h?.messaging_limit_tier ?? '—';

const webhookOk = h => {
  const configured = h?.webhook_configuration?.application ?? '';
  const expected = h?.expected_webhook_url ?? '';
  if (!expected) return null;
  return configured.startsWith(expected.split('/webhooks')[0]);
};

const loadHealth = async () => {
  if (isLoading.value) return;
  isLoading.value = true;
  const result = {};
  await Promise.all(
    whatsappInboxes.value.map(async inbox => {
      try {
        const { data } = await InboxesAPI.getHealth(inbox.id);
        result[inbox.id] = { ok: true, ...data };
      } catch (error) {
        result[inbox.id] = {
          ok: false,
          error: error?.response?.data?.error ?? 'Erro ao consultar a Meta',
        };
      }
    })
  );
  healthByInbox.value = result;
  lastRefresh.value = new Date();
  isLoading.value = false;
};

onMounted(async () => {
  await store.dispatch('inboxes/get');
  await loadHealth();
});
</script>

<template>
  <div class="flex flex-col h-full overflow-y-auto p-6 bg-n-surface-1">
    <div class="flex items-center gap-3 mb-6 flex-wrap">
      <div>
        <h1 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
          <span class="i-lucide-activity text-n-brand" />
          Saúde do WhatsApp
        </h1>
        <p class="text-xs text-n-slate-10 mt-0.5">
          Qualidade e limites de cada número conectado — dados ao vivo da Meta
        </p>
      </div>
      <div class="flex-1" />
      <span v-if="lastRefresh" class="text-xs text-n-slate-9">
        atualizado às {{ lastRefresh.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) }}
      </span>
      <button
        class="flex items-center gap-1.5 text-sm px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 transition-colors disabled:opacity-50"
        :disabled="isLoading"
        @click="loadHealth"
      >
        <span class="i-lucide-refresh-cw text-sm" :class="isLoading ? 'animate-spin' : ''" />
        Atualizar
      </button>
    </div>

    <div v-if="isLoading && !Object.keys(healthByInbox).length" class="flex justify-center py-16">
      <Spinner />
    </div>

    <div v-else-if="!whatsappInboxes.length" class="flex flex-col items-center justify-center py-20 text-n-slate-9">
      <span class="i-lucide-smartphone text-5xl mb-4" />
      <p class="text-sm">Nenhum número WhatsApp API oficial conectado.</p>
      <p class="text-xs mt-1">Conecte uma caixa de entrada WhatsApp Cloud para acompanhar a saúde aqui.</p>
    </div>

    <div v-else class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
      <div
        v-for="inbox in whatsappInboxes"
        :key="inbox.id"
        class="bg-n-solid-2 border border-n-weak rounded-xl p-5"
      >
        <template v-if="healthByInbox[inbox.id]?.ok">
          <div class="flex items-center justify-between mb-3 gap-2">
            <div class="min-w-0">
              <p class="text-sm font-semibold text-n-slate-12 truncate">
                {{ healthByInbox[inbox.id].verified_name || inbox.name }}
              </p>
              <p class="text-xs text-n-slate-10">{{ healthByInbox[inbox.id].display_phone_number }}</p>
            </div>
            <span
              class="text-xs px-2.5 py-1 rounded-full flex items-center gap-1.5 font-medium flex-shrink-0"
              :class="qualityMeta(healthByInbox[inbox.id]).cls"
            >
              <span
                class="w-2 h-2 rounded-full"
                :style="{ backgroundColor: qualityMeta(healthByInbox[inbox.id]).dot }"
              />
              Qualidade {{ qualityMeta(healthByInbox[inbox.id]).label }}
            </span>
          </div>

          <div class="space-y-2 text-xs">
            <div class="flex items-center justify-between">
              <span class="text-n-slate-10">Limite de envio</span>
              <span class="text-n-slate-12 font-medium">{{ tierLabel(healthByInbox[inbox.id]) }}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-n-slate-10">Nome verificado</span>
              <span
                class="font-medium"
                :class="healthByInbox[inbox.id].name_status === 'APPROVED' ? 'text-green-600' : 'text-amber-600'"
              >{{ healthByInbox[inbox.id].name_status === 'APPROVED' ? 'Aprovado' : healthByInbox[inbox.id].name_status }}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-n-slate-10">Modo da conta</span>
              <span class="text-n-slate-12 font-medium">{{ healthByInbox[inbox.id].account_mode ?? '—' }}</span>
            </div>
            <div v-if="healthByInbox[inbox.id].throughput?.level" class="flex items-center justify-between">
              <span class="text-n-slate-10">Velocidade (throughput)</span>
              <span class="text-n-slate-12 font-medium">{{ healthByInbox[inbox.id].throughput.level }}</span>
            </div>
            <div v-if="webhookOk(healthByInbox[inbox.id]) !== null" class="flex items-center justify-between">
              <span class="text-n-slate-10">Webhook</span>
              <span
                class="font-medium"
                :class="webhookOk(healthByInbox[inbox.id]) ? 'text-green-600' : 'text-red-500'"
              >{{ webhookOk(healthByInbox[inbox.id]) ? 'Configurado ✓' : 'Verificar!' }}</span>
            </div>
          </div>
        </template>

        <template v-else-if="healthByInbox[inbox.id]">
          <p class="text-sm font-semibold text-n-slate-12 mb-1">{{ inbox.name }}</p>
          <p class="text-xs text-red-500">{{ healthByInbox[inbox.id].error }}</p>
        </template>

        <div v-else class="flex justify-center py-4"><Spinner :size="16" /></div>
      </div>
    </div>

    <p class="text-xs text-n-slate-9 mt-6 max-w-2xl">
      A qualidade é a nota que a Meta dá ao número com base em denúncias e bloqueios dos
      destinatários. Verde = saudável; amarelo = atenção (reduza o volume de campanhas);
      vermelho = risco de restrição. O limite de envio sobe automaticamente conforme o
      número mantém boa qualidade.
    </p>
  </div>
</template>
