require 'webmock/rspec'
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr"
  config.hook_into :webmock
  config.default_cassette_options = {
    :match_requests_on => [
      :method,
      VCR.request_matchers.uri_without_param(:timestamp, :signature, :nonce, :apiKey, :key)
    ]
  }
end
