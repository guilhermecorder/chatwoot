<script setup>
// 🧭 item 394 (11/11) — JORNADA DO PACIENTE de ponta a ponta, numa trilha só:
//   chegou → conversou → orçamento → agendou → confirmou → compareceu →
//   indicação → fechou → operou → pós-operatório
// Cada etapa é um cartão com o número do período, a variação contra a BASE DE
// COMPARAÇÃO (subiu/caiu) e a LINHA dia a dia com a linha de antes desenhada
// junto, mais clara. Tocar numa etapa abre o gráfico grande dela embaixo, com
// o que conta e o rendimento sobre a etapa anterior. Embaixo, os DESVIOS do
// caminho (faltou, remarcou, cancelou). Pedido dele: "enriquecer… para
// visualizar melhor a jornada do paciente… gosto daquelas linhas… sempre ter
// uma base de comparação".
//
// `dados` = payload de Crm::JourneyService (composable useCevicoJourney).
import { ref, computed, watch } from 'vue';
import { variation, variationText } from 'dashboard/helper/cevicoComparison';
import CompareLine from 'dashboard/components-next/cevico/CompareLine.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CvBloco from './CvBloco.vue';

const props = defineProps({
  dados: { type: Object, default: null },
  carregando: { type: Boolean, default: false },
  // etapa aberta ao entrar
  inicial: { type: String, default: 'agendaram' },
  // painel clássico: botão para recolher o bloco (o pai guarda a escolha)
  recolhivel: { type: Boolean, default: false },
  recolhida: { type: Boolean, default: false },
});
const emit = defineEmits(['alternar']);

