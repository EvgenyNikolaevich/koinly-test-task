RSpec.describe GeminiImporter, type: :importer do
  context "old specs" do
    before do
      symbols = VCR.use_cassette('gemini_importer') { GeminiApi.new.symbols }
      allow_any_instance_of(GeminiApi).to receive(:symbols).and_return symbols
    end

    it_behaves_like 'api import', 'gemini_importer', api_key: 'xxx', api_secret: 'xxx'

    it_behaves_like 'api import', 'gemini_importer2', api_key: 'xxx', api_secret: 'xxx'
  end
end
