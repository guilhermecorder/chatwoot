import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  server: {
    allowedHosts: true,
  },
  resolve: { alias: aliases },
  // CEVICO 13/10/2026: não calcular o tamanho "gzip" de cada pedaço no fim do
  // build. É só um relatório no terminal, mas comprime de novo os pedaços
  // gigantes (dashboard ~7 MB, ícones ~15 MB) e era o que estourava a memória
  // da máquina do GitHub. Não muda nada nos arquivos gerados.
  build: {
    reportCompressedSize: false,
  },
});
