class KrakenMapper < BaseMapper
  tag Tag::KRAKEN
  mappings [
    {
      id: 'kraken-ledgers',
      required_headers: ['txid', 'refid', 'time', 'type', 'aclass', 'asset', 'amount', 'fee', 'balance']
    },
    {
      id: 'kraken-trades',
      required_headers: ["txid", "ordertxid", "pair", "time", "type", "ordertype", "price", "cost", "fee", "vol", "margin", "misc", "ledgers"],
      error: 'Please upload the kraken Ledgers file!'
    },
    {
      id: 'kraken-futures',
      required_headers: ['uid','dateTime','account','type','symbol','change','new balance','realized pnl','fee','realized funding','collateral'],
      header_mappings: {
        date: 'dateTime',
        currency: 'symbol',
        amount: 'change',
        external_id: 'uid',
      },
      row_defaults: {
        label: Txn::REALIZED_GAIN
      },
      process: -> (mapped, raw, _) do
        mapped[:skip] = true if raw['type'] != 'futures trade' || raw['symbol'].include?('_')
      end
    }
  ]

  # kraken ledgers have individual entries for the from part and to part of the trade so we have to merge them
  def fetch_rows(header, spreadsheet)
    rows = super
    return rows if mapping[:id] == 'kraken-futures'

    @date_format = TxnHelper.determine_date_format(rows.sample(100).map{ |row| row['time'] })

    trades = {}
    staking_txns = []
    new_rows = rows.map do |row|
      next if row['txid'].blank?
      if row['asset'].end_with?('.S')
        staking_txns << row
        next
      end

      mapped_row = {
        date: parse_date(row['time']),
        external_id: row['txid'],
        external_data: row,
      }
      amount = row['amount'].clean_d - row['fee'].clean_d

      case row['type']
      when 'deposit', 'withdrawal', 'adjustment'
        mapped_row.merge!(currency: row['asset'], amount: amount)
      when 'transfer'
        label = Txn::AIRDROP
        label = Txn::FORK if row['asset'] == 'BCH' || row['asset'] == 'BSV'
        label = nil if amount < 0
        mapped_row.merge!(currency: row['asset'], amount: amount, label: label)
      when 'staking'
        mapped_row.merge!(currency: row['asset'], amount: amount, label: Txn::STAKING)
      when 'margin', 'settled'
        next if amount.zero?
        mapped_row.merge!(currency: row['asset'], amount: amount, label: Txn::REALIZED_GAIN)
      when 'rollover'
        next if amount.zero?
        mapped_row.merge!(currency: row['asset'], amount: amount, label: Txn::MARGIN_INTEREST_FEE, txdest: 'Kraken Rollover Fees', group_name: 'rollover_fees')
      when 'trade'
        trades[row['refid']] ||= []
        trades[row['refid']] << row
        next
      else
        mapped_row[:error] = "#{row['type']} not supported"
      end
      mapped_row
    end.compact

    # remove transfers to/from staking accounts
    new_rows.reject! { |x| staking_txn?(x, staking_txns) }

    trades.each do |k, trade|
      if trade.count > 3 || (trade.count == 3 && trade.none?{ |tr| tr['asset'] == 'KFEE' })
        new_rows << { error: "multiple matches for #{trade[0]['refid']}"}
      elsif trade.count == 1
        from = trade.find{ |tr| tr['amount'].clean_d < 0 }
        to = trade.find{ |tr| tr['amount'].clean_d >= 0 }
        from ||= to
        amount = from['amount'].clean_d - from['fee'].clean_d
        new_rows << {
          date: parse_date(from['time']),
          txhash: from['txid'],
          external_id: from['refid'],
          from_amount: amount,
          from_currency: from['asset'],
        }
      else
        from = trade.find{ |tr| tr['amount'].clean_d < 0 }
        to = trade.find{ |tr| tr['amount'].clean_d > 0 }
        fee = trade.find{ |tr| tr['amount'].clean_d.zero? && tr['fee'].clean_d > 0 }

        from['amount'] = from['amount'].clean_d - from['fee'].clean_d if from
        to['amount'] = to['amount'].clean_d - to['fee'].clean_d if to
        fee_amount, fee_currency = fee['fee'], fee['asset'] if fee

        new_rows << {
          date: parse_date((from || to)['time']),
          txhash: (from || to)['txid'],
          external_id: (from || to)['refid'],
          from_amount: from&.dig('amount')&.clean_d&.abs,
          from_currency: from&.dig('asset'),
          to_amount: to&.dig('amount')&.clean_d&.abs,
          to_currency: to&.dig('asset'),
          fee_amount: fee_amount,
          fee_currency: fee_currency,
        } if from || to
      end
    end

    new_rows
  end

  def parse_row(mapped_row, raw_row, _)
    return mapped_row if mapping[:id] == 'kraken-futures'
    raw_row
  end

  private

  def staking_txn?(row, staked_txns)
    txn = row[:external_data]
    return false unless txn
    return true if txn['asset'].end_with?('.S')
    staked_txns.find do |staked|
      if (txn['asset'] + '.S') == staked['asset'] && (parse_date(txn['time']).to_i - parse_date(staked['time']).to_i).abs < 6.hour.to_i # some txns can be quite far apart
        txn_amount = txn['amount'].clean_d
        staked_amount = staked['amount'].clean_d
        # should be equal but opposite i.e. deposit and withdrawal
        return true if txn_amount.abs == staked_amount.abs && txn_amount != staked_amount
      end
    end
    false
  end

  def parse_date(date)
    TxnHelper.convert_date_with_fmt(date, @date_format)
  end
end
