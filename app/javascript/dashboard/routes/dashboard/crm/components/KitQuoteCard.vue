<script setup>
// 📦 Caixa de um orçamento guardado (Gerador de proposta, LIFE · 12/11): cliente, valor, até quando
// vale (7 dias), se já foi enviado, os PDFs e as ações (marcar como enviada, abrir o cliente, excluir).
import { computed, reactive, ref } from 'vue';
import { formatMoney as reais } from 'dashboard/helper/proposalBuilder';

const props = defineProps({
  // { id, cliente: { id, nome }, valor, tipo, margem, na_faixa, criado_em, por, enviado_em, valida_ate, valido, arquivos }
  orcamento: { type: Object, required: true },
  mostrarCliente: { type: Boolean, default: true },
  podeEditar: { type: Boolean, default: false },
  ocupado: { type: Boolean, default: false },
  // lixeira (só o dono vê): mostra quem excluiu e o motivo, e o botão Restaurar
  naLixeira: { type: Boolean, default: false },
});
const emit = defineEmits([
  'enviar',
  'abrir',
  'excluir',
  'restaurar',
  'whatsapp',
  'editar',
]);

const NOME_TIPO = {
  micro: 'Micro inversor',
  string: 'Inversor string',
  hibrido: 'Inversor híbrido',
};
const dia = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const soDia = iso =>
  iso
    ? new Date(iso).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      })
    : '';
const pct = v =>
  `${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 }).format((v || 0) * 100)}%`;

// enviado (verde) · valendo (laranja) · vencido (cinza)
const situacao = computed(() => {
  const o = props.orcamento;
  if (props.naLixeira) {
    return {
      cor: '#dc2626',
      icone: 'i-lucide-trash-2',
      texto: `Excluído em ${dia(o.excluido_em)}`,
    };
  }
  if (!o.enviado_em && o.aguardando_envio) {
    return {
      cor: '#2563eb',
      icone: 'i-lucide-hourglass',
      texto: 'Aguardando o cliente responder',
    };
  }
  if (o.enviado_em) {
    return {
      cor: '#16a34a',
      icone: 'i-lucide-send',
      texto: `Enviado em ${dia(o.enviado_em)}`,
    };
  }
  if (o.valido) {
    return {
      cor: '#ea580c',
      icone: 'i-lucide-clock',
      texto: `Vale até ${soDia(o.valida_ate)}`,
    };
  }
  return {
    cor: '#64748b',
    icone: 'i-lucide-calendar-x',
    texto: `Venceu em ${soDia(o.valida_ate)}`,
  };
});

// excluir = mandar para a lixeira, com o motivo (fica registrado quem excluiu)
const excluir = () => {
  const o = props.orcamento;
  // eslint-disable-next-line no-alert
  const motivo = window.prompt(
    `Excluir o orçamento de ${reais(o.valor)}${o.cliente?.nome ? ` de ${o.cliente.nome}` : ''}?\n\nEle vai para a lixeira e fica registrado quem excluiu. Qual o motivo?`
  );
  if (motivo === null) return;
  if (!motivo.trim()) {
    // eslint-disable-next-line no-alert
    window.alert('Escreva o motivo para excluir.');
    return;
  }
  emit('excluir', o, motivo.trim());
};
// ✏️ editar (13/11): nome, cidade/UF, telhado e validade; os PDFs saem de novo
const editando = ref(false);
const form = reactive({
  nome: '',
  cidade: '',
  uf: '',
  telhado: '',
  validade_dias: 7,
});
const abrirEdicao = () => {
  const e = props.orcamento.editavel || {};
  Object.assign(form, {
    nome: e.nome || props.orcamento.cliente?.nome || '',
    cidade: e.cidade || '',
    uf: e.uf || '',
    telhado: e.telhado || '',
    validade_dias: e.validade_dias || 7,
  });
  editando.value = true;
};
const salvarEdicao = () => {
  if (!form.nome.trim()) return;
  emit('editar', props.orcamento, { ...form });
  editando.value = false;
};
const TXT = {
  editar: 'Editar',
  editarDica:
    'Corrigir nome, cidade, telhado ou validade. Os PDFs são gerados de novo.',
  salvar: 'Salvar e gerar os PDFs',
  cancelar: 'Cancelar',
  fNome: 'Nome do cliente',
  fCidade: 'Cidade',
  fUf: 'UF',
  fTelhado: 'Tipo de telhado',
  fValidade: 'Vale por (dias)',
  geradoPor: 'por',
  semArquivos: 'Sem PDF guardado',
  marcarEnviada: 'Marcar como enviada',
  abrir: 'Abrir',
  piso: 'Piso para negociar (20%):',
  whats: 'Enviar pelo WhatsApp',
  whatsDica:
    'Manda a proposta, o resumo e a pergunta de fechamento. Fora da janela de 24 h, manda antes o aviso "seu orçamento está pronto".',
  alguem: 'Alguém',
  excluiu: 'excluiu',
  restaurar: 'Restaurar',
  excluir: 'Excluir',
  lucro: 'lucro',
};
</script>

