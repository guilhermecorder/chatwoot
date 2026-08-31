<script setup>
// ⚙️ Configurações → HUB (rodada 14)
// Ambiente do admin pro sistema pessoal: liga/desliga recursos do mundo
// Saúde. O boxe nasce DESLIGADO pra todo mundo — o admin libera aqui.
// Salvo em agenda_config['health']['features'] (config compartilhada).
import { ref, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();

const isLoading = ref(true);
const isSaving = ref(false);
const healthConfig = ref({});
const boxingOn = ref(false);

onMounted(async () => {
  try {
    const { data } = await CrmAPI.getHealth();
    healthConfig.value = data.config || {};
    boxingOn.value = healthConfig.value.features?.boxing === true;
  } catch {
    useAlert('Não consegui carregar as configurações do HUB.');
  } finally {
    isLoading.value = false;
  }
});

const save = async () => {
  isSaving.value = true;
  try {
    await CrmAPI.updateHealthConfig({
      ...healthConfig.value,
      features: { ...(healthConfig.value.features || {}), boxing: boxingOn.value },
    });
    healthConfig.value.features = {
      ...(healthConfig.value.features || {}),
      boxing: boxingOn.value,
    };
    // o menu lê health_features do settings — recarrega pra refletir já
    await store.dispatch('crm/fetchSettings').catch(() => {});
    useAlert(boxingOn.value ? '🥊 Boxe liberado pra todo mundo.' : 'Boxe ocultado do sistema.');
  } catch {
    useAlert('Não consegui salvar.');
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex-1 overflow-auto p-6">
    <div class="max-w-3xl mx-auto">
      <h1 class="text-xl font-bold text-n-slate-12 mb-1">⬡ HUB</h1>
      <p class="text-xs text-n-slate-10 mb-6">
        Recursos do sistema pessoal. O que estiver desligado some do menu e das telas
        de todos os usuários do mundo Saúde.
      </p>

      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>
      <template v-else>
        <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 mb-4 flex items-center justify-between gap-3">
          <div>
            <p class="text-sm font-bold text-n-slate-12">🥊 Mundo Boxe</p>
            <p class="text-[11px] text-n-slate-10">
              Aba de treino de boxe (sequências, rounds, tempo) e os gráficos dele no
              dashboard. Desligado, ninguém vê — nem no painel.
            </p>
          </div>
          <button
            class="hub-toggle shrink-0"
            :class="{ 'is-on': boxingOn }"
            role="switch"
            :aria-checked="boxingOn"
            @click="boxingOn = !boxingOn"
          >
            <span class="hub-toggle-knob" />
          </button>
        </div>

        <button
          class="h-10 px-5 rounded-xl text-sm font-bold text-white disabled:opacity-60"
          style="background: linear-gradient(135deg, #27408b, #4169e1)"
          :disabled="isSaving"
          @click="save"
        >
          {{ isSaving ? 'Salvando…' : 'Salvar' }}
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* chavinha iOS: trilho que desliza — verde-royal quando ligada */
.hub-toggle {
  width: 3.1rem;
  height: 1.85rem;
  border-radius: 9999px;
  background: rgba(127, 127, 127, 0.35);
  padding: 3px;
  transition: background 0.2s ease;
  display: inline-flex;
  align-items: center;
}
.hub-toggle.is-on {
  background: #4169e1;
}
.hub-toggle-knob {
  width: 1.45rem;
  height: 1.45rem;
  border-radius: 9999px;
  background: #fff;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.35);
  transition: transform 0.2s ease;
}
.hub-toggle.is-on .hub-toggle-knob {
  transform: translateX(1.25rem);
}
</style>
