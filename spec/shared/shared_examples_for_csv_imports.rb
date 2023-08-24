RSpec.shared_examples 'csv import' do |file_names, options = {}|
  let(:importer_tag) { try(:tag) }

  before do
    CsvAdapter.singleton_class.alias_method(:original_new, :new)
  end

  it("imports from #{options[:name] || file_names}", options[:slow] ? { slow: true } : { fast: true }) do |_example|
    file_names = Array(file_names).map do |file_name_or_url|
      file_name_or_url.match?(/^\/|https?\:\/\//) ? download_file(file_name_or_url, options) : file_name_or_url
    end

    raise 'Must set options[:name] if providing an array of file_names!' if file_names.count > 1 && !options[:name]
    next file_names.each { |file_name| delete_file(file_name) } if options[:destroy]

    csv_imports = []
    file_names.each do |file_name|
      # Need to have new adapter for each file
      adapter = CsvAdapter.original_new(request_id: '123', wallet_id: '123')
      allow(CsvAdapter).to receive(:new).and_return(adapter)

      allow(adapter).to receive(:publish) do |_, payload|
        payload = JSON.parse(JSON.generate(payload))
        csv_imports << { file_name:, payload: }

        dump_payload(file_name, payload) if ENV['DUMP_PAYLOAD'].to_boolean

        expect(payload['error']).to be_nil

        if payload['state'] == 'unknown_csv'
          header = payload['initial_rows'][0].map { |x| "'#{x}'" }.join(', ')
          raise "No mapper matched these headers: [#{header}] (#{file_name})"
        elsif payload['state'] == 'enter_mapping_id'
          raise "Multiple mappers found: #{payload['potential_mappers'].join(', ')} (#{file_name})"
        else
          expect(payload['state']).to eq 'completed'
        end
      end

      run_csv_import(file_name, importer_tag, options)
    end

    if csv_imports.one?
      txns = csv_imports.first[:payload]['txns']
    else
      payloads = csv_imports.pluck(:payload)
      txns = payloads.pluck('txns').flatten
    end

    formatter = SnapshotFormatter.new(txns:)

    dump_txns(formatter) if ENV['DUMP'].to_boolean

    snapshots = formatter.call.sort_by { |x| [x[:name], x[:txn_count], x[:entry_count]] }
    wallet_snapshot = snapshots.one? ? snapshots.first : { wallets: snapshots }

    if csv_imports.one?
      wallet_snapshot[:csv_import] = csv_imports.first[:payload]['results'].except('errors', 'skipped')
      snapshot_file_name = csv_imports.first[:file_name]
    else
      csv_imports.sort_by! { |import| import[:file_name] }
      wallet_snapshot[:csv_imports] = csv_imports.map do |import|
        import[:payload]['results'].except('errors', 'skipped').merge(file_name: import[:file_name])
      end
      snapshot_file_name = options[:name]
    end

    expect(wallet_snapshot).to match_snapshot(csv_import_snapshot_path(snapshot_file_name))
  end
end

def run_csv_import(file_name, wallet_service_tag = nil, payload_options = {})
  CsvImportStarted.new.process({
    'id' => '123',
    'started_at' => Time.now.to_i,
    'priority' => 'normal',
    'csv_import' => {
      'id' => 1,
      'file_url' => csv_import_file_path(file_name),
      'max_rows_limit' => 100_000,
      'options' => payload_options.slice(:timezone, :currency_id, :withdrawal_label, :deposit_label, :mapping_id).stringify_keys,
    },
    'wallet' => {
      'id' => '123',
      'name' => 'Test Wallet',
      'created_at' => Time.now,
      'synced_at' => nil,
      'txn_count' => 0,
      'wallet_service_tag' => wallet_service_tag,
    },
  })
end

def csv_import_file_path(file_name)
  "#{Dir.pwd}/spec/fixtures/files/#{file_name}"
end

def csv_import_snapshot_path(file_name)
  "#{Dir.pwd}/spec/fixtures/snapshots/csv_imports/#{file_name}.json"
end

def download_file(url, options)
  file_name = options[:as] || url.split('/').last.gsub(/\?[0-9]+$/, '')
  file_path = csv_import_file_path(file_name)
  return file_name if File.exist?(file_path)

  WebMock.allow_net_connect!
  data = VCR.turned_off { URI.open(url).read }
  WebMock.disable_net_connect!

  FileUtils.mkdir_p(File.dirname(file_path))
  File.binwrite(file_path, data)

  puts "Downloaded file: #{url}"

  file_name
end

# delete the file along with snapshot
def delete_file(file_name)
  snapshot_path = csv_import_snapshot_path(file_name)
  file_path = csv_import_file_path(file_name)
  FileUtils.rm_f(snapshot_path)
  FileUtils.rm_f(file_path)
  puts "Deleted #{file_name}"
end
