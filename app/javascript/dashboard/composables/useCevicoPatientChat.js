// 💬 item 298 (30/09): ABRIR A CONVERSA do paciente de qualquer tela (Agenda,
// Espaço do Paciente, botão direito) sem sair de onde está. Abre o MESMO popup
// de conversa do CRM. Paciente que ainda não tem conversa cai no "Nova
// conversa" de sempre (item 199). O popup é montado uma vez no Dashboard
// (PatientChatHost.vue); quem quer abrir chama openPatientChat().
import { reactive } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import { openNovaConversa } from 'dashboard/helper/cevicoNovaConversa';

const state = reactive({ card: null, stages: [], loading: false });

export const closePatientChat = () => {
  state.card = null;
  state.stages = [];
};

// { contactId?, phone? } — pelo menos um dos dois
export const openPatientChat = async ({ contactId, phone } = {}) => {
  if (state.loading) return;
  if (!contactId && !phone) {
    useAlert('Este agendamento não tem paciente ligado nem telefone.');
    return;
  }
  state.loading = true;
  try {
    const { data } = await CrmAPI.patientChat(
      contactId ? { contact_id: contactId } : { phone }
    );
    if (!data.found) {
      useAlert(
        'Não achei o cadastro deste paciente. Abra uma conversa nova pelo telefone.'
      );
      openNovaConversa({});
    } else if (!data.has_conversation) {
      useAlert('Este paciente ainda não tem conversa. Vamos começar uma.');
      openNovaConversa({ contactId: data.card.contact_id });
    } else {
      state.stages = data.stages || [];
      state.card = data.card;
    }
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não consegui abrir a conversa agora.'
    );
  } finally {
    state.loading = false;
  }
};

export const useCevicoPatientChat = () => ({
  state,
  openPatientChat,
  closePatientChat,
});
