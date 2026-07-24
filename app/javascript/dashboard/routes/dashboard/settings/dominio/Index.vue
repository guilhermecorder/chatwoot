<script setup>
// 🌐 Configurações → Domínio (pedido 17/07)
// O admin aponta aqui o domínio público oficial das páginas e formulários
// (ex.: sistema.cevico.com.br). A tela guia o apontamento (Hostinger +
// EasyPanel), verifica DNS/HTTPS na hora e explica o que muda. A config
// fica no banco — sem mexer em env na VPS.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const info = ref(null); // config atual (host, app_host, dedicated, exemplos)
const hostInput = ref('');
const isLoading = ref(true);
const isSaving = ref(false);
const isChecking = ref(false);
const checkResult = ref(null);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getPublicDomain();
    info.value = data;
    hostInput.value = data.host || '';
    loadHub(data);
    loadTracking(data);
  } catch {
    useAlert('Não consegui carregar a configuração de domínio.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

const cleanedInput = computed(() =>
  hostInput.value
    .trim()
    .replace(/^https?:\/\//i, '')
    .replace(/\/+$/, '')
);

const runCheck = async () => {
  if (!cleanedInput.value) return null;
  isChecking.value = true;
  checkResult.value = null;
  try {
    const { data } = await CrmAPI.checkPublicDomain(cleanedInput.value);
    checkResult.value = data;
    return data;
  } catch {
    useAlert('Não consegui verificar o domínio agora.');
    return null;
  } finally {
    isChecking.value = false;
  }
};

const save = async () => {
  // salvar vazio = desligar o domínio oficial (volta ao endereço da VPS)
  if (cleanedInput.value) {
    const check = await runCheck();
    const ok = check?.dns_ok && check?.http_ok;
    if (!ok) {
      const msg =
        'O domínio ainda não responde como o sistema (confira o passo a passo abaixo).\n\n' +
        'Se salvar agora, os links antigos já passam a redirecionar para ele. Salvar mesmo assim?';
      // eslint-disable-next-line no-alert
      if (!window.confirm(msg)) return;
    }
  }
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updatePublicDomain(cleanedInput.value);
    info.value = data;
    hostInput.value = data.host || '';
    useAlert(
      data.host
        ? `Domínio oficial salvo: ${data.host} 🎉`
        : 'Domínio oficial desligado — links voltam ao endereço do sistema.'
    );
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o domínio.');
  } finally {
    isSaving.value = false;
  }
};

// ── 🚪 HUB (porta de entrada na raiz do domínio dedicado) ──
const hub = ref({ whatsapp: '', tagline: '', cta_text: '' });
const isSavingHub = ref(false);
const loadHub = data => {
  hub.value = {
    whatsapp: data.hub?.whatsapp || '',
    tagline: data.hub?.tagline || '',
    cta_text: data.hub?.cta_text || '',
  };
};
const saveHub = async () => {
  isSavingHub.value = true;
  try {
    const { data } = await CrmAPI.updatePublicHub(hub.value);
    info.value = data;
    loadHub(data);
    useAlert('Porta de entrada salva! 🚪✨');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o hub.');
  } finally {
    isSavingHub.value = false;
  }
};

// ── 📊 RASTREAMENTO central (item 117): Pixel da Meta + GA4 ──
// Preenche uma vez; toda página publicada (e o hub) sai carimbada, com o
// nome da página dentro dos eventos. Clique no WhatsApp = evento de Lead.
const tracking = ref({ meta_pixel_id: '', ga4_id: '' });
const isSavingTracking = ref(false);
const loadTracking = data => {
  tracking.value = {
    meta_pixel_id: data.tracking?.meta_pixel_id || '',
    ga4_id: data.tracking?.ga4_id || '',
  };
};
const saveTracking = async () => {
  isSavingTracking.value = true;
  try {
    const { data } = await CrmAPI.updatePublicTracking(tracking.value);
    info.value = data;
    loadTracking(data);
    useAlert('Rastreamento salvo — todas as páginas já saem carimbadas! 📊');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o rastreamento.');
  } finally {
    isSavingTracking.value = false;
  }
};

const copyTarget = async () => {
  try {
    await navigator.clipboard.writeText(info.value?.app_host || '');
    useAlert('Endereço copiado!');
  } catch {
    useAlert(info.value?.app_host || '');
  }
};

const hasChanges = computed(() => (info.value?.host || '') !== cleanedInput.value);
</script>

<template>
  <div class="flex-1 overflow-y-auto">
    <div class="max-w-[860px] mx-auto px-6 py-8">
      <!-- Header -->
      <div class="flex items-center gap-3 mb-1">
        <span
          class="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
          style="background: linear-gradient(135deg, #152c61, #0f5fa6)"
        >
          <span class="i-lucide-globe text-white text-lg" />
        </span>
        <div>
          <h1 class="text-lg font-bold text-n-slate-12">Domínio</h1>
          <p class="text-sm text-n-slate-10">
            O endereço oficial das suas páginas e formulários — do jeito que a Meta e o Google gostam.
          </p>
        </div>
      </div>

      <div v-if="isLoading" class="py-16 text-center text-n-slate-10 text-sm">Carregando…</div>

      <template v-else>
        <!-- Domínio atual -->
        <div class="mt-6 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #8a6620, #c9a24b, #f5e9b8, #d4af37)" />
          <div class="p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">Domínio público oficial</h2>
            <p class="text-xs text-n-slate-10 mb-3">
              Digite só o domínio, sem <code class="text-[11px]">https://</code> — ex.:
              <b>sistema.cevico.com.br</b>. Deixe vazio para usar o endereço da VPS.
            </p>

            <div class="flex items-center gap-2 flex-wrap">
              <input
                v-model="hostInput"
                class="flex-1 min-w-[240px] px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:border-n-brand"
                placeholder="sistema.cevico.com.br"
                @keyup.enter="save"
              />
              <button
                class="px-3 py-2 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 whitespace-nowrap"
                :disabled="isChecking || !cleanedInput"
                @click="runCheck"
              >
                {{ isChecking ? 'Verificando…' : '🔍 Verificar' }}
              </button>
              <button
                class="px-4 py-2 text-sm font-semibold text-white rounded-lg hover:opacity-90 disabled:opacity-50 whitespace-nowrap"
                style="background: linear-gradient(135deg, #0f5fa6, #7c3aed)"
                :disabled="isSaving || !hasChanges"
                @click="save"
              >
                {{ isSaving ? 'Salvando…' : 'Salvar' }}
              </button>
            </div>

            <!-- resultado da verificação -->
            <div v-if="checkResult" class="mt-3 flex items-center gap-2 flex-wrap text-xs">
              <span
                class="px-2.5 py-1 rounded-full font-semibold"
                :class="checkResult.dns_ok ? 'bg-emerald-500/15 text-emerald-600' : 'bg-red-500/15 text-red-600'"
              >
                {{ checkResult.dns_ok ? `✓ DNS ok (${checkResult.dns_ip})` : '✗ DNS ainda não aponta' }}
              </span>
              <span
                v-if="checkResult.dns_ok"
                class="px-2.5 py-1 rounded-full font-semibold"
                :class="checkResult.http_ok ? 'bg-emerald-500/15 text-emerald-600' : 'bg-amber-500/15 text-amber-600'"
              >
                {{ checkResult.http_ok ? '✓ Respondendo como o sistema (HTTPS ok)' : `⚠ HTTPS ainda não responde${checkResult.http_error ? ` (${checkResult.http_error})` : ''}` }}
              </span>
              <span v-if="checkResult.dns_ok && checkResult.http_ok" class="text-emerald-600 font-semibold">
                Pronto para salvar! 🎉
              </span>
            </div>

            <!-- aviso: veio da env -->
            <p v-if="info?.from_env" class="mt-3 text-[11px] text-amber-600 bg-amber-500/10 rounded-lg px-3 py-2">
              ⚙️ O domínio atual veio da variável de ambiente da VPS. Salvar aqui passa a valer no lugar dela.
            </p>

            <!-- estado atual -->
            <div v-if="info?.host" class="mt-4 rounded-xl border border-n-weak bg-n-solid-1 p-3.5 space-y-1.5">
              <p class="text-xs text-n-slate-11">
                <b class="text-n-slate-12">Modo:</b>
                {{ info.dedicated
                  ? 'domínio dedicado às páginas — a raiz dele vira o índice dos seus conteúdos'
                  : 'mesmo domínio do sistema — o sistema continua na raiz e as páginas moram nos caminhos' }}
              </p>
              <p class="text-xs text-n-slate-11">
                <b class="text-n-slate-12">Páginas:</b>
                <span class="text-n-brand">{{ info.example_page_url }}</span>
              </p>
              <p class="text-xs text-n-slate-11">
                <b class="text-n-slate-12">Formulários:</b>
                <span class="text-n-brand">{{ info.example_form_url }}</span>
                (links novos do WhatsApp já saem assim; os antigos redirecionam sozinhos)
              </p>
            </div>
          </div>
        </div>

        <!-- 🚪 HUB: porta de entrada na raiz do domínio dedicado -->
        <div v-if="info?.dedicated || !info?.host" class="mt-5 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #152c61, #0f5fa6, #d4af37)" />
          <div class="p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">🚪 Porta de entrada (hub)</h2>
            <p class="text-xs text-n-slate-10 mb-3">
              A raiz do domínio dedicado vira o hub da CEVICO: os três caminhos
              (Refrativa · Catarata · Lente Trifocal), o botão de WhatsApp com rastreio
              (Protocolo) e o índice das páginas publicadas. Configure aqui o atendimento.
            </p>
            <div class="grid gap-3 md:grid-cols-2">
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">WhatsApp do atendimento (só números, com DDI)</span>
                <input v-model="hub.whatsapp" type="text" placeholder="5567999990000" class="mt-1 w-full px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12" />
              </label>
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Frase de boas-vindas (aparece sob o logo)</span>
                <input v-model="hub.tagline" type="text" placeholder="Tecnologia de ponta, acolhimento humano e clareza visual." class="mt-1 w-full px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12" />
              </label>
            </div>
            <label class="block mt-3">
              <span class="text-[11px] font-medium text-n-slate-11">Mensagem que o paciente envia ao clicar no WhatsApp</span>
              <input v-model="hub.cta_text" type="text" placeholder="Olá! Vim do site da CEVICO e quero agendar uma avaliação." class="mt-1 w-full px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12" />
            </label>
            <div class="flex items-center gap-3 mt-3">
              <button
                class="px-4 py-2 text-sm font-semibold rounded-lg text-white hover:opacity-90 disabled:opacity-50"
                style="background: linear-gradient(135deg, #152c61, #0f5fa6)"
                :disabled="isSavingHub"
                @click="saveHub"
              >
                {{ isSavingHub ? 'Salvando…' : 'Salvar porta de entrada' }}
              </button>
              <span v-if="info?.hub_whatsapp_url" class="text-[11px] text-emerald-600 font-semibold">✓ WhatsApp ativo no hub</span>
              <span v-else class="text-[11px] text-amber-600">Sem WhatsApp, o hub mostra só as páginas.</span>
            </div>
          </div>
        </div>

        <!-- 📊 RASTREAMENTO: Pixel da Meta + GA4 em todas as páginas -->
        <div class="mt-5 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #0f5fa6, #7c3aed, #d4af37)" />
          <div class="p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-1">📊 Rastreamento (Pixel da Meta + Google GA4)</h2>
            <p class="text-xs text-n-slate-10 mb-3">
              Preencha <b>uma vez</b> e pronto: toda página publicada (e a porta de entrada)
              sai com o Pixel e o GA4, com o <b>nome da página dentro do evento</b> — nos
              relatórios da Meta e do Google você filtra por página. O clique no WhatsApp
              dispara evento de <b>Lead</b> nas duas plataformas, amarrado ao Protocolo.
            </p>
            <div class="grid gap-3 md:grid-cols-2">
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Pixel da Meta (só o número)</span>
                <input v-model="tracking.meta_pixel_id" type="text" placeholder="1234567890123456" class="mt-1 w-full px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12" />
                <span class="text-[10px] text-n-slate-9">Meta Business → Gerenciador de Eventos → seu Pixel → o ID numérico.</span>
              </label>
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Google GA4 (código G-…)</span>
                <input v-model="tracking.ga4_id" type="text" placeholder="G-AB12CD34EF" class="mt-1 w-full px-3 py-2 text-sm bg-n-alpha-1 border border-n-weak rounded-lg text-n-slate-12" />
                <span class="text-[10px] text-n-slate-9">GA4 → Administrador → Fluxos de dados → seu site → ID da métrica.</span>
              </label>
            </div>
            <div class="flex items-center gap-3 mt-3 flex-wrap">
              <button
                class="px-4 py-2 text-sm font-semibold rounded-lg text-white hover:opacity-90 disabled:opacity-50"
                style="background: linear-gradient(135deg, #0f5fa6, #7c3aed)"
                :disabled="isSavingTracking"
                @click="saveTracking"
              >
                {{ isSavingTracking ? 'Salvando…' : 'Salvar rastreamento' }}
              </button>
              <span v-if="info?.tracking?.meta_pixel_id" class="text-[11px] text-emerald-600 font-semibold">✓ Pixel ativo em todas as páginas</span>
              <span v-if="info?.tracking?.ga4_id" class="text-[11px] text-emerald-600 font-semibold">✓ GA4 ativo em todas as páginas</span>
              <span v-if="!info?.tracking?.meta_pixel_id && !info?.tracking?.ga4_id" class="text-[11px] text-n-slate-9">Sem IDs, as páginas seguem só com o rastreio interno (Protocolo).</span>
            </div>
          </div>
        </div>

        <!-- Passo a passo do apontamento -->
        <div class="mt-5 bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-3">Apontamento em 3 passos (Hostinger + EasyPanel)</h2>
          <ol class="list-none space-y-3">
            <li class="flex gap-3">
              <span class="w-6 h-6 rounded-full flex items-center justify-center text-[11px] font-bold text-white flex-shrink-0" style="background: linear-gradient(135deg, #0f5fa6, #7c3aed)">1</span>
              <div class="text-xs text-n-slate-11 leading-relaxed">
                <b class="text-n-slate-12">Na Hostinger (conta do site da CEVICO):</b>
                Domínios → cevico.com.br → <b>DNS / Zona de DNS</b> → Adicionar registro
                <b>CNAME</b> com nome <code class="text-[11px]">sistema</code> (ou o subdomínio que preferir)
                apontando para:
                <span class="inline-flex items-center gap-1.5 mt-1">
                  <code class="text-[11px] bg-n-alpha-1 rounded px-2 py-0.5">{{ info?.app_host || 'endereço do sistema' }}</code>
                  <button class="text-[10px] px-2 py-0.5 rounded border border-n-weak hover:bg-n-alpha-1" @click="copyTarget">copiar</button>
                </span>
              </div>
            </li>
            <li class="flex gap-3">
              <span class="w-6 h-6 rounded-full flex items-center justify-center text-[11px] font-bold text-white flex-shrink-0" style="background: linear-gradient(135deg, #0f5fa6, #7c3aed)">2</span>
              <div class="text-xs text-n-slate-11 leading-relaxed">
                <b class="text-n-slate-12">No EasyPanel (serviço web):</b>
                projeto sistema_cevico → serviço <b>web</b> → aba <b>Domains</b> → Add Domain →
                digite o mesmo subdomínio (ex.: sistema.cevico.com.br) e salve — o certificado
                HTTPS é emitido sozinho em ~1 minuto.
              </div>
            </li>
            <li class="flex gap-3">
              <span class="w-6 h-6 rounded-full flex items-center justify-center text-[11px] font-bold text-white flex-shrink-0" style="background: linear-gradient(135deg, #0f5fa6, #7c3aed)">3</span>
              <div class="text-xs text-n-slate-11 leading-relaxed">
                <b class="text-n-slate-12">Aqui nesta tela:</b>
                clique em <b>Verificar</b> (os dois selos precisam ficar verdes) e depois em
                <b>Salvar</b>. Pronto — páginas e formulários passam a viver no domínio oficial.
              </div>
            </li>
          </ol>
          <p class="mt-3 text-[11px] text-n-slate-9">
            💡 Dica: prefira <b>sistema.cevico.com.br</b> (sem "www." na frente do subdomínio) —
            fica mais curto e evita um segundo apontamento.
          </p>
        </div>

        <!-- O que muda -->
        <div class="mt-5 bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-2">O que acontece quando o domínio está ativo</h2>
          <ul class="list-none text-xs text-n-slate-11 space-y-1.5 leading-relaxed">
            <li>• As páginas ganham endereço limpo: <b>seu-domínio/nome-da-pagina</b> (sem /p/).</li>
            <li>• Links de formulário enviados no WhatsApp já saem no domínio oficial.</li>
            <li>• Endereços antigos redirecionam sozinhos (301) — nenhum link já divulgado quebra.</li>
            <li>• Google e Meta passam a enxergar um endereço só (canonical), o que fortalece anúncios e SEO.</li>
          </ul>
        </div>
      </template>
    </div>
  </div>
</template>
