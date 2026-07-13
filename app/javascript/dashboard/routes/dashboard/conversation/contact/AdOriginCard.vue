<script setup>
// "Por qual anúncio essa pessoa chegou" — atribuição CTWA gravada pelo
// Crm::AdAttributionService no additional_attributes do contato/conversa.
// Visão de gestor: só admin vê (painel do agente fica simples).
import { computed } from 'vue';
import { useAdmin } from 'dashboard/composables/useAdmin';

const props = defineProps({
  contact: { type: Object, default: () => ({}) },
  conversationAttributes: { type: Object, default: () => ({}) },
});

const { isAdmin } = useAdmin();

const adData = computed(() => {
  if (!isAdmin.value) return null;
  return (
    props.contact?.additional_attributes?.meta_ads ||
    props.conversationAttributes?.meta_ads ||
    null
  );
});

const capturedAt = computed(() => {
  if (!adData.value?.captured_at) return '';
  const d = new Date(adData.value.captured_at);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString('pt-BR');
});
</script>

<template>
  <div
    v-if="adData"
    class="mx-4 mb-2 rounded-xl border border-blue-500/40 bg-blue-500/5 p-3"
  >
    <div class="flex items-center gap-1.5 mb-1">
      <span class="i-lucide-megaphone text-blue-500 text-sm flex-shrink-0" />
      <span class="text-xs font-semibold text-blue-600">
        Veio de anúncio (Meta)
      </span>
      <span v-if="capturedAt" class="text-[10px] text-n-slate-9 ml-auto">
        {{ capturedAt }}
      </span>
    </div>
    <!-- nome interno do anúncio (nomenclatura do Gerenciador) em destaque -->
    <p
      v-if="adData.ad_name"
      class="text-sm font-semibold text-n-slate-12 mb-0.5"
    >
      {{ adData.ad_name }}
    </p>
    <p
      v-if="adData.headline"
      class="text-xs text-n-slate-11 mb-0.5"
      :class="{ 'text-sm font-medium text-n-slate-12': !adData.ad_name }"
    >
      {{ adData.headline }}
    </p>
    <p v-if="adData.body" class="text-xs text-n-slate-11 line-clamp-2 mb-1">
      {{ adData.body }}
    </p>
    <div class="flex items-center gap-3">
      <a
        v-if="adData.source_url"
        :href="adData.source_url"
        target="_blank"
        rel="noopener noreferrer"
        class="text-xs text-blue-600 hover:underline flex items-center gap-1"
      >
        <span class="i-lucide-external-link text-[11px]" />
        Ver anúncio
      </a>
      <span v-if="adData.source_id" class="text-[10px] text-n-slate-9">
        ID {{ adData.source_id }}
      </span>
    </div>
  </div>
</template>
