class BaseImporter
  include ActiveModel::Validations
  include SyncMetadataAndPagination
  attr_reader :wallet, :started_at, :options, :adapter, :api_syncdata

  delegate :sync_amount, :sync_receive, :sync_send, :sync_withdrawal, :sync_trade, :sync_txn, to: :adapter

  metadata :balances
  metadata :initial_sync_done
  metadata :known_markets

  validate :ensure_required_options_present

  def initialize(adapter, wallet:, api_options:, api_syncdata:)
    @adapter = adapter
    @wallet = wallet.symbolize_keys
    @options = api_options.symbolize_keys
    @api_syncdata = api_syncdata || {}
    @started_at = Time.now
  end

  def self.required_options
    []
  end

  # these are optional options that an api may require, you can set the type of the field ex.
  # [start_from: :datetime, import_trades: :boolean]
  # supported types: boolean, string
  def self.other_options
    []
  end

  # these are hardcoded on the frontend
  def self.basic_options
    [:deposit_label, :withdrawal_label, :start_date, :ignore_reported_balances]
  end

  # this is displayed to users. prefix with "good", "bad" and "limit" so frontend
  # can display it correctly. You can also use html.
  def self.notes
    []
  end

  # this acts as both getter and setter. tag must be unique for every importer
  def self.tag(tag = nil)
    @tag ||= tag || name.underscore.sub('_importer', '')
  end

  def self.symbol_alias_tag
    tag
  end

  # optional: returns oauth url if wallet supports it
  def self.oauth_url
  end

  def self.process(wallet, options)
    importer = new(wallet, options)
    if importer.valid?
      importer.process
    else
      raise SyncAuthError, importer.errors.full_messages.join(', ')
    end
  end

  def import_and_commit!
    import_txns_and_balances

    adapter.commit!(
      api_syncdata,
      @synced_balances,
      @error
    )
  end

  def import_txns_and_balances
    import
    @synced_balances = (sync_balances || {}).delete_if{ |_, v| v.nil? }
    self.initial_sync_done = true
  rescue SyncError => e
    @error = { auth_failed: e.is_a?(SyncAuthError), message: e.message.first(300), type: e.class.name }
  rescue StandardError => e
    byebug
    @error = {
      auth_failed: false,
      message: 'Something went wrong while syncing, try again in a few minutes or contact support.',
      internal_message: e.message.first(300),
      type: e.class.name
    }
  end

  protected

  def import
    fail 'not implemented'
  end

  # should return hash of balances, the key may also be a currency object
  #   { "BTC" => 2.55, "ETH" => 35 }
  def sync_balances
    fail 'not implemented'
  end

  # this is the max amount of txns we want to import (used by coins)
  def historical_txns_limit
    10_000
  end

  # this is the max pages that the with_pagination method will loop
  def max_pages_per_sync
    50
  end

  protected

  def ensure_required_options_present
    missing = self.class.required_options - options.keys
    errors.add(:base, "missing required fields: #{missing.join(', ')}") if missing.any?
  end

  def skip_txn?(date)
    options[:start_date].present? && (@start_date ||= Time.parse(options[:start_date])) > date
  end

  def skip_trade?(date)
    options[:trade_start_date].present? && (@trade_start_date ||= Time.parse(options[:trade_start_date])) > date
  end

  def wallet_created_after?(date)
    wallet[:created_at] > date.to_datetime
  end

  # use this when converting amounts to decimals, this avoids memory leak if decimals
  # are exceptionally high, an eth token had 100000000 which caused pg to go oom
  #   decimalize(1000_0000, 8) = 1
  def decimalize(amount, decimals)
    # note: dont use Helper.normalize since it returns abs()
    (amount.to_d / 10**decimals.to_i.clamp(0, 1000)).round(10)
  end

  def initial_sync?
    !initial_sync_done?
  end

  # helper method for saving known markets, useful for exchanges that require looping
  # over all markets to find trades. save the known ones in each sync and check trades
  # on subsequent syncs
  def add_known_market(market)
    return if market.nil? || known_markets&.include?(market)
    self.known_markets ||= []
    known_markets.append(market)
  end

  # error can be an exception or a string
  # this method must return the logged error message
  def log_error(error, data = {})
    @logged_errors ||= []
    message = error.try(:message) || error
    unless @logged_errors.include?(message)
      if error.is_a?(Exception)
        Rollbar.error(error, data.merge(current_wallet: current_wallet.id))
      else
        Rollbar.warning(error, data.merge(current_wallet: current_wallet.id))
      end
      @logged_errors << message
    end
    message
  end

  def fail(message, data = nil)
    Rollbar.debug(message, data) if data
    raise SyncError, message
  end

  def fail_perm(message, data = nil)
    Rollbar.debug(message, data) if data
    raise SyncAuthError, message
  end
end
