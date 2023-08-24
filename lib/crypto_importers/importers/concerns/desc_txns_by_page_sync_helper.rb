# use this when api uses page numbers and page sizes
module DescTxnsByPageSyncHelper
  extend ActiveSupport::Concern
  included do
    # use this for api's where its not possible to sort in asc order by date.
    # how it works:
    # we make a request to get the total txns, compare it to the total
    # txns in the last run to determine how many new txns we have then,
    # paginate through the new txns
    #
    # example usage:
    # fetcher = ->(page, per_page) do
    #   txns = api.fetch(page: page, limit: per_page)
    #   [txns['total'], txns['list']]
    # end
    # sync_in_desc_order_by_page(:deposits, fetcher, 50, 5000) do |txn, idx|
    #   sync_receive(txn)
    # end
    def sync_in_desc_order_by_page(pagination_key, fetcher, items_per_request, max_txns_limit)
      # we use shared offset so that we dont have to pull txns twice in each pagination run
      # once with offset 0 and again with offset set correctly
      shared_page = 1
      with_pagination(pagination_key) do |total_synced_txns_at_last_sync|
        total_synced_txns_at_last_sync ||= 0
        page = shared_page
        total, txns = fetcher.call(page, items_per_request)

        new_txns = total - total_synced_txns_at_last_sync
        return if new_txns.zero?

        skipped_txns = 0
        if new_txns > max_txns_limit
          skipped_txns = new_txns - max_txns_limit
          new_txns = max_txns_limit
        end

        pages_to_sync = (new_txns / items_per_request.to_f).ceil
        if pages_to_sync > page
          page = pages_to_sync
          new_total, txns = fetcher.call(pages_to_sync, items_per_request)
          fail 'new txns added mid-sync' if new_total != total
        end

        if txns.count > items_per_request
          fail "fetch should return at most #{items_per_request} items, returned #{txns.count}"
        end

        new_items_on_this_page = new_txns - items_per_request * (page - 1)
        txns.take(new_items_on_this_page).reverse_each.with_index { |txn, idx| yield(txn, total_synced_txns_at_last_sync + idx) }

        if page > 1
          shared_page = page - 1
          [total_synced_txns_at_last_sync + skipped_txns + new_items_on_this_page, true]
        else
          [total, false]
        end
      end
    end
  end
end
