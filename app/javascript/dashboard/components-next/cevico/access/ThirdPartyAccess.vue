<script setup>
// 🚪 item 420 (26/11) — ACESSOS DE TERCEIROS, a parte do administrador.
// Terceiro = alguém de fora da equipe com um login que abre UMA coisa só (hoje:
// a agenda particular de um médico, para a secretária dele). Não é atendente
// nem administrador: entra direto no portal, sem menu, e o resto do sistema
// fica fechado para ele no servidor.
// Aqui o administrador cria o acesso (nome, e-mail, médico e as faixas de
// horário liberadas), ajusta, confere como a pessoa vê e encerra.
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import CvBloco from 'dashboard/components-next/cevico/guia/CvBloco.vue';
import { WEEKDAYS, windowsText } from 'dashboard/helper/cevicoPortal';

const route = useRoute();
const data = ref(null); // { kinds, doctors, doctor_windows, units, list }
const isLoading = ref(true);
const isSaving = ref(false);
const form = ref(null);
const toClose = ref(null);

const apply = payload => {
  if (payload && Array.isArray(payload.list)) data.value = payload;
};
const errorText = e =>
  e?.response?.data?.error || 'Não consegui gravar. Tente de novo.';
const load = async () => {
  try {
    const { data: payload } = await CrmAPI.getThirdParties();
    apply(payload);
  } catch {
    useAlert('Não consegui carregar os acessos de terceiros.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

const list = computed(() => data.value?.list || []);
const units = computed(() => data.value?.units || []);
const doctors = computed(() => data.value?.doctors || []);
const unitLabel = key => units.value.find(u => u.key === key)?.label || key;
const faixas = row => windowsText(row.windows, unitLabel);
const ativos = computed(() => list.value.filter(r => r.active).length);

const whenText = iso => {
  if (!iso) return 'ainda não entrou';
  const d = new Date(iso);
  return `último acesso em ${d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} às ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`;
};
const portalLink = row =>
  `/app/accounts/${route.params.accountId}/portal?as=${row.user_id}`;

// ── formulário ──────────────────────────────────────────────────────────
const blankWindow = () => ({
  dow: 2,
  start: '13:00',
  end: '14:00',
  unit: units.value[0]?.key || '',
  block: 15,
});
const openNew = () => {
  form.value = {
    user_id: null,
    name: '',
    email: '',
    label: '',
    doctor: doctors.value[0] || '',
    windows: [blankWindow()],
    title: 'Novo acesso de terceiro',
  };
};
const openEdit = row => {
  form.value = {
    user_id: row.user_id,
    name: row.name || '',
    email: row.email || '',
    label: row.label || '',
    doctor: row.doctor || '',
    windows: (row.windows || []).map(w => ({ ...w })),
    title: `Ajustar · ${row.name}`,
  };
};
const addWindow = () => form.value.windows.push(blankWindow());
const removeWindow = i => form.value.windows.splice(i, 1);
const copyDoctorWindows = () => {
  const wins = data.value?.doctor_windows?.[form.value.doctor] || [];
  if (!wins.length) {
    useAlert('Esse médico não tem faixas na Agenda da clínica.');
    return;
  }
  form.value.windows = wins.map(w => ({ ...w }));
};
const frase = computed(() => {
  const f = form.value;
  if (!f) return '';
  const quem = f.name.trim() || 'Esta pessoa';
  const medico = f.doctor || 'o médico escolhido';
  const quando = windowsText(f.windows, unitLabel);
  return `${quem} vai entrar direto na agenda particular de ${medico}, vendo e marcando só consultas particulares${quando.length ? ` em: ${quando.join('; ')}` : ' (sem faixa liberada, não consegue marcar)'}. Nada mais do sistema abre para essa pessoa.`;
});

const save = async () => {
  const f = form.value;
  if (!f || isSaving.value) return;
  const body = {
    name: f.name.trim(),
    label: f.label.trim(),
    doctor: f.doctor,
    kind: 'agenda_medico',
    windows: f.windows,
  };
  isSaving.value = true;
  try {
    const { data: payload } = f.user_id
      ? await CrmAPI.updateThirdParty(f.user_id, body)
      : await CrmAPI.createThirdParty({ ...body, email: f.email.trim() });
    apply(payload);
    useAlert(
      f.user_id
        ? 'Acesso atualizado.'
        : 'Acesso criado. O convite para criar a senha foi por e-mail.'
    );
    form.value = null;
  } catch (e) {
    useAlert(errorText(e));
  } finally {
    isSaving.value = false;
  }
};
const closeAccess = async () => {
  const row = toClose.value;
  toClose.value = null;
  if (!row) return;
  try {
    const { data: payload } = await CrmAPI.closeThirdParty(row.user_id);
    apply(payload);
    useAlert(`Acesso de ${row.name} encerrado.`);
  } catch (e) {
    useAlert(errorText(e));
  }
};
const reopen = async row => {
  try {
    const { data: payload } = await CrmAPI.updateThirdParty(row.user_id, {
      active: true,
    });
    apply(payload);
    useAlert(`Acesso de ${row.name} reaberto.`);
  } catch (e) {
    useAlert(errorText(e));
  }
};
const invite = async row => {
  try {
    await CrmAPI.inviteThirdParty(row.user_id);
    useAlert(`Convite reenviado para ${row.email}.`);
  } catch (e) {
    useAlert(errorText(e));
  }
};
</script>

<template>
  <CvBloco
    titulo="Acessos de terceiros"
    subtitulo="Gente de fora da equipe que entra para ver uma coisa só. Hoje: a secretária de um médico, que vê e marca só as consultas particulares dele. O que ela marca aparece na Agenda da clínica, mas fica fora das contagens."
    icon="i-lucide-door-open"
  >
    <template #acoes>
      <span v-if="list.length" class="cvg-chip">
        {{ ativos }} {{ ativos === 1 ? 'ativo' : 'ativos' }}
      </span>
      <button class="cvg-btn cvg-btn--principal" type="button" @click="openNew">
        <span class="i-lucide-plus text-base" /> Novo acesso
      </button>
    </template>

    <p v-if="isLoading" class="cvg-vazio">Carregando…</p>
    <p v-else-if="!list.length" class="cvg-vazio">
      Nenhum acesso de terceiro ainda. Crie o primeiro: a pessoa recebe um
      e-mail para criar a senha e entra direto no portal, sem menu.
    </p>
    <div v-else class="cvg-cards">
      <div v-for="row in list" :key="row.user_id" class="cvg-card">
        <div class="min-w-0">
          <h3 class="cvg-card-titulo">{{ row.name }}</h3>
          <p class="cvg-legenda break-all">{{ row.email }}</p>
        </div>
        <div class="flex flex-wrap gap-2">
          <span v-if="!row.active" class="cvg-chip cvg-chip--atencao">
            <span class="i-lucide-lock text-xs" /> encerrado
          </span>
          <span v-else-if="!row.confirmed" class="cvg-chip cvg-chip--atencao">
            <span class="i-lucide-mail text-xs" /> convite enviado, sem senha
          </span>
          <span v-else class="cvg-chip cvg-chip--dia">
            <span class="i-lucide-check text-xs" /> ativo
          </span>
          <span v-if="row.label" class="cvg-chip">{{ row.label }}</span>
        </div>
        <p class="cvg-texto-2 text-sm leading-snug">
          Agenda particular de <b>{{ row.doctor || 'médico não escolhido' }}</b>
        </p>
        <ul class="cvg-legenda space-y-0.5">
          <li v-for="txt in faixas(row)" :key="txt">{{ txt }}</li>
          <li v-if="!faixas(row).length">
            sem faixa liberada: vê a agenda, mas não consegue marcar
          </li>
        </ul>
        <p class="cvg-legenda">
          {{ row.stats.booked }} marcada{{
            row.stats.booked === 1 ? '' : 's'
          }}
          no total · {{ row.stats.upcoming }} por vir ·
          {{ whenText(row.last_seen_at) }}
        </p>
        <p v-if="row.ignored_admin" class="cvg-legenda">
          Atenção: esta pessoa virou administradora. Administrador nunca é
          barrado, então este acesso restrito deixou de valer.
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            class="cvg-btn cvg-btn--ghost cvg-btn--sm"
            type="button"
            @click="openEdit(row)"
          >
            Ajustar
          </button>
          <a
            v-if="row.active"
            class="cvg-btn cvg-btn--ghost cvg-btn--sm"
            :href="portalLink(row)"
            target="_blank"
            rel="noopener noreferrer"
          >
            Ver como a pessoa vê
          </a>
          <button
            v-if="!row.confirmed"
            class="cvg-btn cvg-btn--ghost cvg-btn--sm"
            type="button"
            @click="invite(row)"
          >
            Reenviar convite
          </button>
          <button
            v-if="row.active"
            class="cvg-btn cvg-btn--problema cvg-btn--sm"
            type="button"
            @click="toClose = row"
          >
            Encerrar
          </button>
          <button
            v-else
            class="cvg-btn cvg-btn--ghost cvg-btn--sm"
            type="button"
            @click="reopen(row)"
          >
            Reabrir
          </button>
        </div>
      </div>
    </div>

    <!-- ══ modal: novo / ajustar ══ -->
    <div
      v-if="form"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-2 sm:p-4"
      @click.self="form = null"
    >
      <div class="cv-modal w-full max-w-2xl flex flex-col max-h-[94vh]">
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span class="i-lucide-door-open text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-xs opacity-85">Acessos de terceiros</p>
            <h2 class="text-base font-bold leading-tight">{{ form.title }}</h2>
          </div>
          <button
            class="cv-glass-btn cv-iconbtn flex-shrink-0"
            type="button"
            aria-label="Fechar"
            @click="form = null"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </div>
        <div class="p-4 sm:p-6 overflow-y-auto flex flex-col gap-5">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <label class="cvg-campo-rotulo">
              <span class="cvg-rotulo">Nome da pessoa</span>
              <input
                v-model="form.name"
                class="cvg-campo"
                maxlength="80"
                placeholder="Ex.: Maria Souza"
              />
            </label>
            <label class="cvg-campo-rotulo">
              <span class="cvg-rotulo">E-mail (o login da pessoa)</span>
              <input
                v-model="form.email"
                class="cvg-campo"
                type="email"
                :disabled="!!form.user_id"
                placeholder="um e-mail só dessa pessoa"
              />
            </label>
            <label class="cvg-campo-rotulo">
              <span class="cvg-rotulo">Quem é (aparece no rastro)</span>
              <input
                v-model="form.label"
                class="cvg-campo"
                maxlength="80"
                placeholder="Ex.: Secretária da Dra. Roberta"
              />
            </label>
            <label class="cvg-campo-rotulo">
              <span class="cvg-rotulo">Médico</span>
              <select v-model="form.doctor" class="cvg-campo">
                <option
                  v-if="!doctors.includes(form.doctor)"
                  :value="form.doctor"
                >
                  {{ form.doctor || 'escolha' }}
                </option>
                <option v-for="d in doctors" :key="d" :value="d">
                  {{ d }}
                </option>
              </select>
            </label>
          </div>

          <div>
            <div class="flex flex-wrap items-center justify-between gap-2">
              <span class="cvg-rotulo">Horários liberados para marcar</span>
              <button
                class="cvg-btn cvg-btn--ghost cvg-btn--sm"
                type="button"
                @click="copyDoctorWindows"
              >
                Copiar as faixas do médico
              </button>
            </div>
            <div class="mt-2 flex flex-col gap-2">
              <div
                v-for="(w, i) in form.windows"
                :key="i"
                class="grid grid-cols-2 sm:grid-cols-[1.3fr_1fr_1fr_1.3fr_0.9fr_auto] gap-2 items-end"
              >
                <label class="cvg-campo-rotulo">
                  <span class="cvg-legenda">Dia</span>
                  <select
                    v-model.number="w.dow"
                    class="cvg-campo cvg-campo--sm"
                  >
                    <option v-for="(name, d) in WEEKDAYS" :key="d" :value="d">
                      {{ name }}
                    </option>
                  </select>
                </label>
                <label class="cvg-campo-rotulo">
                  <span class="cvg-legenda">Das</span>
                  <input
                    v-model="w.start"
                    type="time"
                    class="cvg-campo cvg-campo--sm"
                  />
                </label>
                <label class="cvg-campo-rotulo">
                  <span class="cvg-legenda">Até</span>
                  <input
                    v-model="w.end"
                    type="time"
                    class="cvg-campo cvg-campo--sm"
                  />
                </label>
                <label class="cvg-campo-rotulo">
                  <span class="cvg-legenda">Unidade</span>
                  <select v-model="w.unit" class="cvg-campo cvg-campo--sm">
                    <option v-for="u in units" :key="u.key" :value="u.key">
                      {{ u.label }}
                    </option>
                  </select>
                </label>
                <label class="cvg-campo-rotulo">
                  <span class="cvg-legenda">A cada (min)</span>
                  <input
                    v-model.number="w.block"
                    type="number"
                    min="5"
                    max="120"
                    step="5"
                    class="cvg-campo cvg-campo--sm"
                  />
                </label>
                <button
                  class="cvg-btn cvg-btn--ghost cvg-btn--sm"
                  type="button"
                  aria-label="Tirar esta faixa"
                  @click="removeWindow(i)"
                >
                  <span class="i-lucide-trash-2 text-sm" />
                </button>
              </div>
              <div>
                <button
                  class="cvg-btn cvg-btn--ghost cvg-btn--sm"
                  type="button"
                  @click="addWindow"
                >
                  <span class="i-lucide-plus text-sm" /> Outra faixa
                </button>
              </div>
            </div>
          </div>

          <p class="cvg-legenda leading-relaxed">{{ frase }}</p>
        </div>
        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <button
            class="cvg-btn cvg-btn--principal"
            type="button"
            :disabled="isSaving"
            @click="save"
          >
            {{
              isSaving
                ? 'Salvando…'
                : form.user_id
                  ? 'Salvar'
                  : 'Criar acesso e enviar convite'
            }}
          </button>
          <button
            class="cvg-btn cvg-btn--ghost"
            type="button"
            @click="form = null"
          >
            Cancelar
          </button>
        </div>
      </div>
    </div>

    <!-- ══ modal: encerrar ══ -->
    <div
      v-if="toClose"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="toClose = null"
    >
      <div class="cv-modal w-full max-w-md flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span class="i-lucide-lock text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-xs opacity-85">Acessos de terceiros</p>
            <h2 class="text-base font-bold leading-tight">
              Encerrar o acesso de {{ toClose.name }}?
            </h2>
          </div>
        </div>
        <p class="p-4 sm:p-6 text-sm leading-relaxed">
          A pessoa deixa de abrir o portal na hora. As consultas que marcou
          continuam na Agenda, com o rastro de quem marcou. Dá para reabrir
          depois.
        </p>
        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <button
            class="cvg-btn cvg-btn--problema"
            type="button"
            @click="closeAccess"
          >
            Encerrar acesso
          </button>
          <button
            class="cvg-btn cvg-btn--ghost"
            type="button"
            @click="toClose = null"
          >
            Cancelar
          </button>
        </div>
      </div>
    </div>
  </CvBloco>
</template>
