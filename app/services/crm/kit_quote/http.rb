require 'net/http'

# Chamada HTTP simples do cotador: devolve [status, dados].
# dados é Hash/Array quando vem JSON; senão, o texto.
class Crm::KitQuote::Http
  NETWORK_ERRORS = [SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError].freeze
  # Falha passageira ao achar o endereço (várias consultas ao mesmo tempo): tenta de novo.
  RETRIES = 2

  def self.get(url, params: nil, headers: {}, timeout: 40)
    new(url, params).perform(Net::HTTP::Get, nil, headers, timeout)
  end

  def self.post(url, body:, headers: {}, timeout: 40)
    new(url, nil).perform(Net::HTTP::Post, body, headers, timeout)
  end

  def initialize(url, params)
    @uri = URI.parse(url)
    return if params.blank?

    query = URI.decode_www_form(@uri.query.to_s) + params.compact.map { |k, v| [k.to_s, v.to_s] }
    @uri.query = URI.encode_www_form(query)
  end

  def perform(verb, body, headers, timeout)
    attempts = 0
    begin
      response = send_request(build_request(verb, body, headers), timeout)
      [response.code.to_i, parse(response.body)]
    rescue SocketError
      attempts += 1
      raise if attempts > RETRIES

      sleep(0.4 * attempts)
      retry
    end
  rescue *NETWORK_ERRORS => e
    raise Crm::KitQuote::NoAccess, "não consegui falar com #{@uri.host}: #{e.class.name.demodulize}"
  end

  private

  def send_request(request, timeout)
    Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https', open_timeout: 15, read_timeout: timeout) do |http|
      http.request(request)
    end
  end

  def build_request(verb, body, headers)
    request = verb.new(@uri)
    request['Accept'] = 'application/json'
    request['User-Agent'] = 'Mozilla/5.0 (cotador)'
    headers.each { |k, v| request[k] = v }
    return request unless body

    request['Content-Type'] = 'application/json'
    request.body = body.to_json
    request
  end

  def parse(raw)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    raw.to_s.dup.force_encoding('UTF-8').scrub
  end
end
