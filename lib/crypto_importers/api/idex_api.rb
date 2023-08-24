class IdexApi < BaseApi
  attr_reader :address

  BASE_URL = 'https://api.idex.market'.freeze

  def initialize(address=nil)
    @address = address
  end

  def balances
    post('/returnCompleteBalances')
  end

  def deposits_withdrawals(params)
    post("/returnDepositsWithdrawals", params)
  end

  def trade_history(params)
    post('/returnTradeHistory', params)
  end

  private

  def post(path, query=nil)
    query ||= {}
    query.merge!(address: address)

    response = HTTP.post("#{BASE_URL}#{path}", params: query)

    json = JSON.parse(response.body)
    if response.code != 200
      raise SyncAuthError, "Wallet address is invalid" if json['error'] == "Invalid value for parameter: address"
      raise_error response, json['error']
    end

    json
  end
end