<template>
  <article class="qc" :style="{ '--s': situacao.cor }">
    <header class="flex items-start gap-3">
      <div class="min-w-0 flex-1">
        <p
          v-if="mostrarCliente"
          class="text-sm font-semibold text-n-slate-12 break-words"
        >
          {{ orcamento.cliente?.nome || 'Cliente' }}
        </p>
        <p class="qc-valor text-n-slate-12">{{ reais(orcamento.valor) }}</p>
        <p class="text-xs text-n-slate-11">
          {{ NOME_TIPO[orcamento.tipo] || orcamento.tipo }} · {{ TXT.lucro }}
          <span
            class="font-semibold"
            :class="orcamento.na_faixa ? 'text-n-teal-11' : 'text-n-ruby-11'"
          >
            {{ pct(orcamento.margem) }}
          </span>
        </p>
        <p v-if="orcamento.piso?.valor" class="qc-floor">
          {{ TXT.piso }} {{ reais(orcamento.piso.valor) }}
        </p>
        <p class="text-[11px] text-n-slate-10 mt-0.5">
          {{ dia(orcamento.criado_em) }}
          <template v-if="orcamento.por">
            {{ TXT.geradoPor }} {{ orcamento.por }}
          </template>
        </p>
      </div>
      <span class="qc-badge">
        <span :class="situacao.icone" />
        {{ situacao.texto }}
      </span>
    </header>

    <div v-if="orcamento.arquivos?.length" class="flex flex-wrap gap-1.5">
      <a
        v-for="a in orcamento.arquivos"
        :key="a.nome"
        :href="a.url"
        target="_blank"
        rel="noopener noreferrer"
        class="qc-file text-n-slate-12"
        :title="a.nome"
      >
        <span
          :class="
            String(a.tipo).startsWith('image/')
              ? 'i-lucide-image'
              : 'i-lucide-file-text'
          "
        />
        {{
          String(a.tipo).startsWith('image/')
            ? 'Resumo'
            : /justific/i.test(a.nome)
              ? 'Justificativa'
              : 'Proposta'
        }}
      </a>
    </div>
    <p v-else class="text-xs text-n-slate-10">{{ TXT.semArquivos }}</p>

    <form
      v-if="editando && !naLixeira"
      class="qc-edit"
      @submit.prevent="salvarEdicao"
    >
      <label class="qc-campo qc-largo">
        <span>{{ TXT.fNome }}</span>
        <input v-model="form.nome" maxlength="80" required />
      </label>
      <label class="qc-campo">
        <span>{{ TXT.fCidade }}</span>
        <input v-model="form.cidade" maxlength="60" />
      </label>
      <label class="qc-campo qc-uf">
        <span>{{ TXT.fUf }}</span>
        <input v-model="form.uf" maxlength="2" />
      </label>
      <label class="qc-campo">
        <span>{{ TXT.fTelhado }}</span>
        <input v-model="form.telhado" maxlength="40" />
      </label>
      <label class="qc-campo qc-uf">
        <span>{{ TXT.fValidade }}</span>
        <input
          v-model.number="form.validade_dias"
          type="number"
          min="1"
          max="30"
        />
      </label>
      <div class="qc-largo flex justify-end gap-1.5">
        <button
          type="button"
          class="qc-act text-n-slate-12"
          @click="editando = false"
        >
          {{ TXT.cancelar }}
        </button>
        <button type="submit" class="qc-act qc-act-main" :disabled="ocupado">
          <span class="i-lucide-save" />
          {{ TXT.salvar }}
        </button>
      </div>
    </form>

    <p v-if="naLixeira" class="qc-trash text-n-slate-12">
      <strong>{{ orcamento.excluido_por || TXT.alguem }}</strong>
      {{ TXT.excluiu }}
      <template v-if="orcamento.motivo">
        {{ `· “${orcamento.motivo}”` }}
      </template>
    </p>
    <footer v-if="naLixeira" class="qc-foot">
      <button
        type="button"
        class="qc-act qc-act-main"
        :disabled="ocupado"
        @click="emit('restaurar', orcamento)"
      >
        <span class="i-lucide-rotate-ccw" />
        {{ TXT.restaurar }}
      </button>
    </footer>
    <footer v-else class="qc-foot">
      <button
        v-if="podeEditar"
        type="button"
        class="qc-act qc-act-del"
        :title="TXT.excluir"
        :disabled="ocupado"
        @click="excluir"
      >
        <span class="i-lucide-trash-2" />
      </button>
      <button
        v-if="podeEditar && !editando"
        type="button"
        class="qc-act text-n-slate-12"
        :title="TXT.editarDica"
        :disabled="ocupado"
        @click="abrirEdicao"
      >
        <span class="i-lucide-pencil" />
        {{ TXT.editar }}
      </button>
      <button
        v-if="podeEditar && !orcamento.enviado_em && orcamento.arquivos?.length"
        type="button"
        class="qc-act qc-act-wa"
        :disabled="ocupado"
        :title="TXT.whatsDica"
        @click="emit('whatsapp', orcamento)"
      >
        <span class="i-lucide-message-circle" />
        {{ TXT.whats }}
      </button>
      <button
        v-if="podeEditar && !orcamento.enviado_em"
        type="button"
        class="qc-act text-n-slate-12"
        :disabled="ocupado"
        :title="TXT.marcarEnviada"
        @click="emit('enviar', orcamento)"
      >
        <span class="i-lucide-check-check" />
      </button>
      <button
        v-if="mostrarCliente && orcamento.cliente?.id"
        type="button"
        class="qc-act text-n-slate-12"
        @click="emit('abrir', orcamento)"
      >
        <span class="i-lucide-user-round" />
        {{ TXT.abrir }}
      </button>
    </footer>
  </article>
