# 🎯 item 371 (27/10): QUAL procedimento é o do paciente — numa palavra só,
# para viajar na conversão do Google Ads (variável `procedimento`).
#
# O sistema guarda o procedimento em vários cantos, cada um com texto livre:
# a etiqueta exigida pela automação ("Refrativa"), o campo do card
# (procedure_of_interest, preenchido à mão ou pelo Oftalmofácil), a cirurgia
# do Oftalmofácil (procedure_name/procedure_type: "FACECTOMIA + LIO
# TRIFOCAL OD"), as etiquetas do contato e a página de origem (refrativa,
# trifocal…). Aqui tudo vira um dos nomes fixos abaixo — o Google Ads só
# aprende com nome repetido, não com 40 grafias.
module Cevico::Procedure
  module_function

  # ordem importa: o mais específico primeiro
  RULES = [
    ['lente_facica',      /artisan|f[áa]cica|\bicl\b|\bipcl\b|implante de lente f/],
    ['lasik',             /lasik|femto/],
    ['prk',               /\bprk\b|\btrans.?prk\b|\bsmile\b|\blasek\b/],
    ['catarata_trifocal', /trifocal|panoptix|galaxy|multifocal|foco estendido|\bedof\b|vivity/],
    ['catarata_monofocal', /monofocal|t[óo]rica|rayner|nacional|\bmono\b/],
    ['catarata',          /catarata|facectomia|facoemuls|\blio\b|\bfaco\b/],
    ['refrativa',         /refrativ|miopia|astigmat|hipermetrop|grau|[óo]culos/],
    ['pterigio',          /pter[íi]gio/],
    ['ceratocone',        /ceratocone|crosslink/]
  ].freeze

  LABELS = {
    'lente_facica' => 'Lente fácica', 'lasik' => 'LASIK', 'prk' => 'PRK', 'catarata_trifocal' => 'Catarata trifocal',
    'catarata_monofocal' => 'Catarata monofocal', 'catarata' => 'Catarata', 'refrativa' => 'Refrativa',
    'pterigio' => 'Pterígio', 'ceratocone' => 'Ceratocone'
  }.freeze

  # texto livre → nome fixo (nil quando não reconhece)
  def normalize(text)
    plain = text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
    return nil if plain.blank?

    RULES.find { |_slug, regex| plain.match?(regex) }&.first
  end

  # o procedimento do paciente, procurado do mais certo para o mais vago:
  # etiqueta exigida pela automação → card → cirurgia do Oftalmofácil →
  # etiquetas do contato → página de origem. Devolve [slug, origem].
  def of_contact(contact, pipeline: nil, label: nil)
    candidates(contact, pipeline, label).each do |source, text|
      slug = normalize(text)
      return [slug, source] if slug
    end
    [nil, nil]
  end

  def candidates(contact, pipeline, label)
    list = [['etiqueta_exigida', label]]
    list << ['card', card_procedure(contact, pipeline)]
    list << ['oftalmofacil', surgery_procedure(contact)]
    Array(contact&.label_list).each { |l| list << ['etiqueta', l] }
    page = contact&.additional_attributes&.dig('page_ads') || {}
    list << ['pagina', "#{page['slug']} #{page['title']}"]
    list.reject { |_s, text| text.blank? }
  end

  def card_procedure(contact, pipeline)
    return nil if contact.nil?

    scope = Crm::Contact.where(contact_id: contact.id)
    scope = scope.where(pipeline_id: pipeline.id) if pipeline
    scope.where.not(procedure_of_interest: [nil, '']).order(updated_at: :desc).pick(:procedure_of_interest)
  rescue StandardError
    nil
  end

  # a cirurgia mais recente do paciente no Oftalmofácil (só o que é cirurgia)
  def surgery_procedure(contact)
    return nil if contact.nil?

    Crm::OftalmofacilSurgery.where(contact_id: contact.id).cirurgias
                            .order(Arel.sql('surgery_date DESC NULLS LAST, id DESC'))
                            .pick(:procedure_name, :procedure_type)&.compact_blank&.join(' ')
  rescue StandardError
    nil
  end
end
