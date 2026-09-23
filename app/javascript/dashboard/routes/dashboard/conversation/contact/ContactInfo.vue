<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContactInfoRow from './ContactInfoRow.vue';
import Avatar from 'next/avatar/Avatar.vue';
import {
  personColorFor,
  BOT_COLOR,
  UNASSIGNED_COLOR,
} from 'dashboard/helper/cevicoPersonColors';
import SocialIcons from './SocialIcons.vue';
import EditContact from './EditContact.vue';
import ContactMergeModal from 'dashboard/modules/contact/ContactMergeModal.vue';
import ContactDeleteModal from 'dashboard/modules/contact/ContactDeleteModal.vue';
import {
  openNovaConversa,
  timeAgoPt,
} from 'dashboard/helper/cevicoNovaConversa';
import NextButton from 'dashboard/components-next/button/Button.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
// 📞 CEVICO item 167: ligar pelo nosso módulo (Graph API + WebRTC)
import CevicoCallButton from 'dashboard/components-next/cevico/calls/CevicoCallButton.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

export default {
  components: {
    NextButton,
    ContactInfoRow,
    EditContact,
    Avatar,
    SocialIcons,
    ContactMergeModal,
    ContactDeleteModal,
    VoiceCallButton,
    CevicoCallButton,
    InlineInput,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
    showAvatar: {
      type: Boolean,
      default: true,
    },
  },
  emits: ['panelClose'],
  setup() {
    const { isAdmin } = useAdmin();
    return {
      isAdmin,
    };
  },
  data() {
    return {
      showEditModal: false,
      isEditingName: false,
      editName: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'contacts/getUIFlags',
      currentChat: 'getSelectedChat',
    }),
    contactProfileLink() {
      return `/app/accounts/${this.$route.params.accountId}/contacts/${this.contact.id}`;
    },
    // 🎨 item 212b: a "foto" do paciente na cor de quem cuida da conversa
    patientGradient() {
      const assignee = this.currentChat?.meta?.assignee;
      if (!assignee?.id && !assignee?.name) return UNASSIGNED_COLOR.grad;
      if (this.currentChat?.meta?.assignee_type === 'AgentBot')
        return BOT_COLOR.grad;
      return personColorFor(
        this.$store.getters['agents/getAgents'] || [],
        assignee.id ?? assignee.name,
        this.$store.getters['crm/getSettings']?.person_colors || {}
      ).grad;
    },
    // "no cadastro desde ontem" / "no cadastro há 3 dias"
    contactSince() {
      const label = timeAgoPt(this.contact.created_at);
      if (!label) return '';
      if (label === 'hoje' || label === 'ontem') {
        return `no cadastro desde ${label}`;
      }
      return `no cadastro ${label}`;
    },
    // CEVICO: com o módulo de ligações ligado, o telefone é o nosso
    cevicoCallsOn() {
      return this.$store.getters['crm/getSettings']?.calls?.enabled === true;
    },
    additionalAttributes() {
      return this.contact.additional_attributes || {};
    },
    location() {
      const {
        country = '',
        city = '',
        country_code: countryCode,
      } = this.additionalAttributes;
      const cityAndCountry = [city, country].filter(item => !!item).join(', ');

      if (!cityAndCountry) {
        return '';
      }
      return this.findCountryFlag(countryCode, cityAndCountry);
    },
    socialProfiles() {
      const {
        social_profiles: socialProfiles,
        screen_name: twitterScreenName,
        social_telegram_user_name: telegramUsername,
      } = this.additionalAttributes;

      const telegram = socialProfiles?.telegram || telegramUsername || '';
      const twitter = socialProfiles?.twitter || twitterScreenName || '';

      return {
        ...(socialProfiles || {}),
        twitter,
        telegram,
      };
    },
  },
  watch: {
    'contact.id': {
      handler(id) {
        this.$store.dispatch('contacts/fetchContactableInbox', id);
      },
      immediate: true,
    },
  },
  methods: {
    dynamicTime,
    openNovaConversa,
    timeAgoPt,
    toggleEditModal() {
      this.showEditModal = !this.showEditModal;
    },
    findCountryFlag(countryCode, cityAndCountry) {
      try {
        if (!countryCode) {
          return `${cityAndCountry} 🌎`;
        }

        const code = countryCode?.toLowerCase();
        return `${cityAndCountry} <span class="fi fi-${code} size-3.5"></span>`;
      } catch (error) {
        return '';
      }
    },
    startEditingName() {
      this.editName = this.contact.name || '';
      this.isEditingName = true;
      this.$nextTick(() => {
        this.$refs.nameInput?.focus();
      });
    },
    saveNameEdit() {
      if (!this.isEditingName) return;
      this.isEditingName = false;
      const trimmed = this.editName.trim();
      if (trimmed && trimmed !== this.contact.name) {
        this.updateContactField({ name: trimmed });
      }
    },
    cancelNameEdit() {
      this.isEditingName = false;
    },
    onFieldUpdate(field, value) {
      this.updateContactField({ [field]: value });
    },
    async updateContactField(attrs) {
      const contactId = this.contact.id;
      try {
        await this.$store.dispatch('contacts/update', {
          id: contactId,
          ...attrs,
        });
        useAlert(this.$t('CONTACT_FORM.SUCCESS_MESSAGE'));
        await this.$store.dispatch('contacts/fetchContactableInbox', contactId);
      } catch (error) {
        if (error instanceof DuplicateContactException) {
          const detail = error.contactErrorDetail;
          if (detail) {
            useAlert(detail);
          } else {
            const invalidAttrs = Array.isArray(error.data) ? error.data : [];
            if (invalidAttrs.includes('email')) {
              useAlert(this.$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.DUPLICATE'));
            } else if (invalidAttrs.includes('phone_number')) {
              useAlert(this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
            } else {
              useAlert(this.$t('CONTACT_FORM.ERROR_MESSAGE'));
            }
          }
        } else if (error instanceof ExceptionWithMessage) {
          useAlert(error.data);
        } else {
          useAlert(error.message || this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        }
      }
    },
  },
};
</script>

<template>
  <!-- CEVICO 199 (22/09): ficha de identidade no estilo Contatos da Apple —
       foto grande centralizada, nome, ações redondas com rótulo e só os
       dados que existem (nada de "Indisponível" empilhado). -->
  <div class="cv-side-card cv-side-id relative w-full p-5">
    <div class="flex flex-col items-center text-center gap-1.5">
      <Avatar
        v-if="showAvatar"
        :src="contact.thumbnail"
        :name="contact.name"
        :status="contact.availability_status"
        :size="72"
        hide-offline-status
        rounded-full
        gradient
        :gradient-override="patientGradient"
      />
      <div
        v-if="showAvatar"
        class="group/name flex items-center justify-center min-w-0 gap-1.5 max-w-full mt-1"
      >
        <InlineInput
          v-if="isEditingName"
          ref="nameInput"
          v-model="editName"
          custom-input-class="!text-base !font-semibold !w-auto max-w-full [field-sizing:content] text-center"
          class="!w-fit min-w-0"
          @enter-press="saveNameEdit"
          @escape-press="cancelNameEdit"
          @blur="saveNameEdit"
        />
        <h3
          v-else
          class="flex-shrink max-w-full min-w-0 my-0 text-[17px] font-bold leading-tight break-words text-n-slate-12 cursor-pointer hover:text-n-slate-12/80"
          :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
          @click="startEditingName"
        >
          {{ contact.name }}
        </h3>
        <NextButton
          ghost
          xs
          slate
          icon="i-lucide-pencil"
          :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
          class="flex-shrink-0 -mx-1 opacity-0 transition-opacity"
          :class="
            isEditingName
              ? 'invisible'
              : 'group-hover/name:opacity-100 focus-visible:opacity-100'
          "
          @click="startEditingName"
        />
      </div>
      <p
        v-if="additionalAttributes.description"
        class="text-xs text-n-slate-11 m-0 break-words max-w-full"
      >
        {{ additionalAttributes.description }}
      </p>
      <p
        class="text-[11px] text-n-slate-10 m-0 flex items-center gap-1.5 flex-wrap justify-center"
      >
        <span v-if="contact.created_at">
          {{ contactSince }}
        </span>
        <a
          :href="contactProfileLink"
          target="_blank"
          rel="noopener nofollow noreferrer"
          class="inline-flex items-center gap-0.5 text-n-slate-11 hover:text-n-slate-12"
          title="Abrir a página completa do contato"
        >
          <span class="i-lucide-external-link text-[11px]" /> perfil completo
        </a>
      </p>
    </div>

    <!-- ações redondas com rótulo -->
    <div class="cv-side-actions mt-4">
      <button
        class="cv-side-action cv-side-action-main"
        title="Começar uma conversa com esta pessoa por qualquer caixa"
        @click="openNovaConversa({ contactId: contact.id })"
      >
        <span class="cv-side-action-btn"
          ><span class="i-lucide-message-square-plus"
        /></span>
        <span>Conversa</span>
      </button>
      <div class="cv-side-action" title="Ligar">
        <CevicoCallButton
          :phone="contact.phone_number"
          :contact-id="contact.id"
          :inbox-id="currentChat?.inbox_id"
          :ghost="false"
          faded
        />
        <span>Ligar</span>
      </div>
      <div
        v-if="!cevicoCallsOn"
        class="cv-side-action"
        title="Ligar (Chatwoot)"
      >
        <VoiceCallButton
          :phone="contact.phone_number"
          :contact-id="contact.id"
          :conversation-id="currentChat?.id"
          icon="i-lucide-phone"
          sm
          faded
          slate
          :tooltip-label="$t('CONTACT_PANEL.CALL')"
        />
        <span>Ligar</span>
      </div>
      <button
        class="cv-side-action"
        title="Editar o cadastro"
        @click="toggleEditModal"
      >
        <span class="cv-side-action-btn"
          ><span class="i-lucide-pencil-line"
        /></span>
        <span>Editar</span>
      </button>
      <ContactMergeModal :primary-contact="contact">
        <template #trigger>
          <button
            class="cv-side-action"
            title="Juntar com outro cadastro da mesma pessoa"
            :disabled="uiFlags.isMerging"
          >
            <span class="cv-side-action-btn"
              ><span class="i-lucide-merge"
            /></span>
            <span>Mesclar</span>
          </button>
        </template>
      </ContactMergeModal>
      <ContactDeleteModal
        v-if="isAdmin"
        :contact="contact"
        @deleted="$emit('panelClose')"
      >
        <template #trigger>
          <button
            class="cv-side-action cv-side-action-danger"
            title="Excluir o contato"
            :disabled="uiFlags.isDeleting"
          >
            <span class="cv-side-action-btn"
              ><span class="i-lucide-trash-2"
            /></span>
            <span>Excluir</span>
          </button>
        </template>
      </ContactDeleteModal>
    </div>

    <!-- dados de contato: telefone sempre (é o WhatsApp), o resto só se existir -->
    <div class="cv-side-rows mt-4">
      <ContactInfoRow
        :href="contact.phone_number ? `tel:${contact.phone_number}` : ''"
        :value="contact.phone_number"
        icon="call"
        emoji="📞"
        :title="$t('CONTACT_PANEL.PHONE_NUMBER')"
        show-copy
        editable
        @update="value => onFieldUpdate('phone_number', value)"
      />
      <ContactInfoRow
        :href="contact.email ? `mailto:${contact.email}` : ''"
        :value="contact.email"
        icon="mail"
        emoji="✉️"
        :title="$t('CONTACT_PANEL.EMAIL_ADDRESS')"
        show-copy
        editable
        @update="value => onFieldUpdate('email', value)"
      />
      <ContactInfoRow
        v-if="contact.identifier"
        :value="contact.identifier"
        icon="contact-identify"
        emoji="🪪"
        :title="$t('CONTACT_PANEL.IDENTIFIER')"
      />
      <ContactInfoRow
        v-if="additionalAttributes.company_name"
        :value="additionalAttributes.company_name"
        icon="building-bank"
        emoji="🏢"
        :title="$t('CONTACT_PANEL.COMPANY')"
        editable
        @update="
          value =>
            updateContactField({
              additional_attributes: {
                ...additionalAttributes,
                company_name: value,
              },
            })
        "
      />
      <ContactInfoRow
        v-if="location || additionalAttributes.location"
        :value="location || additionalAttributes.location"
        icon="map"
        emoji="🌍"
        :title="$t('CONTACT_PANEL.LOCATION')"
      />
      <SocialIcons :social-profiles="socialProfiles" />
    </div>
    <EditContact
      :show="showEditModal"
      :contact="contact"
      @cancel="toggleEditModal"
    />
  </div>
</template>
