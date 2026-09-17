<script setup>
// 📞 Configuração das LIGAÇÕES (WhatsApp) — item 167. Sub-página de
// Integrações (mesmo molde do MetaAds.vue): formulário ligado a
// settings.calls (crm/getSettings), "Ativar ligações na Meta" (mostra a
// resposta/erro cru da Meta para o técnico), painel "Estado na Meta" e o
// salvar via crm/updateCalls. Caixa: só WhatsApp Cloud; quem atende: lista
// de atendentes (vazio = todos os membros da caixa).
import { ref, computed, onMounted, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const settings = useMapGetter('crm/getSettings');
const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');

const DEFAULT_PERMISSION_MESSAGE =
  'Olá! Podemos te ligar pelo WhatsApp para falar sobre o seu atendimento? Toque em permitir para autorizar.';

const form = ref({
  enabled: false,
  inbox_id: null,
  ring_user_ids: [],
  business_hours_only: true,
  hours: { start: '08:00', end: '19:00' },
  record: true,
  transcribe: true,
  permission_message: DEFAULT_PERMISSION_MESSAGE,
});

const callsConfig = computed(() => settings.value?.calls ?? {});
const isLoading = ref(true);
const isSaving = ref(false);
const isEnabling = ref(false);
const isCheckingMeta = ref(false);
const enableResult = ref(null); // { ok, meta, error }
const metaStatus = ref(null); // GET calls_meta_status
const metaStatusError = ref('');

const fillForm = () => {
  const c = callsConfig.value || {};
  form.value = {
    enabled: Boolean(c.enabled),
    inbox_id: c.inbox_id || null,
    ring_user_ids: Array.isArray(c.ring_user_ids)
      ? c.ring_user_ids.map(Number)
      : [],
    business_hours_only: c.business_hours_only !== false,
    hours: {
      start: c.hours?.start || '08:00',
      end: c.hours?.end || '19:00',
    },
    record: c.record !== false,
    transcribe: c.transcribe !== false,
    permission_message: c.permission_message || DEFAULT_PERMISSION_MESSAGE,
  };
};

const whatsappInboxes = computed(() =>
  (inboxes.value || []).filter(
    i =>
      i.channel_type === 'Channel::Whatsapp' && i.provider === 'whatsapp_cloud'
  )
);
const agentList = computed(() =>
  [...(agents.value || [])].sort((a, b) =>
    String(a.name || '').localeCompare(String(b.name || ''), 'pt-BR')
  )
);

const toggleAgent = id => {
  const n = Number(id);
  const list = form.value.ring_user_ids;
  form.value.ring_user_ids = list.includes(n)
    ? list.filter(x => x !== n)
    : [...list, n];
};

const checkMetaStatus = async () => {
  if (!form.value.inbox_id || isCheckingMeta.value) return;
  isCheckingMeta.value = true;
  metaStatusError.value = '';
  try {
    // { ok, meta: { calling_status, callback_permission_status, checked_at, error }, health: { messaging_limit_tier, quality_rating } }
    const result = await store.dispatch('crm/callsMetaStatus');
    if (result?.ok === false) {
      metaStatus.value = null;
      metaStatusError.value = result.error || 'A Meta não respondeu.';
      return;
    }
    metaStatus.value = result;
  } catch (error) {
    metaStatus.value = null;
    metaStatusError.value =
      error?.response?.data?.error || 'Não consegui consultar a Meta agora.';
  } finally {
    isCheckingMeta.value = false;
  }
};

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('crm/fetchSettings'),
      store.dispatch('agents/get'),
      store.dispatch('inboxes/get'),
    ]);
  } catch {
    // a tela abre mesmo assim, com o que tiver
  }
  fillForm();
  isLoading.value = false;
  if (form.value.inbox_id) checkMetaStatus();
});
watch(callsConfig, () => {
  if (!isSaving.value && !isEnabling.value) fillForm();
});

const payload = () => ({
  enabled: form.value.enabled,
  inbox_id: form.value.inbox_id ? Number(form.value.inbox_id) : null,
  ring_user_ids: form.value.ring_user_ids,
  business_hours_only: form.value.business_hours_only,
  hours: { ...form.value.hours },
  record: form.value.record,
  transcribe: form.value.transcribe,
  permission_message: form.value.permission_message.trim(),
});

const save = async () => {
  if (form.value.enabled && !form.value.inbox_id) {
    useAlert('Escolha a caixa de WhatsApp que vai receber as ligações.');
    return;
  }
  isSaving.value = true;
  try {
    await store.dispatch('crm/updateCalls', payload());
    useAlert('Configurações das ligações salvas!');
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Erro ao salvar. Tente novamente.'
    );
  } finally {
    isSaving.value = false;
  }
};

