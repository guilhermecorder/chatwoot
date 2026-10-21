<script setup>
import { computed } from 'vue';
import Auth from 'dashboard/api/auth';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import SidebarProfileMenuStatus from './SidebarProfileMenuStatus.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { initCevicoFontCombo } from 'dashboard/helper/cevicoFontHelper';

import {
  DropdownContainer,
  DropdownBody,
  DropdownSection,
  DropdownSeparator,
  DropdownItem,
} from 'next/dropdown-menu/base';
import CustomBrandPolicyWrapper from '../../components/CustomBrandPolicyWrapper.vue';

defineProps({
  isCollapsed: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'openKeyShortcutModal']);

defineOptions({
  inheritAttrs: false,
});

const { t } = useI18n();

const currentUser = useMapGetter('getCurrentUser');
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const accountId = useMapGetter('getCurrentAccountId');
const globalConfig = useMapGetter('globalConfig/get');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

// ── 🏢 Empresa (rodada 334): as contas da pessoa (CEVICO, Sua Ótica…) no menu
// do avatar — a atual com ✓ e o papel; clicar em outra troca de empresa. Com
// uma conta só, aparece uma linha discreta sem ação.
const userAccounts = useMapGetter('getUserAccounts');
const companyAccounts = computed(() =>
  [...(currentUser.value?.accounts || userAccounts.value || [])].sort((a, b) =>
    String(a.name || '').localeCompare(String(b.name || ''))
  )
);
const hasManyCompanies = computed(() => companyAccounts.value.length > 1);
const currentCompany = computed(() =>
  companyAccounts.value.find(a => a.id === accountId.value)
);
const roleLabel = account => {
  if (account.custom_role_id && account.custom_role?.name) {
    return account.custom_role.name;
  }
  return account.role === 'administrator' ? 'administrador' : 'atendente';
};
const switchCompany = account => {
  if (account.id === accountId.value) return;
  window.location.href = `/app/accounts/${account.id}/dashboard`;
};

const showChatSupport = computed(() => {
  return (
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CONTACT_CHATWOOT_SUPPORT_TEAM
    ) && globalConfig.value.chatwootInboxToken
  );
});

const toggleChatSupport = () => {
  if (window.$chatwoot) {
    window.$chatwoot.toggle();
  }
};

// ── CEVICO: Alterar fontes — seleção em painel, igual ao menu de temas ──
initCevicoFontCombo(); // aplica a combinação salva ao abrir o sistema

const menuItems = computed(() => {
  return [
    {
      show: showChatSupport.value,
      showOnCustomBrandedInstance: false,
      label: t('SIDEBAR_ITEMS.CONTACT_SUPPORT'),
      icon: 'i-lucide-life-buoy',
      click: toggleChatSupport,
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.KEYBOARD_SHORTCUTS'),
      icon: 'i-lucide-keyboard',
      click: () => {
        emit('openKeyShortcutModal');
      },
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.PROFILE_SETTINGS'),
      icon: 'i-lucide-user-pen',
      link: { name: 'profile_settings_index' },
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.APPEARANCE'),
      icon: 'i-lucide-palette',
      click: () => {
        const ninja = document.querySelector('ninja-keys');
        ninja.open({ parent: 'appearance_settings' });
      },
    },
    {
      // CEVICO: feedback de bugs — vira card no board do Guilherme
      show: true,
      showOnCustomBrandedInstance: true,
      label: 'Reportar problema 🐞',
      icon: 'i-lucide-bug',
      click: () => {
        window.dispatchEvent(new CustomEvent('cevico:report-bug'));
      },
    },
    {
      // CEVICO: abre o painel de combinações (mesmo padrão do menu de temas)
      show: true,
      showOnCustomBrandedInstance: true,
      label: 'Alterar fontes',
      icon: 'i-lucide-type',
      click: () => {
        const ninja = document.querySelector('ninja-keys');
        ninja.open({ parent: 'font_settings' });
      },
    },
    {
      show: true,
      showOnCustomBrandedInstance: false,
      label: t('SIDEBAR_ITEMS.DOCS'),
      icon: 'i-lucide-book',
      link: 'https://www.chatwoot.com/hc/user-guide/en',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: true,
      showOnCustomBrandedInstance: false,
      label: t('SIDEBAR_ITEMS.CHANGELOG'),
      icon: 'i-lucide-scroll-text',
      link: 'https://www.chatwoot.com/changelog/',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: currentUser.value.type === 'SuperAdmin',
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.SUPER_ADMIN_CONSOLE'),
      icon: 'i-lucide-castle',
      link: '/super_admin',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.LOGOUT'),
      icon: 'i-lucide-power',
      click: Auth.logout,
    },
  ];
});

