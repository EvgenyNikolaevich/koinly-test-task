class CoinmetroMapper < BaseMapper
  tag Tag::COIN_METRO
  mappings [
    {
      id: 'coinmetro-transactions',
      required_headers: %w[Currency Date Description Amount Fees Price Pair Other\ Currency Other\ Amount],
      optional_headers: %w[IBAN Transaction\ Hash Additional\ Info],
      header_mappings: {
        date: 'Date',
        amount: 'Amount',
        currency: 'Currency',
        txhash: 'Transaction hash',
        description: 'Description',
        fee_currency: 'Currency',
        fee_amount: 'Fees'
      },
      group: {
        by_hash: ->(_mapped, raw_row) { raw_row['Description'] },
      },
      process: -> (mapped_row, raw_row, _) do
        mapped_row[:skip] = true if raw_row['Description'].match?(/TGE/)
      end
    },
  ]
end
