<script setup>
// 🏢 MEUS NEGÓCIOS (21/10/2026) — a porta do dono para cada empresa.
// Mesma ideia da tela de "mundos" do HUB: um cartão por negócio; clicar
// pede ao servidor o link de entrada (SSO de uso único) e abre o sistema
// daquela empresa numa aba nova. Cada sistema segue na sua VPS, isolado.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

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

// gradiente do cartão a partir da cor do negócio (escurece para o canto)
const estilo = n => ({
  background: `linear-gradient(135deg, ${n.cor} 0%, color-mix(in srgb, ${n.cor} 55%, #0b1020) 100%)`,
});

const entrar = async n => {
  if (abrindo.value) return;
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

// rótulos do cartão (fora do template para o prettier não quebrar linha)
const descricao = n =>
  n.descricao || (n.local ? 'este sistema' : 'sistema próprio');
const icone = n =>
  abrindo.value === n.chave
    ? 'i-lucide-loader-2 animate-spin'
    : 'i-lucide-arrow-right';
const rotulo = n => {
  if (abrindo.value === n.chave) return 'Abrindo';
  return n.local ? 'Estou aqui' : 'Entrar';
};

onMounted(carregar);
</script>

<template>
  <div class="neg-page">
    <header class="neg-head">
      <h1 class="neg-title">Meus negócios</h1>
      <p class="neg-sub">Escolha a empresa de hoje.</p>
    </header>

    <div v-if="loading" class="neg-grid">
      <div v-for="i in 3" :key="i" class="neg-card neg-card-skel" />
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
        v-for="(n, i) in negocios"
        :key="n.chave"
        class="neg-card"
        :style="estilo(n)"
        :disabled="Boolean(abrindo)"
        :title="n.local ? 'Este sistema' : n.url"
        @click="entrar(n)"
      >
        <span class="neg-num">{{ i + 1 }}</span>
        <span class="neg-logo">
          <img v-if="n.logo" :src="n.logo" :alt="n.nome" />
          <span v-else class="neg-inicial">{{ inicial(n) }}</span>
        </span>
        <span class="neg-nome">{{ n.nome }}</span>
        <span class="neg-desc">{{ descricao(n) }}</span>
        <span class="neg-cta">
          <span :class="icone(n)" />
          {{ rotulo(n) }}
        </span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.neg-page {
  @apply w-full h-full overflow-auto px-6 py-10 flex flex-col items-center;
}
.neg-head {
  @apply text-center mb-8;
}
.neg-title {
  @apply text-2xl font-semibold tracking-tight text-slate-900 dark:text-slate-50;
}
.neg-sub {
  @apply mt-1 text-sm text-slate-500 dark:text-slate-400;
}
.neg-grid {
  @apply grid gap-5 w-full max-w-4xl;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
}
.neg-card {
  @apply relative text-left rounded-3xl p-6 min-h-[190px] text-white shadow-lg flex flex-col;
  transition:
    transform 0.18s ease,
    box-shadow 0.18s ease;
}
.neg-card:hover:not(:disabled) {
  transform: translateY(-3px);
  box-shadow: 0 18px 40px rgba(0, 0, 0, 0.25);
}
.neg-card:disabled {
  @apply cursor-wait opacity-80;
}
.neg-card-skel {
  @apply animate-pulse bg-slate-200 dark:bg-slate-800;
}
.neg-num {
  @apply absolute top-5 right-5 w-7 h-7 rounded-full bg-white/20 text-xs font-semibold flex items-center justify-center;
}
.neg-logo {
  @apply w-12 h-12 rounded-2xl bg-white/15 flex items-center justify-center overflow-hidden mb-6;
}
.neg-logo img {
  @apply w-10 h-10 object-contain;
}
.neg-inicial {
  @apply text-xl font-bold;
}
.neg-nome {
  @apply text-xl font-semibold tracking-tight;
}
.neg-desc {
  @apply text-sm text-white/75 mt-0.5;
}
.neg-cta {
  @apply mt-auto pt-5 inline-flex items-center gap-1.5 self-start rounded-full bg-white/20 px-3.5 py-1.5 text-sm font-medium;
}
.neg-empty {
  @apply flex flex-col items-center gap-3 text-center text-slate-500 dark:text-slate-400 max-w-md;
}
.neg-empty code {
  @apply text-xs px-1 rounded bg-slate-100 dark:bg-slate-800;
}
</style>
