import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

// 🏠 11/11/2026 (LIFE, pedido do Guilherme): o NOME do ambiente da pessoa (a
// página com tudo dela) vem do vocabulário da empresa (Cevico::Company,
// palavras 'espaco' e 'o_espaco'): "Espaço do Paciente" na clínica, "Central
// do cliente" na LIFE. Só o rótulo muda — rota (patient_space), chaves e nós
// de acesso continuam os mesmos.
//   spaceName       "Central do cliente"
//   theSpace        "a Central do cliente"   (para frases: `n${theSpace}`)
//   openSpaceLabel  "Abrir a Central do cliente"
// Antes de as configurações chegarem vale o nome de sempre.
export const DEFAULT_SPACE_NAME = 'Espaço do Paciente';

export const spaceWords = vocabulary => {
  const name = vocabulary?.espaco || DEFAULT_SPACE_NAME;
  const withArticle = vocabulary?.o_espaco || `o ${name}`;
  return { name, withArticle, open: `Abrir ${withArticle}` };
};

export function useCevicoSpaceName() {
  const company = useMapGetter('crm/getCompany');
  const words = computed(() => spaceWords(company.value?.vocabulary));
  return {
    spaceName: computed(() => words.value.name),
    theSpace: computed(() => words.value.withArticle),
    openSpaceLabel: computed(() => words.value.open),
  };
}
