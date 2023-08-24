require "active_model"
require "active_support/core_ext"

[
  "/tag.rb",
  "/services/concerns/*.rb",
  "/services/*.rb",
  "/helpers/*.rb",
  "/errors/*.rb",
  "/adapters/txn.rb",
  "/importers/concerns/*.rb",
  "/**/base_*.rb",
  "/api/*.rb",
  "/adapters/*.rb",
  "/importers/*.rb",
  "/mappers/*.rb",
  "/api_definitions.rb",
].each do |folder|
  Dir[File.dirname(__FILE__) + "/crypto_importers" + folder].sort.each do |f|
    require(f)
  end
end

module CryptoImporters
end
