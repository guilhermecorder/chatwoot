<script setup>
// BARRA DE ABAS estilo iPhone (rodada 20) — pedido dele 18/09: "fácil
// chegar a qualquer lugar com 1 ou 2 cliques, como um app feito pela
// Apple". No celular a sidebar fica escondida atrás do hambúrguer (2
// toques); esta barra fixa no rodapé leva a qualquer canto do mundo
// Saúde com 1 toque. No desktop (≥ 768px) a sidebar já resolve — some.
import { computed, onMounted, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const props = defineProps({
  boxingOn: { type: Boolean, default: false },
});

const route = useRoute();
const router = useRouter();

const items = computed(() => [
  { name: 'hub_health_painel', label: 'Painel', icon: 'i-lucide-gauge' },
  { name: 'hub_health', label: 'Treino', icon: 'i-lucide-dumbbell' },
  ...(props.boxingOn ? [{ name: 'hub_health_boxe', label: 'Boxe', icon: 'i-lucide-swords' }] : []),
  { name: 'hub_health_corpo', label: 'Corpo', icon: 'i-lucide-ruler' },
  { name: 'hub_health_dieta', label: 'Dieta', icon: 'i-lucide-utensils' },
  { name: 'hub_health_dash', label: 'Análises', icon: 'i-lucide-area-chart' },
  { name: 'hub_health_rotina', label: 'Rotina', icon: 'i-lucide-calendar-range' },
]);

// o botão-hambúrguer do app (fixo no canto inferior esquerdo) sobe pra
// não cobrir a 1ª aba — marca no body enquanto a barra existe
onMounted(() => document.body.classList.add('hub-tabbar-on'));
onUnmounted(() => document.body.classList.remove('hub-tabbar-on'));

const isOn = name => route.name === name;
const go = name => {
  if (isOn(name)) return;
  router.push({ name, params: { accountId: route.params.accountId } });
};
</script>

<template>
  <nav class="hub-tabbar" aria-label="Navegação da Saúde">
    <button
      v-for="it in items"
      :key="it.name"
      class="hub-tab"
      :class="{ 'is-on': isOn(it.name) }"
      :aria-current="isOn(it.name) ? 'page' : undefined"
      @click="go(it.name)"
    >
      <span class="hub-tab-icon" :class="it.icon" />
      <span class="hub-tab-label">{{ it.label }}</span>
    </button>
  </nav>
</template>

<style>
/* hambúrguer do app acima da barra de abas (só no celular) */
@media (max-width: 767px) {
  body.hub-tabbar-on #mobile-sidebar-launcher {
    bottom: calc(4.4rem + env(safe-area-inset-bottom, 0px));
  }
}
</style>

<style scoped>
/* vidro azul-noite fixo no rodapé, respeitando a barra do iPhone */
.hub-tabbar {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 35;
  display: flex;
  align-items: stretch;
  justify-content: space-around;
  padding: 6px 4px calc(6px + env(safe-area-inset-bottom, 0px));
  background: rgba(17, 28, 63, 0.9);
  -webkit-backdrop-filter: blur(18px) saturate(1.6);
  backdrop-filter: blur(18px) saturate(1.6);
  border-top: 1px solid rgba(143, 169, 245, 0.22);
  box-shadow: 0 -8px 24px -16px rgba(17, 28, 63, 0.8);
}
/* desktop (≥ 768px): a sidebar já dá 1 clique — a barra some (a regra
   fica aqui e não em md:hidden porque o estilo scoped venceria o utilitário) */
@media (min-width: 768px) {
  .hub-tabbar {
    display: none;
  }
}
.hub-tab {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 3px;
  padding: 4px 2px;
  border-radius: 12px;
  color: rgba(255, 255, 255, 0.62);
  transition:
    color 0.15s ease,
    transform 0.12s ease;
}
.hub-tab:active {
  transform: scale(0.94);
}
.hub-tab-icon {
  font-size: 22px;
  line-height: 1;
}
.hub-tab-label {
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.01em;
  white-space: nowrap;
}
.hub-tab.is-on {
  color: #ffb25e;
}
.hub-tab.is-on .hub-tab-icon {
  color: #ff8a00;
  filter: drop-shadow(0 0 6px rgba(255, 138, 0, 0.55));
}
</style>
