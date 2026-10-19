# 📏 "NOSSA MÉDIA" (item 352): a régua do agente é o PRÓPRIO histórico da
# conta — os mesmos indicadores da leitura, fechados em 5 janelas que terminam
# ONTEM: 7, 30, 90, 180 e 360 dias, por canal (Meta, Google) e no total.
# Guardada por 1 hora (a conta de 360 dias lê o ano inteiro de anúncios).
class Cevico::CampaignAgent::Baselines
  WINDOWS = Cevico::CampaignAgent::Params::WINDOWS
  CACHE_TTL = 1.hour

  def initialize(account:, goal: 'booked', until_date: Date.current - 1)
    @account = account
    @goal = goal
    @until_date = until_date
  end

  # { 'all' => { 7 => linha, 30 => linha, … }, 'meta' => {…}, 'google' => {…} }
  def call
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { compute }
  end

  def refresh!
    Rails.cache.delete(cache_key)
    call
  end

  # a linha da régua escolhida (baseline_days) para um canal; cai no total se o canal não tem volume
  def self.pick(baselines, channel, days)
    row = baselines.dig(channel, days) || baselines.dig(channel, days.to_s)
    row = baselines.dig('all', days) || baselines.dig('all', days.to_s) if row.nil? || row['spend'].to_f.zero?
    row
  end

  private

  def cache_key
    "cevico/campaign_agent/baselines/#{@account.id}/#{@goal}/#{@until_date.iso8601}"
  end

  def compute
    WINDOWS.each_with_object({}) do |days, acc|
      totals = Cevico::CampaignAgent::Reader.new(account: @account, since_date: @until_date - (days - 1), until_date: @until_date, goal: @goal).totals
      totals.each do |channel, row|
        (acc[channel] ||= {})[days] = row.merge('days' => days, 'since' => (@until_date - (days - 1)).iso8601, 'until' => @until_date.iso8601,
                                                'daily_spend' => (row['spend'].to_f / days).round(2))
      end
    end
  end
end
