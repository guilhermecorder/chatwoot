<script setup>
// 👑 PAINEL DO EMPRESÁRIO — ambiente próprio (27/09, pedido do Guilherme):
// sai de dentro da aba do Estratégico e fica no TOPO do menu, acima do Meu
// Painel. É o quadro da parede do dono, agora em quadros soltos com ÍMÃ
// (MagnetBoard): arrasta pelo título, estica pela borda/canto, tudo encaixa
// sozinho. Cada anotação nasce com DATA e pode ser ATUALIZADA (ação feita,
// conquista, pivô, ajuste) — tudo cai na Linha do tempo. Novo: a TEIA RADAR
// gêmea (status atual × desejado por área da empresa). Só admin; salva
// sozinho em agenda_config.business_board.
import { ref, onMounted } from 'vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CrmAPI from 'dashboard/api/crm';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import BusinessBoardBody from './BusinessBoardBody.vue';
import { CARDS } from './cards';

const { isAdmin } = useAdmin();
const pal = useCevicoPalette({
  scope: 'empresario',
  blocks: CARDS.map(c => ({ id: c.id, label: c.title, icon: c.icon })),
});
const { cvVars } = pal;

const loading = ref(true);
const loadError = ref(false);
const initial = ref(null);
const metrics = ref(null);
onMounted(async () => {
  if (!isAdmin.value) {
    loading.value = false;
    return;
  }
  try {
    const { data } = await CrmAPI.getStrategyBoard();
    initial.value = data.business || {};
    metrics.value = data.metrics || null;
  } catch {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div
    class="cv-page cv-biz flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-[1500px] mx-auto w-full p-4 sm:p-6 lg:p-8">
      <CevicoHero
        :pal="pal"
        title="Painel do empresário"
        subtitle="a mesa do dono: onde a empresa está, onde queremos chegar e o que fazer esta semana"
        icon="i-lucide-crown"
      />
      <div v-if="!isAdmin" class="cv-block p-6 text-sm text-n-slate-11">
        O Painel do empresário é só do administrador.
      </div>
      <div v-else-if="loading" class="biz-loading">
        <div v-for="i in 4" :key="i" class="biz-skel biz-skel-lg" />
      </div>
      <div v-else-if="loadError" class="cv-block p-6 text-sm text-n-slate-11">
        Não consegui abrir o quadro agora. Recarregue a página em instantes —
        nada do que estava salvo se perdeu.
      </div>
      <BusinessBoardBody v-else :initial="initial" :metrics="metrics" />
    </div>
  </div>
</template>
