class DefaultMapper < BaseMapper
  mappings [
    {
      id: 'sample',
      downcase_headers: true,
      determine_date_format: :not_american,
      required_headers: ['date', 'sent amount', 'sent currency', 'received amount', 'received currency'],
      optional_headers: ['fee amount', 'fee currency', 'net worth amount', 'net worth currency', 'label', 'description', 'txhash'],
      header_mappings: {
        date: 'date',
        from_amount: 'sent amount',
        from_currency: 'sent currency',
        to_amount: 'received amount',
        to_currency: 'received currency',
        fee_amount: 'fee amount',
        fee_currency: 'fee currency',
        net_worth_amount: 'net worth amount',
        net_worth_currency: 'net worth currency',
        fee_worth_amount: 'fee worth amount',
        fee_worth_currency: 'fee worth currency',
        label: 'label',
        description: 'description',
        txhash: 'txhash'
      },
    },
    {
      id: 'polonidex-trades',
      importer_tag: Tag::TRX_MARKET,
      determine_date_format: true,
      required_headers: ['Time', 'Pair', 'Side', 'Price', 'Amount', 'Volume', 'Progress', 'Status'],
      header_mappings: {
        date: 'Time',
        type: 'Side',
        pair: 'Pair',
        amount: 'Amount',
        total_price: 'Volume'
      },
      process: ->(mapped, raw, _) do
        mapped[:skip] = true if raw['Progress'] == '0.00%'
        mapped[:total_price].gsub!(',', '')
        mapped[:amount].gsub!(',', '')
      end
    },
    {
      id: 'coindeal-trades',
      tag: Tag::COINDEAL,
      required_headers: ['id','datetime','market','baseCurrency','quoteCurrency','category','type','price','amount','total','color','order'],
      header_mappings: {
        date: 'datetime',
        type: 'category',
        pair: 'market',
        amount: 'amount',
        total_price: 'total',
        external_id: 'id',
        txhash: 'order'
      }
    }
  ]
end