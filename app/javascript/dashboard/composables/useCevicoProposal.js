import { computed, ref, unref, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CrmAPI from 'dashboard/api/crm';

// 📄 11/11/2026 (LIFE, pedido do Guilherme): o botão "Gerar orçamento" do Meu
// Painel, da conversa e da Central do cliente. Abre o Gerador de proposta já
// no cliente — …/crm/cotador?contact=<id>. Só aparece para quem tem a área do
// gerador liberada (nó crm.cotador).
export const PROPOSAL_LABEL = 'Gerar orçamento';
export const PROPOSAL_TITLE = 'Abrir o gerador de orçamento já neste cliente';
export const PROPOSAL_WAITING =
  'Libera quando o cliente enviar a conta de luz ou os dados.';

export function useCevicoProposal() {
  const router = useRouter();
  const route = useRoute();
  const { canView } = useCevicoAccess();

  const canMakeProposal = computed(() => canView('crm.cotador'));
  const openProposal = contactId => {
    if (!contactId) return;
    router.push({
      name: 'crm_cotador',
      params: { accountId: route.params.accountId },
      query: { contact: contactId },
    });
  };

  return {
    canMakeProposal,
    openProposal,
    proposalLabel: PROPOSAL_LABEL,
    proposalTitle: PROPOSAL_TITLE,
  };
}

// 🔓 NA CONVERSA o botão só libera depois que o cliente mandou a conta de luz
// ou os dados ("ele seja liberado depois que a pessoa enviou a conta", Guilherme,
// 11/11/2026). Quem decide é o servidor (Crm::KitQuote::Ready): conta anotada
// no resumo do cliente, ou cartão na coluna do orçamento em diante.
//   contactId: ref, getter ou número
// Travado, o clique confere de novo (o cliente pode ter acabado de mandar) e,
// se ainda não liberou, explica o que falta.
export function useProposalReady(contactId) {
  const { canMakeProposal, openProposal } = useCevicoProposal();
  const idOf = () =>
    typeof contactId === 'function' ? contactId() : unref(contactId);

  const ready = ref(false);
  const waiting = ref(PROPOSAL_WAITING);
  let seq = 0;

  const check = async () => {
    const id = idOf();
    seq += 1;
    const mine = seq;
    if (!id || !canMakeProposal.value) {
      ready.value = false;
      return false;
    }
    try {
      const { data } = await CrmAPI.getKitQuoteReady(id);
      if (mine !== seq) return ready.value;
      ready.value = !!data.liberado;
      waiting.value = data.falta || PROPOSAL_WAITING;
    } catch {
      if (mine === seq) ready.value = false;
    }
    return ready.value;
  };
  watch(idOf, check, { immediate: true });
  watch(canMakeProposal, check);

  const openWhenReady = async () => {
    const id = idOf();
    if (ready.value || (await check())) {
      openProposal(id);
    } else {
      useAlert(waiting.value);
    }
  };

  return {
    canMakeProposal,
    proposalReady: ready,
    proposalHint: computed(() =>
      ready.value ? PROPOSAL_TITLE : waiting.value
    ),
    proposalLabel: PROPOSAL_LABEL,
    openWhenReady,
    recheckProposal: check,
  };
}
