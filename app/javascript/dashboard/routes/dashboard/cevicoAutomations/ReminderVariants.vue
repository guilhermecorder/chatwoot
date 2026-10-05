<script setup>
// 🎯 MODELOS PERSONALIZADOS do lembrete de confirmação (item 327, 05/10).
// Pedido do Guilherme: "vamos precisar de modelos de mensagens específicos
// para quando for RETORNO… e também quero poder personalizar POR MÉDICO".
//
// Cada cartão é uma regra "para quem": um tipo de atendimento, um médico, ou
// os dois — com os SEUS modelos (Av. Paulista, Tatuapé, geral e reforço),
// escolhidos da lista de modelos aprovados do número desta caixa. Quem não se
// encaixa em nenhum cartão recebe os modelos padrão, logo acima.
// Vale sempre o mais específico: médico + tipo → médico → tipo → padrão; e,
// dentro de cada um, o modelo da unidade da consulta antes do geral.
//
// O pai (ConfirmationAgentCard) é dono dos dados e de como salvar; aqui é só
// a edição. `variants` é a lista reativa do pai, alterada no lugar.
import { computed } from 'vue';
import { DOCTORS } from 'dashboard/helper/cevicoAgenda';

const props = defineProps({
  variants: { type: Array, required: true },
  // modelos APROVADOS do número desta caixa
  templates: { type: Array, default: () => [] },
  // o que cada {{n}} costuma ser (1 nome, 2 data, 3 horário, 4 valor)
  suggestedVars: { type: Object, default: () => ({}) },
  uid: { type: [String, Number], default: '' },
  withFollowup: { type: Boolean, default: false },
  boxName: { type: String, default: '' },
});
const emit = defineEmits(['touch']);

const TYPES = [
  { key: '', label: 'Qualquer tipo' },
  { key: 'avaliacao', label: 'Avaliação', color: '#2563EB' },
  { key: 'retorno', label: 'Retorno', color: '#D4A017' },
  { key: 'pos_op', label: 'Pós-operatório', color: '#DB2777' },
  { key: 'exames', label: 'Exame', color: '#0D9488' },
  { key: 'teleconsulta', label: 'Teleconsulta', color: '#7C3AED' },
];
const SLOTS = [
  { key: 'paulista', label: 'Av. Paulista' },
  { key: 'tatuape', label: 'Tatuapé' },
  { key: 'geral', label: 'Geral', hint: 'outros locais / reserva' },
];
const blankSlot = () => ({ name: '', vars: {}, saved: null, preview: '' });

const typeOf = v => TYPES.find(t => t.key === (v.modality || '')) || TYPES[0];
const doctorColor = name =>
  DOCTORS.find(d => d.name === name)?.color || '#64748B';
const accent = v =>
  v.doctor ? doctorColor(v.doctor) : typeOf(v).color || '#64748B';
const title = v => {
  const parts = [v.modality ? typeOf(v).label : '', v.doctor].filter(Boolean);
  return parts.length ? parts.join(' · ') : 'Escolha o tipo ou o médico';
};
const incomplete = v => !v.modality && !v.doctor;
const slotsOf = v => [
  ...SLOTS.map(s => ({ ...s, slot: v.slots[s.key] })),
  ...(props.withFollowup
    ? [
        {
          key: 'followup',
          label: 'Reforço',
          hint: 'para quem não respondeu',
          slot: v.followup,
        },
      ]
    : []),
];
const chosenCount = v => slotsOf(v).filter(s => s.slot.name).length;
// duas regras para o mesmo "para quem" — só a primeira valeria
const duplicated = computed(() => {
  const seen = new Set();
  const dup = new Set();
  props.variants.forEach(v => {
    const k = `${v.modality || ''}|${(v.doctor || '').toLowerCase()}`;
    if (seen.has(k)) dup.add(k);
    seen.add(k);
  });
  return v => dup.has(`${v.modality || ''}|${(v.doctor || '').toLowerCase()}`);
});

const tplOf = slot => props.templates.find(t => t.name === slot.name) || null;
const bodyOf = slot =>
  tplOf(slot)?.components?.find(c => c.type === 'BODY')?.text ||
  slot.preview ||
  '';
const tokensOf = slot => {
  const found = new Set();
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  const body = bodyOf(slot);
  let m = re.exec(body);
  while (m !== null) {
    found.add(m[1]);
    m = re.exec(body);
  }
  return [...found];
};
const varHint = token =>
  props.suggestedVars[token]
    ? `{{${token}}} — em branco = ${props.suggestedVars[token]} (da Agenda)`
    : `{{${token}}} — escreva o texto ou uma variável`;
