class SnapshotFormatter
  PRECISION = 8

  attr_accessor :txns, :api_balances, :diffs_enabled, :wallets

  CurrencyValue = Struct.new(:symbol, :name, :blockchain, :token_address, :nft_token) do
    def self.build(attrs)
      params =
        case attrs
        when String
          { symbol: attrs }
        when Hash
          attrs.slice(:symbol, :blockchain).merge(token_address: attrs[:address])
        when Array
          attrs.first.merge(symbol: attrs.last) if attrs.first.is_a?(Hash)
        end

      return if params.blank?

      params[:token_address] = params[:token_address].strip.downcase if params[:token_address].present?
      params[:nft_token] = params[:nft_token].strip.downcase if params[:nft_token].present?
      params[:symbol] = params[:symbol]&.upcase&.strip
      params[:name] ||= params[:symbol]

      new(*params.values_at(:symbol, :name, :blockchain, :token_address, :nft_token))
    end

    def fiat?
      return false if blockchain

      symbol.in?(TxnHelper::FIATS)
    end

    def crypto?
      !fiat?
    end

    def humanize
      symbol
    end

    def ==(other)
      return false if other.nil?

      symbol == other.symbol && blockchain == other.blockchain && fiat? == other.fiat?
    end
  end

  class FakeTxn < Txn
    DEPRECATED_TYPES =
      %w[
        buy
        sell
        exchange
        transfer
        fiat_deposit
        fiat_withdrawal
        crypto_deposit
        crypto_withdrawal
      ].freeze

    def initialize(attrs)
      super

      self.to_currency = CurrencyValue.build(to_currency)
      self.from_currency = CurrencyValue.build(from_currency)
      self.fee_currency = CurrencyValue.build(fee_currency)

      self.net_worth_currency = CurrencyValue.build(net_worth_currency)
      self.net_worth_currency = nil unless net_worth_currency&.fiat?

      self.fee_worth_currency = CurrencyValue.build(fee_worth_currency)
      self.fee_worth_currency = nil unless fee_worth_currency&.fiat?

      self.type =
        if from_currency.present? && to_currency.present?
          if from_currency == to_currency
            TRANSFER
          elsif (from_currency.fiat? && to_currency.fiat?) || (!from_currency.fiat? && !to_currency.fiat?)
            'exchange'
          elsif from_currency.fiat?
            'buy'
          else
            'sell'
          end
        elsif from_currency
          from_currency.fiat? ? 'fiat_withdrawal' : 'crypto_withdrawal'
        else
          to_currency.fiat? ? 'fiat_deposit' : 'crypto_deposit'
        end

      if type == 'crypto_withdrawal' && from_currency == fee_currency
        self.fee_currency = nil
      end

      if type == 'crypto_deposit' && to_currency == fee_currency
        self.fee_currency = nil
      end

      if transfer? && self.fee_amount.zero? && (self.from_amount - self.to_amount).nonzero?
        self.fee_amount = self.from_amount - self.to_amount
        self.fee_currency = self.from_currency
        self.from_amount = self.from_amount - self.fee_amount
      end
    end

    def valid?
      return false if from_currency == to_currency && from_currency.crypto? && to_currency.crypto? && from_wallet == to_wallet

      true
    end

    def prettify
      from = "#{from_amount} #{from_currency.humanize}" if from_currency
      to = "#{to_amount} #{to_currency.humanize}" if to_currency
      result =
        if from && to
          "#{from} -> #{to}"
        elsif from
          "Withdraw #{from}"
        else
          "Deposit #{to}"
        end

      extra_info = []
      extra_info << "fee: #{fee_amount} #{fee_currency.humanize}" if fee_currency
      extra_info << "net worth: #{net_worth_amount} #{net_worth_currency.humanize}" if net_worth_currency&.fiat?
      extra_info << "fee worth: #{fee_worth_amount} #{fee_worth_currency.humanize}" if fee_worth_currency&.fiat?
      extra_info << "label: #{label}" if label
      extra_info << "desc: #{description.strip}" if description.present?
      extra_info << "txhash: #{txhash}" if txhash.present?
      extra_info << "txsrc: #{txsrc}" if txsrc.present?
      extra_info << "txdest: #{txdest}" if txdest.present?
      extra_info << "contract: #{contract_address}" if contract_address.present?
      extra_info << "method: #{method_name || method_hash}" if (method_name || method_hash).present?
      extra_info << "importer_tag: #{importer_tag}" if importer_tag.present?
      extra_info << 'margin trade!' if margin

      "#{date} | #{result}#{extra_info.any? ? " (#{extra_info.join(', ')})" : ''}"
    end

    def deposit?
      super || type.include?('_deposit') # legacy types
    end

    def withdrawal?
      super || type.include?('_withdrawal') # legacy types
    end

    def fee?
      fee_currency.present? && fee_amount > 0
    end

    def margin?
      margin
    end

    def from_entry
      return nil unless from_amount && from_currency

      {
        date:,
        ledger: from_currency.humanize,
        amount: -from_amount,
        synced:,
        txhash:,
        external_id:,
        importer_tag:,
        unique_hash:,
      }
    end

    def to_entry
      return nil unless to_amount && to_currency

      {
        date:,
        ledger: to_currency.humanize,
        amount: to_amount,
        synced:,
        txhash:,
        external_id:,
        importer_tag:,
        unique_hash:,
      }
    end

    def fee_entry
      return nil unless fee_amount > 0 && fee_currency

      {
        date:,
        fee: true,
        ledger: fee_currency.humanize,
        amount: -fee_amount,
        synced:,
        txhash:,
        external_id:,
        importer_tag:,
        unique_hash:,
      }
    end

    private

    def pick_first_value(procs)
      procs.detect do |proc|
        value = instance_exec(&proc)
        return value if value.present?
      end
    end
  end

  def initialize(txns:, api_balances: {}, diffs_enabled: false)
    self.wallets = { nil => [] }
    self.txns =
      txns
        .map { |txn| FakeTxn.new(txn.deep_symbolize_keys) }
        .select(&:valid?)
        .then(&method(:group_transactions))
        .map { |txn| add_to_wallets(txn) }
    self.api_balances = api_balances
    self.diffs_enabled = diffs_enabled
  end

  def call
    wallets.map { |wallet, wallet_txns| generate_snapshot(wallet, wallet_txns) }
  end

  def entries
    @entries ||= begin
      from_entries = txns.select { |txn| txn.from_currency }.map(&:from_entry)
      to_entries = txns.select { |txn| txn.to_currency }.map(&:to_entry)
      fee_entries = txns.select { |txn| txn.fee_currency }.map(&:fee_entry)

      from_entries + to_entries + fee_entries
    end
  end

  private

  def generate_snapshot(wallet, wallet_txns)
    types =
      FakeTxn::DEPRECATED_TYPES.sort.filter_map do |type| # use legacy types
        txns_sneak_peek(wallet_txns.select { _1.type == type }, type)
      end

    withdrawals =
      Txn::WITHDRAWAL_LABELS.sort.filter_map do |label|
        txns_sneak_peek(wallet_txns.select { _1.from_currency && _1.label == label }, label)
      end

    deposits =
      Txn::DEPOSIT_LABELS.sort.filter_map do |label|
        txns_sneak_peek(wallet_txns.select { _1.to_currency && _1.label == label }, label)
      end

    balances = calculate_balances(wallet, wallet_txns)

    fmt = {
      name: wallet.to_h.fetch(:name, 'Test Wallet'),
      txn_count: wallet_txns.count,
      entry_count: wallet_entries(wallet, wallet_txns).count,
      balances:,
      balance_diff: balance_diff(balances),
      txns: types,
      labeled_txns: [withdrawals + deposits],
      txn_with_fee: txns_sneak_peek(wallet_txns.select(&:fee_currency), 'with fee'),
      txn_with_net_worth: txns_sneak_peek(wallet_txns.select(&:net_worth_currency), 'with metadata'),
      txn_with_desc: txns_sneak_peek(wallet_txns.select(&:description), 'with desc'),
    }

    margin_trades = txns_sneak_peek(wallet_txns.select(&:margin), 'margin trades')
    fmt[:margin_trades] = margin_trades if margin_trades.present?

    fmt
  end

  def wallet_entries(wallet, wallet_txns)
    from_entries = wallet_txns.select { |txn| txn.from_currency && txn.from_wallet == wallet }.map(&:from_entry)
    to_entries = wallet_txns.select { |txn| txn.to_currency && txn.to_wallet == wallet }.map(&:to_entry)
    fee_entries = wallet_txns.select { |txn| txn.fee_currency && txn.from_wallet == wallet }.map(&:fee_entry)

    from_entries + to_entries + fee_entries
  end

  def txns_sneak_peek(filtered_txns, type)
    q = filtered_txns.sort_by do |txn|
      [
        txn.date,
        txn.txhash.to_s,
        txn.from_amount.to_d,
        txn.to_amount.to_d,
        txn.from_currency&.humanize.to_s,
        txn.to_currency&.humanize.to_s,
        txn.net_worth_amount.to_d,
        txn.description.to_s,
      ]
    end
    total = filtered_txns.count
    return unless total > 0

    {
      type:,
      count: total,
      first: q.first.prettify,
      last: (total > 1 && q.last.prettify),
    }
  end

  def group_transactions(txns)
    groupable = txns.select { |txn| txn.group_name && (txn.deposit? || txn.withdrawal?) }
    groups = groupable.group_by do |txn|
      if txn.from_currency
        [txn.group_name, txn.type, txn.from_currency, txn.from_wallet, txn.date.strftime('%Y-%m-%d')]
      else
        [txn.group_name, txn.type, txn.to_currency, txn.to_wallet, txn.date.strftime('%Y-%m-%d')]
      end
    end
    groups.each do |_, group|
      earliest_date = group.map(&:date).min
      oldest_date = group.map(&:date).max

      grouped_txn = group.first.dup
      grouped_txn.date = grouped_txn.to_currency ? earliest_date : oldest_date
      group[1..].each do |txn|
        grouped_txn.from_amount += txn.from_amount
        grouped_txn.to_amount += txn.to_amount
      end

      txns.push(grouped_txn)
    end

    txns - groupable
  end

  def calculate_amounts(wallet, wallet_txns)
    wallet_txns.each_with_object(Hash.new(0)) do |txn, balance|
      balance[txn.from_currency.humanize] -= txn.from_amount if txn.from_currency && txn.from_wallet == wallet
      balance[txn.to_currency.humanize] += txn.to_amount if txn.to_currency && txn.to_wallet == wallet
      balance[txn.fee_currency.humanize] -= txn.fee_amount if txn.fee_currency && txn.from_wallet == wallet
      balance
    end.transform_values { _1.clamp(-10**14, 10**14).to_d }
  end

  def calculate_balances(wallet, wallet_txns)
    calculate_amounts(wallet, wallet_txns)
      .transform_values { _1.round(PRECISION).to_s }
      .reject { |currency, balance| currency.blank? || balance.to_d.zero? }
      .sort
      .to_h
  end

  def balance_diff(balances)
    return unless diffs_enabled

    adjusted_balances = api_balances.inject(Hash.new(0)) do |memo, (currency, balance)|
      if balance.is_a?(Hash)
        currency = CurrencyValue.build(balance[:currency]).humanize
        balance = balance[:balance]
      end

      memo.tap { memo[currency.to_s.upcase.strip] += balance.to_d }
    end

    diff = (adjusted_balances.keys | balances.keys).inject({}) do |memo, symbol|
      memo.tap { memo[symbol] = balances[symbol].to_d.round(PRECISION) - adjusted_balances[symbol].to_d.round(PRECISION) }
    end

    diff = diff.delete_if { |k, v| k.blank? || v.zero? }.transform_values!(&:to_s).sort.to_h

    return if diff.blank?

    diff
  end

  def add_to_wallets(txn)
    wallets[txn.from_wallet] ||= []
    wallets[txn.to_wallet] ||= []
    wallets[txn.from_wallet] << txn
    wallets[txn.to_wallet] << txn if txn.to_wallet != txn.from_wallet && txn.to_currency

    txn
  end
end