// liga na Meta (calling ENABLED + callback ENABLED) e mostra a resposta crua
const enableAtMeta = async () => {
  if (!form.value.inbox_id) {
    useAlert('Escolha a caixa de WhatsApp antes de ativar na Meta.');
    return;
  }
  isEnabling.value = true;
  enableResult.value = null;
  try {
    // salva antes, para o backend saber a caixa
    await store.dispatch('crm/updateCalls', payload());
    const result = await store.dispatch('crm/enableCallsAtMeta');
    enableResult.value = result;
    if (result?.ok) {
      useAlert('Ligações ativadas na Meta!');
      checkMetaStatus();
    }
  } catch (error) {
    enableResult.value = {
      ok: false,
      error:
        error?.response?.data?.error ||
        error?.message ||
        'Erro inesperado ao falar com a Meta.',
      meta: error?.response?.data?.meta || null,
    };
  } finally {
    isEnabling.value = false;
  }
};

const pretty = value => {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
};

const META_ON = ['ENABLED', 'enabled', true];
const metaOn = v => META_ON.includes(v);
const liveMeta = computed(
  () => metaStatus.value?.meta || callsConfig.value?.meta || {}
);
const metaCalling = computed(() => liveMeta.value.calling_status);
const metaCallback = computed(() => liveMeta.value.callback_permission_status);
const metaTier = computed(() => metaStatus.value?.health?.messaging_limit_tier);
const metaQuality = computed(() => metaStatus.value?.health?.quality_rating);
const metaCheckedAt = computed(() => liveMeta.value.checked_at);
const fmtDate = ts =>
  ts
    ? new Date(ts).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';

