<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { relativeTime } from '../helpers';

const props = defineProps({
  contact: { type: Object, required: true },
});

const emit = defineEmits(['click']);

const accountLabels = useMapGetter('labels/getLabels');

const initials = computed(() => {
  if (!props.contact.name) return '?';
  return props.contact.name.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase();
});

const labelColorMap = computed(() => {
  const map = {};
  accountLabels.value.forEach(l => { map[l.title] = l.color; });
  return map;
});

const visibleLabels = computed(() => props.contact.labels?.slice(0, 4) ?? []);
const extraLabels = computed(() => Math.max(0, (props.contact.labels?.length ?? 0) - 4));

const entryDate = computed(() => {
  if (!props.contact.crm_created_at) return null;
  return new Date(props.contact.crm_created_at).toLocaleDateString('pt-BR', {
    day: '2-digit', month: '2-digit', year: '2-digit',
  });
});

const lastActivity = computed(() => relativeTime(props.contact.last_activity_at));

const channelIcon = (channelType) => {
  const map = {
    'Channel::Whatsapp':    'i-lucide-message-circle',
    'Channel::WebWidget':   'i-lucide-globe',
    'Channel::Email':       'i-lucide-mail',
    'Channel::Sms':         'i-lucide-smartphone',
    'Channel::TwilioSms':   'i-lucide-smartphone',
    'Channel::Api':         'i-lucide-code',
    'Channel::TelegramBot': 'i-lucide-send',
    'Channel::FacebookPage':'i-lucide-message-square',
    'Channel::Instagram':   'i-lucide-instagram',
  };
  return map[channelType] ?? 'i-lucide-inbox';
};
</script>

<template>
  <div
    class="bg-n-solid-2 border border-n-weak rounded-xl p-3 mb-2 cursor-pointer hover:border-n-brand hover:shadow-sm transition-all select-none"
    @click="emit('click', contact)"
  >
    <!-- Identity row -->
    <div class="flex items-center gap-2">
      <div class="w-7 h-7 rounded-full bg-n-brand flex items-center justify-center text-white text-[10px] font-semibold flex-shrink-0 overflow-hidden">
        <img v-if="contact.avatar_url" :src="contact.avatar_url" class="w-7 h-7 rounded-full object-cover" />
        <span v-else>{{ initials }}</span>
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-n-slate-12 truncate leading-tight">{{ contact.name }}</p>
        <p v-if="contact.phone_number" class="text-xs text-n-slate-10 truncate">{{ contact.phone_number }}</p>
      </div>
    </div>

    <!-- Labels with colored dots -->
    <div class="flex flex-wrap gap-1 mt-2">
      <span
        v-for="label in visibleLabels"
        :key="label"
        class="inline-flex items-center gap-1 text-xs bg-n-alpha-2 text-n-slate-11 px-1.5 py-0.5 rounded"
      >
        <span
          class="w-1.5 h-1.5 rounded-full flex-shrink-0"
          :style="{ backgroundColor: labelColorMap[label] ?? '#6B7280' }"
        />
        {{ label }}
      </span>
      <span v-if="extraLabels > 0" class="text-xs text-n-slate-9 px-1 py-0.5">+{{ extraLabels }}</span>
    </div>

    <!-- Value -->
    <div v-if="contact.value" class="mt-1.5">
      <span class="text-xs font-semibold text-green-600">
        R$&nbsp;{{ Number(contact.value).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) }}
      </span>
    </div>

    <!-- Inbox + assignee -->
    <div class="flex items-center justify-between mt-2 gap-1">
      <div
        v-if="contact.last_conversation?.inbox_name"
        class="flex items-center gap-1 text-xs text-n-slate-9 truncate min-w-0"
      >
        <span :class="channelIcon(contact.last_conversation.channel_type)" class="text-xs flex-shrink-0" />
        <span class="truncate">{{ contact.last_conversation.inbox_name }}</span>
      </div>
      <span v-if="contact.assignee" class="flex items-center gap-1 text-xs text-n-slate-10 flex-shrink-0 ml-auto">
        <span class="i-lucide-user text-[10px]" />
        <span>{{ contact.assignee.name }}</span>
      </span>
    </div>

    <!-- Entry date (left) + last activity (right) -->
    <div class="flex items-center justify-between mt-1 gap-1">
      <span v-if="entryDate" class="text-xs text-n-slate-9">{{ entryDate }}</span>
      <span v-if="lastActivity" class="text-xs text-n-slate-9 ml-auto">{{ lastActivity }}</span>
    </div>
  </div>
</template>
