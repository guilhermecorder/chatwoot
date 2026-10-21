# 🔒 PORTA FECHADA dos comandos de TESTE (auditoria 10/2026, #211/#212).
#
# Os rakes de simulação (cevico:voice_simulate, voice_tools, calls_simulate,
# calls_end, wa_agent_simulate, creatives_demo_funnel) marcam consulta, criam
# ligação, chamam a IA e mandam WhatsApp pelo MESMO caminho de produção. Rodar
# um deles por engano na VPS podia cair num paciente de verdade (o telefone
# padrão era o 1º contato da conta).
#
# Regra:
# - no ambiente LOCAL (development/test) tudo segue livre, como antes;
# - fora dele o comando ABORTA, a não ser que a pessoa ligue de propósito a
#   variável CEVICO_SIMULATION_OK=1 — e mesmo assim nunca em cima de paciente
#   real: PHONE= é obrigatório, não pode ser de ninguém cadastrado, e
#   CONTACT_ID=/CAMPAIGN_ID= são recusados.
module Cevico::SimulationGuard
  ESCAPE_VAR = 'CEVICO_SIMULATION_OK'.freeze
  # número claramente inválido (no Brasil nenhum número começa com 0 depois
  # do DDD) — é o padrão quando ninguém informa PHONE=
  FAKE_PHONE = '5511000000000'.freeze
  # variáveis que apontam para paciente/campanha de verdade
  REAL_PATIENT_VARS = %w[CONTACT_ID CAMPAIGN_ID].freeze

  def self.local?
    Rails.env.local?
  end

  # fora do local, só com a variável de escape ligada de propósito
  def self.allowed?
    local? || ENV[ESCAPE_VAR] == '1'
  end

  # chamar no COMEÇO do rake, antes de tocar em qualquer registro
  def self.check!(task_name)
    return if local?

    unless ENV[ESCAPE_VAR] == '1'
      abort "⛔ #{task_name} é um comando de TESTE: só roda em desenvolvimento. Fora dele, só de propósito com " \
            "#{ESCAPE_VAR}=1 e PHONE= de um número que não é de paciente."
    end
    REAL_PATIENT_VARS.each do |var|
      next if ENV[var].blank?

      abort "⛔ #{task_name}: fora do desenvolvimento a simulação não usa paciente nem campanha de verdade (tire #{var}=)."
    end
  end

  # telefone da simulação, só dígitos. Fora do local: PHONE= obrigatório e
  # não pode casar com paciente cadastrado (Task.match_contact, o critério
  # de "mesma pessoa" do sistema).
  def self.phone!(account, raw, task_name)
    digits = raw.to_s.gsub(/\D/, '')
    return digits if local?

    abort "⛔ #{task_name}: fora do desenvolvimento informe PHONE= com um número fictício (ex.: PHONE=#{FAKE_PHONE})." if ENV['PHONE'].blank?
    existing = Task.match_contact(account, digits)
    if existing
      abort "⛔ #{task_name}: o número #{digits} é de um paciente cadastrado (##{existing.id}) — " \
            'a simulação só roda com número que não é de ninguém.'
    end
    digits
  end
end
