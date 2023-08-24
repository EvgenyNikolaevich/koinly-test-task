RSpec.describe HitbtcImporter, type: :importer do
  it_behaves_like 'api import', 'hitbtc_importer', api_key: 'xxx', api_secret: 'xxx'
end