const touch = () => emit('touch');
const onPick = slot => {
  slot.vars = {};
  tokensOf(slot).forEach(t => {
    slot.vars[t] = props.suggestedVars[t] || '';
  });
  touch();
};

const add = () => {
  props.variants.push({
    id: `v${Date.now().toString(36)}`,
    modality: 'retorno',
    doctor: '',
    slots: { paulista: blankSlot(), tatuape: blankSlot(), geral: blankSlot() },
    followup: blankSlot(),
    open: true,
  });
  touch();
};
const remove = idx => {
  props.variants.splice(idx, 1);
  touch();
};
</script>

<template>
  <div class="cv-rv">
    <div class="flex items-start gap-3 flex-wrap">
      <span class="cv-rv-icon"><span class="i-lucide-wand-sparkles" /></span>
      <div class="flex-1 min-w-0">
        <p class="cv-rv-title">
          Modelos personalizados{{ boxName ? ` · ${boxName}` : '' }}
        </p>
        <p class="cv-rv-sub">
          Uma mensagem própria para um tipo de atendimento (retorno,
          pós-operatório, exame…), para um médico, ou para os dois. Quem não se
          encaixa em nenhum recebe os modelos padrão acima.
        </p>
      </div>
      <button
        type="button"
        class="cv-btn cv-btn-sm"
        :disabled="variants.length >= 16"
        @click="add"
      >
        <span class="i-lucide-plus text-xs" /> Novo modelo personalizado
      </button>
    </div>

    <p v-if="!variants.length" class="cv-rv-empty">
      Nenhum ainda. Exemplo: crie um para <b>Retorno</b> (sem valor de consulta)
      e outro para a <b>Dra. Roberta</b>.
    </p>

    <div
      v-for="(v, idx) in variants"
      :key="uid + 'rv' + v.id"
      class="cv-rv-card"
      :style="{ '--rv': accent(v) }"
    >
      <!-- cabeçalho: para quem vale + resumo; clica para abrir/fechar -->
      <div class="cv-rv-head">
        <button
          type="button"
          class="flex items-center gap-2 flex-1 min-w-0 text-left"
          @click="v.open = !v.open"
        >
          <span class="cv-rv-dot" />
          <span class="cv-rv-name">{{ title(v) }}</span>
          <span class="cv-rv-count">
            {{ chosenCount(v) }} modelo{{ chosenCount(v) === 1 ? '' : 's' }}
          </span>
          <span
            v-if="incomplete(v)"
            class="cv-rv-warn"
            title="Sem tipo e sem médico este cartão não vale para ninguém"
            >escolha para quem</span
          >
          <span
            v-else-if="duplicated(v)"
            class="cv-rv-warn"
            title="Já existe outro cartão para o mesmo tipo e médico — só o primeiro vale"
            >repetido</span
          >
          <span
            :class="v.open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            class="text-sm ml-auto shrink-0"
          />
        </button>
        <button
          type="button"
          class="cv-btn cv-btn-ghost cv-btn-sm cv-iconbtn"
          title="Apagar este modelo personalizado"
          @click="remove(idx)"
        >
          <span class="i-lucide-trash-2 text-xs" />
        </button>
      </div>

      <div v-if="v.open" class="cv-rv-body">
        <!-- para quem -->
        <div class="grid grid-cols-1 lg:grid-cols-[1.6fr_1fr] gap-3">
          <div>
            <p class="cv-rv-label">Tipo de atendimento</p>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="t in TYPES"
                :key="uid + v.id + 't' + t.key"
                type="button"
                class="cv-chip"
                :class="(v.modality || '') === t.key ? 'cv-chip-on' : ''"
                @click="
                  v.modality = t.key;
                  touch();
                "
              >
                {{ t.label }}
              </button>
            </div>
          </div>
          <div>
            <p class="cv-rv-label">Médico</p>
            <select
              v-model="v.doctor"
              class="cv-input w-full !h-8 text-xs"
              style="margin-bottom: 0"
              @change="touch"
            >
              <option value="">Qualquer médico</option>
              <option
                v-for="d in DOCTORS"
                :key="uid + v.id + d.name"
                :value="d.name"
              >
                {{ d.name }}
              </option>
            </select>
          </div>
        </div>

        <!-- os modelos deste cartão -->
        <div
          class="grid grid-cols-1 gap-2"
          :class="withFollowup ? 'lg:grid-cols-4' : 'lg:grid-cols-3'"
        >
          <div
            v-for="s in slotsOf(v)"
            :key="uid + v.id + s.key"
            class="cv-stat p-3 space-y-1.5"
          >
            <p class="text-[11px] font-bold text-n-slate-12">
              {{ s.label }}
              <span v-if="s.hint" class="font-normal text-n-slate-9"
                >({{ s.hint }})</span
              >
            </p>
            <select
              v-model="s.slot.name"
              class="cv-input w-full !h-8 text-xs"
              style="margin-bottom: 0"
              @change="onPick(s.slot)"
            >
              <option value="">— usa o padrão —</option>
              <option
                v-if="
                  s.slot.name && !templates.some(t => t.name === s.slot.name)
                "
                :value="s.slot.name"
              >
                {{ s.slot.name }} (salva)
              </option>
              <option
                v-for="t in templates"
                :key="uid + v.id + s.key + t.name + t.language"
                :value="t.name"
              >
                {{ t.name }} ({{ t.language }})
              </option>
            </select>
            <template v-if="s.slot.name">
              <p
                class="text-[10px] text-n-slate-10 whitespace-pre-wrap max-h-28 overflow-auto bg-n-alpha-1 rounded-lg px-2 py-1.5"
              >
                {{ bodyOf(s.slot) || 'prévia indisponível' }}
              </p>
              <input
                v-for="token in tokensOf(s.slot)"
                :key="uid + v.id + s.key + 'v' + token"
                v-model="s.slot.vars[token]"
                class="cv-input w-full !h-7 text-[11px] font-mono"
                style="margin-bottom: 0"
                :placeholder="varHint(token)"
                @input="touch"
              />
            </template>
          </div>
        </div>
        <p class="text-[10px] text-n-slate-9">
          Em branco = usa o padrão. Ex.: só a Av. Paulista preenchida → no
          Tatuapé este atendimento segue o modelo padrão do Tatuapé.
        </p>
      </div>
    </div>

    <p v-if="variants.length" class="cv-rv-rule">
      <span class="i-lucide-list-ordered text-xs" />
      Vale sempre o mais específico: <b>médico + tipo</b> → <b>médico</b> →
      <b>tipo</b> → <b>padrão</b>. Dentro de cada um, o modelo da unidade da
      consulta antes do geral.
    </p>
  </div>
