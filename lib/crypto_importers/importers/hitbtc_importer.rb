# NOTE: Hitbtc can have balance diffs due to missing trades. debugged this with
# a user Saltydog72 on intercom (1/2/2020 at 2am ist). his files and api are all
# missing trades for VERI, even the web dashboard doesnt show these trades but
# he definitely made them around 2018-04-18 5:28:04 UTC. Maybe they delisted
# it and deleted all trade logs? The deposits/withdrawals for VERI were still
# visible. This resulted in him having a +8.56 ETH diff on his wallet
class HitbtcImporter < BaseImporter
  attr_accessor :api

  def initialize(adapter, wallet:, api_options:, api_syncdata:)
    super
    self.api = HitbtcApi.new(options[:api_key], options[:api_secret])
  end

  def self.required_options
    [:api_key, :api_secret]
  end

  protected

  def import
    sync_trades
    sync_transactions
  end

  def sync_balances
    memo = api.account_balance.inject(Hash.new(0)) do |memo, account|
      balance = account['available'].to_d + account['reserved'].to_d
      memo.tap { memo[account['currency']] += balance unless balance.zero? }
    end

    api.trading_balance.inject(memo) do |memo, account|
      balance = account['available'].to_d + account['reserved'].to_d
      memo.tap { memo[account['currency']] += balance unless balance.zero? }
    end
  end

  private

  def sync_transactions
    with_pagination(:transactions) do |offset|
      offset ||= 0
      txns = api.transactions(offset: offset, sort: 'ASC', limit: 1000).each do |txn|
        next if txn['status'] == 'failed'
        case txn['type']
        when 'payin', 'deposit'
          sync_receive(
            amount: txn['amount'].to_d,
            currency: txn['currency'],
            date: txn['createdAt'],
            txhash: txn['hash'],
            txdest: txn['address'],
            label: txn['type'] == 'deposit' ? Txn::AIRDROP : nil,
            external_id: txn['id'],
            external_data: txn,
          )
        when 'payout', 'withdraw'
          sync_send(
            amount: txn['amount'].to_d + txn['fee'].to_d,
            currency: txn['currency'],
            date: txn['createdAt'],
            txhash: txn['hash'],
            txdest: txn['address'],
            external_id: txn['id'],
            external_data: txn,
          )
        when 'bankToExchange', 'exchangeToBank'
          # ignore these inter-account transfers
        else
          fail "unknown txn type #{txn['type']}"
        end
      end

      [offset + txns.count, txns.count == 1000]
    end
  end

  def sync_trades
    with_pagination(:trades) do |offset|
      offset ||= 0
      txns = api.trades(offset: offset, sort: 'ASC', limit: 1000).each do |txn|
        symbol_info = symbols.find { |sym| sym['id'] == txn['symbol'] }
        is_buy = txn['side'] == 'buy'

        # hitbtc can give fee rebates which results in negative fees, we simply
        # add or subtract those to/from the quote price
        txn['fee'] = txn['fee'].to_d
        txn['price'] = txn['price'].to_d
        amount = txn['price'].to_d * txn['quantity'].to_d
        if txn['fee'] < 0
          fail 'fee is not in quote currency' if symbol_info['quoteCurrency'] != symbol_info['feeCurrency']
          amount = is_buy ? (amount - txn['fee'].abs) : (amount + txn['fee'].abs)
        end

        sync_trade(
          base_amount: txn['quantity'],
          base_symbol: symbol_info['baseCurrency'],
          quote_amount: amount,
          quote_symbol: symbol_info['quoteCurrency'],
          fee_amount: txn['fee'] > 0 ? txn['fee'].to_d.abs : nil,
          fee_currency: txn['fee'] > 0 ? symbol_info['feeCurrency'] : nil,
          is_buy: txn['side'] == 'buy',
          date: txn['timestamp'],
          trade_identifier: txn['id'],
          order_identifier: txn['id'],
          external_data: txn,
        )
      end

      [offset + txns.count, txns.count == 1000]
    end
  end

  def symbols
    @symbols ||= api.symbols
  end
end
