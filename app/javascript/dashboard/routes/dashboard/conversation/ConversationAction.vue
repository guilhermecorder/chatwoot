<!-- eslint-disable vue/v-slot-style -->
<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import ContactDetailsItem from './ContactDetailsItem.vue';
import ConversationLabels from './labels/LabelBox.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
// 🎨 item 212: a cor fixa de cada pessoa (a mesma da lista de conversas)
import { personColorFor, BOT_COLOR } from 'dashboard/helper/cevicoPersonColors';

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
    const { agentsList } = useAgentsList(true, { includeAgentBots: true });
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
        const assignee = this.currentChat.meta.assignee;
        return (
          assignee && {
            ...assignee,
            assignee_type: this.currentChat.meta.assignee_type || 'User',
          }
        );
      },
      set(agent) {
        const agentId = agent ? agent.id : null;
        const assigneeType = agent ? agent.assignee_type || 'User' : null;
        this.$store.dispatch('setCurrentChatAssignee', {
          conversationId: this.currentChat.id,
          assignee: agent,
          assigneeType,
        });
        this.$store
          .dispatch('assignAgent', {
            conversationId: this.currentChat.id,
            agentId,
            assigneeType,
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
      if (
        this.assignedAgent.id !== this.currentUser.id ||
        (this.assignedAgent.assignee_type || 'User') !== 'User'
      ) {
        return true;
      }
      return false;
    },
    // botões em linha: só pessoas de verdade (sem a opção "None" — clicar
    // de novo no selecionado já desatribui)
    assignableAgents() {
      return (this.agentsList || []).filter(agent => agent.id);
    },
    teamAgents() {
      return this.$store.getters['agents/getAgents'] || [];
    },
    personColorOverrides() {
      return this.$store.getters['crm/getSettings']?.person_colors || {};
    },
  },
  methods: {
    // cor da pessoa (robôs = lilás "sistema")
    personColor(agent) {
      if ((agent.assignee_type || agent.type) === 'AgentBot') return BOT_COLOR;
      return personColorFor(
        this.teamAgents,
        agent.id ?? agent.name,
        this.personColorOverrides
      );
    },
    isAssigned(agent) {
      return (
        this.assignedAgent &&
        this.assignedAgent.id === agent.id &&
        (this.assignedAgent.assignee_type || 'User') ===
          (agent.assignee_type || 'User')
      );
    },
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
      if (
        this.assignedAgent?.id === selectedItem.id &&
        (this.assignedAgent?.assignee_type || 'User') ===
          (selectedItem.assignee_type || 'User')
      ) {
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
        <!-- item 212: cada pessoa na SUA cor (a mesma da lista); a escolhida
             fica cheia, as outras mostram só a bolinha da cor -->
        <button
          v-for="agent in assignableAgents"
          :key="`${agent.assignee_type || 'User'}-${agent.id}`"
          class="cv-tag cv-tag-btn cv-tag-md"
          :class="isAssigned(agent) ? 'cv-tag-solid' : ''"
          :style="{ '--lb': personColor(agent).solid }"
          @click="onClickAssignAgent(agent)"
        >
          <img
            v-if="agent.thumbnail"
            :src="agent.thumbnail"
            class="w-4 h-4 rounded-full object-cover -ml-1"
          />
          <span v-else class="cv-tag-dot" />
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
