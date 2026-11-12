# 🔑 Gerador de proposta (LIFE, 12/11/2026): mantém a cotação da Bluesun ligada
# e avisa quando alguém precisa entrar no portal.
#
# A Bluesun não tem acesso oficial: a sessão do portal vale 3 h e a chave de
# renovação vale 7 dias. Cada renovação devolve uma chave nova de 7 dias, então
# o robô renova de hora em hora (antes de vencer) e a sessão não cai sozinha.
#
# Se mesmo assim a chave estiver perto do fim (portal com limite próprio) ou a
# sessão caiu (portal recusou a renovação), abre UMA tarefa urgente para o
# administrador, com o passo a passo de 2 minutos. Quando a sessão nova entra
# (ou a renovação volta a funcionar), o próprio robô fecha a tarefa.
class Crm::KitQuoteKeepaliveJob < ApplicationJob
  queue_as :low

  RENEW_BEFORE = 75.minutes # roda de hora em hora: renova antes de chegar a vencer
  WARN_BEFORE = 24.hours    # aviso com 1 dia de folga
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  TITLE = '🔑 Entrar no portal da Bluesun (cotação do Gerador de proposta)'.freeze
  PASSOS = <<~TXT.strip.freeze
    O que fazer (2 minutos, no computador):
    1. Abra o Gerador de proposta e clique em "Acessos dos fornecedores".
    2. Clique em "portal da Bluesun" e entre com o seu login.
    3. Já logado no portal, clique no favorito "Copiar sessão Bluesun".
    4. Volte ao sistema, cole no campo da Bluesun e clique em "Salvar sessão".
    Esta tarefa fecha sozinha quando a sessão nova entrar.
  TXT

  def perform
    CrmSetting.find_each do |settings|
      next if settings.ai_config&.dig(Crm::KitQuote::Store::KEY, 'bluesun_sessao').blank?

      check(settings.account)
    rescue StandardError => e
      Rails.logger.error "[LIFE cotação Bluesun] conta #{settings.account_id}: #{e.message}"
    end
  end

  private

  def check(account)
    store = Crm::KitQuote::Store.new(account)
    Crm::KitQuote::Bluesun.new(store.config, store.secrets, store).prepare(margin: RENEW_BEFORE.to_i)

    status = Crm::KitQuote::Store.new(account).status['bluesun']
    vence = parse(status['vence_em'])
    renova = parse(status['renova_ate'])
    now = Time.current

    if vence.nil? || vence <= now
      warn!(account, "#{stamp(now)} · A cotação da Bluesun caiu: o portal não renovou a sessão. " \
                     'Enquanto isso, o Gerador de proposta cota só com os outros fornecedores.', :urgent)
    elsif renova && renova <= now + WARN_BEFORE
      warn!(account, "#{stamp(now)} · A chave da Bluesun vence em #{stamp(renova)}. Até lá o sistema renova sozinho; " \
                     'depois disso, o Gerador de proposta para de cotar na Bluesun.', :high)
    else
      close!(account, now)
    end
  end

  # uma tarefa aberta por vez; a repetição de hora em hora não cria outra
  def warn!(account, line, priority)
    return if account.tasks.exists?(title: TITLE, status: %i[todo doing])

    admin = account.administrators.order(:id).first
    return if admin.nil?

    account.tasks.create!(title: TITLE, description: "#{line}\n\n#{PASSOS}", priority: priority, status: :todo,
                          due_at: Time.current, creator: admin, assignee: admin)
  end

  def close!(account, now)
    line = "#{stamp(now)} · sessão da Bluesun ligada de novo — tarefa fechada pelo sistema."
    account.tasks.where(title: TITLE, status: %i[todo doing]).find_each do |task|
      task.update!(status: :done, description: [task.description.presence, line].compact.join("\n\n"))
    end
  end

  def parse(iso)
    iso.present? ? Time.zone.parse(iso.to_s) : nil
  rescue ArgumentError
    nil
  end

  def stamp(time)
    time.in_time_zone(TZ).strftime('%d/%m às %H:%M')
  end
end
