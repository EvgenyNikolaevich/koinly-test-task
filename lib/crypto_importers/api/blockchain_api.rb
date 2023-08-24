class BlockchainApi
  attr_reader :address

  BASE_URL = 'https://blockchain.info'.freeze

  def initialize(address)
    @address = address
  end

  def balance
    get('/balance', active: address)
  end

  def txn_list(query)
    get('/multiaddr', query.merge(active: address))
  end

  private

  def get(path, query)
    response = HTTP.get(BASE_URL + path, params: query)
    raise SyncError, response.to_s if response.mime_type != 'application/json'
    response.parse
  end
end