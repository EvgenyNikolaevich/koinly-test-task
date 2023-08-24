module SyncMetadataAndPagination
  extend ActiveSupport::Concern

  class_methods do
    # note: dont allow setting a default since any declared default would be a class variable
    # and all instances might end up modifying the same default variable, ex. passing an empty
    # array would mean that all instances will add to the same array if they use append/push
    def metadata(method)
      define_method(method) do
        get_sync_metadata(method)
      end

      define_method(method.to_s + "=") do |val|
        save_sync_metadata(method, val)
      end

      define_method(method.to_s + "?") do
        get_sync_metadata(method).present?
      end
    end
  end

  included do
    def get_sync_metadata(key)
      api_syncdata[key]
    end

    def save_sync_metadata(key, data)
      api_syncdata[key] = data
    end

    # loops at most X times to fetch data
    def with_pagination(*keys)
      key = pagination_key(*keys)
      count = 0
      loop do
        new_data, got_more = yield(get_sync_metadata(key))
        save_sync_metadata(key, new_data) if new_data
        break unless got_more
        count += 1
        fail 'too much data for one sync, try syncing again' if count > max_pages_per_sync
      end
    end

    def pagination_key(*keys)
      'paginate_' + keys.join('_').downcase
    end
  end
end