</template>

<style scoped>
.qc {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 16px 12px;
  border-radius: 18px;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-top: 3px solid var(--s);
  box-shadow: 0 6px 18px -14px rgb(15 23 42 / 0.45);
}
.dark .qc {
  background: #16181b;
  border-color: #2b2e33;
  border-top-color: var(--s);
}
.qc-valor {
  font-size: 22px;
  font-weight: 800;
  letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums;
  line-height: 1.2;
  margin: 2px 0;
}
.qc-badge {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 4px 9px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
  color: var(--s);
  background: color-mix(in srgb, var(--s) 12%, transparent);
  white-space: nowrap;
}
.qc-badge > span {
  width: 12px;
  height: 12px;
}
.qc-file {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  height: 30px;
  padding: 0 10px;
  border-radius: 9px;
  font-size: 12px;
  font-weight: 600;
  background: rgb(15 23 42 / 0.05);
}
.qc-file:hover {
  background: rgb(15 23 42 / 0.1);
}
.dark .qc-file {
  background: rgb(255 255 255 / 0.06);
}
.dark .qc-file:hover {
  background: rgb(255 255 255 / 0.12);
}
.qc-file > span {
  width: 14px;
  height: 14px;
  color: #ea580c;
}
.qc-foot {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 6px;
  padding-top: 10px;
  border-top: 1px solid rgb(15 23 42 / 0.07);
}
.dark .qc-foot {
  border-top-color: rgb(255 255 255 / 0.07);
}
.qc-act {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  height: 30px;
  padding: 0 10px;
  border-radius: 9px;
  font-size: 12px;
  font-weight: 600;
  border: 1px solid rgb(15 23 42 / 0.12);
}
.dark .qc-act {
  border-color: rgb(255 255 255 / 0.12);
}
.qc-act:hover {
  background: rgb(15 23 42 / 0.05);
}
.qc-act > span {
  width: 14px;
  height: 14px;
}
.qc-floor {
  margin-top: 4px;
  font-size: 11px;
  font-weight: 700;
  color: #7c3aed;
}
.qc-act-wa {
  color: #fff;
  background: #16a34a;
  border-color: #16a34a;
}
.qc-act-wa:hover {
  background: #15803d;
}
.qc-act-main {
  color: #fff;
  background: #16a34a;
  border-color: #16a34a;
}
.qc-act-main:hover {
  background: #15803d;
}
.qc-act-del {
  color: #dc2626;
  padding: 0 8px;
  margin-right: auto;
}
.qc-trash {
  font-size: 12px;
  padding: 8px 10px;
  border-radius: 10px;
  background: rgb(220 38 38 / 0.08);
}
.qc-edit {
  display: grid;
  grid-template-columns: 1fr 64px;
  gap: 8px;
  padding: 10px;
  border-radius: 12px;
  background: rgb(15 23 42 / 0.04);
}
.dark .qc-edit {
  background: rgb(255 255 255 / 0.05);
}
.qc-largo {
  grid-column: 1 / -1;
}
.qc-campo {
  display: flex;
  flex-direction: column;
  gap: 3px;
  font-size: 11px;
  font-weight: 600;
}
.qc-campo input {
  height: 32px;
  padding: 0 8px;
  border-radius: 8px;
  font-size: 13px;
  border: 1px solid rgb(15 23 42 / 0.15);
  background: #fff;
  margin: 0;
}
.dark .qc-campo input {
  background: #0f1113;
  border-color: rgb(255 255 255 / 0.15);
}
.qc-act:disabled {
  opacity: 0.5;
}
</style>
