module Kernel
  # provide a "reload" param if you want to retry on certain conditions ex. if response code is 502 etc
  # provide a "catch" param for custom retry logic
  def with_retry(exceptions, retries: 5, catch: nil, reload: nil)
    try = 0
    begin
      res = yield try
      while reload && reload.call(res, try)
        try += 1
        res = yield try
      end
      res
    rescue *exceptions => e
      try += 1
      try <= retries ? retry : raise
    rescue => e
      if catch && catch.call(e, try)
        try += 1
        retry
      end
      raise
    end
  end
end
