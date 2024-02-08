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
        to_amount: 'Other Amount',
        to_currency: 'Other Currency',
        txhash: 'Transaction hash',
        description: 'Description',
        fee_currency: 'Currency',
        fee_amount: 'Fees'
      },
      group: {
        by_hash: ->(_mapped, row) { row['Description'] },
        eligible: ->(_mapped, row) { row['Description'].match?(/order/i) },
      }
    },
  ]
end
