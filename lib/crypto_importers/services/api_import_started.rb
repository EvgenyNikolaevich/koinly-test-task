class ApiImportStarted
  def process(payload)
    wallet = payload['wallet'].symbolize_keys
    api_options = wallet[:api_options].symbolize_keys
    api_syncdata = wallet[:api_syncdata]

    importer_klass = payload['importer'].constantize

    adapter = ApiAdapter.new(
      request_id: payload['id'],
      wallet_id: wallet[:id],
      start_date: api_options[:start_date],
      deposit_label: api_options[:deposit_label],
      importer_tag: importer_klass.tag,
    )

    importer_klass.new(
      adapter,
      wallet: wallet,
      api_options: api_options,
      api_syncdata: api_syncdata
    ).import_and_commit!
  end
end
