RSpec.describe IdexImporter, type: :importer do
  context "with negative balances fixed" do
    include_examples 'api import', 'idex_importer', address: '0x8277fCe34eFba4e596E40Dde7E95c09C3c7B27CA'
  end
end
