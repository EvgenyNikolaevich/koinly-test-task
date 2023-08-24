class GeminiImporter < BaseImporter
  attr_accessor :api

  def initialize(adapter, wallet:, api_options:, api_syncdata:)
    super
    self.api = GeminiApi.new(options[:api_key], options[:api_secret])
  end

  def self.required_options
    [:api_key, :api_secret]
  end

  def self.markets
    @markets ||= GeminiApi.new.symbols
  end

  protected

  def import
    sync_transfers
    self.class.markets.uniq.each { |market| sync_trades(*split_market(market)) }
  end

  def sync_balances
    api.balances.inject(Hash.new(0)) do |memo, account|
      balance = account['amount'].to_d
      memo.tap { memo[account['currency']] += balance unless balance.zero? }
    end
  end

  private

  def sync_transfers
    with_pagination(:transfers) do |last_ts|
      transfers = api.transfers(limit_transfers: 50, timestamp: last_ts || 0)
      transfers.each do |txn|
        raise "unknown txn status #{txn['status']}" unless %w[Advanced Complete].include?(txn['status'])
        raise "unknown txn type #{txn['type']}" unless %w[Deposit Withdrawal].include?(txn['type'])

        params = {
          date: txn['timestampms'],
          amount: txn['amount'],
          currency: txn['currency'],
          external_id: txn['eid'],
          txhash: txn['txHash'],
          txdest: txn['destination'],
          description: txn['method'] || txn['purpose'],
          external_data: txn,
        }

        send(txn['type'] == 'Deposit' ? :sync_receive : :sync_send, **params)
      end

      last_ts = transfers.first.try(:dig, 'timestampms').to_i / 1000 if transfers.any?
      [last_ts, transfers.count == 50]
    end
  end

  def sync_trades(base, quote)
    with_pagination(:trades, base, quote) do |last_ts|
      trades = api.my_trades(symbol: (base.downcase + quote.downcase), limit_trades: 500, timestamp: last_ts || 0)
      trades.each do |trade|
        sync_trade(
          base_amount: trade['amount'],
          base_symbol: base,
          quote_amount: trade['price'].to_d * trade['amount'].to_d,
          quote_symbol: quote,
          fee_amount: trade['fee_amount'],
          fee_currency: trade['fee_currency'],
          is_buy: trade['type'] == 'Buy',
          date: trade['timestampms'],
          trade_identifier: trade['tid'],
          order_identifier: trade['order_id'],
          external_data: trade,
        )
      end

      last_ts = trades.first.try(:dig, 'timestampms').to_i / 1000 if trades.any?
      [last_ts, trades.count == 500]
    end
  end

  def split_market(market)
    fail "unknown market symbol #{market}" if market.length != 6
    [market.first(3).upcase, market.last(3).upcase]
  end
end