</template>

<style scoped>
.cv-rv {
  margin-top: 0.75rem;
  padding: 0.9rem;
  border-radius: 1rem;
  border: 1px dashed rgb(var(--cv-rgb, 37 99 235) / 0.45);
  background: rgb(var(--cv-rgb, 37 99 235) / 0.04);
}
.cv-rv-icon {
  width: 2rem;
  height: 2rem;
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 0.7rem;
  color: #fff;
  background: linear-gradient(135deg, #7c3aed, #ec4899);
}
.cv-rv-title {
  font-size: 0.9rem;
  font-weight: 800;
  line-height: 1.2;
}
.cv-rv-sub {
  font-size: 0.7rem;
  line-height: 1.4;
  opacity: 0.7;
  margin-top: 2px;
}
.cv-rv-empty {
  font-size: 0.72rem;
  opacity: 0.75;
  margin-top: 0.7rem;
}
.cv-rv-card {
  margin-top: 0.7rem;
  border-radius: 0.9rem;
  border: 1px solid color-mix(in srgb, var(--rv) 35%, transparent);
  border-left: 5px solid var(--rv);
  background: color-mix(in srgb, var(--rv) 5%, transparent);
  overflow: hidden;
}
.cv-rv-head {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.55rem 0.7rem;
}
.cv-rv-dot {
  width: 0.65rem;
  height: 0.65rem;
  flex-shrink: 0;
  border-radius: 9999px;
  background: var(--rv);
}
.cv-rv-name {
  font-size: 0.85rem;
  font-weight: 800;
  overflow-wrap: anywhere;
}
.cv-rv-count {
  font-size: 0.68rem;
  font-weight: 700;
  padding: 1px 8px;
  border-radius: 9999px;
  white-space: nowrap;
  color: var(--rv);
  background: color-mix(in srgb, var(--rv) 14%, transparent);
}
.cv-rv-warn {
  font-size: 0.66rem;
  font-weight: 700;
  padding: 1px 8px;
  border-radius: 9999px;
  white-space: nowrap;
  color: #92400e;
  background: #fde68a;
}
.cv-rv-body {
  padding: 0.2rem 0.7rem 0.8rem;
  display: flex;
  flex-direction: column;
  gap: 0.7rem;
}
.cv-rv-label {
  font-size: 0.66rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  opacity: 0.7;
  margin-bottom: 0.3rem;
}
.cv-rv-rule {
  display: flex;
  align-items: baseline;
  gap: 0.35rem;
  flex-wrap: wrap;
  font-size: 0.68rem;
  opacity: 0.75;
  margin-top: 0.7rem;
}
</style>
