<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import PatientSpaceIcon from 'dashboard/routes/dashboard/patient/PatientSpaceIcon.vue';
import countries from 'shared/constants/countries';
import { dynamicTime } from 'shared/helpers/timeHelper';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Flag from 'dashboard/components-next/flag/Flag.vue';

const props = defineProps({
  id: {
    type: [String, Number],
    default: 0,
  },
  email: {
    type: String,
    default: '',
  },
  phone: {
    type: String,
    default: '',
  },
  name: {
    type: String,
    default: '',
  },
  thumbnail: {
    type: String,
    default: '',
  },
  accountId: {
    type: [String, Number],
    default: 0,
  },
  additionalAttributes: {
    type: Object,
    default: () => ({}),
  },
  updatedAt: {
    type: Number,
    default: 0,
  },
  // CEVICO (14/09): funil/coluna do CRM em que o paciente está + atalhos
  crmJourneys: {
    type: Array,
    default: () => [],
  },
  lastConversationId: {
    type: [String, Number],
    default: null,
  },
});

const router = useRouter();

const navigateTo = computed(() => {
  return frontendURL(`accounts/${props.accountId}/contacts/${props.id}`);
});

// os mesmos 2 atalhos do card do CRM: Espaço do Paciente + conversa
const openPatient = () => {
  router.push(frontendURL(`accounts/${props.accountId}/patient/${props.id}`));
};
const openChat = () => {
  const target = props.lastConversationId
    ? `accounts/${props.accountId}/conversations/${props.lastConversationId}`
    : `accounts/${props.accountId}/contacts/${props.id}`;
  router.push(frontendURL(target));
};
const chatTitle = computed(() =>
  props.lastConversationId
    ? 'Abrir a conversa mais recente'
    : 'Sem conversa ainda — abrir o contato para iniciar uma'
);

const countriesMap = computed(() => {
  return countries.reduce((acc, country) => {
    acc[country.id] = country;
    return acc;
  }, {});
});

const updatedAtTime = computed(() => {
  if (!props.updatedAt) return '';
  return dynamicTime(props.updatedAt);
});

const countryDetails = computed(() => {
  const { country, countryCode, city } = props.additionalAttributes;

  if (!country && !countryCode) return null;

  const activeCountry =
    countriesMap.value[country] || countriesMap.value[countryCode];

  if (!activeCountry) return null;

  return {
    countryCode: activeCountry.id,
    city: city ? `${city},` : null,
    name: activeCountry.name,
  };
});

const formattedLocation = computed(() => {
  if (!countryDetails.value) return '';

  return [countryDetails.value.city, countryDetails.value.name]
    .filter(Boolean)
    .join(' ');
});
</script>

<template>
  <router-link :to="navigateTo">
    <CardLayout
      layout="row"
      class="[&>div]:justify-start [&>div]:px-4 [&>div]:py-3 [&>div]:items-start hover:bg-n-slate-2 dark:hover:bg-n-solid-3"
    >
      <Avatar
        :name="name"
        :src="thumbnail"
        :size="24"
        rounded-full
        class="mt-1 flex-shrink-0"
      />
      <div class="min-w-0 flex flex-col items-start gap-1.5 w-full">
        <div class="flex items-center min-w-0 justify-between gap-2 w-full">
          <h5 class="text-sm font-medium truncate min-w-0 text-n-slate-12 py-1">
            {{ name }}
          </h5>
          <span class="flex items-center gap-1.5 shrink-0">
            <span
              v-if="updatedAtTime"
              class="text-sm font-normal min-w-0 truncate text-n-slate-11"
            >
              {{ $t('SEARCH.UPDATED_AT', { time: updatedAtTime }) }}
            </span>
            <button
              class="flex items-center justify-center w-8 h-8 rounded-lg transition-transform hover:scale-110"
              title="Espaço do Paciente"
              @click.prevent.stop="openPatient"
            >
              <PatientSpaceIcon :size="24" />
            </button>
            <button
              class="flex items-center justify-center w-8 h-8 rounded-lg transition-colors"
              :class="
                lastConversationId
                  ? 'text-n-brand bg-n-brand/10 hover:bg-n-brand hover:text-white'
                  : 'text-n-slate-9 border border-dashed border-n-weak hover:text-n-brand hover:border-n-brand'
              "
              :title="chatTitle"
              @click.prevent.stop="openChat"
            >
              <span class="i-lucide-message-circle-more text-lg" />
            </button>
          </span>
        </div>
        <!-- funil › coluna em que o paciente está (um chip por funil) -->
        <div v-if="crmJourneys.length" class="flex flex-wrap gap-1">
          <span
            v-for="j in crmJourneys"
            :key="`${j.pipelineId}-${j.stageId}`"
            class="inline-flex items-center gap-1 px-2 h-5 rounded-full text-[11px] font-medium border border-n-weak text-n-slate-11 bg-n-alpha-1"
            :title="`Funil ${j.pipelineName} · coluna ${j.stageName}`"
          >
            <span class="i-lucide-funnel text-[10px] text-n-slate-9" />
            <span class="truncate max-w-[10rem]">{{ j.pipelineName }}</span>
            <span class="text-n-slate-9">›</span>
            <span
              class="w-1.5 h-1.5 rounded-full shrink-0"
              :style="{ background: j.stageColor || '#94A3B8' }"
            />
            <span class="truncate max-w-[12rem] text-n-slate-12">{{
              j.stageName
            }}</span>
          </span>
        </div>
        <div
          v-else
          class="inline-flex items-center gap-1 px-2 h-5 rounded-full text-[11px] border border-dashed border-n-weak text-n-slate-9"
          title="Este contato ainda não está em nenhum funil do CRM"
        >
          <span class="i-lucide-funnel text-[10px]" />
          Fora do CRM
        </div>
        <div
          class="grid items-center gap-3 m-0 text-sm overflow-hidden min-w-0 grid-cols-[minmax(0,max-content)_auto_minmax(0,max-content)_auto_minmax(0,max-content)]"
        >
          <span
            v-if="email"
            class="truncate text-n-slate-11 min-w-0"
            :title="email"
          >
            {{ email }}
          </span>

          <div v-if="email && phone" class="w-px h-3 bg-n-slate-6 rounded" />

          <span
            v-if="phone"
            :title="phone"
            class="truncate text-n-slate-11 min-w-0"
          >
            {{ phone }}
          </span>

          <div
            v-if="(email || phone) && countryDetails"
            class="w-px h-3 bg-n-slate-6 rounded"
          />

          <span
            v-if="countryDetails"
            class="truncate text-n-slate-11 flex items-center gap-1 min-w-0"
          >
            <Flag
              :country="countryDetails.countryCode"
              class="size-3 shrink-0"
            />
            <span class="truncate min-w-0">{{ formattedLocation }}</span>
          </span>
        </div>
      </div>
    </CardLayout>
  </router-link>
</template>
