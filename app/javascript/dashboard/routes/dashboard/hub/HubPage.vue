<script setup>
// PORTA DE ENTRADA DO HUB — a tela dos mundos (desenho do Guilherme 25/08):
// 1 · Negócios (todo o sistema atual) · 2 · Saúde (mundo isolado, só
// treino/dieta/corpo) · 3 · reservado pro futuro. A escolha define o
// hub_mode (localStorage) e o Sidebar troca o menu inteiro de acordo.
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';

const router = useRouter();
const { accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();

const setMode = mode => {
  localStorage.setItem('hub_mode', mode);
  window.dispatchEvent(new CustomEvent('hub:mode', { detail: mode }));
};

const abrirNegocios = () => {
  setMode('negocios');
  router.push(accountScopedRoute('inicio_home'));
};

const abrirSaude = () => {
  setMode('saude');
  router.push(accountScopedRoute('hub_health_painel'));
};

// convidado (não-admin) não vê o mundo Negócios — o HUB dele é a Saúde
const MUNDOS_ALL = [
  {
    numero: 1,
    titulo: 'Negócios',
    desc: 'CRM · conversas · financeiro · páginas',
    icon: 'i-lucide-briefcase',
    grad: 'linear-gradient(135deg, #0F5FA6 0%, #7C3AED 100%)',
    action: abrirNegocios,
  },
  {
    numero: 2,
    titulo: 'Saúde',
    desc: 'treino · dieta · corpo',
    icon: 'i-lucide-heart-pulse',
    grad: 'linear-gradient(135deg, #065F46 0%, #10B981 100%)',
    action: abrirSaude,
  },
];
const MUNDOS = computed(() =>
  isAdmin.value ? MUNDOS_ALL : MUNDOS_ALL.filter(m => m.numero !== 1)
);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-3xl mx-auto w-full p-4 sm:p-8 flex flex-col justify-center min-h-full">
      <!-- Cabeçalho -->
      <div class="text-center mb-8">
        <h1 class="text-2xl font-bold text-n-slate-12">HUB</h1>
        <p class="text-sm text-n-slate-10 mt-1">Escolha o mundo de hoje.</p>
      </div>

      <!-- Mundos 1 e 2 -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-4">
        <button
          v-for="mundo in MUNDOS"
          :key="mundo.numero"
          class="relative rounded-3xl p-6 text-left text-white transition-transform hover:scale-[1.02] active:scale-[0.99] shadow-lg"
          :style="{ background: mundo.grad }"
          @click="mundo.action"
        >
          <span
            class="absolute top-4 right-4 w-8 h-8 rounded-full bg-white/20 flex items-center justify-center text-sm font-bold"
          >
            {{ mundo.numero }}
          </span>
          <span :class="mundo.icon" class="text-4xl block mb-4" />
          <span class="block text-xl font-bold">{{ mundo.titulo }}</span>
          <span class="block text-xs opacity-80 mt-1">{{ mundo.desc }}</span>
          <span class="inline-flex items-center gap-1 mt-4 text-xs font-bold bg-white/15 rounded-full px-3 py-1.5">
            Entrar <span class="i-lucide-arrow-right" />
          </span>
        </button>
      </div>

      <!-- Mundo 3 — reservado -->
      <div class="flex justify-center">
        <div
          class="w-full sm:w-1/2 rounded-3xl p-6 border-2 border-dashed border-n-weak text-center text-n-slate-9"
        >
          <span
            class="inline-flex w-8 h-8 rounded-full bg-n-alpha-1 items-center justify-center text-sm font-bold mb-2"
          >
            3
          </span>
          <p class="text-sm font-medium">Em breve</p>
          <p class="text-[11px] mt-0.5">o terceiro mundo ainda vai ganhar nome</p>
        </div>
      </div>
    </div>
  </div>
</template>
