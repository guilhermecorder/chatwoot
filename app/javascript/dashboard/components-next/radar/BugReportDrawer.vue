<script setup>
// 🐞 Feedback de bugs do TIME: gaveta lateral onde qualquer pessoa
// registra um problema do sistema. Vira um card no board de tarefas do
// Guilherme; quando ele conclui, quem reportou recebe o aviso no Meu
// Painel ("seu report foi resolvido 🎉").
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import CrmAPI from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';

const route = useRoute();
const open = ref(false);
const sending = ref(false);
const sent = ref(false);
const form = ref({ title: '', description: '' });

const show = () => {
  sent.value = false;
  form.value = { title: '', description: '' };
  open.value = true;
};
const hide = () => {
  open.value = false;
};

const send = async () => {
  if (!form.value.title.trim()) {
    useAlert('Descreva o problema em uma frase.');
    return;
  }
  sending.value = true;
  try {
    await CrmAPI.reportBug({
      title: form.value.title.trim(),
      description: form.value.description.trim(),
      screen: route.fullPath,
    });
    sent.value = true;
  } catch {
    useAlert('Não consegui enviar o report — tenta de novo?');
  } finally {
    sending.value = false;
  }
};

const onEvent = () => show();
onMounted(() => window.addEventListener('cevico:report-bug', onEvent));
onBeforeUnmount(() => window.removeEventListener('cevico:report-bug', onEvent));
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="fixed inset-0 z-[9990] bg-black/40" @click.self="hide">
      <div class="cevico-drawer fixed top-0 right-0 bottom-0 w-full max-w-md bg-n-solid-1 shadow-2xl flex flex-col">
        <div class="h-1.5 w-full flex-shrink-0" style="background: linear-gradient(90deg, #DC2626, #F59E0B)" />
        <div class="p-5 flex-1 overflow-y-auto">
          <div class="flex items-center gap-2 mb-1">
            <span class="text-xl">🐞</span>
            <h2 class="text-sm font-bold text-n-slate-12 flex-1">Reportar problema do sistema</h2>
            <button class="w-7 h-7 rounded-lg hover:bg-n-alpha-1 flex items-center justify-center text-n-slate-10" @click="hide">
              <span class="i-lucide-x text-sm" />
            </button>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            Vira um card no board do Guilherme — e você recebe o aviso no seu painel quando for resolvido.
          </p>

          <template v-if="!sent">
            <label class="block mb-3">
              <span class="text-[11px] font-medium text-n-slate-11">O que aconteceu? (uma frase) *</span>
              <input
                v-model="form.title"
                type="text"
                placeholder="Ex: não consigo ouvir os áudios das conversas"
                class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
                @keyup.enter="send"
              />
            </label>
            <label class="block mb-4">
              <span class="text-[11px] font-medium text-n-slate-11">Detalhes (o que você fez, o que apareceu…)</span>
              <textarea
                v-model="form.description"
                rows="5"
                placeholder="Quanto mais detalhe, mais rápido o conserto: qual paciente/conversa, que horas, apareceu erro na tela?"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-2 text-[13px] text-n-slate-12"
              />
            </label>
            <p class="text-[10px] text-n-slate-9 mb-3">A tela onde você está agora vai junto no report, automaticamente.</p>
            <button
              class="w-full py-2.5 rounded-xl font-bold text-sm text-white disabled:opacity-60"
              style="background: linear-gradient(135deg, #DC2626, #F59E0B)"
              :disabled="sending"
              @click="send"
            >
              {{ sending ? 'Enviando…' : 'Enviar report 🐞' }}
            </button>
          </template>

          <div v-else class="text-center py-10">
            <p class="text-4xl mb-3">💙</p>
            <p class="text-sm font-bold text-n-slate-12 mb-1">Report enviado!</p>
            <p class="text-xs text-n-slate-10 mb-5">
              Já virou um card no board do Guilherme. Quando for resolvido, o aviso aparece no seu Meu Painel.
            </p>
            <button class="px-4 h-9 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-1" @click="hide">
              Fechar
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.cevico-drawer {
  animation: drawerIn 0.28s ease;
}
@keyframes drawerIn {
  from { transform: translateX(40px); opacity: 0; }
  to { transform: none; opacity: 1; }
}
</style>
