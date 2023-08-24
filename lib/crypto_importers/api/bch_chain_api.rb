class BchChainApi
  attr_reader :address

  BASE_URL = 'https://bch-chain.api.btc.com'.freeze
  API_KEY = '95576b16c753'.freeze

  def initialize(address)
    @address = address
  end

  def info
    get("/v3/address/#{address}")
  end

  def txns(query)
    get("/v3/address/#{address}/tx", query)
  end

  private

  def get(path, query={})
    response = HTTP.get(BASE_URL + path, params: query)
    json = response.parse
    if response.code >= 400 || json['err_msg'].present?
      raise SyncAuthError, json['err_msg'] if json['err_no'] == 2
      raise SyncError, json['err_msg']
    end
    json
  end
end