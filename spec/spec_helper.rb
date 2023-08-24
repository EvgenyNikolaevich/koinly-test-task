ENV["RACK_ENV"] = "test"

require_relative "../config/environment"

Dir["#{File.dirname(__FILE__)}/shared/*.rb"].sort.each { |f| require f }
Dir["#{File.dirname(__FILE__)}/support/*.rb"].sort.each { |f| require f }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

Zip.warn_invalid_date = false # Suppress `invalid date/time in zip entry`
