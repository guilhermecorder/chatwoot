<script setup>
// 🔑 Acessos dos fornecedores do Gerador de proposta (LIFE): sessão do portal da Bluesun e
// da AVT, usuário e senha da AVT, token e código do cliente. Só o administrador vê.
// Os segredos entram por aqui e nunca voltam do servidor: a tela só sabe se estão
// ligados e até quando.
import { computed, reactive, ref, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  // { avt: { sessao, vence_em, token, id_cliente, login }, bluesun: { sessao, vence_em, renova_ate } }
  acesso: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['update:acesso']);

const { isAdmin } = useCevicoAccess();

const FORNECEDORES = [
  {
    id: 'bluesun',
    nome: 'Bluesun',
    portal: 'https://orcamentos.bluesundobrasil.com.br',
    // eslint-disable-next-line no-script-url
    favorito: `javascript:(()=>{navigator.clipboard.writeText(localStorage.orcamento_auth_v1||'').then(()=>alert('Sessão copiada. Volte ao sistema e cole em Acessos dos fornecedores.'))})()`,
  },
  {
    id: 'avt',
    nome: 'AVT',
    portal: 'https://portal.avtenergy.com.br',
    // eslint-disable-next-line no-script-url
    favorito: `javascript:(()=>{const t=JSON.parse(localStorage.token||'{}');navigator.clipboard.writeText(JSON.stringify({accessToken:t.accessToken,expirationDate:t.expirationDate,urlApi:(localStorage.urlApi||'').replace(/"/g,'')})).then(()=>alert('Sessão copiada. Volte ao sistema e cole em Acessos dos fornecedores.'))})()`,
  },
];
const COR = {
  verde: 'bg-n-teal-9',
  amarelo: 'bg-n-amber-9',
  vermelho: 'bg-n-ruby-9',
  cinza: 'bg-n-slate-8',
};

const aberto = ref(false);
const colado = reactive({ bluesun: '', avt: '' });
const avtToken = ref('');
const avtEmail = ref('');
const avtSenha = ref('');
const avtCliente = ref('');
const salvando = ref('');

const quando = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';

const estado = id => {
  const a = props.acesso?.[id] || {};
  // 12/11: a AVT pôs verificação de robô no login, então o usuário e a senha salvos não
  // entram mais sozinhos. Sessão vencida = amarelo, com o que fazer.
  if (
    id === 'avt' &&
    a.sessao !== 'ok' &&
    (a.login || a.sessao === 'vencida')
  ) {
    return {
      cor: 'amarelo',
      texto:
        'Sessão venceu: entre no portal da AVT e cole a sessão de novo (vale cerca de 1 hora)',
    };
  }
  if (id === 'avt' && a.token && a.sessao !== 'ok') {
    return { cor: 'amarelo', texto: 'Token salvo, aguardando a AVT liberar' };
  }
  if (a.sessao === 'ok') {
    return { cor: 'verde', texto: `Ligada até ${quando(a.vence_em)}` };
  }
  // a Bluesun renova sozinha enquanto a chave de renovação valer (7 dias)
  if (id === 'bluesun' && a.sessao === 'vencida' && a.renova_ate) {
    const vale = new Date(a.renova_ate) > new Date();
    if (vale) {
      return {
        cor: 'verde',
        texto: `Renova sozinha até ${quando(a.renova_ate)}`,
      };
    }
  }
  if (a.sessao === 'vencida') {
    return { cor: 'vermelho', texto: `Sessão venceu em ${quando(a.vence_em)}` };
  }
  return { cor: 'cinza', texto: 'Sem acesso' };
};

const algumLigado = computed(() =>
  FORNECEDORES.some(f => estado(f.id).cor === 'verde')
);
// abre sozinho quando nada está ligado: é a primeira coisa a resolver
watch(
  () => props.acesso,
  (atual, anterior) => {
    if (!anterior || !Object.keys(anterior).length) {
      aberto.value = isAdmin.value && !algumLigado.value;
    }
  }
);

const salvarAcesso = async (chave, payload, limpar) => {
  if (salvando.value) return;
  salvando.value = chave;
  try {
    const { data } = await CrmAPI.updateKitQuoteAccess(payload);
    emit('update:acesso', data.acesso || props.acesso);
    limpar();
    useAlert('Acesso salvo.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não foi possível salvar o acesso.');
  } finally {
    salvando.value = '';
  }
};

const salvarSessao = id =>
  salvarAcesso(id, { fornecedor: id, sessao: colado[id] }, () => {
    colado[id] = '';
  });
const salvarLogin = () =>
  salvarAcesso(
    'avt_login',
    { avt_email: avtEmail.value, avt_senha: avtSenha.value },
    () => {
      avtEmail.value = '';
      avtSenha.value = '';
    }
  );
const salvarToken = () =>
  salvarAcesso('avt_token', { avt_token: avtToken.value }, () => {
    avtToken.value = '';
  });
const salvarCliente = () =>
  salvarAcesso('avt_cliente', { avt_id_cliente: avtCliente.value }, () => {
    avtCliente.value = '';
  });
// textos da tela (fora do template, como pede o eslint do projeto)
const TXT = {
  acessosDosFornecedores: 'Acessos dos fornecedores',
  renovacaoValeAte: '(renovação vale até',
  arrasteEsteBotaoPara:
    'Arraste este botão para a barra de favoritos (só na primeira vez):',
  copiarSessao: 'Copiar sessão',
  entreNo: 'Entre no',
  portalDa: 'portal da',
  eCliqueNoFavorito: 'e clique no favorito.',
  coleAquiESalve: 'Cole aqui e salve.',
  coleASessaoCopiada: 'Cole a sessão copiada',
  salvarSessao: 'Salvar sessão',
  paraAAvtEntrar: 'Para a AVT entrar sozinha, sem precisar copiar sessão:',
  usuarioEMailDo: 'Usuário (e-mail) do portal da AVT',
  salvarLogin: 'Salvar login',
  salvarToken: 'Salvar token',
  salvarCodigo: 'Salvar código',
};
</script>

