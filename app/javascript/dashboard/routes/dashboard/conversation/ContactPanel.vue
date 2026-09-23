<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ContactConversations from './ContactConversations.vue';
import ConversationAction from './ConversationAction.vue';
import ConversationParticipant from './ConversationParticipant.vue';
import ContactInfo from './contact/ContactInfo.vue';
import AdOriginCard from './contact/AdOriginCard.vue';
import ConversationSummaryCard from './contact/ConversationSummaryCard.vue';
import ContactNotes from './contact/ContactNotes.vue';
import ConversationInfo from './ConversationInfo.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import SharedFiles from './SharedFiles.vue';
import Draggable from 'vuedraggable';
import MacrosList from './Macros/List.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const {
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  toggleSidebarUIState,
} = useUISettings();

const dragging = ref(false);
const conversationSidebarItems = ref([]);

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => props.conversationId);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

const contactGetter = useMapGetter('contacts/getContact');
const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = computed(() => contactGetter.value(contactId.value));
const contactAdditionalAttributes = computed(
  () => contact.value.additional_attributes || {}
);

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: conversationSidebarItems.value,
  });
};

const closeContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

// CEVICO: painel enxuto — Macros, Atributos, Time/Prioridade, Informações
// da conversa e Participantes saem da lista (as informações importantes
// ficam no card-resumo no topo)
const HIDDEN_SIDEBAR_ITEMS = [
  'macros',
  'contact_attributes',
  'conversation_info',
  'conversation_participants',
];

onMounted(() => {
  conversationSidebarItems.value = conversationSidebarItemsOrder.value.filter(
    item => !HIDDEN_SIDEBAR_ITEMS.includes(item.name)
  );
  getContactDetails();
  store.dispatch('attributes/get', 0);
  // Load integrations to ensure linear integration state is available
  store.dispatch('integrations/get', 'linear');
});
</script>

