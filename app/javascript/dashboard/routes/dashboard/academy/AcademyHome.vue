<script setup>
// Academia CEVICO — ambiente de educação do time interno.
// Trilhas em cards estilo streaming; conteúdos chegarão em fases ("Em breve").

const TRACKS = [
  {
    section: 'Trilhas de Treinamento',
    items: [
      {
        title: 'Treinamento para Médicos',
        desc: 'Protocolos, jornada do paciente e boas práticas clínicas',
        icon: 'i-lucide-stethoscope',
        gradient: 'linear-gradient(135deg, #0F5FA6 0%, #063a68 100%)',
      },
      {
        title: 'Treinamento para Vendedores',
        desc: 'Do primeiro contato ao fechamento da cirurgia',
        icon: 'i-lucide-trending-up',
        gradient: 'linear-gradient(135deg, #BF953F 0%, #7a5c1e 100%)',
      },
      {
        title: 'Atendimento WhatsApp Pós-Cirurgia',
        desc: 'Acompanhamento, cuidados e encantamento no pós-operatório',
        icon: 'i-lucide-heart-handshake',
        gradient: 'linear-gradient(135deg, #12A594 0%, #0a5d54 100%)',
      },
      {
        title: 'Agendamento de Consultas',
        desc: 'Scripts e fluxo ideal para converter conversas em consultas',
        icon: 'i-lucide-calendar-check',
        gradient: 'linear-gradient(135deg, #6E56CF 0%, #3d2f74 100%)',
      },
      {
        title: 'Agendamento de Cirurgias',
        desc: 'Orçamento, indicação e confirmação cirúrgica sem fricção',
        icon: 'i-lucide-calendar-heart',
        gradient: 'linear-gradient(135deg, #E54666 0%, #83243c 100%)',
      },
    ],
  },
  {
    section: 'Procedimentos Mapeados',
    items: [
      {
        title: 'Cirurgia Refrativa',
        desc: 'Jornada completa: captação, orçamento e conversão',
        icon: 'i-lucide-eye',
        gradient: 'linear-gradient(135deg, #2781F6 0%, #0d3a75 100%)',
      },
      {
        title: 'Catarata',
        desc: 'Fluxo do diagnóstico ao pós-operatório',
        icon: 'i-lucide-scan-eye',
        gradient: 'linear-gradient(135deg, #0F5FA6 0%, #BF953F 130%)',
      },
      {
        title: 'Consultas e Exames',
        desc: 'Padrões de atendimento e triagem',
        icon: 'i-lucide-clipboard-list',
        gradient: 'linear-gradient(135deg, #12A594 0%, #0F5FA6 130%)',
      },
    ],
  },
  {
    section: 'Materiais de Apoio',
    items: [
      {
        title: 'Checklists Operacionais',
        desc: 'Passo a passo de cada rotina do dia a dia',
        icon: 'i-lucide-list-checks',
        gradient: 'linear-gradient(135deg, #60646C 0%, #1c2024 100%)',
      },
      {
        title: 'Scripts de Atendimento',
        desc: 'Mensagens prontas e tom de voz CEVICO',
        icon: 'i-lucide-message-square-quote',
        gradient: 'linear-gradient(135deg, #BF953F 0%, #0F5FA6 140%)',
      },
      {
        title: 'Cultura CEVICO',
        desc: 'Valores, responsabilidades e o jeito de servir do time',
        icon: 'i-lucide-gem',
        gradient: 'linear-gradient(135deg, #6E56CF 0%, #E54666 140%)',
      },
    ],
  },
];
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <!-- Hero -->
    <div
      class="px-8 pt-10 pb-8 relative overflow-hidden flex-shrink-0"
      style="background: linear-gradient(120deg, rgba(15,95,166,0.14), rgba(191,149,63,0.12) 60%, transparent)"
    >
      <p class="text-xs font-semibold tracking-widest text-n-gold uppercase mb-1">
        Educação do time
      </p>
      <h1 class="text-2xl font-bold text-n-slate-12 flex items-center gap-2">
        <span class="i-lucide-graduation-cap text-n-brand" />
        Academia CEVICO
      </h1>
      <p class="text-sm text-n-slate-10 mt-2 max-w-xl">
        Treinamentos, checklists e scripts para elevar o padrão de atendimento —
        dos médicos ao time de vendas. Os primeiros conteúdos chegam em breve.
      </p>
    </div>

    <!-- Trilhas -->
    <div class="px-8 pb-10 space-y-8">

      <!-- Destaque: Sistema TACOH (link externo, ao vivo) -->
      <div>
        <h2 class="text-sm font-semibold text-n-slate-12 mb-3">Destaque</h2>
        <a
          href="https://cevico.guilhermecorder.com.br/conteudos/"
          target="_blank"
          rel="noopener noreferrer"
          class="group relative flex items-center gap-6 rounded-2xl overflow-hidden p-6 transition-transform duration-200 hover:scale-[1.01] hover:shadow-xl"
          style="background: linear-gradient(120deg, #0a1c3d 0%, #10254f 55%, #16305f 100%)"
        >
          <!-- Logo TACOH -->
          <svg viewBox="0 0 200 200" class="w-28 h-28 flex-shrink-0 drop-shadow" xmlns="http://www.w3.org/2000/svg">
            <defs>
              <linearGradient id="tacoh-gold" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0%" stop-color="#E7CC8A" />
                <stop offset="50%" stop-color="#C6A15B" />
                <stop offset="100%" stop-color="#9c7a34" />
              </linearGradient>
            </defs>
            <circle cx="100" cy="100" r="78" fill="none" stroke="url(#tacoh-gold)" stroke-width="9" />
            <!-- nós com letras -->
            <g font-family="Georgia, serif" font-weight="bold" font-size="20" fill="#0a1c3d" text-anchor="middle">
              <g><circle cx="100" cy="22" r="15" fill="url(#tacoh-gold)" /><text x="100" y="29">T</text></g>
              <g><circle cx="174" cy="76" r="15" fill="url(#tacoh-gold)" /><text x="174" y="83">A</text></g>
              <g><circle cx="146" cy="163" r="15" fill="url(#tacoh-gold)" /><text x="146" y="170">C</text></g>
              <g><circle cx="54" cy="163" r="15" fill="url(#tacoh-gold)" /><text x="54" y="170">O</text></g>
              <g><circle cx="26" cy="76" r="15" fill="url(#tacoh-gold)" /><text x="26" y="83">H</text></g>
            </g>
            <!-- funil central -->
            <g font-family="Georgia, serif" font-weight="bold" fill="#E7CC8A" text-anchor="middle">
              <text x="100" y="92" font-size="15">GANCHO</text>
              <text x="100" y="108" font-size="10" fill="#C6A15B">↓</text>
              <text x="100" y="123" font-size="15">CORPO</text>
            </g>
          </svg>

          <div class="flex-1 min-w-0">
            <span class="text-[10px] font-bold uppercase tracking-widest text-n-gold">Sistema TACOH</span>
            <h3 class="text-lg font-bold text-white mt-1 leading-snug">
              Sistema Tacoh para produção de conteúdos
            </h3>
            <p class="text-sm text-white/70 mt-1">
              Método de criação de conteúdo: Gancho → Corpo → CTA. Clique para acessar o material completo.
            </p>
            <span class="inline-flex items-center gap-1 mt-3 text-sm font-semibold text-n-gold group-hover:gap-2 transition-all">
              Acessar conteúdos
              <span class="i-lucide-external-link text-xs" />
            </span>
          </div>
        </a>
      </div>

      <div v-for="section in TRACKS" :key="section.section">
        <h2 class="text-sm font-semibold text-n-slate-12 mb-3">{{ section.section }}</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <div
            v-for="item in section.items"
            :key="item.title"
            class="group relative rounded-2xl overflow-hidden cursor-pointer transition-transform duration-200 hover:scale-[1.03] hover:shadow-xl"
            style="aspect-ratio: 16/9"
            :style="{ background: item.gradient }"
          >
            <!-- brilho -->
            <div class="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300"
                 style="background: radial-gradient(600px 200px at 30% 0%, rgba(255,255,255,0.14), transparent)" />

            <!-- selo em breve -->
            <span class="absolute top-3 right-3 text-[10px] font-bold uppercase tracking-wide px-2 py-1 rounded-full bg-black/35 text-white backdrop-blur-sm">
              Em breve
            </span>

            <!-- conteúdo -->
            <div class="absolute inset-0 flex flex-col justify-end p-4">
              <span :class="item.icon" class="text-3xl text-white/90 mb-2" />
              <p class="text-sm font-bold text-white leading-tight">{{ item.title }}</p>
              <p class="text-[11px] text-white/75 mt-1 leading-snug">{{ item.desc }}</p>
            </div>
          </div>
        </div>
      </div>

      <p class="text-xs text-n-slate-9 max-w-2xl">
        Este é o espaço de cultura e educação da CEVICO. Cada card vai virar uma trilha com
        vídeos, documentos e avaliações — administrados por aqui mesmo, sem ferramentas externas.
      </p>
    </div>
  </div>
</template>
