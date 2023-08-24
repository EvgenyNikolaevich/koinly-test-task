class AbraMapper < BaseMapper
  tag Tag::ABRA
  mappings [
    {
      id: 'abra-transactions',
      determine_date_format: true,
      required_headers: ['Transaction date (UTC)', 'Transaction ID', 'Transaction type', 'Description', 'Product'],
      optional_headers: ['Gross Quantity', 'Network Fees', 'Fees', 'Net Quantity', 'Quantity', 'Net Amount (USD)', 'Amount (USD)'],
      header_mappings: {
        date: 'Transaction date (UTC)',
        amount: ['Net Quantity', 'Quantity'],
        currency: 'Product',
        txhash: 'Transaction ID',
        description: 'Description',
      },
      group: {
        by_hash: ->(mapped, row) { row['Transaction ID'] },
        eligible: ->(mapped, row) { row['Transaction type'].match(/Buy|Sell/) },
      }
    },
    {
      id: 'abra-transactions-2',
      required_headers: ['Transaction date (UTC)', 'Transaction type', 'Description', 'Product'],
      optional_headers: ['Gross Quantity', 'Network Fees', 'Fees', 'Net Quantity', 'Quantity', 'Net Amount (USD)', 'Amount (USD)'],
      error: "This file does not contain your Transaction IDs, please download a new file from abra."
    }
  ]

  def fetch_rows(headers, spreadsheet)
    @amount_header = headers.find { |header| header.match(/Amount \(\w+\)/) }
    @currency = @amount_header.match(/Amount \((\w+)\)/)[1]
    super
  end

  def parse_row(mapped_row, raw_row, _)
    mapped_row[:net_worth_amount] = raw_row[@amount_header]
    mapped_row[:net_worth_currency] = @currency

    case raw_row['Transaction type'].downcase
    when 'outbound transfer', 'sell'
      mapped_row[:amount] = -mapped_row[:amount].clean_d
      # override the net worth of 'sell' with the buys worth
      mapped_row[:net_worth_amount] = mapped_row[:net_worth_currency] = nil if raw_row['Transaction type'] == 'Sell'
    when 'inbound transfer', 'buy'
    else
      mapped_row.merge!(error: log_error("unknown abra txn type #{raw_row['Transaction type']}"))
    end
    mapped_row
  end
end
