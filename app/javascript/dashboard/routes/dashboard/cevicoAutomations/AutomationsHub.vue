<script setup>
import { ref, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import FollowupBotModal from 'dashboard/routes/dashboard/crm/components/FollowupBotModal.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();

const inboxes = useMapGetter('inboxes/getInboxes');

const activeTab = ref(route.query.tab === 'robos' ? 'robos' : 'reguas');

// ── Réguas de mensagem (mesmo motor da Campanha WhatsApp) ──
const automations = ref([]);
const loadingReguas = ref(true);

const loadReguas = async () => {
  loadingReguas.value = true;
  try {
    automations.value = await store.dispatch('crm/fetchMessageAutomations');
  } catch {
    useAlert('Erro ao carregar réguas');
  } finally {
    loadingReguas.value = false;
  }
};

const toggleRegua = async a => {
  try {
    await store.dispatch('crm/updateMessageAutomation', { id: a.id, active: !a.active });
    a.active = !a.active;
  } catch {
    useAlert('Erro ao atualizar');
  }
};

const deleteRegua = async a => {
  try {
    await store.dispatch('crm/deleteMessageAutomation', a.id);
    automations.value = automations.value.filter(x => x.id !== a.id);
    useAlert('Régua excluída');
  } catch {
    useAlert('Erro ao excluir');
  }
};

const goToCampaign = () => {
  router.push({ name: 'crm_campaigns', params: { accountId: accountId.value } });
};

// ── Robôs de follow-up ──
const bots = ref([]);
const loadingBots = ref(true);

const loadBots = async () => {
  loadingBots.value = true;
  try {
    bots.value = await store.dispatch('crm/fetchFollowupBots');
  } catch {
    useAlert('Erro ao carregar robôs');
  } finally {
    loadingBots.value = false;
  }
};

const showBotModal = ref(false);
const editingBot = ref(null);

const openCreateBot = () => { editingBot.value = null; showBotModal.value = true; };
const openEditBot = bot => { editingBot.value = bot; showBotModal.value = true; };
const onBotSaved = async () => { showBotModal.value = false; editingBot.value = null; await loadBots(); };

const toggleBot = async bot => {
  try {
    const data = await store.dispatch('crm/updateFollowupBot', { id: bot.id, active: !bot.active });
    bot.active = data.active;
  } catch {
    useAlert('Erro ao atualizar');
  }
};

const deleteBotConfirmId = ref(null);
const deleteBot = async bot => {
  try {
    await store.dispatch('crm/deleteFollowupBot', bot.id);
    bots.value = bots.value.filter(b => b.id !== bot.id);
    deleteBotConfirmId.value = null;
    useAlert('Robô excluído');
  } catch {
    useAlert('Erro ao excluir');
  }
};

const delayLabel = step => {
  const hours = step.delay_value != null
    ? Number(step.delay_value) * (step.delay_unit === 'days' ? 24 : 1)
    : Number(step.delay_hours);
  if (hours < 1) return `${Math.round(hours * 60)}min`;
  if (hours < 24) return `${hours}h`;
  return `${Math.round(hours / 24)}d`;
};

onMounted(() => {
  if (!inboxes.value.length) store.dispatch('inboxes/get');
  loadReguas();
  loadBots();
});
</script>

<template>
  <div class="bg-n-surface-1 flex flex-col h-full w-full">
    <!-- Header -->
    <div class="px-6 py-4 border-b border-n-weak flex-shrink-0">
      <h1 class="text-lg font-semibold text-n-slate-12">Automações & Robôs</h1>
      <p class="text-xs text-n-slate-10 mt-0.5">
        Réguas de mensagem e robôs de follow-up — o mesmo motor da Campanha WhatsApp, num só lugar.
      </p>
      <!-- Tabs -->
      <div class="flex gap-1 mt-3">
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors"
          :class="activeTab === 'reguas' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="activeTab = 'reguas'"
        >Réguas de mensagem</button>
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors"
          :class="activeTab === 'robos' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="activeTab = 'robos'"
        >Robôs de follow-up</button>
      </div>
    </div>

    <div class="flex-1 overflow-y-auto p-6">
      <!-- ══ RÉGUAS ══ -->
      <div v-if="activeTab === 'reguas'" class="max-w-3xl">
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-n-slate-11">Envios automáticos por etiqueta/coluna após X dias.</p>
          <button
            class="text-sm px-3 py-2 rounded-lg bg-n-brand text-white hover:bg-n-brand/90 flex items-center gap-1.5"
            @click="goToCampaign"
          >
            <span class="i-lucide-external-link text-sm" />
            Criar/editar na Campanha
          </button>
        </div>

        <div v-if="loadingReguas" class="flex justify-center py-10"><Spinner :size="28" class="text-n-brand" /></div>
        <div v-else-if="!automations.length" class="text-center py-12 text-n-slate-10">
          <span class="i-lucide-timer text-4xl mb-2 block mx-auto" />
          <p class="text-sm">Nenhuma régua criada ainda.</p>
        </div>
        <div v-else class="space-y-2">
          <div
            v-for="a in automations"
            :key="a.id"
            class="flex items-center gap-3 p-3 bg-n-solid-2 border border-n-weak rounded-xl"
          >
            <span
              class="w-2 h-2 rounded-full flex-shrink-0"
              :class="a.active ? 'bg-green-500' : 'bg-n-slate-9'"
            />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">{{ a.name }}</p>
              <p class="text-xs text-n-slate-10 truncate">
                {{ a.inbox_name }} ·
                {{ a.trigger_label ? `etiqueta "${a.trigger_label}"` : '' }}
                {{ a.trigger_stage_name ? `coluna "${a.trigger_stage_name}"` : '' }}
                · {{ a.delay_days }}d
              </p>
            </div>
            <button
              class="text-xs px-2 py-1 rounded-lg border border-n-weak"
              :class="a.active ? 'text-yellow-600' : 'text-green-600'"
              @click="toggleRegua(a)"
            >{{ a.active ? 'Pausar' : 'Ativar' }}</button>
            <button class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm" @click="deleteRegua(a)" />
          </div>
        </div>
      </div>

      <!-- ══ ROBÔS ══ -->
      <div v-else class="max-w-3xl">
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-n-slate-11">
            Cutucadas simples para reabrir a conversa quando o paciente some. Ex.: 3h "oi, pode falar?",
            10h "[nome], no seu tempo ok?". Para sozinho se o paciente responder.
          </p>
          <button
            class="text-sm px-3 py-2 rounded-lg bg-n-brand text-white hover:bg-n-brand/90 flex items-center gap-1.5 flex-shrink-0"
            @click="openCreateBot"
          >
            <span class="i-lucide-plus text-sm" />
            Novo robô
          </button>
        </div>

        <div v-if="loadingBots" class="flex justify-center py-10"><Spinner :size="28" class="text-n-brand" /></div>
        <div v-else-if="!bots.length" class="text-center py-12 text-n-slate-10">
          <span class="i-lucide-bot text-4xl mb-2 block mx-auto" />
          <p class="text-sm">Nenhum robô criado ainda.</p>
        </div>
        <div v-else class="space-y-3">
          <div v-for="bot in bots" :key="bot.id" class="p-4 bg-n-solid-2 border border-n-weak rounded-xl">
            <div class="flex items-center gap-2 mb-2">
              <span class="w-2 h-2 rounded-full flex-shrink-0" :class="bot.active ? 'bg-green-500' : 'bg-n-slate-9'" />
              <p class="text-sm font-semibold text-n-slate-12 flex-1 truncate">{{ bot.name }}</p>
              <span class="text-xs text-n-slate-10">{{ bot.inbox_name }}</span>
              <button
                class="text-xs px-2 py-1 rounded-lg border border-n-weak ml-1"
                :class="bot.active ? 'text-yellow-600' : 'text-green-600'"
                @click="toggleBot(bot)"
              >{{ bot.active ? 'Pausar' : 'Ativar' }}</button>
              <button class="text-n-slate-9 hover:text-n-brand i-lucide-pencil text-sm" @click="openEditBot(bot)" />
              <button
                v-if="deleteBotConfirmId !== bot.id"
                class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm"
                @click="deleteBotConfirmId = bot.id"
              />
              <button v-else class="text-xs text-red-500" @click="deleteBot(bot)">Confirmar</button>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <span
                v-for="(s, i) in bot.steps"
                :key="i"
                class="text-[11px] bg-n-alpha-2 text-n-slate-11 rounded-full px-2 py-0.5"
              >
                {{ delayLabel(s) }}: {{ s.template_params ? `📋 ${s.template_params.name}` : `"${s.message}"` }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal robô (componente compartilhado) -->
    <FollowupBotModal
      v-if="showBotModal"
      :bot="editingBot"
      @close="showBotModal = false"
      @saved="onBotSaved"
    />
  </div>
</template>
