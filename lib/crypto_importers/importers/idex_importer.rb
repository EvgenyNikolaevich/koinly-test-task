class IdexImporter < BaseImporter
  attr_accessor :api, :address

  # some coins contain the address in the currency field and decimals are also wrong
  MALFORMED_COINS = {
    '0x5b0751713b2527d7f002c0c4e2a37e1219610a6b' => {
      symbol: 'HORSE',
      decimals: 18
    },
    '0x53148bb4551707edf51a1e8d7a93698d18931225' => {
      symbol: 'PCL',
      decimals: 8
    }
  }

  def initialize(adapter, wallet:, api_options:, api_syncdata:)
    super
    self.address = options[:address]
    self.api = IdexApi.new(address)
  end

  def self.required_options
    [:address]
  end

  protected

  def import
    sync_transactions
    sync_trades
  end

  def sync_balances
    api.balances.inject(Hash.new(0)) do |memo, (symbol, account)|
      balance = account['available'].to_d + account['onOrders'].to_d
      info = MALFORMED_COINS[symbol.downcase]
      if info
        balance = fetch_amount(balance, symbol)
        symbol = info[:symbol]
      end
      memo.tap { memo[symbol] += balance unless balance.zero? }
    end
  end

  private

  def sync_transactions
    with_pagination(:deposits_withdrawals) do |last_ts|
      last_ts ||= 0
      transactions = api.deposits_withdrawals(start: last_ts)
      transactions['deposits'].each do |txn|
        sync_receive(
          amount: fetch_amount(txn['amount'], txn['currency']),
          currency: fetch_currency(txn['currency']),
          date: Time.at(txn['timestamp']),
          txhash: txn['transactionHash'],
          external_id: txn['depositNumber'],
          external_data: txn
        )
      end
      transactions['withdrawals'].each do |txn|
        sync_send(
          amount: fetch_amount(txn['amount'], txn['currency']),
          currency: fetch_currency(txn['currency']),
          date: Time.at(txn['timestamp']),
          txhash: txn['transactionHash'],
          external_id: txn['withdrawalNumber'],
          external_data: txn
        )
      end

      last_deposit_ts = transactions['deposits'].last.try(:dig, 'timestamp')
      last_withdrawal_ts = transactions['withdrawals'].last.try(:dig, 'timestamp')
      last_ts = [last_deposit_ts, last_withdrawal_ts].compact.sort.last
      [last_ts, false]
    end
  end

  def sync_trades
    with_pagination(:trades) do |last_ts|
      last_ts ||= 0
      market_trades = api.trade_history(sort: 'asc', count: 100, start: last_ts)
      market_trades.each do |market, trades|
        quote, base = market.split '_'
        trades.each do |txn|
          is_buy = txn['type'] == 'buy'
          fee = is_buy ? txn['buyerFee'] : txn['sellerFee']
          fee_curr = is_buy ? base : quote
          if txn['taker'].downcase == address.downcase
            fee = fee.to_d + txn['gasFee'].to_d
          end

          sync_trade(
            base_amount: txn['amount'],
            base_symbol: fetch_currency(base),
            quote_amount: txn['total'],
            quote_symbol: fetch_currency(quote),
            fee_amount: fee,
            fee_currency: fetch_currency(fee_curr),
            net_worth_amount: txn['usdValue'],
            net_worth_currency: 'USD',
            is_buy: is_buy,
            date: Time.at(txn['timestamp']),
            trade_identifier: txn['tid'],
            order_identifier: txn['orderHash'],
            external_data: txn.merge(market: market),
          )
        end
      end

      last_ts = market_trades.values.map { |arr| arr[-1]['timestamp'] }.sort.last

      [last_ts, market_trades.values.sum(&:count) == 100]
    end
  end

  def fetch_amount(amount, currency)
    key = currency.downcase
    if MALFORMED_COINS[key]
      amount.to_d / "1#{'0' * MALFORMED_COINS[key][:decimals]}".to_d
    else
      amount
    end
  end

  def fetch_currency(currency)
    key = currency.downcase
    if MALFORMED_COINS[key]
      MALFORMED_COINS[key][:symbol]
    else
      currency
    end
  end
end
