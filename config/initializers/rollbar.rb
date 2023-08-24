require 'rollbar'

Rollbar.configure do |config|
  config.access_token = ENV['ROLLBAR_ACCESS_TOKEN']
  config.enabled = false if %w(development test).include?(ENV["RACK_ENV"])
  config.environment = ENV["ROLLBAR_ENV"] || ENV["RACK_ENV"]
  config.populate_empty_backtraces = true
end
