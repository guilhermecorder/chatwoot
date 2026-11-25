# 📍 MARCOS DO ATENDIMENTO (24/11/2026): a data em que algo grande mudou no
# atendimento por IA (troca de motor, prompt novo numa caixa, volta ao formato
# antigo). O Laboratório usa o marco para comparar ANTES × DEPOIS por caixa.
# Mora em ai_config['marcos'] (o mais novo primeiro; até CAP).
module Crm::AttendanceMilestones
  module_function

  KEY = 'marcos'.freeze
  CAP = 40

  def list(account)
    Array((CrmSetting.find_by(account: account)&.ai_config || {})[KEY]).select { |m| m.is_a?(Hash) && m['at'].present? }
  end

  def find(account, id)
    all = list(account)
    all.find { |m| m['id'] == id.to_s } || all.first
  end

  # só o marco com ESTE id (find devolve o mais novo quando não acha)
  def find_exact(account, id)
    return nil if id.blank?

    list(account).find { |m| m['id'] == id.to_s }
  end

  # 📍 item 419: `inbox_ids` = as caixas em que a mudança valeu (vazio = todas);
  # o Comparativo de caixas desenha o marco só nos gráficos delas
  def add!(account, title:, note: nil, at: nil, by: nil, inbox_ids: nil) # rubocop:disable Metrics/AbcSize, Metrics/ParameterLists
    moment = (at.presence && parse(at)) || Time.current
    boxes = Array(inbox_ids).map(&:to_i).select(&:positive?).uniq.first(30)
    entry = { 'id' => SecureRandom.hex(4), 'at' => moment.iso8601, 'title' => title.to_s.strip.first(120),
              'note' => note.to_s.strip.first(600).presence, 'by' => by.to_s.presence, 'created_at' => Time.current.iso8601,
              'inbox_ids' => boxes.presence }.compact
    Cevico::SettingMerge.merge!(account, :ai_config) do |cfg|
      cfg[KEY] = ([entry] + Array(cfg[KEY])).sort_by { |m| m['at'].to_s }.reverse.first(CAP)
      cfg
    end
    entry
  end

  def remove!(account, id)
    Cevico::SettingMerge.merge!(account, :ai_config) do |cfg|
      cfg[KEY] = Array(cfg[KEY]).reject { |m| m['id'] == id.to_s }
      cfg
    end
  end

  def parse(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
