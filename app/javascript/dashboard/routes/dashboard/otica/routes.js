import { frontendURL } from '../../../helper/URLHelper';
import OticaVenda from './OticaVenda.vue';
import OticaProdutos from './OticaProdutos.vue';
import OticaProducao from './OticaProducao.vue';
import OticaEstoque from './OticaEstoque.vue';

// 👓 Sua Ótica — fase 1 (22/10/2026): a loja dentro do sistema.
// Venda (O.S.), Produtos e estoque, Estoque (fase 2), Produção e entregas. Quem entra é
// decidido pela árvore de acessos (nó `otica` e filhos, só no ramo ótica).
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/otica/venda'),
      name: 'otica_venda',
      meta: { permissions: ['administrator', 'agent'] },
      component: OticaVenda,
    },
    {
      path: frontendURL('accounts/:accountId/otica/produtos'),
      name: 'otica_produtos',
      meta: { permissions: ['administrator', 'agent'] },
      component: OticaProdutos,
    },
    {
      path: frontendURL('accounts/:accountId/otica/estoque'),
      name: 'otica_estoque',
      meta: { permissions: ['administrator', 'agent'] },
      component: OticaEstoque,
    },
    {
      path: frontendURL('accounts/:accountId/otica/producao'),
      name: 'otica_producao',
      meta: { permissions: ['administrator', 'agent'] },
      component: OticaProducao,
    },
  ],
};
