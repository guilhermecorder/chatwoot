<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import InboxesAPI from 'dashboard/api/inboxes';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';

const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');

// 🍎 formato novo (rodada 163): kit "iMac G3 + vidro" com a paleta desta
// página (o admin escolhe pelo chip do banner; cada bloco pode ter a sua)
const pal = useCevicoPalette({
  scope: 'report:whatsapp',
  blocks: [
    { id: 'numeros', label: 'Números conectados', icon: 'i-lucide-smartphone' },
    { id: 'legenda', label: 'Como ler a qualidade', icon: 'i-lucide-info' },
  ],
});
const { cvVars, blockVars } = pal;

const healthByInbox = ref({});
const isLoading = ref(false);
const lastRefresh = ref(null);

const whatsappInboxes = computed(() =>
  inboxes.value.filter(i => i.channel_type === 'Channel::Whatsapp')
);

// verde/âmbar/vermelho têm SIGNIFICADO (nota da Meta): chips semânticos do kit
const QUALITY_META = {
  GREEN:   { label: 'Alta',      cls: 'cv-green', dot: '#22C55E' },
  YELLOW:  { label: 'Média',     cls: 'cv-amber', dot: '#F59E0B' },
  RED:     { label: 'Baixa',     cls: 'cv-red',   dot: '#EF4444' },
  UNKNOWN: { label: 'Sem dados', cls: 'cv-slate', dot: '#9CA3AF' },
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
  <div class="cv-page flex flex-col h-full overflow-y-auto p-6 bg-n-surface-1" :style="cvVars">
    <!-- banner de vidro na paleta da página (rodada 163) -->
    <CevicoHero
      :pal="pal"
      title="Saúde do WhatsApp"
      subtitle="Qualidade e limites de cada número conectado — dados ao vivo da Meta"
      icon="i-lucide-activity"
    >
      <template #actions>
        <span v-if="lastRefresh" class="cevico-hero-chip">
          <span class="i-lucide-clock text-xs" />
          atualizado às {{ lastRefresh.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) }}
        </span>
        <button
          class="cevico-hero-btn disabled:opacity-50"
          :disabled="isLoading"
          @click="loadHealth"
        >
          <span class="i-lucide-refresh-cw text-xs" :class="isLoading ? 'animate-spin' : ''" />
          Atualizar
        </button>
      </template>
    </CevicoHero>

    <!-- 📱 Números conectados: um cartão por número, com a nota da Meta -->
    <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('numeros')">
      <div class="flex items-center gap-2 mb-5 flex-wrap">
        <span class="cv-icon"><span class="i-lucide-smartphone text-base" /></span>
        <h2 class="text-sm font-bold text-n-slate-12">Números conectados</h2>
        <span v-if="whatsappInboxes.length" class="cv-chip">{{ whatsappInboxes.length }} número(s)</span>
      </div>

      <div v-if="isLoading && !Object.keys(healthByInbox).length" class="flex justify-center py-16">
        <Spinner />
      </div>

      <div v-else-if="!whatsappInboxes.length" class="flex flex-col items-center justify-center py-16 text-n-slate-9">
        <span class="cv-icon cv-icon-xl mb-4"><span class="i-lucide-smartphone text-2xl" /></span>
        <p class="text-sm">Nenhum número WhatsApp API oficial conectado.</p>
        <p class="text-xs mt-1">Conecte uma caixa de entrada WhatsApp Cloud para acompanhar a saúde aqui.</p>
      </div>

      <div v-else class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
        <div
          v-for="inbox in whatsappInboxes"
          :key="inbox.id"
          class="cv-sub p-4"
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
                class="cv-chip flex-shrink-0"
                :class="qualityMeta(healthByInbox[inbox.id]).cls"
              >
                <span
                  class="w-2 h-2 rounded-full"
                  :style="{ backgroundColor: qualityMeta(healthByInbox[inbox.id]).dot }"
                />
                Qualidade {{ qualityMeta(healthByInbox[inbox.id]).label }}
              </span>
            </div>

            <div class="space-y-1.5 text-xs">
              <div class="cv-row flex items-center justify-between gap-2 px-3 py-1.5">
                <span class="text-n-slate-10">Limite de envio</span>
                <span class="text-n-slate-12 font-medium">{{ tierLabel(healthByInbox[inbox.id]) }}</span>
              </div>
              <div class="cv-row flex items-center justify-between gap-2 px-3 py-1.5">
                <span class="text-n-slate-10">Nome verificado</span>
                <span
                  class="font-medium"
                  :class="healthByInbox[inbox.id].name_status === 'APPROVED' ? 'text-green-600' : 'text-amber-600'"
                >{{ healthByInbox[inbox.id].name_status === 'APPROVED' ? 'Aprovado' : healthByInbox[inbox.id].name_status }}</span>
              </div>
              <div class="cv-row flex items-center justify-between gap-2 px-3 py-1.5">
                <span class="text-n-slate-10">Modo da conta</span>
                <span class="text-n-slate-12 font-medium">{{ healthByInbox[inbox.id].account_mode ?? '—' }}</span>
              </div>
              <div v-if="healthByInbox[inbox.id].throughput?.level" class="cv-row flex items-center justify-between gap-2 px-3 py-1.5">
                <span class="text-n-slate-10">Velocidade (throughput)</span>
                <span class="text-n-slate-12 font-medium">{{ healthByInbox[inbox.id].throughput.level }}</span>
              </div>
              <div v-if="webhookOk(healthByInbox[inbox.id]) !== null" class="cv-row flex items-center justify-between gap-2 px-3 py-1.5">
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
    </div>

    <!-- ℹ️ Como ler a nota da Meta (faixa fina) -->
    <div class="cv-block cv-strip p-5 mb-6" :style="blockVars('legenda')">
      <div class="flex items-start gap-3">
        <span class="cv-icon"><span class="i-lucide-info text-base" /></span>
        <div class="min-w-0">
          <h2 class="text-sm font-bold text-n-slate-12">Como ler a qualidade</h2>
          <p class="text-xs text-n-slate-10 mt-1 max-w-2xl leading-relaxed">
            A qualidade é a nota que a Meta dá ao número com base em denúncias e bloqueios dos
            destinatários. Verde = saudável; amarelo = atenção (reduza o volume de campanhas);
            vermelho = risco de restrição. O limite de envio sobe automaticamente conforme o
            número mantém boa qualidade.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
