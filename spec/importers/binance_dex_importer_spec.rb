RSpec.describe BinanceDexImporter, type: :importer do
  before do
    allow_any_instance_of(BinanceDexApi).to receive(:sleep)
  end

  it_behaves_like 'api import', 'bnb_0', address: 'justignoreme', error: SyncAuthError.new("address is not valid")

  context "at 2020-03-08 13:00 UTC" do
    before { allow_any_instance_of(described_class).to receive(:max_sync_time) { "2020-03-08 13:00 UTC".to_datetime } }
    it_behaves_like 'api import', 'bnb_address_1', address: 'bnb1k2v0g4eylh2h74w94u06rfn7qu4dl0y0d8wnax'
    it_behaves_like 'api import', 'bnb_address_2', address: 'bnb1w3cvs5gu82m8ju55vewwzsdqna52gz8jxy6mgx'
    it_behaves_like 'api import', 'bnb_address_3', address: 'bnb1xha2gyrgygr7crnny9xcl6yrmp8qp08llnd80y'

    # this one has multisend txns which are not supported
    it_behaves_like 'api import', 'bnb_address_4', address: 'bnb1ea5ucfqfxpwfzsq3ukmf9ued4wemx970ahpdfs'

    it_behaves_like 'api import', 'bnb_address_5', address: 'bnb1df40dsktseerh0mh0cdj33zcmssdmvv970ml59', no_repeat: true
    it_behaves_like 'api import', 'bnb_address_6', address: 'bnb1a0mn35y7v37ut0unhduw6gwurwznpf79zywn0k'
  end

  context "at 2020-04-14 00:00 UTC" do
    before { allow_any_instance_of(described_class).to receive(:max_sync_time) { "2020-04-14 00:00 UTC".to_datetime } }
    it_behaves_like 'api import', 'bnb_address_7', address: 'bnb1ea5ucfqfxpwfzsq3ukmf9ued4wemx970ahpdfs'
  end

  context "at 2020-07-31 18:37 IST" do
    before { allow_any_instance_of(described_class).to receive(:max_sync_time) { "2020-07-31 18:37 IST".to_datetime } }
    # contains multi send transactions (rune airdrops)
    it_behaves_like 'api import', 'bnb_address_8', address: 'bnb107lpz8zcxrqsl2pfdzm6ajnkmf0dshltuzxpmr'
  end
end
