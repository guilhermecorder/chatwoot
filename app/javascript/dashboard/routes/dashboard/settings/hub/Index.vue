<script setup>
// ⚙️ Configurações → HUB (rodada 14; rodada 34 = ACESSOS POR PESSOA)
// Ambiente do admin pro sistema pessoal: liga/desliga recursos do mundo
// Saúde (boxe nasce DESLIGADO) e marca, pessoa a pessoa, quais módulos
// cada um vê — pedido dele 20/09: "o admin precisa ter o controle de quem
// terá acesso a que; algumas pessoas não precisam do software de boxe".
// Recursos: agenda_config['health']['features']. Acessos:
// crm_settings.agent_permissions (grants 'health' + health_modules).
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import { HEALTH_MODULES } from '../../health/useHealthAccess';

const store = useStore();
const crmSettings = useMapGetter('crm/getSettings');
const agents = useMapGetter('agents/getAgents');

const isLoading = ref(true);
const isSaving = ref(false);
const healthConfig = ref({});
const boxingOn = ref(false);
const busyUser = ref(null);

onMounted(async () => {
  try {
    const [{ data }] = await Promise.all([
      CrmAPI.getHealth(),
      store.dispatch('agents/get').catch(() => {}),
      store.dispatch('crm/fetchSettings').catch(() => {}),
    ]);
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
    healthConfig.value.features = { ...(healthConfig.value.features || {}), boxing: boxingOn.value };
    await store.dispatch('crm/fetchSettings').catch(() => {});
    useAlert(boxingOn.value ? 'Boxe liberado (pra quem tiver o módulo).' : 'Boxe ocultado do sistema.');
  } catch {
    useAlert('Não consegui salvar.');
  } finally {
    isSaving.value = false;
  }
};

// ── acessos por pessoa ──
const perms = computed(() => crmSettings.value?.agent_permissions ?? {});
const people = computed(() =>
  [...(agents.value || [])]
    .filter(a => a.role !== 'administrator')
    .sort((a, b) => String(a.name).localeCompare(String(b.name)))
);
const admins = computed(() => (agents.value || []).filter(a => a.role === 'administrator'));
const grantsOf = a => perms.value.grants?.[String(a.id)] ?? [];
const hasHealth = a => grantsOf(a).includes('health');
const modulesOf = a => perms.value.health_modules?.[String(a.id)] ?? [];
const moduleOn = (a, key) => hasHealth(a) && (modulesOf(a).length === 0 || modulesOf(a).includes(key));

const saveAccess = async (a, payload) => {
  busyUser.value = a.id;
  try {
    await store.dispatch('crm/updateAgentGrants', { userId: a.id, ...payload });
  } catch {
    useAlert('Não consegui salvar o acesso.');
  } finally {
    busyUser.value = null;
  }
};
const toggleHealth = a => {
  const g = grantsOf(a);
  const grants = hasHealth(a) ? g.filter(k => k !== 'health') : [...g, 'health'];
  saveAccess(a, { grants, healthModules: hasHealth(a) ? [] : modulesOf(a) });
};
const toggleModule = (a, key) => {
  if (!hasHealth(a)) return;
  let list = modulesOf(a);
  if (list.length === 0) list = HEALTH_MODULES.map(m => m.key).filter(k => k !== key);
  else if (list.includes(key)) list = list.filter(k => k !== key);
  else list = [...list, key];
  if (list.length === HEALTH_MODULES.length) list = [];
  saveAccess(a, { healthModules: list });
};
const allOn = a => saveAccess(a, { healthModules: [] });
</script>

<template>
  <div class="hub-page flex-1 overflow-auto p-6">
    <div class="max-w-4xl mx-auto">
      <h1 class="hub-h1 mb-1">HUB</h1>
      <p class="text-xs text-n-slate-10 mb-6">
        Recursos do sistema pessoal e quem vê o quê no mundo Saúde.
      </p>

      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>
      <template v-else>
        <!-- recursos -->
        <div class="hub-block p-5 mb-8">
          <h2 class="hub-h2 mb-4"><span class="hub-h-ico i-lucide-toggle-right" />Recursos</h2>
          <div class="hub-crystal t-orange rounded-2xl p-4 flex items-center justify-between gap-3 mb-4">
            <div>
              <p class="text-sm font-bold text-n-slate-12">Mundo Boxe</p>
              <p class="text-[11px] text-n-slate-10">
                Aba de treino de boxe (sequências, rounds, tempo) e os gráficos dele nas Análises.
                Desligado, ninguém vê. Ligado, aparece pra quem tiver o módulo abaixo.
              </p>
            </div>
            <button class="hub-toggle shrink-0" :class="{ 'is-on': boxingOn }" role="switch" :aria-checked="boxingOn" @click="boxingOn = !boxingOn">
              <span class="hub-toggle-knob" />
            </button>
          </div>
          <button class="h-10 px-5 rounded-xl text-sm font-bold text-white disabled:opacity-60" style="background: linear-gradient(135deg, #27408b, #4169e1)" :disabled="isSaving" @click="save">
            {{ isSaving ? 'Salvando…' : 'Salvar recursos' }}
          </button>
        </div>

        <!-- acessos por pessoa -->
        <div class="hub-block p-5 mb-8">
          <h2 class="hub-h2 mb-1"><span class="hub-h-ico i-lucide-shield-check" />Acessos por pessoa</h2>
          <p class="text-[11px] text-n-slate-10 mb-4">
            Ligue "Saúde" pra pessoa entrar no mundo Saúde e escolha os módulos que ela vê. Meu Painel é de todo mundo. Salva sozinho a cada toque.
          </p>
          <p v-if="!people.length" class="text-xs text-n-slate-10">Ainda não há outras pessoas na conta. Convide em Configurações → Agentes.</p>
          <div v-for="a in people" :key="a.id" class="hub-crystal t-royal rounded-2xl p-4 mb-3" :class="{ 'opacity-60': busyUser === a.id }">
            <div class="flex items-center justify-between gap-3 flex-wrap mb-3">
              <div class="min-w-0">
                <p class="text-sm font-bold text-n-slate-12 truncate">{{ a.name }}</p>
                <p class="text-[11px] text-n-slate-10 truncate">{{ a.email }}</p>
              </div>
              <label class="flex items-center gap-2 text-xs font-bold text-n-slate-11 cursor-pointer">
                Saúde
                <button class="hub-toggle" :class="{ 'is-on': hasHealth(a) }" role="switch" :aria-checked="hasHealth(a)" @click="toggleHealth(a)">
                  <span class="hub-toggle-knob" />
                </button>
              </label>
            </div>
            <div class="flex flex-wrap gap-1.5" :class="{ 'opacity-40 pointer-events-none': !hasHealth(a) }">
              <button
                v-for="m in HEALTH_MODULES"
                :key="m.key"
                class="hub-tag"
                :class="{ 'is-on': moduleOn(a, m.key) }"
                :title="m.key === 'boxe' && !boxingOn ? 'Boxe está desligado nos recursos' : ''"
                @click="toggleModule(a, m.key)"
              >
                <span :class="m.icon" class="hub-ico" style="width: 13px; height: 13px" />{{ m.label }}
              </button>
              <button class="hub-tag" @click="allOn(a)">todos</button>
            </div>
          </div>
          <p v-if="admins.length" class="text-[11px] text-n-slate-10 mt-2">
            Administradores ({{ admins.map(x => x.name.split(' ')[0]).join(', ') }}) veem tudo.
          </p>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* chavinha iOS: trilho que desliza — royal quando ligada */
.hub-toggle { width: 3.1rem; height: 1.85rem; border-radius: 9999px; background: rgba(127, 127, 127, 0.35); padding: 3px; transition: background 0.2s ease; display: inline-flex; align-items: center; }
.hub-toggle.is-on { background: #4169e1; }
.hub-toggle-knob { width: 1.45rem; height: 1.45rem; border-radius: 9999px; background: #fff; box-shadow: 0 1px 3px rgba(0, 0, 0, 0.35); transition: transform 0.2s ease; }
.hub-toggle.is-on .hub-toggle-knob { transform: translateX(1.25rem); }
</style>
