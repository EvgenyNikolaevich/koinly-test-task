class EtherscanApi
  BASE_URL = 'http://api.etherscan.io/api'.freeze
  API_KEY = 'FFGZ14MSXGXMD5MZ76SK3MD3TYHFSQEPRU'.freeze
  attr_reader :address

  def initialize(address)
    @address = address
  end

  def balance
    get('balance', address: address)
  end

  def txlist(query)
    get('txlist', { address: address }.merge(query))
  end

  def txlistinternal(query)
    get('txlistinternal', { address: address }.merge(query))
  end

  def tokentx(query)
    get('tokentx', { address: address }.merge(query))
  end

  private

  def get(action, query)
    json = HTTP.get(BASE_URL, params: {
      module: 'account',
      action: action,
      apikey: API_KEY
    }.merge(query)).parse

    if json['message'] == 'NOTOK'
      raise SyncAuthError, json['result'] if json['result'] == 'Error! Invalid address format'
      raise SyncError, json['result']
    end
    json
  end
end