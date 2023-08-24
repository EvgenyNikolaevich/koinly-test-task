class BaseApi
  # sleeps until the set number of seconds have passed since the last call to this method
  def rate_limit(delay_calls_by)
    this_call = Time.now.to_f
    if @last_call.present?
      secs_since_last = this_call - @last_call
      if secs_since_last < delay_calls_by
        rate_limited_for = delay_calls_by - secs_since_last
        puts "rate limited for: #{rate_limited_for} seconds" unless ENV['RACK_ENV'] == 'test'
        sleep(rate_limited_for)
      end
    end
    result = yield
    @last_call = Time.now.to_f
    result
  end

  def safe_json(response)
    begin
      json = JSON.parse(response.body)
    rescue JSON::ParserError
      body = response.body.to_s
      if body.blank? && response.code == 200
        return nil
      elsif body.include?('cloudflare')
        raise SyncError, "cant fetch data due to cloudflare (#{response.code}), try again in a few minutes"
      elsif body.include?('502 Bad Gateway') || body.include?('502 Server Error')
        raise SyncError, "api returned 502 bad gateway (#{response.code}), try again later"
      elsif body.include?('scraperapi')
        # Request failed. You will not be charged for this request. Please make sure your url is correct and try the request again. If this continues to happen, please contact support@scraperapi.com
        raise SyncError, "proxy error, most likely rate limit"
      else
        raise SyncError, "[#{response.code}] " + body.first(500)
      end
    end
    json
  end

  # removes nil objects and sorts the keys in alphabetical order (some api's require this)
  def safe_query(query)
    query = query.stringify_keys
    query.keys.sort.each_with_object({}) do |key, obj|
      obj[key] = query[key] if query[key].present?
    end
  end

  def raise_error(response, message)
    raise SyncAuthError, message.to_s if response.code == 401 || response.code == 403
    raise SyncError, message.to_s + " (#{response.code})"
  end

  # during tests the headers are returned in Capital case while during prod
  # the raw headers might be in a different case so this method returns upper
  # case headers always
  def safe_headers(response)
    response.headers.to_h.transform_keys(&:upcase)
  end
end
