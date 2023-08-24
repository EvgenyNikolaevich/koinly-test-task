RSpec.shared_examples 'api import' do |name, options|
  subject do
    ApiImportStarted.new.process(
      'id' => '123',
      'started_at' => Time.now.to_i,
      'priority' => 'normal',
      'importer' => described_class.to_s,
      'wallet' => {
        'id' => '123',
        'name' => 'Test Wallet',
        'created_at' => Time.now,
        'synced_at' => nil,
        'txn_count' => 0,
        'api_options' => options.stringify_keys,
        'api_syncdata' => nil,
        'wallet_service_tag' => wallet_service_tag,
      },
    )
  end

  let(:adapter) { ApiAdapter.new(request_id: '123', wallet_id: '123', importer_tag: wallet_service_tag, start_date: options[:start_date]) }
  let(:wallet_service_tag) { try(:tag) || described_class.tag }
  let(:vcr_options) do
    Hash(options[:vcr_options]).tap do |opts|
      opts[:record] ||= ENV['VCR_RECORD_MODE']&.to_sym || :once # all, none, new_episodes, once
    end
  end

  before do
    # Stubbing max_sync_time needed to not get VCR::Errors::UnhandledHTTPRequestError when paginating via time ranges
    # Possible ways to set time to be stubbed:
    #   let(:at) { '2020-10-11 22:30:00 UTC' }
    #   context 'at time', at: '2020-10-11 22:30:00 UTC' { ... }
    #   it_behaves_like 'api import', at: '2020-10-11 22:30:00 UTC', ...
    time_string = options[:at] || RSpec.current_example.metadata[:at] || try(:at)
    if time_string
      if described_class.method_defined?(:max_sync_time) || described_class.private_method_defined?(:max_sync_time)
        allow_any_instance_of(described_class).to receive(:max_sync_time).and_return(Time.parse(time_string))
      else
        raise "#{described_class} doesn't have method :max_sync_time"
      end
    end

    FileUtils.rm_f(api_vcr_path(name)) if ENV['OVERRIDE_VCR'].to_boolean

    allow(ApiAdapter).to receive(:new).and_return(adapter)
  end

  it "imports from #{name}" do
    next delete_file(name) if options[:destroy]

    allow(adapter).to receive(:publish) do |_, payload|
      if described_class.tag && described_class.tag != wallet_service_tag
        payload['txns'] = payload['txns'].map do |txn|
          txn['importer_tag'] = described_class.tag
          txn
        end
      end

      formatter = SnapshotFormatter.new(txns: payload['txns'], api_balances: payload['api_balances'], diffs_enabled: !options[:no_balances])

      dump_txns(formatter) if ENV['DUMP'].to_boolean
      dump_payload(name, payload) if ENV['DUMP_PAYLOAD'].to_boolean

      expect(formatter.call.first).to match_snapshot(api_snapshot_path(name)) unless options[:error]
    end

    # NOTE: Allowing repeatable playback causes issues with POST requests as VCR ignores the request bodies by default.
    # Body can be added to request_matchers, see solana_importer_spec for example.
    VCR.use_cassette(name, vcr_options) do
      if options[:error].present?
        expect(subject.dig('error', :message)).to eq(options[:error].message)
        expect(subject.dig('error', :type)).to eq(options[:error].class.to_s)
      else
        subject
      end
    end
  end
end

def api_vcr_path(name)
  VCR.configuration.cassette_library_dir + "/#{name}.zz"
end

def api_snapshot_path(name)
  "#{Dir.pwd}/spec/fixtures/snapshots/api_imports/#{name}.json"
end

def delete_file(name)
  snapshot_path = api_snapshot_path(name)
  vcr_path = api_vcr_path(name)
  FileUtils.rm_f(snapshot_path)
  FileUtils.rm_f(vcr_path)
  puts "Deleted #{name}"
end
