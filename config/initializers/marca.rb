# ═══════════════════════════════════════════════════════════════════
# PACOTE DE MARCAS (CEVICO ↔ LIFE ↔ futuras)
#
# A marca é decidida pelo AMBIENTE de cada VPS, nunca pelo código:
#   sem MARCA (ou MARCA=cevico) → comportamento idêntico ao de sempre
#   MARCA=life                  → o sistema veste a camisa da Life
#
# O que a marca controla (fase 1): nome do sistema, logos e favicon.
# Na subida, as configurações de instalação da marca são gravadas no
# banco DA PRÓPRIA VPS (idempotente) — a outra instalação nunca é
# tocada, porque cada uma tem seu banco.
# ═══════════════════════════════════════════════════════════════════
marca_id = ENV.fetch('MARCA', 'cevico').strip.downcase
arquivo = Rails.root.join('config', 'brands', "#{marca_id}.yml")
unless File.exist?(arquivo)
  Rails.logger&.warn("[marca] pacote '#{marca_id}' não existe — usando cevico")
  marca_id = 'cevico'
  arquivo = Rails.root.join('config', 'brands', 'cevico.yml')
end

MARCA = YAML.safe_load(File.read(arquivo)).freeze

Rails.application.config.after_initialize do
  # A marca padrão só corrige o NOME da instalação quando ele ainda é um dos
  # antigos (o "Chatwoot" de fábrica ou os nomes que já usamos) — assim o título
  # da aba vira o nome oficial do pacote sem ninguém mexer em painel. O resto
  # (logos, cores) continua vindo do banco.
  # Sem banco de verdade (ex.: montagem da imagem no GitHub, assets:precompile)
  # o Rails 7.2 avisa com ActiveRecord::DatabaseConnectionError (filha de
  # ConnectionNotEstablished) — por isso o rescue abaixo cobre as duas famílias.
  if MARCA['id'] == 'cevico'
    begin
      if ActiveRecord::Base.connection.data_source_exists?('installation_configs')
        config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_NAME')
        antigos = ['', 'Chatwoot', 'Sistema CEVICO', 'CEVICO S.I']
        if antigos.include?(config.value.to_s.strip) && config.value != MARCA['nome']
          config.value = MARCA['nome']
          config.save!
          GlobalConfig.clear_cache
          Rails.logger&.info("[marca] nome da instalação atualizado para '#{MARCA['nome']}'")
        end
      end
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, PG::Error => e
      Rails.logger&.warn("[marca] nome adiado (banco indisponível): #{e.class}")
    end
    next
  end

  begin
    next unless ActiveRecord::Base.connection.data_source_exists?('installation_configs')

    {
      'INSTALLATION_NAME' => MARCA['nome'],
      'BRAND_NAME'        => MARCA['brand_name'],
      'LOGO'              => MARCA.dig('logos', 'logo'),
      'LOGO_DARK'         => MARCA.dig('logos', 'logo_dark'),
      'LOGO_THUMBNAIL'    => MARCA.dig('logos', 'logo_thumbnail')
    }.each do |nome, valor|
      next if valor.blank?

      config = InstallationConfig.find_or_initialize_by(name: nome)
      next if config.value == valor

      config.value = valor
      config.save!
    end
    GlobalConfig.clear_cache
    Rails.logger&.info("[marca] instalação vestiu a marca '#{MARCA['id']}'")
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, PG::Error => e
    # banco ainda não existe/está fora (ex.: durante o prepare) — sem drama,
    # na próxima subida a marca é aplicada.
    Rails.logger&.warn("[marca] adiado (banco indisponível): #{e.class}")
  end
end
