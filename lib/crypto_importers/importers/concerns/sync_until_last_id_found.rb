# use this when we have an id and can only paginate in desc order. it will stop as soon as the last id is encountered
module SyncUntilLastIdFound
  extend ActiveSupport::Concern
  included do
    include DescTxnsSyncHelper
    # If api returns data in desc order then use this method.
    # example usage:
    # sync_until_last_id_found(
    #   :transactions,
    #   ->(page) { api.order_history(account_type: 0, size: ITEMS_PER_PAGE, page: page).dig('result', 0, 'result', 'items') },
    #   ->(txn) { txn['id'] }
    # ) do |txn|
    # end
    def sync_until_last_id_found(pagination_key, fetcher, id_fetcher)
      last_synced_id = get_sync_metadata(pagination_key)
      first_id = nil

      # start sync from latest txn and continue looping until we hit the last synced transaction
      max_pages_per_sync.times do |page|
        transactions = fetcher.call(page + 1)
        transactions.each do |trx|
          current_id = id_fetcher.call(trx)
          first_id ||= current_id
          return save_sync_metadata(pagination_key, first_id) if current_id.to_s == last_synced_id.to_s
          yield(trx)
        end

        return save_sync_metadata(pagination_key, first_id || last_synced_id) if transactions.empty?
      end
    end
  end
end
