class ZelcoreMapper < BaseMapper
  tag Tag::ZELCORE_WALLET
  mappings [
    {
      id: 'zelcore-txns',
      required_headers: ['txid','formattedDate','timestamp','amount','direction'],
      header_mappings: {
        date: 'timestamp',
        amount: 'amount',
        txhash: 'txid'
      }
    }
  ]

  def parse_row(mapped_row, raw_row, options)
    currency = currency_from_file_name options[:file_name]
    mapped_row[:currency] = currency
    mapped_row[:error] = "Zelcore file name must be in this format: XYZ_transactions.csv. Redownload or rename the file and try again." unless currency
    mapped_row
  end

  def currency_from_file_name(file_name)
    @name ||= file_name.match(/([A-Z]+)_transactions/).to_a.second # XYZ_transactions_Username.csv
  end
end