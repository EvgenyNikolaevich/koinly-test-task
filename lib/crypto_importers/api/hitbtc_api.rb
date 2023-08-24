class HitbtcApi < BaseApi
  attr_reader :api_key, :api_secret

  BASE_URL = 'https://api.hitbtc.com'.freeze

  def initialize(api_key=nil, api_secret=nil)
    @api_key = api_key
    @api_secret = api_secret
  end

  def account_balance
    get('/api/2/account/balance')
  end

  def trading_balance
    get('/api/2/trading/balance')
  end

  def transactions(q=nil)
    get('/api/2/account/transactions', q)
  end

  def trades(q=nil)
    get('/api/2/history/trades', q)
  end

  def symbols
    get('/api/2/public/symbol')
  end

  private

  def get(path, query=nil)
    query ||= {}
    response = HTTP.basic_auth(user: api_key, pass: api_secret).get("#{BASE_URL}#{path}?" + URI.encode_www_form(query))
    json = JSON.parse(response.body)
    if response.code >= 400
      raise SyncAuthError, json['error']['message'] if response.code == 403
      raise_error response, json['error']['message']
    end

    json
  end
end
