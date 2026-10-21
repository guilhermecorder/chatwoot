<script setup>
// 🏢 MEUS NEGÓCIOS (21/10/2026) — a porta do dono para cada empresa.
// Ambiente limpo (sem painel lateral, como a porta do HUB): só os
// quadradinhos de cada negócio, com o logo oficial. Clicar pede ao servidor
// o link de entrada (SSO de uso único) e abre o sistema daquela empresa;
// o negócio "local" é este sistema. Cada sistema segue na sua VPS, isolado.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/crm';

const { accountScopedRoute } = useAccount();

const loading = ref(true);
const dono = ref(false);
const negocios = ref([]);
const abrindo = ref('');

const carregar = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAPI.getNegocios();
    dono.value = Boolean(data.dono);
    negocios.value = data.negocios || [];
  } catch (e) {
    useAlert('Não consegui carregar os negócios.');
  } finally {
    loading.value = false;
  }
};

const inicial = n => (n.nome || '?').trim().charAt(0).toUpperCase();

// fundo do quadradinho = a cor do negócio (o logo cobre o quadrado)
const estilo = n => ({ background: n.cor });

const entrar = async n => {
  if (abrindo.value) return;
  if (n.pendente) {
    useAlert(
      `${n.nome} ainda não está ligado: preencha MEUS_NEGOCIOS no ambiente (manual em docs/MEUS_NEGOCIOS.md).`
    );
    return;
  }
  abrindo.value = n.chave;
  // a aba nova precisa nascer no clique (senão o navegador bloqueia);
  // o endereço entra depois que o servidor devolver o link
  const aba = n.local ? null : window.open('', '_blank');
  try {
    const { data } = await CrmAPI.loginNegocio(n.chave);
    if (n.local) {
      window.location.assign(data.url);
    } else if (aba) {
      aba.location.href = data.url;
    } else {
      window.location.assign(data.url);
    }
  } catch (e) {
    if (aba) aba.close();
    const msg =
      e?.response?.data?.error || 'Não consegui abrir este negócio agora.';
    useAlert(msg);
  } finally {
    abrindo.value = '';
  }
};

const vazio = computed(
  () => !loading.value && (!dono.value || !negocios.value.length)
);

// estado escrito embaixo do nome
const estado = n => {
  if (abrindo.value === n.chave) return 'abrindo…';
  if (n.pendente) return 'ligar';
  return n.local ? 'este sistema' : 'entrar';
};

onMounted(carregar);
</script>

<template>
  <div class="neg-page">
    <!-- volta para a porta do HUB (não há painel lateral aqui) -->
    <router-link :to="accountScopedRoute('hub_home')" class="neg-voltar">
      <span class="i-lucide-layout-grid" /> HUB
    </router-link>

    <div class="neg-miolo">
      <header class="neg-head">
        <h1 class="neg-title">Meus negócios</h1>
        <p class="neg-sub">Escolha a empresa de hoje.</p>
      </header>

      <div v-if="loading" class="neg-grid">
        <div v-for="i in 3" :key="i" class="neg-item">
          <div class="neg-tile neg-tile-skel" />
        </div>
      </div>

      <div v-else-if="vazio" class="neg-empty">
        <span class="i-lucide-building-2 text-3xl" />
        <p v-if="!dono">Esta tela é só do dono dos negócios.</p>
        <p v-else>
          Nenhum negócio configurado ainda. Preencha
          <code>MEUS_NEGOCIOS</code> no ambiente da VPS (manual em
          <code>docs/MEUS_NEGOCIOS.md</code>).
        </p>
      </div>

      <div v-else class="neg-grid">
        <button
          v-for="n in negocios"
          :key="n.chave"
          class="neg-item"
          :class="{ 'neg-item-pendente': n.pendente }"
          :disabled="Boolean(abrindo)"
          :title="n.pendente ? 'Ainda não ligado' : n.local ? 'Este sistema' : n.url"
          @click="entrar(n)"
        >
          <span class="neg-tile" :style="estilo(n)">
            <img v-if="n.logo" :src="n.logo" :alt="n.nome" />
            <span v-else class="neg-inicial">{{ inicial(n) }}</span>
            <span v-if="n.pendente" class="neg-plug"
              ><span class="i-lucide-plug"
            /></span>
          </span>
          <span class="neg-nome">{{ n.nome }}</span>
          <span class="neg-estado">{{ estado(n) }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.neg-page {
  @apply relative flex flex-col h-full w-full overflow-y-auto bg-n-surface-1;
}
.neg-voltar {
  @apply absolute top-4 left-4 inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-n-slate-11 bg-n-solid-2 hover:bg-n-alpha-2 transition-colors;
}
.neg-miolo {
  @apply max-w-3xl mx-auto w-full p-4 sm:p-8 flex flex-col justify-center min-h-full;
}
.neg-head {
  @apply text-center mb-10;
}
.neg-title {
  @apply text-2xl font-bold text-n-slate-12;
}
.neg-sub {
  @apply text-sm text-n-slate-10 mt-1;
}
.neg-grid {
  @apply flex flex-wrap justify-center gap-8 sm:gap-12;
}
.neg-item {
  @apply flex flex-col items-center gap-2.5 w-[8.5rem] sm:w-40 text-center;
  transition: transform 0.18s ease;
}
.neg-item:hover:not(:disabled) {
  transform: translateY(-3px);
}
.neg-item:hover:not(:disabled) .neg-tile {
  box-shadow: 0 18px 40px rgba(0, 0, 0, 0.22);
}
.neg-item:disabled {
  @apply cursor-wait;
}
.neg-item-pendente .neg-tile {
  @apply opacity-70 saturate-50;
}
.neg-tile {
  /* o quadradinho: o logo preenche tudo, cantos de app do iPhone */
  @apply relative block w-[8.5rem] h-[8.5rem] sm:w-40 sm:h-40 rounded-[2rem] overflow-hidden shadow-lg;
  transition: box-shadow 0.18s ease;
}
.neg-tile img {
  /* o logo cabe inteiro, com respiro, sobre a cor da marca */
  @apply w-full h-full object-contain;
  padding: 9%;
}
.neg-tile-skel {
  @apply animate-pulse bg-slate-200 dark:bg-slate-800;
}
.neg-inicial {
  @apply w-full h-full flex items-center justify-center text-4xl font-bold text-white;
}
.neg-plug {
  @apply absolute bottom-2 right-2 w-7 h-7 rounded-full flex items-center justify-center text-sm;
  background: rgba(0, 0, 0, 0.5);
  color: #fff;
}
.neg-nome {
  @apply text-sm font-semibold text-n-slate-12 leading-tight;
}
.neg-estado {
  @apply text-[11px] uppercase tracking-wide text-n-slate-10;
}
.neg-empty {
  @apply flex flex-col items-center gap-3 text-center text-n-slate-10 max-w-md mx-auto;
}
.neg-empty code {
  @apply text-xs px-1 rounded bg-n-solid-2;
}
</style>
