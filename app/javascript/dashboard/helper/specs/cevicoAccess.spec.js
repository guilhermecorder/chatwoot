import {
  ROUTE_NODES,
  MENU_NODES,
  AUTOMATION_TAB_NODES,
  routeAllowed,
  routeNodesFor,
  menuNodeFor,
} from '../cevicoAccess';

// 🔐 rodada 334: acessos em árvore (ver × editar) — mapas do front
describe('cevicoAccess', () => {
  describe('mapas', () => {
    it('toda rota CEVICO do briefing tem nó', () => {
      expect(ROUTE_NODES.crm_board).toBe('crm');
      expect(ROUTE_NODES.agenda_board).toBe('agenda');
      expect(ROUTE_NODES.acessos_settings_index).toBe('configuracoes.acessos');
      expect(ROUTE_NODES.empresa_settings_index).toBe('configuracoes.empresa');
      expect(ROUTE_NODES.cevico_builder).toBe('inicio');
      expect(ROUTE_NODES.acquisition_cost_reports).toBe('financeiro.cac');
    });

    it('Financeiro e Automações abrem com QUALQUER filho', () => {
      expect(routeNodesFor('cevico_finance')).toEqual(
        expect.arrayContaining(['financeiro.lancamentos', 'financeiro.estoque'])
      );
      expect(routeNodesFor('cevico_automations')).toEqual(
        expect.arrayContaining(['automacoes.robos', 'automacoes.tratamento'])
      );
    });

    it('rota que não é CEVICO não tem nó', () => {
      expect(routeNodesFor('home')).toEqual([]);
      expect(routeNodesFor('agent_list')).toEqual([]);
      expect(routeNodesFor(undefined)).toEqual([]);
    });

    it('itens do menu apontam para o nó certo', () => {
      expect(menuNodeFor('CRM')).toBe('crm');
      expect(menuNodeFor('Settings Access')).toBe('configuracoes.acessos');
      expect(menuNodeFor('Settings Company')).toBe('configuracoes.empresa');
      expect(menuNodeFor('Automations AI Panel')).toBe('automacoes.agentes_ia');
      expect(menuNodeFor('Label Dashboard')).toBe('relatorios.core');
      // core do Chatwoot: sem nó (segue a regra antiga)
      expect(menuNodeFor('Settings Agents')).toBeNull();
      expect(menuNodeFor('Captain')).toBeNull();
      expect(Object.keys(MENU_NODES).length).toBeGreaterThan(50);
    });

    it('abas de Automações têm nó', () => {
      expect(AUTOMATION_TAB_NODES.regras).toBe('automacoes.regras');
      expect(AUTOMATION_TAB_NODES.programacao).toBe('automacoes.agentes_ia');
    });
  });

  describe('routeAllowed', () => {
    const me = {
      crm: 'edit',
      'agenda.lixeira': 'view',
      agenda: 'view',
      financeiro: 'none',
      'financeiro.lancamentos': 'none',
      'financeiro.estoque': 'view',
      'financeiro.cac': 'none',
    };

    it('rota sem nó passa sempre', () => {
      expect(routeAllowed('home', null, false)).toBe(true);
      expect(routeAllowed('agent_list', me, false)).toBe(true);
    });

    it('antes das settings carregarem: admin passa, atendente não', () => {
      expect(routeAllowed('crm_board', null, true)).toBe(true);
      expect(routeAllowed('crm_board', null, false)).toBe(false);
      expect(routeAllowed('crm_board', undefined, false)).toBe(false);
    });

    it('ver libera; none barra', () => {
      expect(routeAllowed('agenda_board', me, false)).toBe(true);
      expect(routeAllowed('crm_board', me, false)).toBe(true);
      expect(routeAllowed('acquisition_cost_reports', me, false)).toBe(false);
      // nó que nem está em `me` (ex.: cirurgias numa ótica) = none
      expect(routeAllowed('doctors_reports', me, false)).toBe(false);
    });

    it('lista "qualquer um": basta um filho visível', () => {
      expect(routeAllowed('cevico_finance', me, false)).toBe(true);
      expect(routeAllowed('cevico_automations', me, false)).toBe(false);
    });

    it('admin também perde o que não está em `me` depois de carregado', () => {
      expect(routeAllowed('doctors_reports', me, true)).toBe(false);
      expect(routeAllowed('crm_board', me, true)).toBe(true);
    });
  });
});
