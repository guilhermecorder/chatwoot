<script setup>
// 📣 item 380/381 (03/11): a REATIVAÇÃO tem casa própria no menu (Guilherme:
// "precisa ser mais fácil de acessar… é uma coisa importante para nós, precisa
// estar bem estabelecida"). A mesma tela também aparece como aba dentro de
// Campanha WhatsApp; aqui ela é a página inteira, com mais respiro.
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import ReativacaoMensagens from 'dashboard/components-next/cevico/campanhas/ReativacaoMensagens.vue';

const router = useRouter();
const { canEdit } = useCevicoAccess();
const canEditCampaigns = computed(() => canEdit('crm.campanhas'));
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-solid-1 overflow-hidden">
    <!-- Header no padrão das telas do CRM -->
    <div class="flex items-center gap-3 px-6 py-4 border-b border-n-weak flex-shrink-0 flex-wrap">
      <button
        class="flex items-center gap-1 text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="router.push({ name: 'crm_board' })"
      >
        <span class="i-lucide-arrow-left" />
        CRM
      </button>
      <span class="text-n-slate-8">/</span>
      <h1 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
        <span
          class="w-8 h-8 rounded-xl flex items-center justify-center"
          style="background: linear-gradient(135deg, #B45309, #F59E0B)"
        >
          <span class="i-lucide-rotate-ccw text-white text-base" />
        </span>
        Reativação
        <CevicoViewOnlyPill v-if="!canEditCampaigns" />
      </h1>
      <div class="flex-1" />
      <button
        class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1"
        title="Campanhas, automações e ligações"
        @click="router.push({ name: 'crm_campaigns' })"
      >
        <span class="i-lucide-megaphone" />
        Campanha WhatsApp
      </button>
    </div>

    <!-- a tela inteira rola (regra: toda tela rola até o fim) -->
    <div class="flex-1 overflow-y-auto p-6 sm:p-10">
      <ReativacaoMensagens :can-edit="canEditCampaigns" espacoso />
    </div>
  </div>
</template>
