# use this when we can only query txns during a certain period and have to paginate in that period as well
# see BinanceDex
module TimeboundTxnsSyncHelper
  extend ActiveSupport::Concern
  included do
    include DescTxnsSyncHelper
    # If api returns data in desc order then use this method.
    # example usage:
    # fetcher = ->(start_time, end_time, offset, limit) do
    #   txns = api.fetch(startTime: start_time, endTime: end_time, offset: offset, limit: limit)
    #   [txns['total'], txns['list']]
    # end
    # with_timebound_desc(:deposits, '2018-01-01 00:00'.to_datetime, Time.now, 90.days, fetcher, 50, 5000) do |txn|
    #   sync_receive(txn)
    # end
    def with_timebound_desc(pagination_key, initial_starting_time, ending_time, pagination_interval, fetcher, txns_per_call, max_txns_limit)
      with_pagination(pagination_key) do |ts|
        ts ||= initial_starting_time.to_i
        ts = Time.at(ts).utc
        end_time = ts + pagination_interval
        end_time = ending_time if end_time > ending_time

        internal_fetcher = ->(offset, limit) do
          fetcher.call(ts, end_time, offset, limit)
        end

        sync_in_desc_order(pagination_key.to_s + '_' + ts.to_i.to_s, internal_fetcher, txns_per_call, max_txns_limit) do |txn|
          yield(txn)
        end

        [end_time.to_i, end_time != ending_time]
      end
    end

    # Use this method when api returns data in asc order. Pagination is handled using end_time.
    # example usage:
    # fetcher = ->(start_time, end_time) do
    #   txns = api.fetch(startTime: start_time, endTime: end_time)
    #   txns['list']
    # end
    # to_time = ->(txn) { txn['time'].to_datetime }
    # with_timebound_desc(:deposits, '2018-01-01 00:00'.to_datetime, Time.now, 90.days, fetcher, to_time, 100) do |txn|
    #   sync_receive(txn)
    # end
    def with_timebound_asc(pagination_key, initial_starting_time, ending_time, pagination_interval, fetcher, to_time, txns_per_call)
      with_pagination(pagination_key) do |ts|
        ts ||= initial_starting_time.to_i
        ts = Time.at(ts)
        end_time = ts + pagination_interval
        end_time = ending_time if end_time > ending_time

        txns = fetcher.call(ts, end_time).map do |txn|
          yield(txn)
        end

        last_time = txns.map { |x| to_time.call(x) }.sort.last
        last_time += 1.second if last_time == ts && txns.count == txns_per_call # in case too many txns at same ts
        last_time = end_time if txns.count < txns_per_call # no more txns in this period

        # continue syncing if we havnt synced full history yet or if the current period requires pagination
        [last_time.to_i, end_time != max_sync_time || txns.count == txns_per_call]
      end
    end
  end
end
