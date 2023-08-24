class BinanceDexApi < BaseApi
  BASE_URL = "https://dex.binance.org".freeze

  attr_reader :address

  def initialize(address: nil)
    @address = address
  end

  def balances
    get('/api/v1/account/' + address)
  end

  def trades(q)
    get('/api/v1/trades', q.merge(address: address))
  end

  def transactions(q={})
    get('/api/v1/transactions', q.merge(address: address))
  end

  private

  def get(path, query={})
    query = safe_query(query)

    res = rate_limit(0.5.seconds) do
      with_retry([HTTP::ConnectionError, OpenSSL::SSL::SSLError]) do
        HTTP
          .get(path.start_with?('http') ? path : BASE_URL + path, params: query)
      end
    end

    parse_response(res)
  end

  def parse_response(res)
    json = safe_json(res)

    if json.is_a?(Hash) && json['message'].present?
      message = json['message']
      raise SyncAuthError, message if message == 'address is not valid'
      raise SyncError, message
    end

    json
  end
end
