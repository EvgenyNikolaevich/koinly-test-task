# use this when api uses offsets and limits
module DescTxnsSyncHelper
  extend ActiveSupport::Concern
  included do
    # use this for api's where its not possible to sort in asc order by date.
    # how it works:
    # we make a request to get the total txns, compare it to the total
    # txns in the last run to determine how many new txns we have then,
    # paginate through the new txns
    #
    # example usage:
    # fetcher = ->(offset, limit) do
    #   txns = api.fetch(offset: offset, limit: limit)
    #   [txns['total'], txns['list']]
    # end
    # sync_in_desc_order(:deposits, fetcher, 50, 5000) do |txn|
    #   sync_receive(txn)
    # end
    def sync_in_desc_order(pagination_key, fetcher, items_per_request, max_txns_limit)
      # we use shared offset so that we dont have to pull txns twice in each pagination run
      # once with offset 0 and again with offset set correctly
      shared_offset = 0

      with_pagination(pagination_key) do |total_synced_txns_at_last_sync|
        total_synced_txns_at_last_sync ||= 0
        offset = shared_offset
        total, txns = fetcher.call(offset, items_per_request)

        new_txns = total - total_synced_txns_at_last_sync
        return if new_txns.zero?

        # this means we have synced more txns than present in the wallet - usually happens if user changes address or keys
        if new_txns < 0
          fail_perm "Found fewer txns than last run (#{total_synced_txns_at_last_sync} vs #{total}). Try removing and re-adding auto-sync."
        end

        if new_txns > max_txns_limit
          total_synced_txns_at_last_sync += new_txns - max_txns_limit
          new_txns = max_txns_limit
        end

        # this will handle the case where lots of new txns were added between
        # our runs. in such cases we want to reset the offset. this also ensures
        # that we can sync all history
        if (new_txns - offset) > items_per_request
          offset = new_txns - items_per_request
          new_total, txns = fetcher.call(offset, items_per_request)
          fail 'new txns added mid-sync' if new_total != total
        end

        if txns.count > items_per_request
          fail "fetch should return at most #{items_per_request} items, returned #{txns.count}"
        end

        txns = txns.take(new_txns) if offset.zero?
        txns.reverse_each.with_index { |txn, idx| yield(txn, total_synced_txns_at_last_sync + idx) } # add oldest to newest

        if new_txns > items_per_request
          shared_offset = offset > items_per_request ? offset - items_per_request : 0
          [total_synced_txns_at_last_sync + items_per_request, true]
        else
          [total, false]
        end
      end
    end
  end
end
