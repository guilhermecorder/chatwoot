<script setup>
// 💸 GASTO DO WHATSAPP (item 303, 30/09/2026 — só admin). Em 01/10/2026 a
// Meta passa a cobrar TODA mensagem enviada (inclusive as respostas dentro
// das 24h). Esta tela mostra, no formato do kit:
//   • a FATURA da Meta (o que ela diz que cobrou, na moeda da conta);
//   • QUEM gastou (Atendente de IA, follow-up, lembretes, cada pessoa) —
//     custo estimado pelas tarifas, porque a Meta marca a categoria em cada
//     mensagem mas não o valor;
//   • a régua da regra de outubro (quanto custaria se ela já valesse);
//   • dia a dia, por caixa, por categoria, tarifas editáveis e a legenda.
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const isSyncing = ref(false);
const isSavingRates = ref(false);
const data = ref(null);
const period = ref({ preset: 'last7', from: '', to: '' });
// 📋 Lista | 🃏 Cards (padrão 25/09: toda listagem com as duas visões)
const whoView = ref('list');

const pal = useCevicoPalette({
  scope: 'report:whatsapp_spend',
  blocks: [
    { id: 'fatura', label: 'Conta da Meta', icon: 'i-lucide-receipt' },
    { id: 'regra', label: 'Regra de outubro', icon: 'i-lucide-calendar-clock' },
    { id: 'quem', label: 'Quem gastou', icon: 'i-lucide-users' },
    { id: 'dia', label: 'Dia a dia', icon: 'i-lucide-activity' },
    {
      id: 'caixas',
      label: 'Por caixa e por categoria',
      icon: 'i-lucide-inbox',
    },
    { id: 'tarifas', label: 'Tarifas', icon: 'i-lucide-tag' },
    { id: 'leitura', label: 'Como ler', icon: 'i-lucide-info' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

const periodParams = () => ({
  preset: period.value.preset,
  ...(period.value.preset === 'custom'
    ? { from: period.value.from, to: period.value.to }
    : {}),
});

// tarifas editáveis (bloco Tarifas) — nasce com o que o servidor devolve
const ratesForm = ref({});

const load = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getWhatsappSpend(periodParams());
    data.value = payload;
    ratesForm.value = { ...payload.rates };
  } catch {
    useAlert('Não consegui carregar o gasto do WhatsApp.');
  } finally {
    isLoading.value = false;
  }
};
watch(period, load, { deep: true });
onMounted(load);

const meta = computed(() => data.value?.meta || {});
const att = computed(() => data.value?.attributed || {});
const rates = computed(() => data.value?.rates || {});
const currency = computed(
  () => meta.value.currency || rates.value.currency || 'BRL'
);

// ── formatação ──
const fmtNum = v => Number(v || 0).toLocaleString('pt-BR');
const money = (v, cur = currency.value, digits = 2) => {
  const n = Number(v || 0);
  const prefix = { BRL: 'R$', USD: 'US$' }[cur] || cur;
  return `${prefix} ${n.toLocaleString('pt-BR', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })}`;
};
const fmtRate = v => money(v, rates.value.currency, 4);
const ago = iso => {
  if (!iso) return 'nunca';
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return 'agora mesmo';
  if (mins < 60) return `há ${mins} min`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `há ${hours}h`;
  return `há ${Math.floor(hours / 24)}d`;
};
const monthLabel = ym => {
  const [y, m] = ym.split('-');
  const names = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  return `${names[Number(m) - 1]}/${y.slice(2)}`;
};

// ── sincronizar com a Meta ──
const sync = async (days = 35) => {
  if (isSyncing.value) return;
  isSyncing.value = true;
  try {
    const { data: result } = await CrmAPI.syncWhatsappSpend(days);
    if (result.queued) {
      useAlert(
        `Pedi à Meta os últimos ${result.days} dias — chega em alguns minutos.`
      );
    } else if (result.ok) {
      useAlert(
        `Fatura da Meta atualizada: ${fmtNum(result.rows)} linha(s), ${result.from} a ${result.to}.`
      );
    } else {
      useAlert(result.error || 'A Meta não respondeu.');
    }
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui falar com a Meta.');
  } finally {
    isSyncing.value = false;
  }
};

// ── tarifas ──
const RATE_FIELDS = [
  {
    key: 'marketing',
    label: 'Marketing',
    hint: 'modelo fora das 24h com oferta/reativação (follow-up de lead sumido, campanhas)',
  },
  {
    key: 'utility',
    label: 'Utilidade',
    hint: 'modelo de aviso: confirmação D-2, lembrete, pós-op',
  },
  {
    key: 'authentication',
    label: 'Autenticação',
    hint: 'código de verificação (não usamos)',
  },
  {
    key: 'service',
    label: 'Serviço',
    hint: 'resposta livre do robô ou da equipe — paga a partir de 01/10/2026',
  },
];
const saveRates = async (reset = false) => {
  isSavingRates.value = true;
  try {
    const payload = reset ? {} : { ...ratesForm.value };
    delete payload.edited;
    const { data: result } = await CrmAPI.saveWhatsappRates(payload);
    ratesForm.value = { ...result.rates };
    useAlert(reset ? 'Tarifas de volta ao padrão da Meta.' : 'Tarifas salvas.');
    await load();
  } catch {
    useAlert('Não consegui salvar as tarifas.');
  } finally {
    isSavingRates.value = false;
  }
};

// ── conta da Meta ──
const CATEGORY_COLORS = {
  marketing: '#FF375F',
  utility: '#0A84FF',
  authentication: '#AF52DE',
  service: '#34C759',
};
const metaCategorySlices = computed(() =>
  (meta.value.by_category || []).map((c, i) => ({
    label: c.label,
    value: c.cost,
    color: CATEGORY_COLORS[c.category] || blockFamily('fatura')[i % 4],
  }))
);
const metaMonths = computed(() => (meta.value.months || []).slice(-12));
const metaMonthsMax = computed(() =>
  Math.max(0, ...metaMonths.value.map(m => Number(m.cost) || 0))
);

// ── quem gastou ──
const whoRows = computed(() => att.value.by_who || []);
const whoBars = computed(() =>
  whoRows.value
    .filter(r => r.messages > 0)
    .slice(0, 12)
    .map(r => ({
      key: r.key,
      label: r.label,
      sub: `${fmtNum(r.messages)} msg · ${fmtNum(r.billable)} cobrada(s)`,
      values: [r.cost],
      color: r.color,
    }))
);
// fatia pela REGRA DE 01/10 (simulated): antes dessa data é a projeção, depois
// é o custo real — só o custo de hoje deixaria o robô e a equipe em zero
const whoKinds = computed(() => {
  const acc = { robo: 0, automacao: 0, equipe: 0, sistema: 0 };
  whoRows.value.forEach(r => {
    acc[r.kind] = (acc[r.kind] || 0) + Number(r.simulated || 0);
  });
  return acc;
});
const kindSlices = computed(() =>
  [
    { key: 'robo', label: 'Atendentes de IA', color: '#059669' },
    {
      key: 'automacao',
      label: 'Lembretes, follow-up, jornada e campanhas',
      color: '#FF9F0A',
    },
    { key: 'equipe', label: 'Equipe (pessoas)', color: '#0A84FF' },
    { key: 'sistema', label: 'Sistema', color: '#8E8E93' },
  ]
    .map(k => ({ ...k, value: whoKinds.value[k.key] || 0 }))
    .filter(k => k.value > 0)
);

// ── dia a dia (atribuição por mensagem) ──
const daily = computed(() => att.value.daily || []);
const dayLabels = computed(() => {
  const n = daily.value.length;
  // muitos dias: só algumas datas para não colidir
  const step = n > 20 ? Math.ceil(n / 8) : 1;
  return daily.value.map((d, i) =>
    i % step === 0 || i === n - 1 ? d.label : ''
  );
});
const dailyCost = computed(() => daily.value.map(d => Number(d.cost) || 0));
const dailySimulated = computed(() =>
  daily.value.map(d => Number(d.simulated) || 0)
);
const dailyMessages = computed(() => daily.value.map(d => d.messages || 0));
const dayMode = ref('cost'); // cost | simulated | messages
const dayValues = computed(() => {
  if (dayMode.value === 'messages') return dailyMessages.value;
  if (dayMode.value === 'simulated') return dailySimulated.value;
  return dailyCost.value;
});
const dayFormat = v =>
  dayMode.value === 'messages' ? `${fmtNum(v)} msg` : money(v);
const busiestDay = computed(() => {
  const max = Math.max(0, ...dayValues.value);
  if (!max) return null;
  const i = dayValues.value.indexOf(max);
  return { label: daily.value[i]?.label, value: max };
});

// ── por caixa / por categoria ──
const inboxBars = computed(() =>
  (att.value.by_inbox || []).map((r, i) => ({
    key: r.inbox_id,
    label: r.name,
    sub: `${fmtNum(r.messages)} msg · ${fmtNum(r.billable)} cobrada(s)`,
    values: [r.cost],
    color: blockFamily('caixas')[i % 4],
  }))
);
const categoryBars = computed(() =>
  (att.value.by_category || []).map(r => ({
    key: r.category,
    label: r.label,
    sub: `${fmtNum(r.messages)} msg`,
    values: [r.cost],
    color: CATEGORY_COLORS[r.category] || '#8E8E93',
  }))
);

// ── regra de outubro ──
const serviceFrom = computed(() => {
  const iso = data.value?.service_charged_from;
  return iso
    ? new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR')
    : '01/10/2026';
});
const octoberExtra = computed(() =>
  Math.max(
    0,
    Number(att.value.simulated_october_cost || 0) - Number(att.value.cost || 0)
  )
);
// tintas do kit (a cor do bloco entra pela variável --cv-rgb)
const TINT_BG = { background: 'rgb(var(--cv-rgb) / 0.12)' };
const HAIRLINE_TOP = { borderTop: '1px solid rgb(var(--cv-rgb) / 0.16)' };
const balloons = computed(() => att.value.balloons || {});
const balloonSaving = computed(() => {
  // se cada resposta do robô fosse 1 balão: quantas mensagens a menos
  const b = balloons.value;
  if (!b.robot_replies) return 0;
  return Math.max(0, (b.robot_messages || 0) - b.robot_replies);
});
const pctKnown = computed(() => {
  const total = att.value.messages || 0;
  if (!total) return 0;
  return Math.round(((total - (att.value.unknown || 0)) * 100) / total);
});
</script>

<template>
  <div class="cv-page cv-overlay" :style="cvVars">
    <CevicoHero
      :pal="pal"
      title="Gasto do WhatsApp"
      subtitle="quanto a Meta cobra pelas mensagens · quem gastou · regra de 01/10/2026 · tarifas"
      icon="i-lucide-receipt"
    />

    <div class="flex items-center gap-3 flex-wrap mb-6">
      <PeriodRuler v-model="period" glass class="flex-1 min-w-0" />
      <button
        class="cv-btn cv-btn-sm flex-shrink-0"
        :disabled="isSyncing"
        title="Pede à Meta a fatura dos últimos 35 dias (pricing_analytics)"
        @click="sync(35)"
      >
        <span
          :class="
            isSyncing
              ? 'i-lucide-loader-circle animate-spin'
              : 'i-lucide-refresh-cw'
          "
          class="text-xs"
        />
        {{ isSyncing ? 'Falando com a Meta…' : 'Atualizar da Meta' }}
      </button>
    </div>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ CONTA DA META: o valor real ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('fatura')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon">
            <span class="i-lucide-receipt text-base" />
          </span>
          <h2 class="text-sm font-bold text-n-slate-12">Conta da Meta</h2>
          <span class="text-[11px] text-n-slate-9 ml-auto">
            <template v-if="meta.synced">
              última leitura da Meta:
              <b class="text-n-slate-11">{{ ago(meta.synced_at) }}</b> · moeda
              da conta: <b class="text-n-slate-11">{{ meta.currency }}</b>
            </template>
            <template v-else>ainda sem leitura da Meta</template>
          </span>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-4">
          o que a própria Meta diz que cobrou no período — é o número que bate
          com a fatura. A Meta fecha o dia com 1–2 dias de atraso.
        </p>

        <div
          v-if="!meta.synced"
          class="cv-sub px-4 py-3.5 flex items-center gap-3 flex-wrap"
        >
          <span class="cv-icon cv-icon-sm">
            <span class="i-lucide-info text-xs" />
          </span>
          <p class="text-xs text-n-slate-11 flex-1 min-w-0">
            Ainda não puxei a conta da Meta. Clique em <b>Atualizar da Meta</b>
            (35 dias) — ou peça os
            <button
              class="underline font-semibold"
              :disabled="isSyncing"
              @click="sync(450)"
            >
              últimos 15 meses
            </button>
            para ver o histórico inteiro.
          </p>
        </div>

        <template v-else>
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            <DashKpi
              compact
              glass
              label="Cobrado pela Meta"
              :value="money(meta.cost)"
              sub="no período, pela fatura"
              :grad="blockFamily('fatura')[0]"
            />
            <DashKpi
              compact
              glass
              label="Mensagens cobradas"
              :value="meta.billable_volume || 0"
              sub="entregues e pagas"
              :grad="blockFamily('fatura')[1]"
            />
            <DashKpi
              compact
              glass
              label="Grátis na janela de 24h"
              :value="meta.free_window_volume || 0"
              :sub="`acaba em ${serviceFrom}`"
              :grad="blockFamily('fatura')[2]"
            />
            <DashKpi
              compact
              glass
              label="Grátis pelo anúncio (72h)"
              :value="meta.free_ad_volume || 0"
              sub="lead do Clique-para-WhatsApp"
              :grad="blockFamily('fatura')[3]"
            />
          </div>

          <div class="grid grid-cols-1 xl:grid-cols-5 gap-4">
            <div class="xl:col-span-2 cv-sub p-4">
              <p class="text-xs font-bold text-n-slate-12 mb-0.5">
                Por categoria
              </p>
              <p class="text-[11px] text-n-slate-9 mb-3">
                fatia do valor cobrado · marketing custa ~9× utilidade
              </p>
              <ShareBar
                :items="metaCategorySlices"
                :format="v => money(v)"
                :height="16"
              />
              <p
                v-if="meta.by_phone?.length > 1"
                class="text-[11px] text-n-slate-9 mt-3"
              >
                por número:
                <template v-for="(p, i) in meta.by_phone" :key="p.phone">
                  <b class="text-n-slate-11">{{ p.inbox }}</b> {{ money(p.cost)
                  }}<span v-if="i < meta.by_phone.length - 1"> · </span>
                </template>
              </p>
            </div>
            <div class="xl:col-span-3 cv-sub p-4">
              <p class="text-xs font-bold text-n-slate-12 mb-0.5">
                Últimos meses na fatura
              </p>
              <p class="text-[11px] text-n-slate-9 mb-3">
                independe do período escolhido acima · peça
                <button
                  class="underline"
                  :disabled="isSyncing"
                  @click="sync(450)"
                >
                  15 meses
                </button>
                se os meses antigos estiverem vazios
              </p>
              <div v-if="metaMonths.length" class="space-y-1.5">
                <div
                  v-for="m in metaMonths"
                  :key="m.month"
                  class="flex items-center gap-2 text-[11px]"
                >
                  <span class="w-12 text-n-slate-9 tabular-nums">{{
                    monthLabel(m.month)
                  }}</span>
                  <div
                    class="flex-1 h-2.5 rounded-full overflow-hidden"
                    :style="TINT_BG"
                  >
                    <div
                      class="h-full rounded-full"
                      :style="{
                        width: `${metaMonthsMax ? Math.max(2, (m.cost / metaMonthsMax) * 100) : 0}%`,
                        background: blockFamily('fatura')[0],
                      }"
                    />
                  </div>
                  <span
                    class="w-24 text-right font-semibold text-n-slate-11 tabular-nums"
                  >
                    {{ money(m.cost) }}
                  </span>
                  <span class="w-16 text-right text-n-slate-9 tabular-nums">
                    {{ fmtNum(m.volume) }} msg
                  </span>
                </div>
              </div>
              <p v-else class="text-[11px] text-n-slate-9">
                sem meses na fatura ainda
              </p>
            </div>
          </div>
        </template>
      </div>

      <!-- ══ REGRA DE OUTUBRO ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('regra')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon">
            <span class="i-lucide-calendar-clock text-base" />
          </span>
          <h2 class="text-sm font-bold text-n-slate-12">
            Regra de {{ serviceFrom }}
          </h2>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-4">
          a partir dessa data toda mensagem enviada é cobrada, inclusive a
          resposta do robô ou da equipe dentro das 24h. Cada balão é uma
          cobrança.
        </p>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
          <DashKpi
            compact
            glass
            label="Custo estimado no período"
            :value="money(att.cost)"
            sub="mensagens marcadas como cobradas × tarifa"
            :grad="blockFamily('regra')[0]"
          />
          <DashKpi
            compact
            glass
            label="Se a regra de outubro valesse"
            :value="money(att.simulated_october_cost)"
            :sub="`+ ${money(octoberExtra)} das respostas na janela`"
            :grad="blockFamily('regra')[1]"
          />
          <DashKpi
            compact
            glass
            label="Balões por resposta do robô"
            :value="
              balloons.per_reply
                ? String(balloons.per_reply).replace('.', ',')
                : '—'
            "
            :sub="`${fmtNum(balloons.robot_messages)} balões em ${fmtNum(balloons.robot_replies)} respostas`"
            :grad="blockFamily('regra')[2]"
          />
          <div
            class="cv-tile rounded-2xl px-4 py-3 text-white shadow-lg"
            :style="{ background: blockFamily('regra')[3] }"
          >
            <p class="text-[11px] font-medium text-white/80 mb-1.5">
              Se o robô juntasse em 1 balão
            </p>
            <p class="text-base font-bold leading-tight">
              {{ fmtNum(balloonSaving) }} msg a menos
            </p>
            <p class="text-[10px] text-white/70 mt-1">
              ≈ {{ money(balloonSaving * Number(rates.service || 0)) }} no
              período
            </p>
          </div>
        </div>
      </div>

      <!-- ══ QUEM GASTOU ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('quem')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-users text-base" /></span>
          <h2 class="text-sm font-bold text-n-slate-12">Quem gastou</h2>
          <div class="ml-auto flex items-center gap-1">
            <button
              class="cv-btn cv-btn-sm"
              :class="whoView === 'list' ? '' : 'cv-btn-ghost'"
              @click="whoView = 'list'"
            >
              <span class="i-lucide-list text-xs" /> Lista
            </button>
            <button
              class="cv-btn cv-btn-sm"
              :class="whoView === 'cards' ? '' : 'cv-btn-ghost'"
              @click="whoView = 'cards'"
            >
              <span class="i-lucide-layout-grid text-xs" /> Cards
            </button>
          </div>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-3">
          custo estimado por quem enviou · {{ fmtNum(att.messages) }} mensagens
          saíram no período, {{ fmtNum(att.billable) }} cobradas,
          {{ fmtNum(att.free_window) }} grátis na janela,
          {{ fmtNum(att.free_ad) }} grátis pelo anúncio
          <template v-if="att.unknown">
            · <b class="text-n-slate-11">{{ fmtNum(att.unknown) }}</b> sem a
            marca da Meta (enviadas antes desta tela ou ainda não entregues) —
            {{ pctKnown }}% do período tem a marca
          </template>
        </p>

        <div class="cv-sub p-4 mb-4">
          <p class="text-xs font-bold text-n-slate-12 mb-0.5">
            Robô × automações × equipe
          </p>
          <p class="text-[11px] text-n-slate-9 mb-2">
            fatia do custo pela regra de {{ serviceFrom }} — a partir dessa data
            é o custo real
          </p>
          <ShareBar :items="kindSlices" :format="v => money(v)" :height="16" />
        </div>

        <HBars
          v-if="whoView === 'list'"
          :rows="whoBars"
          :series="[{ label: 'custo estimado', format: v => money(v) }]"
          :format="v => money(v)"
          :label-width="15"
          empty-text="nenhuma mensagem enviada no período"
        />
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3"
        >
          <div
            v-for="r in whoRows"
            :key="r.key"
            class="cv-sub cv-sub-hover p-4"
          >
            <div class="flex items-center gap-2.5 mb-2">
              <span
                class="cv-icon flex-shrink-0"
                :style="{ background: r.color }"
              >
                <span :class="r.icon" class="text-base" />
              </span>
              <div class="min-w-0 flex-1">
                <p
                  class="text-sm font-bold text-n-slate-12 leading-tight truncate"
                >
                  {{ r.label }}
                </p>
                <p class="text-[10px] text-n-slate-9">
                  {{
                    {
                      robo: 'atendente de IA',
                      automacao: 'automação',
                      equipe: 'pessoa da equipe',
                      sistema: 'sistema',
                    }[r.kind]
                  }}
                </p>
              </div>
            </div>
            <div class="grid grid-cols-3 gap-2">
              <div>
                <p class="text-lg font-bold leading-none text-n-slate-12">
                  {{ money(r.cost) }}
                </p>
                <p class="text-[9px] text-n-slate-9 mt-1">custo estimado</p>
              </div>
              <div>
                <p class="text-lg font-bold leading-none text-n-slate-12">
                  {{ fmtNum(r.messages) }}
                </p>
                <p class="text-[9px] text-n-slate-9 mt-1">mensagens</p>
              </div>
              <div>
                <p class="text-lg font-bold leading-none text-n-slate-12">
                  {{ fmtNum(r.billable) }}
                </p>
                <p class="text-[9px] text-n-slate-9 mt-1">cobradas</p>
              </div>
            </div>
            <p
              class="text-[10px] text-n-slate-9 mt-2 pt-2"
              :style="HAIRLINE_TOP"
            >
              grátis: {{ fmtNum(r.free_window) }} na janela ·
              {{ fmtNum(r.free_ad) }} pelo anúncio · com a regra de outubro:
              <b class="text-n-slate-11">{{ money(r.simulated) }}</b>
            </p>
          </div>
        </div>
      </div>

      <!-- ══ DIA A DIA + POR CAIXA / CATEGORIA ══ -->
      <div class="grid grid-cols-1 xl:grid-cols-5 gap-4 mb-4">
        <div
          class="xl:col-span-3 cv-block p-5 sm:p-6"
          :style="blockVars('dia')"
        >
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon">
              <span class="i-lucide-activity text-base" />
            </span>
            <h2 class="text-sm font-bold text-n-slate-12">Dia a dia</h2>
            <div class="ml-auto flex items-center gap-1">
              <button
                v-for="m in [
                  { k: 'cost', l: 'custo' },
                  { k: 'simulated', l: 'regra de out.' },
                  { k: 'messages', l: 'mensagens' },
                ]"
                :key="m.k"
                class="cv-btn cv-btn-sm"
                :class="dayMode === m.k ? '' : 'cv-btn-ghost'"
                @click="dayMode = m.k"
              >
                {{ m.l }}
              </button>
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-3">
            pela marca da Meta em cada mensagem
            <template v-if="busiestDay">
              · dia mais caro:
              <b class="text-n-slate-11">{{ busiestDay.label }}</b> ({{
                dayFormat(busiestDay.value)
              }})
            </template>
          </p>
          <div class="cv-sub p-4 pb-2">
            <MiniBars
              :values="dayValues"
              :labels="dayLabels"
              :color="hexFromGrad(blockFamily('dia')[1]) || '#0F5FA6'"
              :height="150"
              :format="dayFormat"
            />
          </div>
        </div>

        <div
          class="xl:col-span-2 cv-block p-5 sm:p-6"
          :style="blockVars('caixas')"
        >
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon">
              <span class="i-lucide-inbox text-base" />
            </span>
            <h2 class="text-sm font-bold text-n-slate-12">Por caixa</h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-3">
            custo estimado por número do WhatsApp
          </p>
          <HBars
            :rows="inboxBars"
            :series="[{ label: 'custo', format: v => money(v) }]"
            :format="v => money(v)"
            :label-width="10"
            empty-text="nenhuma caixa enviou no período"
          />
          <div class="flex items-center gap-2 mt-5 mb-1 flex-wrap">
            <span class="cv-icon">
              <span class="i-lucide-tags text-base" />
            </span>
            <h2 class="text-sm font-bold text-n-slate-12">Por categoria</h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-3">
            a Meta decide a categoria de cada modelo e pode mudar utilidade →
            marketing
          </p>
          <HBars
            :rows="categoryBars"
            :series="[{ label: 'custo', format: v => money(v) }]"
            :format="v => money(v)"
            :label-width="10"
            empty-text="sem mensagens com a marca da Meta"
          />
        </div>
      </div>

      <!-- ══ TARIFAS ══ -->
      <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('tarifas')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-tag text-base" /></span>
          <h2 class="text-sm font-bold text-n-slate-12">
            Tarifas por mensagem
          </h2>
          <span class="text-[11px] text-n-slate-9 ml-auto">
            {{
              rates.edited
                ? 'editadas por você'
                : 'padrão da Meta (Brasil, lidas em 30/09/2026)'
            }}
          </span>
        </div>
        <p class="text-[11px] text-n-slate-9 mb-4">
          usadas só nas estimativas desta tela e no Meu Painel. A Meta pode
          mudar no dia 1º de cada trimestre — confira no WhatsApp Manager e
          corrija aqui.
        </p>
        <div class="grid grid-cols-2 lg:grid-cols-5 gap-3 items-end">
          <label
            v-for="f in RATE_FIELDS"
            :key="f.key"
            class="cv-sub p-3 block"
            :title="f.hint"
          >
            <span class="text-[11px] font-bold text-n-slate-12 block mb-1">{{
              f.label
            }}</span>
            <span class="text-[10px] text-n-slate-9 block mb-2 leading-snug">{{
              f.hint
            }}</span>
            <input
              v-model="ratesForm[f.key]"
              type="number"
              step="0.0001"
              min="0"
              class="cv-input w-full text-sm"
            />
          </label>
          <label class="cv-sub p-3 block">
            <span class="text-[11px] font-bold text-n-slate-12 block mb-1">
              Moeda
            </span>
            <span class="text-[10px] text-n-slate-9 block mb-2 leading-snug">
              a conta migra para reais até 30/06/2027
            </span>
            <select
              v-model="ratesForm.currency"
              class="cv-input w-full text-sm"
            >
              <option value="BRL">R$ (BRL)</option>
              <option value="USD">US$ (USD)</option>
            </select>
          </label>
        </div>
        <div class="flex items-center gap-2 mt-3 flex-wrap">
          <button
            class="cv-btn cv-btn-sm"
            :disabled="isSavingRates"
            @click="saveRates(false)"
          >
            <span class="i-lucide-save text-xs" /> Salvar tarifas
          </button>
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm"
            :disabled="isSavingRates"
            @click="saveRates(true)"
          >
            Voltar ao padrão
          </button>
          <span class="text-[11px] text-n-slate-9">
            hoje: marketing {{ fmtRate(rates.marketing) }} · utilidade
            {{ fmtRate(rates.utility) }} · serviço {{ fmtRate(rates.service) }}
          </span>
        </div>
      </div>

      <!-- ══ COMO LER ══ -->
      <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('leitura')">
        <div class="flex items-center gap-2 mb-3 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-info text-base" /></span>
          <h2 class="text-sm font-bold text-n-slate-12">Como ler esta tela</h2>
        </div>
        <div
          class="grid grid-cols-1 md:grid-cols-2 gap-3 text-[11px] text-n-slate-11"
        >
          <div class="cv-sub p-3">
            <b class="text-n-slate-12">Conta da Meta</b> — a Meta soma o que
            cobrou por dia e categoria. É o número da fatura. Vem por leitura
            diária (04:40) ou pelo botão <b>Atualizar da Meta</b>.
          </div>
          <div class="cv-sub p-3">
            <b class="text-n-slate-12">Quem gastou</b> — cada mensagem que sai
            leva a marca de quem mandou (robô, lembrete, pessoa). A Meta
            responde dizendo se cobrou e a categoria; o valor é
            <b>estimado</b> pelas tarifas abaixo. Por isso pode diferir alguns
            centavos da conta.
          </div>
          <div class="cv-sub p-3">
            <b class="text-n-slate-12">Grátis na janela</b> — até
            {{ serviceFrom }}, responder em até 24h depois da mensagem do
            paciente não custava. Depois dessa data, custa o preço de serviço.
          </div>
          <div class="cv-sub p-3">
            <b class="text-n-slate-12">Grátis pelo anúncio</b> — lead que veio
            do anúncio Clique-para-WhatsApp pelo celular e foi respondido em
            24h: tudo grátis por 72h, inclusive modelos. Continua valendo depois
            de outubro.
          </div>
          <div class="cv-sub p-3">
            <b class="text-n-slate-12">Balões</b> — o robô manda até 3 balões
            por resposta (item 200). Cada balão é uma cobrança. Juntar em 1
            balão corta o custo dele em até 3×.
          </div>
          <div class="cv-sub p-3">
            <b class="text-n-slate-12">Sem a marca da Meta</b> — mensagens
            enviadas antes desta tela existir, ainda não entregues, ou de caixas
            fora da API oficial. Entram na contagem, não no custo.
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
