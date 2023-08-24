class BinanceDexImporter < BaseImporter
  include TimeboundTxnsSyncHelper

  PAGE_LIMIT = 1000
  EARLIEST_SYNC_DATE = '2019-04-20 00:00 UTC'.to_datetime

  attr_accessor :api
  attr_accessor :address

  def initialize(adapter, wallet:, api_options:, api_syncdata:)
    super
    self.api = BinanceDexApi.new(address: options[:address].strip)
    self.address = options[:address].strip.downcase
  end

  def self.required_options
    [:address]
  end

  def self.notes
    [
      "good:Trades & fees",
      "good:Deposits",
      "good:Withdrawals",
      "bad:Multisend transactions"
    ]
  end

  protected

  def import
    sync_transactions
    sync_trades
  end

  def sync_balances
    api.balances['balances'].each_with_object(Hash.new(0)) do |account, memo|
      balance = account['free'].to_d + account['locked'].to_d + account['frozen'].to_d
      memo.tap { memo[fetch_asset_symbol(account['symbol'])] = balance }
    end
  end

  private

  # so we can stub it in specs
  def max_sync_time
    @now ||= Time.now
  end

  def sync_transactions
    fetcher = ->(start_time, end_time, offset, limit) do
      txns = api.transactions(startTime: start_time.to_i * 1000, endTime: end_time.to_i * 1000, offset: offset, limit: limit)
      [txns['total'], txns['tx']]
    end

    # TYPES: NEW_ORDER,ISSUE_TOKEN,BURN_TOKEN,LIST_TOKEN,CANCEL_ORDER,FREEZE_TOKEN,UN_FREEZE_TOKEN,TRANSFER,PROPOSAL,VOTE,MINT,DEPOSIT,CREATE_VALIDATOR,REMOVE_VALIDATOR,TIME_LOCK,TIME_UNLOCK,TIME_RELOCK,SET_ACCOUNT_FLAG,HTL_TRANSFER,CLAIM_HTL,DEPOSIT_HTL,REFUND_HTL
    with_timebound_desc(:txns, EARLIEST_SYNC_DATE, max_sync_time, 89.days, fetcher, PAGE_LIMIT, historical_txns_limit) do |txn|
      next if txn['txType'].in?(%w[NEW_ORDER CANCEL_ORDER FREEZE_TOKEN UN_FREEZE_TOKEN TIME_LOCK TIME_UNLOCK TIME_RELOCK])

      currency = fetch_asset_symbol(txn['txAsset'])
      amount = txn['value'].to_d
      amount = -amount if txn['fromAddr'].downcase == address.downcase

      if amount < 0
        if currency == 'BNB'
          amount -= txn['txFee'].to_d
        else
          sync_amount(
            amount: -txn['txFee'].to_d,
            currency: 'BNB',
            date: txn['timeStamp'],
            txhash: txn['txHash'] + '_fee',
            label: Txn::COST,
            description: 'Withdrawal Fee',
            external_data: txn,
            )
        end
      end

      sync_amount(
        amount: amount,
        currency: currency,
        date: txn['timeStamp'], # 2020-03-08T11:10:43.495Z
        txhash: txn['txHash'],
        txsrc: txn['fromAddr'],
        txdest: txn['toAddr'],
        external_data: txn,
        )
    end
  end

  def sync_trades
    fetcher = ->(start_time, end_time, offset, limit) do
      txns = api.trades(start: start_time.to_i * 1000, end: end_time.to_i * 1000, offset: offset, limit: limit, total: 1)
      [txns['total'], txns['trade']]
    end
    with_timebound_desc(:trades, EARLIEST_SYNC_DATE, max_sync_time, 89.days, fetcher, PAGE_LIMIT, historical_txns_limit) do |txn|
      is_buy = txn['buyerId'].downcase == address.downcase

      # #Cxl:1;BNB:0.00085000;
      # BNB:0.00034574;
      fee = txn[is_buy ? 'buySingleFee' : 'sellSingleFee']
      all_fees = fee ? fee.split(';').reject { |x| x.blank? || x.match(/#/) } : []
      fee_currency, fee_amount = (all_fees.find { |x| x.include?('BNB:') } || all_fees.first).split(':') if all_fees.any?

      sync_trade(
        date: txn['time'], # 1583670343417
        base_amount: txn['quantity'],
        base_symbol: fetch_asset_symbol(txn['baseAsset']),
        quote_amount: (txn['price'].to_d * txn['quantity'].to_d),
        quote_symbol: fetch_asset_symbol(txn['quoteAsset']),
        fee_amount: fee_amount,
        fee_currency: fetch_asset_symbol(fee_currency),
        is_buy: is_buy,
        order_identifier: txn[is_buy ? "buyerOrderId" : "sellerOrderId"],
        trade_identifier: txn["tradeId"],
        external_data: txn,
        )
    end
  end

  def fetch_asset_symbol(symbol)
    return unless symbol
    symbol.split('-').first # XRPBULL-E7C, AERGO-46B
  end
end
