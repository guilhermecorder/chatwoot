# ═══════════════════════════════════════════════════════════════════
# SEGMENTO DE MERCADO — o "coringa" do sistema.
#
# A marca decide o segmento (config/brands/<marca>.yml → segmento:) e o
# ambiente pode forçar com SEGMENTO=... na VPS. Sem nada configurado vale
# a pré-seleção de fábrica: clinica (oftalmológica) — o comportamento de
# sempre, sem mudar um pixel da CEVICO.
#
# O segmento é um pacote EDITÁVEL em config/segmentos/<id>.yml:
# terminologia (paciente→cliente...), profissionais, unidades, janelas
# de agenda, modalidades, tabela de preços padrão, jornada, metas e os
# prompts dos robôs de IA. Criar um mercado novo = criar um yml novo,
# sem tocar em código.
#
# Regra de ouro: TODO valor lido daqui tem o preset da clínica como
# fallback natural — o yml da clínica guarda exatamente os valores que
# antes estavam chumbados no código.
# ═══════════════════════════════════════════════════════════════════
module Segmento
  FALLBACK_ID = 'clinica'.freeze

  module_function

  def config
    @config ||= begin
      wanted = ENV['SEGMENTO'].to_s.strip.downcase.presence ||
               (defined?(MARCA) ? MARCA['segmento'].to_s.strip.downcase.presence : nil) ||
               FALLBACK_ID
      pacote = load_yml(wanted)
      if pacote.nil? && wanted != FALLBACK_ID
        Rails.logger&.warn("[segmento] pacote '#{wanted}' não existe — usando #{FALLBACK_ID}")
        pacote = load_yml(FALLBACK_ID)
      end
      (pacote || {}).freeze
    end
  end

  def load_yml(seg_id)
    file = Rails.root.join('config', 'segmentos', "#{seg_id}.yml")
    return nil unless File.exist?(file)

    YAML.safe_load(File.read(file))
  end

  def id
    config['id'] || FALLBACK_ID
  end

  def clinica?
    id == 'clinica'
  end

  # ── Terminologia ────────────────────────────────────────────
  # termo(:cliente) → 'paciente' (clínica) / 'cliente' (empresa)
  def termo(chave)
    config.dig('termos', chave.to_s) || chave.to_s
  end

  # 'paciente' → 'Paciente' (só a primeira letra; preserva acentos)
  def termo_cap(chave)
    t = termo(chave)
    t.blank? ? t : t[0].upcase + t[1..]
  end

  # frases prontas (rótulos compostos onde gênero/concordância mudam)
  def frase(chave, padrao = nil)
    config.dig('frases', chave.to_s).presence || padrao || chave.to_s
  end

  # ── Profissionais (os "médicos" do segmento) ────────────────
  def profissionais
    Array(config['profissionais'])
  end

  # { 'Dr. Gustavo Bittar' => 'gustavo|bittar', ... } — nome oficial →
  # padrão de grafias tolerante (campo doctor das tasks é texto livre)
  def profissionais_grafias
    profissionais.each_with_object({}) do |p, map|
      next if p['nome'].blank?

      map[p['nome']] = p['grafias'].presence || Regexp.escape(p['nome'])
    end
  end

  # ── Unidades ────────────────────────────────────────────────
  def unidades
    Array(config['unidades'])
  end

  def unidade_keys
    unidades.filter_map { |u| u['key'] }
  end

  def unit_label(key)
    unidades.find { |u| u['key'] == key.to_s }&.dig('nome') || key.to_s
  end

  # { 'tatuape' => 'Tatuapé', ... } — substituto dos UNIT_LABELS chumbados
  def unit_labels
    unidades.each_with_object({}) { |u, map| map[u['key']] = u['nome'] if u['key'] }
  end

  # ── Agenda ──────────────────────────────────────────────────
  def janelas_padrao
    Array(config['janelas_padrao'])
  end

  def modalidades
    Array(config['modalidades'])
  end

  # ── Tabela de preços padrão do segmento ─────────────────────
  def precos_padrao
    Array(config['precos'])
  end

  # ── Jornada / metas / estrutura ─────────────────────────────
  def jornada
    config['jornada'] || {}
  end

  def pilares
    Array(config['pilares'])
  end

  def indicadores
    config['indicadores'] || {}
  end

  def indicadores_percentuais
    config['indicadores_percentuais'] || {}
  end

  def financeiro_categorias
    config['financeiro_categorias'] || {}
  end

  def estoque_categorias
    config['estoque_categorias'] || {}
  end

  # ── Robôs de IA ─────────────────────────────────────────────
  # prompt do segmento para um serviço ('conversation_insight',
  # 'instagram_agent'...). nil = o serviço usa o SYSTEM_PROMPT chumbado
  # (que É o preset da clínica — por isso o clinica.yml não traz prompts).
  def prompt(chave)
    config.dig('prompts', chave.to_s).presence
  end

  # trava de segurança do segmento; nil = usa a trava chumbada (clínica)
  def guardrail(respondedor:)
    config.dig('guardrails', respondedor ? 'respondedor' : 'operacional').presence
  end

  # contexto do negócio p/ {{CONTEXTO_DO_NEGOCIO}} nos prompts genéricos
  def contexto_negocio
    config['contexto'].to_s
  end

  # ── Fatia enviada ao navegador (window.SEGMENTO) ────────────
  # sem prompts/guardrails: o front não precisa e o HTML fica leve
  def frontend
    config.slice(
      'id', 'nome', 'termos', 'frases', 'profissionais', 'unidades',
      'janelas_padrao', 'modalidades', 'problemas', 'procedimentos',
      'metas', 'paineis'
    )
  end
end