<template>
  <!-- CEVICO 199 (22/09): painel do paciente em CARTÕES brancos sobre o cinza
       Apple — identidade, origem, jornada/IA/ligações, e as gavetas
       (Conversa, Notas, Anexos, Conversas anteriores) cada uma no seu cartão -->
  <div class="cv-side w-full">
    <SidebarActionsHeader title="Paciente" @close="closeContactPanel" />
    <div class="px-3 pt-3 pb-8 flex flex-col gap-3">
      <ContactInfo :contact="contact" :channel-type="channelType" />
      <AdOriginCard
        :contact="contact"
        :conversation-attributes="conversationAdditionalAttributes"
      />
      <ConversationSummaryCard
        :conversation-id="conversationId"
        :contact="contact"
      />
      <div class="list-group">
        <Draggable
          :list="conversationSidebarItems"
          animation="200"
          ghost-class="ghost"
          handle=".drag-handle"
          item-key="name"
          class="flex flex-col gap-3"
          @start="dragging = true"
          @end="onDragEnd"
        >
          <template #item="{ element }">
            <div
              v-if="element.name === 'conversation_actions'"
              class="cv-side-card conversation--actions"
            >
              <AccordionItem
                title="Conversa"
                lucide="i-lucide-user-round-check"
                tone="slate"
                :is-open="isContactSidebarItemOpen('is_conv_actions_open')"
                @toggle="
                  value => toggleSidebarUIState('is_conv_actions_open', value)
                "
              >
                <ConversationAction
                  :conversation-id="conversationId"
                  :inbox-id="inboxId"
                />
              </AccordionItem>
            </div>
            <div
              v-else-if="element.name === 'conversation_participants'"
              class="cv-side-card conversation--actions"
            >
              <AccordionItem
                :title="$t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE')"
                lucide="i-lucide-users-round"
                tone="slate"
                :is-open="isContactSidebarItemOpen('is_conv_participants_open')"
                @toggle="
                  value =>
                    toggleSidebarUIState('is_conv_participants_open', value)
                "
              >
                <ConversationParticipant
                  :conversation-id="conversationId"
                  :inbox-id="inboxId"
                />
              </AccordionItem>
            </div>
            <div v-else-if="element.name === 'conversation_info'" class="cv-side-card">
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')"
                lucide="i-lucide-info"
                tone="slate"
                :is-open="isContactSidebarItemOpen('is_conv_details_open')"
                compact
                @toggle="
                  value => toggleSidebarUIState('is_conv_details_open', value)
                "
              >
                <ConversationInfo
                  :conversation-attributes="conversationAdditionalAttributes"
                  :contact-attributes="contactAdditionalAttributes"
                />
              </AccordionItem>
            </div>
            <div v-else-if="element.name === 'contact_attributes'" class="cv-side-card">
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')"
                lucide="i-lucide-list"
                tone="slate"
                :is-open="isContactSidebarItemOpen('is_contact_attributes_open')"
                compact
                @toggle="
                  value =>
                    toggleSidebarUIState('is_contact_attributes_open', value)
                "
              >
                <CustomAttributes
                  attribute-type="contact_attribute"
                  attribute-from="conversation_contact_panel"
                  :contact-id="contact.id"
                  :empty-state-message="
                    $t('CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND')
                  "
                />
              </AccordionItem>
            </div>
            <div v-else-if="element.name === 'previous_conversation'" class="cv-side-card">
              <AccordionItem
                v-if="contact.id"
                title="Conversas anteriores"
                lucide="i-lucide-history"
                tone="cyan"
                :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
                compact
                @toggle="
                  value => toggleSidebarUIState('is_previous_conv_open', value)
                "
              >
                <ContactConversations
                  :contact-id="contact.id"
                  :conversation-id="conversationId"
                />
              </AccordionItem>
            </div>
            <woot-feature-toggle
              v-else-if="element.name === 'macros'"
              feature-key="macros"
            >
              <div class="cv-side-card">
                <AccordionItem
                  :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
                  lucide="i-lucide-zap"
                  tone="slate"
                  :is-open="isContactSidebarItemOpen('is_macro_open')"
                  compact
                  @toggle="value => toggleSidebarUIState('is_macro_open', value)"
                >
                  <MacrosList :conversation-id="conversationId" />
                </AccordionItem>
              </div>
            </woot-feature-toggle>
            <div
              v-else-if="
                element.name === 'linear_issues' &&
                isLinearFeatureEnabled &&
                isLinearClientIdConfigured
              "
              class="cv-side-card"
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
                :is-open="isContactSidebarItemOpen('is_linear_issues_open')"
                compact
                @toggle="
                  value => toggleSidebarUIState('is_linear_issues_open', value)
                "
              >
                <LinearSetupCTA v-if="!isLinearConnected" />
                <LinearIssuesList v-else :conversation-id="conversationId" />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'shopify_orders' && isShopifyFeatureEnabled
              "
              class="cv-side-card"
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
                :is-open="isContactSidebarItemOpen('is_shopify_orders_open')"
                compact
                @toggle="
                  value => toggleSidebarUIState('is_shopify_orders_open', value)
                "
              >
                <ShopifyOrdersList :contact-id="contactId" />
              </AccordionItem>
            </div>
            <!-- Notas SEM gaveta: título + caixa de texto direta -->
            <div v-else-if="element.name === 'contact_notes'" class="cv-side-card p-4">
              <p class="cv-side-title mb-3">
                <span class="cv-side-icon cv-side-icon-amber"><span class="i-lucide-sticky-note" /></span>
                Notas
              </p>
              <ContactNotes :contact-id="contactId" />
            </div>
            <div v-else-if="element.name === 'shared_files'" class="cv-side-card">
              <AccordionItem
                title="Anexos"
                lucide="i-lucide-paperclip"
                tone="blue"
                :is-open="isContactSidebarItemOpen('is_shared_files_open')"
                compact
                @toggle="
                  value => toggleSidebarUIState('is_shared_files_open', value)
                "
              >
                <SharedFiles />
              </AccordionItem>
            </div>
          </template>
        </Draggable>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
:deep(.contact--profile) {
  @apply pb-3 border-b border-solid border-n-weak;
}
/* CEVICO 199: as gavetas moram dentro do cartão — sem a moldura própria */
:deep(.cv-side-card > .accordion-item > button) {
  @apply bg-transparent outline-none;
}
</style>
