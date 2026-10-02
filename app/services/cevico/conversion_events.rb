# Item 313: os eventos de conversão que as colunas do CRM mandam para o
# Google (GA4 → Google Ads) e para a Meta — UMA lista, por ETAPA DO FUNIL.
#
# Por que lista fechada: o Google responde "ok" para qualquer nome e joga
# fora em silêncio o que vier com espaço, acento ou hífen; e evento por
# procedimento ("prk", "refrativa"…) pulveriza o volume que o Google Ads
# precisa para aprender. O procedimento viaja DENTRO do evento
# (parâmetro `procedimento`), não no nome.
module Cevico::ConversionEvents
  # nome GA4 → como a equipe lê. `generate_lead` fica FORA da lista nova: a
  # página já dispara esse nome no clique do WhatsApp (contaria em dobro);
  # automação antiga que usa ele continua funcionando igual.
  GA4_EVENTS = {
    'lead_whatsapp' => 'Lead chegou no WhatsApp (conversa de verdade)',
    'orcamento_enviado' => 'Recebeu orçamento',
    'agendou_consulta' => 'Agendou consulta',
    'compareceu_consulta' => 'Compareceu à consulta',
    'fechou_cirurgia' => 'Fechou cirurgia (com valor)'
  }.freeze

  # eventos de FECHAMENTO: sem valor digitado, vai o valor do card
  CLOSING_GA4 = %w[fechou_cirurgia close_convert_lead purchase].freeze
  CLOSING_META = %w[Purchase].freeze

  GA4_NAME = /\A[a-zA-Z][a-zA-Z0-9_]{0,39}\z/
  # prefixos que o GA4 reserva — evento com eles é descartado
  GA4_RESERVED_PREFIXES = %w[google_ ga_ firebase_ gtag.].freeze

  # Lead que veio de anúncio de WhatsApp (click-to-WhatsApp): a Meta só
  # aceita a lista dela de eventos de mensagem. De-para dos nomes do site.
  META_MESSAGING = {
    'Lead' => 'LeadSubmitted',
    'Contact' => 'LeadSubmitted',
    'CompleteRegistration' => 'LeadSubmitted',
    'Schedule' => 'QualifiedLead'
  }.freeze
  META_MESSAGING_ALLOWED = %w[Purchase LeadSubmitted InitiateCheckout AddToCart ViewContent OrderCreated OrderShipped
                              OrderDelivered OrderCanceled OrderReturned CartAbandoned QualifiedLead RatingProvided
                              ReviewProvided].freeze

  module_function

  def ga4_valid?(name)
    name.to_s.match?(GA4_NAME) && GA4_RESERVED_PREFIXES.none? { |p| name.to_s.downcase.start_with?(p) }
  end

  # Nome que o GA4 aceita. Nome já válido passa INTACTO (não muda evento que
  # já está cadastrado no Google); nome inválido — que hoje é descartado em
  # silêncio — vira a versão aceita: "Refrativa PRK" → "Refrativa_PRK".
  def ga4_name(raw)
    name = raw.to_s.strip
    return name if ga4_valid?(name)

    clean = ActiveSupport::Inflector.transliterate(name).gsub(/[^a-zA-Z0-9_]+/, '_').squeeze('_')
    clean = clean.sub(/\A[^a-zA-Z]+/, '').sub(/_+\z/, '')[0, 40].to_s
    clean = "ev_#{clean}"[0, 40] if GA4_RESERVED_PREFIXES.any? { |p| clean.downcase.start_with?(p) }
    ga4_valid?(clean) ? clean : nil
  end

  # nome que vai para a Meta quando o lead veio de anúncio de WhatsApp
  def meta_messaging_name(name)
    META_MESSAGING[name.to_s] || name.to_s
  end

  def closing_ga4?(name)
    CLOSING_GA4.include?(name.to_s)
  end

  def closing_meta?(name)
    CLOSING_META.include?(name.to_s)
  end
end
