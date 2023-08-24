class EthplorerApi < BaseApi
  BASE_URL = 'http://api.ethplorer.io'.freeze
  API_KEY = 'zwmy34103xxRwu70'.freeze
  attr_reader :address

  def initialize(address)
    @address = address
  end

  def info
    get("/getAddressInfo/#{address}")
  end

  private

  def get(path, query=nil)
    query ||= {}
    query.merge!(apiKey: API_KEY)
    response = HTTP.get(BASE_URL + path, params: query)

    # note: .parse raises error if mime type is not json, when an error occurs mime
    # type returned by ethplorer is text/html even though its returning json
    json = JSON.parse(response.body)
    if response.code != 200
      raise_error response, json.dig('error', 'message')
    end

    json
  end
end