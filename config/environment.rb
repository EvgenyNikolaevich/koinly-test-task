ENV["RACK_ENV"] ||= "development"

require 'bundler/setup'
Bundler.setup(:default, :web, ENV["RACK_ENV"])
Bundler.require(:default, ENV["RACK_ENV"])

Dir[File.dirname(__FILE__) + "/initializers/*.rb"].sort.each { |f| require(f) }

require_relative "../lib/crypto_importers"
