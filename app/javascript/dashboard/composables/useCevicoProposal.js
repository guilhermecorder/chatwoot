import { computed, onUnmounted, ref, unref, watch } from 'vue';
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
  // { auto: true } (12/11): abre já fazendo o orçamento sozinho (Gerador → "Orçamento automático")
  const openProposal = (contactId, { auto = false } = {}) => {
    if (!contactId) return;
    router.push({
      name: 'crm_cotador',
      params: { accountId: route.params.accountId },
      query: auto ? { contact: contactId, auto: '1' } : { contact: contactId },
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

  // 12/11: a conta chegou com a conversa aberta e o cadeado só saía no clique. Travado, confere de
  // novo a cada 20 s (com a aba à vista) e quando a janela volta ao foco; liberado, para de conferir.
  const RECHECK_MS = 20000;
  const recheckIfLocked = () => {
    if (!ready.value && document.visibilityState === 'visible') check();
  };
  const timer = setInterval(recheckIfLocked, RECHECK_MS);
  window.addEventListener('focus', recheckIfLocked);
  onUnmounted(() => {
    clearInterval(timer);
    window.removeEventListener('focus', recheckIfLocked);
  });

  const openWhenReady = async () => {
    const id = idOf();
    if (ready.value || (await check())) {
      // na conversa o botão já faz o orçamento sozinho; você confere e envia (12/11)
      openProposal(id, { auto: true });
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
