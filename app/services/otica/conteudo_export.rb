# 👓 Exporta o CONTEÚDO da ótica de uma conta (a bancada) para o preparo de
# outra (a VPS): roteiro das 6 seções, texto de cada atendente e os textos da
# Jornada (pelo nome). É texto de negócio — o arquivo NUNCA entra no git.
class Otica::ConteudoExport
  def initialize(account)
    @account = account
  end

  def call # rubocop:disable Metrics/CyclomaticComplexity
    ai = CrmSetting.find_by(account: @account)&.ai_config || {}
    names = YAML.safe_load_file(Otica::Preparo::STRUCTURE)['jornada'].pluck('nome')
    {
      'exportado_em' => Time.current.iso8601, 'conta' => @account.name,
      'script' => (ai['script'] || {}).slice(*Otica::Preparo::SCRIPT_KEYS),
      'prompts' => (ai['agents'] || {}).slice('atendente_agendamento', 'atendente_pos', 'atendente_pos_op')
                                       .transform_values { |a| a['prompt'].to_s }.compact_blank,
      'journey' => Crm::JourneyMessage.where(account: @account, name: names)
                                      .to_h { |m| [m.name, m.content&.dig('text').to_s] }.compact_blank
    }
  end
end