const inputClass =
  'w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand';
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    loading-message="Carregando as ligações…"
  >
    <template #header>
      <BaseSettingsHeader
        title="Ligações (WhatsApp)"
        description="Receba e faça ligações de voz pelo WhatsApp direto na tela da conversa — com gravação, transcrição e o card da chamada no histórico do paciente."
        link-text=""
        feature-name="integrations"
      />
    </template>

    <template #body>
      <div class="max-w-2xl space-y-8">
        <!-- Status -->
        <div
          class="flex items-center gap-3 px-4 py-3 rounded-xl border"
          :class="
            callsConfig.enabled && metaOn(metaCalling)
              ? 'bg-green-500/8 border-green-500/20 text-green-700'
              : 'bg-n-alpha-1 border-n-weak text-n-slate-10'
          "
        >
          <span class="i-lucide-phone-call text-base flex-shrink-0" />
          <span class="text-sm font-medium">
            <template v-if="callsConfig.enabled && metaOn(metaCalling)">
              Ligações ativas — a clínica recebe e faz chamadas pelo WhatsApp
            </template>
            <template v-else-if="callsConfig.enabled">
              Ligado aqui, mas a Meta ainda não confirmou — use "Ativar ligações
              na Meta"
            </template>
            <template v-else>Ligações desligadas</template>
          </span>
        </div>

        <!-- Formulário -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5"
        >
          <div class="flex items-center gap-3 mb-1">
            <span
              class="w-10 h-10 rounded-xl flex items-center justify-center border border-n-weak flex-shrink-0"
              style="background: rgba(37, 211, 102, 0.12); color: #128c7e"
            >
              <span class="i-lucide-phone text-lg" />
            </span>
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">
                Como as ligações funcionam aqui
              </h3>
              <p class="text-xs text-n-slate-10">
                Quem atende, horário, gravação e o pedido de permissão
              </p>
            </div>
          </div>

          <!-- Ativar -->
          <label class="flex items-start gap-3 cursor-pointer">
            <input v-model="form.enabled" type="checkbox" class="mt-1" />
            <span>
              <span class="text-sm font-medium text-n-slate-12 block">
                Ativar ligações
              </span>
              <span class="text-xs text-n-slate-10">
                Liga o módulo nesta conta. Depois de salvar, ative também na
                Meta (botão abaixo).
              </span>
            </span>
          </label>

          <!-- Caixa -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Caixa de WhatsApp <span class="text-red-500">*</span>
            </label>
            <select
              v-model="form.inbox_id"
              :class="inputClass"
              @change="checkMetaStatus"
            >
              <option :value="null">Escolha a caixa…</option>
              <option v-for="i in whatsappInboxes" :key="i.id" :value="i.id">
                {{ i.name
                }}<template v-if="i.phone_number">
                  · {{ i.phone_number }}
                </template>
              </option>
            </select>
            <p class="text-xs text-n-slate-9 mt-1">
              Só caixas do WhatsApp Cloud (API oficial da Meta) podem receber
              ligações.
              <template v-if="!whatsappInboxes.length">
                Nenhuma encontrada nesta conta.
              </template>
            </p>
          </div>

          <!-- Quem atende -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Quem atende as ligações
            </label>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="a in agentList"
                :key="a.id"
                type="button"
                class="text-xs px-2.5 py-1 rounded-full border transition-colors"
                :class="
                  form.ring_user_ids.includes(Number(a.id))
                    ? 'bg-n-brand text-white border-n-brand'
                    : 'border-n-weak text-n-slate-11 hover:border-n-brand/40'
                "
                @click="toggleAgent(a.id)"
              >
                {{ a.name }}
              </button>
            </div>
            <p class="text-xs text-n-slate-9 mt-1">
              <template v-if="!form.ring_user_ids.length">
                Ninguém marcado = toca para todos os membros da caixa.
              </template>
              <template v-else>
                Toca só para {{ form.ring_user_ids.length }} atendente(s)
                marcado(s). Quem está "offline" não ouve tocar.
              </template>
            </p>
          </div>

          <!-- Horário -->
          <div class="space-y-2">
            <label class="flex items-start gap-3 cursor-pointer">
              <input
                v-model="form.business_hours_only"
                type="checkbox"
                class="mt-1"
              />
              <span>
                <span class="text-sm font-medium text-n-slate-12 block">
                  Só no horário de atendimento
                </span>
                <span class="text-xs text-n-slate-10">
                  Fora do horário a chamada é recusada na hora e vira "chamada
                  perdida · fora do horário" na conversa.
                </span>
              </span>
            </label>
            <div
              v-if="form.business_hours_only"
              class="flex items-center gap-2 pl-7"
            >
              <input
                v-model="form.hours.start"
                type="time"
                :class="inputClass"
                style="width: 8rem"
              />
              <span class="text-xs text-n-slate-9"> até </span>
              <input
                v-model="form.hours.end"
                type="time"
                :class="inputClass"
                style="width: 8rem"
              />
            </div>
          </div>

          <!-- Gravar / transcrever -->
          <label class="flex items-start gap-3 cursor-pointer">
            <input v-model="form.record" type="checkbox" class="mt-1" />
            <span>
              <span class="text-sm font-medium text-n-slate-12 block">
                Gravar as chamadas
              </span>
              <span class="text-xs text-n-slate-10">
                O navegador da atendente grava os dois lados e salva o áudio no
                card da conversa.
              </span>
            </span>
          </label>
          <label class="flex items-start gap-3 cursor-pointer">
            <input
              v-model="form.transcribe"
              type="checkbox"
              class="mt-1"
              :disabled="!form.record"
            />
            <span>
              <span class="text-sm font-medium text-n-slate-12 block">
                Transcrever e resumir com IA
              </span>
              <span class="text-xs text-n-slate-10">
                Usa a chave do Gemini de Integrações → IA. Sem chave, a
                transcrição fica "pulada".
              </span>
            </span>
          </label>

          <!-- Mensagem de permissão -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Pedido de permissão para ligar
            </label>
            <textarea
              v-model="form.permission_message"
              rows="3"
              :class="inputClass"
            />
            <p class="text-xs text-n-slate-9 mt-1">
              A Meta exige que o paciente autorize antes de a clínica ligar.
              Esse texto vai junto com o botão de permissão no WhatsApp dele.
            </p>
          </div>

          <div class="flex items-center gap-3 flex-wrap pt-1">
            <button
              class="px-4 py-2 rounded-lg text-sm font-semibold text-white bg-n-brand hover:opacity-90 disabled:opacity-50"
              :disabled="isSaving"
              @click="save"
            >
              {{ isSaving ? 'Salvando…' : 'Salvar' }}
            </button>
            <button
              class="px-4 py-2 rounded-lg text-sm font-semibold text-white disabled:opacity-50 flex items-center gap-1.5"
              style="background: linear-gradient(135deg, #128c7e, #25d366)"
              :disabled="isEnabling || !form.inbox_id"
              title="Liga o recurso de chamadas no número, lá na Meta"
              @click="enableAtMeta"
            >
              <span
                :class="
                  isEnabling ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-zap'
                "
                class="text-sm"
              />
              {{
                isEnabling ? 'Falando com a Meta…' : 'Ativar ligações na Meta'
              }}
            </button>
          </div>

          <!-- Resultado da Meta (cru, para o técnico) -->
          <div
            v-if="enableResult"
            class="rounded-lg border px-3 py-2.5 text-sm space-y-2"
            :class="
              enableResult.ok
                ? 'bg-green-500/10 text-green-700 border-green-500/20'
                : 'bg-red-500/10 text-red-700 border-red-500/20'
            "
          >
            <p class="flex items-start gap-2">
              <span
                class="text-base flex-shrink-0 mt-0.5"
                :class="
                  enableResult.ok
                    ? 'i-lucide-check-circle'
                    : 'i-lucide-alert-circle'
                "
              />
              <span>
                <template v-if="enableResult.ok">
                  Ligações ativadas na Meta.
                </template>
                <template v-else>{{
                  enableResult.error || 'A Meta recusou a ativação.'
                }}</template>
              </span>
            </p>
            <p v-if="!enableResult.ok" class="text-xs">
              Dica: a Meta exige limite de 2.000 mensagens/dia ou mais neste
              número.
            </p>
            <div
              v-if="
                enableResult.meta || (!enableResult.ok && enableResult.error)
              "
              class="text-[11px] font-mono whitespace-pre-wrap break-words rounded-md bg-black/5 dark:bg-white/5 p-2 text-n-slate-12 max-h-64 overflow-auto"
            >
              {{ pretty(enableResult.meta || enableResult.error) }}
            </div>
          </div>
        </div>

        <!-- Estado na Meta -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-3"
        >
          <div class="flex items-center gap-2">
            <h3
              class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
            >
              <span class="i-lucide-radio text-base text-n-slate-10" />
              Estado na Meta
            </h3>
            <button
              class="ml-auto text-xs font-medium px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:text-n-brand hover:border-n-brand/40 disabled:opacity-50 flex items-center gap-1"
              :disabled="isCheckingMeta || !form.inbox_id"
              @click="checkMetaStatus"
            >
              <span
                :class="
                  isCheckingMeta
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-refresh-cw'
                "
                class="text-xs"
              />
              Consultar agora
            </button>
          </div>
          <p v-if="!form.inbox_id" class="text-xs text-n-slate-9">
            Escolha a caixa para consultar.
          </p>
          <p v-else-if="metaStatusError" class="text-xs text-red-600">
            {{ metaStatusError }}
          </p>
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
            <div class="rounded-lg bg-n-alpha-1 px-3 py-2">
              <p class="text-n-slate-9">Chamadas (calling)</p>
              <p
                class="font-semibold"
                :class="
                  metaOn(metaCalling) ? 'text-green-600' : 'text-n-slate-12'
                "
              >
                {{ pretty(metaCalling) }}
              </p>
            </div>
            <div class="rounded-lg bg-n-alpha-1 px-3 py-2">
              <p class="text-n-slate-9">Permissão de retorno (callback)</p>
              <p
                class="font-semibold"
                :class="
                  metaOn(metaCallback) ? 'text-green-600' : 'text-n-slate-12'
                "
              >
                {{ pretty(metaCallback) }}
              </p>
            </div>
            <div class="rounded-lg bg-n-alpha-1 px-3 py-2">
              <p class="text-n-slate-9">Limite de mensagens/dia</p>
              <p class="font-semibold text-n-slate-12">
                {{ pretty(metaTier) }}
              </p>
            </div>
            <div class="rounded-lg bg-n-alpha-1 px-3 py-2">
              <p class="text-n-slate-9">Qualidade do número</p>
              <p class="font-semibold text-n-slate-12">
                {{ pretty(metaQuality) }}
              </p>
            </div>
          </div>
          <p v-if="form.inbox_id" class="text-[11px] text-n-slate-9">
            Última consulta: {{ fmtDate(metaCheckedAt) }}
            <template v-if="callsConfig.meta?.error">
              · último erro: {{ callsConfig.meta.error }}
            </template>
          </p>
        </div>

        <!-- Como usar -->
        <div class="bg-n-alpha-1 rounded-2xl p-6 space-y-3">
          <h4
            class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
          >
            <span class="i-lucide-lightbulb text-yellow-500" />
            Como usar
          </h4>
          <ol
            class="space-y-2 text-sm text-n-slate-11 list-decimal list-inside"
          >
            <li>Escolha a caixa, marque quem atende e salve.</li>
            <li>
              Clique em <strong>Ativar ligações na Meta</strong> — o número
              precisa de limite de 2.000 mensagens/dia ou mais.
            </li>
            <li>
              Quando o paciente ligar, o card aparece no canto da tela de quem
              está online: <strong>Atender</strong> ou <strong>Recusar</strong>.
            </li>
            <li>
              Para ligar, abra a conversa e use <strong>Ligar</strong> no painel
              — se a Meta pedir, envie o pedido de permissão.
            </li>
            <li>
              Ao desligar, a gravação e a transcrição aparecem no card da
              chamada na conversa.
            </li>
          </ol>
          <div
            class="flex items-start gap-2 px-3 py-2.5 bg-yellow-500/8 border border-yellow-400/20 rounded-lg mt-3"
          >
            <span
              class="i-lucide-shield text-yellow-500 flex-shrink-0 mt-0.5"
            />
            <p class="text-xs text-n-slate-11">
              O navegador pede acesso ao <strong>microfone</strong> na primeira
              chamada. Libere para a atendente conseguir falar.
            </p>
          </div>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