<template>
  <section v-if="isAdmin" class="rounded-2xl border border-n-weak bg-n-solid-2">
    <button
      class="w-full flex items-center gap-3 p-5 text-left"
      @click="aberto = !aberto"
    >
      <span class="i-lucide-key-round text-n-slate-11" />
      <span class="flex-1 text-sm font-semibold text-n-slate-12">
        {{ TXT.acessosDosFornecedores }}
      </span>
      <span
        v-for="f in FORNECEDORES"
        :key="f.id"
        class="flex items-center gap-1.5 text-xs text-n-slate-11"
      >
        <span class="w-2 h-2 rounded-full" :class="COR[estado(f.id).cor]" />
        {{ f.nome }}
      </span>
      <span
        class="text-n-slate-10"
        :class="aberto ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
      />
    </button>

    <div v-if="aberto" class="border-t border-n-weak divide-y divide-n-weak">
      <div
        v-for="f in FORNECEDORES"
        :key="f.id"
        class="p-5 flex flex-col gap-3"
      >
        <div class="flex flex-wrap items-center gap-2">
          <span class="w-2 h-2 rounded-full" :class="COR[estado(f.id).cor]" />
          <strong class="text-sm text-n-slate-12">{{ f.nome }}</strong>
          <span class="text-xs text-n-slate-11">{{ estado(f.id).texto }}</span>
          <span
            v-if="f.id === 'bluesun' && acesso.bluesun?.renova_ate"
            class="text-xs text-n-slate-10"
          >
            {{ TXT.renovacaoValeAte }} {{ quando(acesso.bluesun.renova_ate) }})
          </span>
        </div>

        <ol
          class="text-xs text-n-slate-11 list-decimal pl-4 flex flex-col gap-1"
        >
          <li>
            {{ TXT.arrasteEsteBotaoPara }}
            <a
              :href="f.favorito"
              class="inline-block ml-1 px-2 py-0.5 rounded-md border border-n-weak text-n-slate-12 cursor-grab"
              @click.prevent
            >
              {{ TXT.copiarSessao }} {{ f.nome }}
            </a>
          </li>
          <li>
            {{ TXT.entreNo }}
            <a
              :href="f.portal"
              target="_blank"
              rel="noopener noreferrer"
              class="underline"
            >
              {{ TXT.portalDa }} {{ f.nome }}
            </a>
            {{ TXT.eCliqueNoFavorito }}
          </li>
          <li>{{ TXT.coleAquiESalve }}</li>
        </ol>

        <div class="flex flex-col sm:flex-row gap-2">
          <textarea
            v-model="colado[f.id]"
            rows="1"
            :placeholder="TXT.coleASessaoCopiada"
            class="!mb-0 flex-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12"
          />
          <button
            class="h-9 px-4 rounded-xl text-xs font-semibold border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="!colado[f.id] || salvando === f.id"
            @click="salvarSessao(f.id)"
          >
            {{ TXT.salvarSessao }}
          </button>
        </div>

        <template v-if="f.id === 'avt'">
          <p class="text-xs text-n-slate-11">
            {{ TXT.paraAAvtEntrar }}
          </p>
          <div class="flex flex-col sm:flex-row gap-2">
            <input
              v-model="avtEmail"
              type="email"
              autocomplete="off"
              :placeholder="TXT.usuarioEMailDo"
              class="!mb-0 h-9 flex-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-xs text-n-slate-12"
            />
            <input
              v-model="avtSenha"
              type="password"
              autocomplete="new-password"
              :placeholder="
                acesso.avt?.login
                  ? 'Senha salva. Digite para trocar'
                  : 'Senha do portal da AVT'
              "
              class="!mb-0 h-9 flex-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-xs text-n-slate-12"
            />
            <button
              class="h-9 px-4 rounded-xl text-xs font-semibold border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
              :disabled="!avtEmail || !avtSenha || salvando === 'avt_login'"
              @click="salvarLogin"
            >
              {{ TXT.salvarLogin }}
            </button>
          </div>
          <div class="flex flex-col sm:flex-row gap-2">
            <input
              v-model="avtToken"
              type="password"
              autocomplete="off"
              :placeholder="
                acesso.avt?.token
                  ? 'Token de Plataformas salvo. Digite para trocar'
                  : 'Token de Plataformas'
              "
              class="!mb-0 h-9 flex-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-xs text-n-slate-12"
            />
            <button
              class="h-9 px-4 rounded-xl text-xs font-semibold border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
              :disabled="!avtToken || salvando === 'avt_token'"
              @click="salvarToken"
            >
              {{ TXT.salvarToken }}
            </button>
          </div>
          <div class="flex flex-col sm:flex-row gap-2">
            <input
              v-model="avtCliente"
              type="text"
              inputmode="numeric"
              :placeholder="
                acesso.avt?.id_cliente
                  ? 'Código do cliente salvo. Digite para trocar'
                  : 'Código do cliente na AVT'
              "
              class="!mb-0 h-9 flex-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-xs text-n-slate-12"
            />
            <button
              class="h-9 px-4 rounded-xl text-xs font-semibold border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
              :disabled="!avtCliente || salvando === 'avt_cliente'"
              @click="salvarCliente"
            >
              {{ TXT.salvarCodigo }}
            </button>
          </div>
        </template>
      </div>
    </div>
  </section>
</template>
