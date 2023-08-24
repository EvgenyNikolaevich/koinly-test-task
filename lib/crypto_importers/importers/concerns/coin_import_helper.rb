module CoinImportHelper
  extend ActiveSupport::Concern
  included do
    include DescTxnsSyncHelper

    def items_per_request
      fail 'not implemented'
    end

    # this should return the total no. of txns & the txns in asc order (oldest to newest)
    # ex: [50, [{...}]]
    # txns must only be new ones! if same txns are returned there will be issues...
    def fetch(offset = 0)
      fail 'not implemented'
    end

    def import
      fetcher = ->(offset, limit) { fetch(offset) }
      sync_in_desc_order(:recent, fetcher, items_per_request, historical_txns_limit) do |txn|
        sync_amount(txn)
      end
    end
  end
end