const allowedMenuItems = computed(() => {
  return menuItems.value.filter(item => item.show);
});
</script>

<template>
  <DropdownContainer
    class="relative min-w-0"
    :class="isCollapsed ? 'w-auto' : 'w-full'"
    @close="emit('close')"
  >
    <template #trigger="{ toggle, isOpen }">
      <button
        class="flex gap-2 items-center p-1 text-left rounded-lg cursor-pointer hover:bg-n-alpha-1"
        :class="[
          { 'bg-n-alpha-1': isOpen },
          isCollapsed ? 'justify-center' : 'w-full',
        ]"
        :title="isCollapsed ? currentUser.available_name : undefined"
        @click="toggle"
      >
        <Avatar
          :size="32"
          :name="currentUser.available_name"
          :src="currentUser.avatar_url"
          :status="currentUserAvailability"
          class="flex-shrink-0"
        />
        <div v-if="!isCollapsed" class="min-w-0">
          <div class="text-sm font-medium leading-4 truncate text-n-slate-12">
            {{ currentUser.available_name }}
          </div>
          <div class="text-xs truncate text-n-slate-11">
            {{ currentUser.email }}
          </div>
        </div>
      </button>
    </template>
    <DropdownBody class="bottom-12 z-50 mb-2 w-80 ltr:left-0 rtl:right-0">
      <SidebarProfileMenuStatus />
      <DropdownSeparator />
      <!-- 🏢 Empresa: troca de conta (rodada 334) -->
      <DropdownSection v-if="hasManyCompanies" title="Empresa">
        <DropdownItem
          v-for="account in companyAccounts"
          :id="`profile-account-${account.id}`"
          :key="account.id"
          :class="
            account.id === accountId ? 'cursor-default' : 'cursor-pointer'
          "
          @click="switchCompany(account)"
        >
          <template #label>
            <div class="flex items-center gap-2 min-w-0 flex-1">
              <span
                class="i-lucide-building-2 size-4 flex-shrink-0 text-n-slate-10"
              />
              <span
                class="text-n-slate-12 truncate min-w-0"
                :title="account.name"
              >
                {{ account.name }}
              </span>
              <span class="flex-shrink-0 w-px h-3 bg-n-strong" />
              <span class="text-n-slate-11 text-xs truncate">
                {{ roleLabel(account) }}
              </span>
            </div>
            <span
              v-if="account.id === accountId"
              class="i-lucide-check size-4 text-n-teal-11 flex-shrink-0"
            />
          </template>
        </DropdownItem>
      </DropdownSection>
      <div
        v-else-if="currentCompany"
        class="px-2 py-1.5 text-xs text-n-slate-11 flex items-center gap-2 min-w-0"
        :title="currentCompany.name"
      >
        <span
          class="i-lucide-building-2 size-4 flex-shrink-0 text-n-slate-10"
        />
        <span class="truncate">Empresa: {{ currentCompany.name }}</span>
      </div>
      <DropdownSeparator />
      <template v-for="item in allowedMenuItems" :key="item.label">
        <CustomBrandPolicyWrapper
          :show-on-custom-branded-instance="item.showOnCustomBrandedInstance"
        >
          <DropdownItem v-if="item.show" v-bind="item" />
        </CustomBrandPolicyWrapper>
      </template>
    </DropdownBody>
  </DropdownContainer>
</template>
