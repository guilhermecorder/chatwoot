<!-- eslint-disable vue/v-slot-style -->
<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import ContactDetailsItem from './ContactDetailsItem.vue';
import ConversationLabels from './labels/LabelBox.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    ContactDetailsItem,
    ConversationLabels,
    NextButton,
  },
  props: {
    conversationId: {
      type: [Number, String],
      required: true,
    },
  },
  setup() {
    const { agentsList } = useAgentsList();
    return {
      agentsList,
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUser: 'getCurrentUser',
    }),
    assignedAgent: {
      get() {
        return this.currentChat.meta.assignee;
      },
      set(agent) {
        const agentId = agent ? agent.id : null;
        this.$store.dispatch('setCurrentChatAssignee', {
          conversationId: this.currentChat.id,
          assignee: agent,
        });
        this.$store
          .dispatch('assignAgent', {
            conversationId: this.currentChat.id,
            agentId,
          })
          .then(() => {
            useAlert(this.$t('CONVERSATION.CHANGE_AGENT'));
          });
      },
    },
    showSelfAssign() {
      if (!this.assignedAgent) {
        return true;
      }
      if (this.assignedAgent.id !== this.currentUser.id) {
        return true;
      }
      return false;
    },
    // botões em linha: só pessoas de verdade (sem a opção "None" — clicar
    // de novo no selecionado já desatribui)
    assignableAgents() {
      return (this.agentsList || []).filter(agent => agent.id);
    },
  },
  methods: {
    onSelfAssign() {
      const {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        avatar_url,
      } = this.currentUser;
      const selfAssign = {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        thumbnail: avatar_url,
      };
      this.assignedAgent = selfAssign;
    },
    onClickAssignAgent(selectedItem) {
      if (this.assignedAgent && this.assignedAgent.id === selectedItem.id) {
        this.assignedAgent = null;
      } else {
        this.assignedAgent = selectedItem;
      }
    },
  },
};
</script>

<template>
  <div>
    <!-- CEVICO: painel enxuto — Pessoa responsável em BOTÕES EM LINHA
         (padrão de seleção do sistema); time e prioridade saíram -->
    <div>
      <ContactDetailsItem compact title="Pessoa responsável">
        <template #button>
          <NextButton
            v-if="showSelfAssign"
            link
            xs
            icon="i-lucide-arrow-right"
            class="!gap-1"
            :label="$t('CONVERSATION_SIDEBAR.SELF_ASSIGN')"
            @click="onSelfAssign"
          />
        </template>
      </ContactDetailsItem>
      <div class="flex items-center gap-1.5 flex-wrap mt-1 mb-2">
        <button
          v-for="agent in assignableAgents"
          :key="agent.id"
          class="px-2.5 h-7 rounded-lg text-xs font-medium border transition-all flex items-center gap-1.5"
          :class="assignedAgent && assignedAgent.id === agent.id
            ? 'text-white border-transparent shadow-sm'
            : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
          :style="assignedAgent && assignedAgent.id === agent.id
            ? { background: 'linear-gradient(135deg, #0EA5E9, #38BDF8)' }
            : {}"
          @click="onClickAssignAgent(agent)"
        >
          <img
            v-if="agent.thumbnail"
            :src="agent.thumbnail"
            class="w-4 h-4 rounded-full object-cover"
          />
          {{ agent.name }}
        </button>
      </div>
    </div>
    <ContactDetailsItem
      compact
      :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_LABELS')"
    />
    <ConversationLabels :conversation-id="conversationId" />
  </div>
</template>
