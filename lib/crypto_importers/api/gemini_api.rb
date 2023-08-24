require 'uri'

class GeminiApi < BaseApi
  attr_reader :api_key, :api_secret

  BASE_URL = "https://api.gemini.com".freeze

  def initialize(api_key=nil, api_secret=nil)
    @api_key, @api_secret = api_key, api_secret
  end

  def symbols
    get '/v1/symbols'
  end

  def balances
    post('/v1/balances')
  end

  def transfers(query = {})
    post('/v1/transfers', query)
  end

  def my_trades(query = {})
    post('/v1/mytrades', query)
  end

  private

  def get(method)
    url = BASE_URL + method
    JSON.parse(HTTP.get(url).body)
  end

  def post(path, query = {})
    query.merge!(
      request: path,
      nonce: (Time.now.to_f * 1_000_000_000).to_i.to_s,
    )

    payload = Base64.strict_encode64(query.to_json)
    signature = OpenSSL::HMAC.hexdigest('sha384', api_secret, payload)

    response = HTTP
      .headers('X-GEMINI-APIKEY' => api_key)
      .headers('X-GEMINI-PAYLOAD' => payload)
      .headers('X-GEMINI-SIGNATURE' => signature)
      .post(BASE_URL + path)

    json = JSON.parse(response.body)
    if json.is_a?(Hash) && json['result'] == 'error'
      raise SyncAuthError, json['reason'] if json['reason'] == 'InvalidSignature'
      raise_error response, json['reason']
    end
    json
  end
end
