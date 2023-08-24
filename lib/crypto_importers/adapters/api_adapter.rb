class ApiAdapter < BaseAdapter
  attr_reader :wallet_id

  def initialize(options)
    super
    @wallet_id = options[:wallet_id]
    @before_api_options_commit = options[:before_api_options_commit]
  end

  def add_txn(txn)
    txn.synced = true
    super
  end

  def commit!(api_syncdata, api_balances, error, config = {})
    api_balances&.each do |k, v|
      if v.is_a?(Hash) && v[:currency].present?
        raise TxnError, "#{k} is not a valid currency for balances - ensure it was built with build_currency!" unless valid_currency?(v[:currency])
      end
    end

    payload = {
      'id' => request_id,
      'wallet_id' => wallet_id,
      'started_at' => initialized_at,
      'finished_at' => Time.now,
      'txns' => pending_txns.map(&:serializable_hash),
      'error' => error,
      'api_syncdata' => api_syncdata,
      'api_balances' => api_balances, # can be array and hash
      'version' => api_syncdata&.dig('version'),
      'config' => config
    }
    publish('job.finished.api_import', payload, content_type: 'application/json+br')

    pending_txns.clear

    payload
  end
end
