class BinanceApi < BaseApi
  attr_reader :api_key, :api_secret

  BASE_URL = 'https://api.binance.com'.freeze

  def initialize(api_key=nil, api_secret=nil)
    @api_key = api_key
    @api_secret = api_secret
  end

  def deposit_history(query)
    get('/wapi/v3/depositHistory.html', query, true)
  end

  def withdraw_history(query)
    get('/wapi/v3/withdrawHistory.html', query, true)
  end

  def my_trades(query)
    get('/api/v3/myTrades', query, true)
  end

  def exchange_info
    get('/api/v1/exchangeInfo')
  end

  def account
    get('/api/v3/account', nil, true)
  end

  def dust_logs
    get('/wapi/v3/userAssetDribbletLog.html', nil, true)
  end

  private

  def get(path, query=nil, signed=false)
    query ||= {}

    if signed
      query.merge!(
        timestamp: DateTime.now.strftime('%Q'),
        recvWindow: 59999
      )

      query[:signature] = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new('sha256'), api_secret, URI.encode_www_form(query)
      )
    end

    response = HTTP
      .headers('X-MBX-APIKEY' => api_key)
      .get("#{BASE_URL}#{path}?" + URI.encode_www_form(query))

    json = JSON.parse(response.body)
    if json.is_a?(Hash) && (json['code'] || json['success'] == false)
      auth_errors = ['Please enable 2FA first', 'API key does not exist']
      raise SyncAuthError, json['msg'] if auth_errors.include?(json['msg'])
      raise_error response, [json['msg'], json['code']].compact.join(' - ')
    end

    # rate limit protection (1200 per minute)
    if response.headers['X-MBX-USED-WEIGHT'].to_i > 1000
      puts "Binance rate limit at #{response.headers['X-MBX-USED-WEIGHT']}..."
      sleep 3
    end

    json
  end
end