const n = v => Number(v || 0).toLocaleString('pt-BR');
const pct = v =>
  `${Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;

const etapas = computed(() => props.dados?.etapas || []);
const desvios = computed(() => props.dados?.desvios || []);
const base = computed(() => props.dados?.comparacao || {});
const rotuloBase = computed(() => base.value.rotulo || 'período anterior');
const balde = computed(() =>
  props.dados?.balde === 'mes' ? 'mês a mês' : 'dia a dia'
);

// rendimento sobre a etapa-base (ex.: agendaram ÷ chegaram), agora e antes
const rendimento = etapa => {
  if (!etapa?.base) return null;
  const ref0 = etapas.value.find(e => e.key === etapa.base);
  if (!ref0 || !ref0.valor) return null;
  const agora = (etapa.valor / ref0.valor) * 100;
  const antes = ref0.anterior ? (etapa.anterior / ref0.anterior) * 100 : null;
  return {
    de: ref0.label,
    agora,
    antes,
    dif: antes === null ? null : variation(agora, antes, { pontos: true }),
  };
};

const cartao = (etapa, i = null) => {
  const bom = etapa.bom_quando_sobe !== false;
  return {
    ...etapa,
    ordem: i === null ? null : i + 1,
    bom,
    dif: variation(etapa.valor, etapa.anterior, { bomQuandoSobe: bom }),
    rend: rendimento(etapa),
  };
};
const trilha = computed(() => etapas.value.map((e, i) => cartao(e, i)));
const fora = computed(() => desvios.value.map(e => cartao(e)));

const aberta = ref(props.inicial);
watch(
  () => props.dados,
  () => {
    const todas = [...etapas.value, ...desvios.value];
    if (todas.length && !todas.some(e => e.key === aberta.value))
      aberta.value = todas[0].key;
  }
);
const detalhe = computed(
  () =>
    [...trilha.value, ...fora.value].find(e => e.key === aberta.value) || null
);
const detalheCmp = computed(() =>
  detalhe.value
    ? variationText(
        detalhe.value.valor,
        detalhe.value.anterior,
        rotuloBase.value,
        { bomQuandoSobe: detalhe.value.bom, format: n }
      )
    : null
);
const vazio = computed(
  () =>
    !!props.dados &&
    [...etapas.value, ...desvios.value].every(e => !e.valor && !e.anterior)
);
</script>

<template>
  <CvBloco
    titulo="Jornada do paciente"
    subtitulo="Do primeiro contato ao pós-operatório: o que aconteceu em cada etapa no período e como foi na base de comparação."
    tom="dia"
    icon="i-lucide-route"
    class="cvj"
  >
    <template v-if="recolhivel" #acoes>
      <button
        type="button"
        class="cvj-recolher"
        :aria-expanded="!recolhida"
        @click="emit('alternar')"
      >
        <span
          :class="recolhida ? 'i-lucide-chevron-down' : 'i-lucide-chevron-up'"
          aria-hidden="true"
        />
        {{ recolhida ? 'Abrir a jornada' : 'Recolher' }}
      </button>
    </template>
    <SkeletonScreen
      v-if="!recolhida && carregando && !dados"
      variant="dashboard"
    />
    <p v-else-if="!recolhida && !dados" class="cvj-nota">
      Não consegui carregar a jornada agora. Troque o período ou recarregue.
    </p>
    <template v-else-if="!recolhida">
      <p class="cvj-legenda">
        <span><i class="cvj-traco" /> {{ dados.periodo?.datas }}</span>
        <span>
          <i class="cvj-traco cvj-traco--antes" /> {{ rotuloBase }}
          <template v-if="base.datas"> ({{ base.datas }})</template>
        </span>
        <span class="cvj-legenda-fim">
          {{ balde }} · toque numa etapa para abrir
        </span>
      </p>

      <!-- ══ a trilha: uma etapa por cartão ══ -->
      <div class="cvj-trilha">
        <button
          v-for="e in trilha"
          :key="e.key"
          type="button"
          class="cvj-etapa"
          :class="{ 'cvj-etapa--on': aberta === e.key }"
          :aria-pressed="aberta === e.key"
          @click="aberta = e.key"
        >
          <span class="cvj-etapa-topo">
            <span class="cvj-ordem">{{ e.ordem }}</span>
            <span :class="e.icon" class="cvj-icone" aria-hidden="true" />
            <span class="cvj-var" :class="`cvj-var--${e.dif.estado}`">
              {{ e.dif.seta }} {{ e.dif.curto }}
            </span>
          </span>
          <span class="cvj-rotulo">{{ e.label }}</span>
          <span class="cvj-valor">{{ n(e.valor) }}</span>
          <span class="cvj-antes">antes {{ n(e.anterior) }}</span>
          <CompareLine
            class="cvj-linha"
            :values="e.serie"
            :prev-values="e.serie_anterior"
            :labels="dados.rotulos"
            :prev-labels="dados.rotulos_anterior"
            :height="44"
            :legend="false"
            :color="aberta === e.key ? '#ffffff' : ''"
            bare
          />
          <span class="cvj-rend">
            <template v-if="e.rend">
              {{ pct(e.rend.agora) }} de “{{ e.rend.de }}”
            </template>
            <template v-else>{{ e.medida }}</template>
          </span>
        </button>
      </div>

      <!-- ══ a etapa aberta: gráfico grande + o que conta ══ -->
      <div v-if="detalhe" class="cvj-detalhe">
        <div class="cvj-detalhe-graf">
          <span class="cvj-detalhe-titulo">
            <span>{{ detalhe.label }} · {{ balde }}</span>
            <span>agora × {{ rotuloBase }}</span>
          </span>
          <CompareLine
            :values="detalhe.serie"
            :prev-values="detalhe.serie_anterior"
            :labels="dados.rotulos"
            :prev-labels="dados.rotulos_anterior"
            :current-label="dados.periodo?.datas || 'agora'"
            :previous-label="rotuloBase"
            :unit="detalhe.medida"
            :good-when-up="detalhe.bom"
            :height="220"
          />
        </div>
        <div class="cvj-detalhe-texto">
          <span class="cvj-rotulo">{{ detalhe.label }}</span>
          <span class="cvj-detalhe-valor">
            {{ n(detalhe.valor) }}
            <small>{{ detalhe.medida }}</small>
          </span>
          <span
            v-if="detalheCmp"
            class="cvj-detalhe-cmp"
            :class="`cvj-var--${detalheCmp.estado}`"
          >
            <template v-if="detalheCmp.seta">{{ detalhe.dif.seta }}</template>
            {{ detalheCmp.texto }}
          </span>
          <p v-if="detalhe.rend" class="cvj-detalhe-p">
            <b>Rendimento:</b> {{ pct(detalhe.rend.agora) }} de “{{
              detalhe.rend.de
            }}”<template v-if="detalhe.rend.antes !== null">
              (antes {{ pct(detalhe.rend.antes)
              }}<template
                v-if="detalhe.rend.dif && detalhe.rend.dif.curto !== 'igual'"
              >
                , {{ detalhe.rend.dif.curto }} </template
              >) </template
            >. É a conta do período: divide esta etapa pela anterior e mistura
            turmas — quem está aqui agora pode ter chegado antes.
          </p>
          <p class="cvj-detalhe-p"><b>O que conta:</b> {{ detalhe.formula }}</p>
        </div>
      </div>

      <!-- ══ desvios do caminho ══ -->
      <div v-if="fora.length" class="cvj-desvios">
        <span class="cvj-desvios-titulo">
          Na Agenda e os desvios do caminho
        </span>
        <div class="cvj-trilha cvj-trilha--desvios">
          <button
            v-for="e in fora"
            :key="e.key"
            type="button"
            class="cvj-etapa cvj-etapa--desvio"
            :class="{ 'cvj-etapa--on': aberta === e.key }"
            :aria-pressed="aberta === e.key"
            @click="aberta = e.key"
          >
            <span class="cvj-etapa-topo">
              <span :class="e.icon" class="cvj-icone" aria-hidden="true" />
              <span class="cvj-var" :class="`cvj-var--${e.dif.estado}`">
                {{ e.dif.seta }} {{ e.dif.curto }}
              </span>
            </span>
            <span class="cvj-rotulo">{{ e.label }}</span>
            <span class="cvj-valor">{{ n(e.valor) }}</span>
            <span class="cvj-antes">antes {{ n(e.anterior) }}</span>
            <CompareLine
              class="cvj-linha"
              :values="e.serie"
              :prev-values="e.serie_anterior"
              :labels="dados.rotulos"
              :prev-labels="dados.rotulos_anterior"
              :height="44"
              :legend="false"
              :color="aberta === e.key ? '#ffffff' : ''"
              :good-when-up="e.bom"
              bare
            />
            <span class="cvj-rend">{{ e.medida }}</span>
          </button>
        </div>
      </div>

      <p v-if="vazio" class="cvj-nota">
        Nada aconteceu nas etapas neste período nem na base de comparação.
      </p>
    </template>
  </CvBloco>
</template>

<style lang="scss">
/* 🧭 Jornada do paciente (item 394) — vive dentro de .cv-page (Meu Painel) */
.cv-page .cvj-recolher {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 32px;
  padding: 0 12px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
  color: var(--g-texto-2, #4b5563);
  background: rgb(var(--cv-rgb) / 0.1);
  border: 1px solid rgb(var(--cv-rgb) / 0.2);
  cursor: pointer;
}
.cv-page .cvj-recolher:hover {
  background: rgb(var(--cv-rgb) / 0.18);
}
.cv-page .cvj-legenda {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 18px;
  margin: 0 0 12px;
  font-size: 12px;
  line-height: 18px;
  color: var(--g-texto-2, #4b5563);
}
.cv-page .cvj-legenda-fim {
  margin-left: auto;
  color: var(--g-texto-3, #6b7280);
}
.cv-page .cvj-traco {
  display: inline-block;
  width: 18px;
  height: 0;
  margin-right: 4px;
  border-top: 3px solid var(--cv);
  border-radius: 2px;
  vertical-align: middle;
}
.cv-page .cvj-traco--antes {
  border-top: 2px dashed var(--cv);
  opacity: 0.55;
}
.cv-page .cvj-trilha {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 12px;
}
.cv-page .cvj-trilha--desvios {
  grid-template-columns: repeat(4, minmax(0, 1fr));
}
@media (max-width: 1280px) {
  .cv-page .cvj-trilha {
    grid-template-columns: repeat(4, minmax(0, 1fr));
  }
}
@media (max-width: 980px) {
  .cv-page .cvj-trilha {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
  .cv-page .cvj-trilha--desvios {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
@media (max-width: 640px) {
  .cv-page .cvj-trilha,
  .cv-page .cvj-trilha--desvios {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
  }
}
.cv-page .cvj-etapa {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
  padding: 12px 12px 10px;
  text-align: left;
  font: inherit;
  color: var(--g-texto, #111827);
  background: rgb(var(--cv-rgb) / 0.08);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
  border-radius: var(--g-raio-md, 14px);
  cursor: pointer;
  transition:
    transform 160ms ease,
    box-shadow 160ms ease,
    background 160ms ease;
}
.dark .cv-page .cvj-etapa {
  background: rgb(var(--cv-rgb) / 0.16);
  border-color: rgb(var(--cv-rgb) / 0.32);
}
.cv-page .cvj-etapa:hover {
  transform: translateY(-1px);
  box-shadow: 0 8px 20px -10px rgb(var(--cv-rgb) / 0.5);
}
.cv-page .cvj-etapa:focus-visible {
  outline: 2px solid var(--cv);
  outline-offset: 2px;
}
/* etapa aberta: o degradê cheio da família, tudo em branco */
.cv-page .cvj-etapa--on,
.dark .cv-page .cvj-etapa--on {
  color: #fff;
  background: var(--cv-grad, var(--cv));
  border-color: rgb(255 255 255 / 0.36);
  box-shadow:
    inset 0 1px 0 rgb(255 255 255 / 0.4),
    0 14px 28px -14px rgb(var(--cv-rgb) / 0.75);
}
.cv-page .cvj-etapa-topo {
  display: flex;
  align-items: center;
  gap: 6px;
  min-height: 22px;
}
.cv-page .cvj-ordem {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
  color: #fff;
  background: var(--cv);
  flex-shrink: 0;
}
.cv-page .cvj-etapa--on .cvj-ordem {
  color: var(--cv-deep, var(--cv));
  background: #fff;
}
.cv-page .cvj-icone {
  font-size: 15px;
  color: var(--cv);
  flex-shrink: 0;
}
.cv-page .cvj-etapa--on .cvj-icone {
  color: #fff;
}
.cv-page .cvj-var {
  margin-left: auto;
  font-size: 12px;
  line-height: 16px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.cv-page .cvj-var--bom {
  color: var(--g-bom, #15803d);
}
.cv-page .cvj-var--atencao {
  color: var(--g-atencao, #b45309);
}
.cv-page .cvj-var--neutro {
  color: var(--g-texto-3, #6b7280);
  font-weight: 500;
}
.cv-page .cvj-etapa--on .cvj-var--bom {
  color: #d9ffe6;
}
.cv-page .cvj-etapa--on .cvj-var--atencao {
  color: #ffe9b3;
}
.cv-page .cvj-etapa--on .cvj-var--neutro {
  color: rgb(255 255 255 / 0.8);
}
.cv-page .cvj-rotulo {
  margin-top: 6px;
  font-size: 13px;
  line-height: 18px;
  font-weight: 500;
  color: var(--g-texto-2, #4b5563);
  overflow-wrap: anywhere;
}
.cv-page .cvj-etapa--on .cvj-rotulo {
  color: rgb(255 255 255 / 0.9);
}
.cv-page .cvj-valor {
  font-size: 28px;
  line-height: 32px;
  font-weight: 600;
  letter-spacing: -0.01em;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.cv-page .cvj-antes,
.cv-page .cvj-rend {
  font-size: 12px;
  line-height: 16px;
  color: var(--g-texto-3, #6b7280);
  font-variant-numeric: tabular-nums;
  overflow-wrap: anywhere;
}
.cv-page .cvj-etapa--on .cvj-antes,
.cv-page .cvj-etapa--on .cvj-rend {
  color: rgb(255 255 255 / 0.82);
}
.cv-page .cvj-linha {
  margin: 6px 0 4px;
}
.cv-page .cvj-detalhe {
  display: grid;
  grid-template-columns: minmax(0, 1.7fr) minmax(0, 1fr);
  gap: 20px;
  margin-top: 16px;
  padding: 16px;
  border-radius: var(--g-raio-md, 14px);
  background: rgb(var(--cv-rgb) / 0.06);
}
.dark .cv-page .cvj-detalhe {
  background: rgb(255 255 255 / 0.04);
}
@media (max-width: 980px) {
  .cv-page .cvj-detalhe {
    grid-template-columns: 1fr;
  }
}
.cv-page .cvj-detalhe-graf {
  min-width: 0;
}
.cv-page .cvj-detalhe-titulo {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 4px 12px;
  margin-bottom: 8px;
  font-size: 13px;
  line-height: 18px;
  font-weight: 500;
  letter-spacing: 0.02em;
  color: var(--g-texto-2, #4b5563);
}
.cv-page .cvj-detalhe-texto {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}
.cv-page .cvj-detalhe-texto .cvj-rotulo {
  margin-top: 0;
}
.cv-page .cvj-detalhe-valor {
  font-size: 44px;
  line-height: 48px;
  font-weight: 600;
  letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums;
  color: var(--gd, var(--cv));
}
.cv-page .cvj-detalhe-valor small {
  font-size: 13px;
  font-weight: 500;
  letter-spacing: 0;
  color: var(--g-texto-3, #6b7280);
}
.cv-page .cvj-detalhe-cmp {
  font-size: 14px;
  line-height: 20px;
  font-weight: 600;
}
.cv-page .cvj-detalhe-p {
  margin: 4px 0 0;
  font-size: 13px;
  line-height: 20px;
  color: var(--g-texto-2, #4b5563);
}
.cv-page .cvj-detalhe-p b {
  font-weight: 600;
  color: var(--g-texto, #111827);
}
.cv-page .cvj-desvios {
  margin-top: 20px;
}
.cv-page .cvj-desvios-titulo {
  display: block;
  margin-bottom: 8px;
  font-size: 13px;
  line-height: 18px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: var(--g-texto-2, #4b5563);
}
.cv-page .cvj-nota {
  margin: 12px 0 0;
  font-size: 13px;
  line-height: 20px;
  color: var(--g-texto-3, #6b7280);
}
</style>
