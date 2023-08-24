class BaseAdapter
  attr_reader :initialized_at, :pending_txns, :deposit_label, :importer_tag, :request_id
  attr_accessor :last_message, :hard_start_date, :soft_start_date, :disallow_external_id

  def initialize(options)
    @hard_start_date = options[:start_date]&.to_datetime
    @deposit_label = options[:deposit_label]
    @importer_tag = options[:importer_tag]
    @initialized_at = Time.now
    @pending_txns = []
    @request_id = options[:request_id]
  end

  def start_date
    # dont use soft_start_date here as anyone relying on it should request it explicitly
    hard_start_date
  end

  def sync_amount(params)
    amount = decimalize(params[:amount], small_decimals: params[:small_decimals])

    if amount > 0
      sync_receive(params)
    elsif amount < 0
      sync_send(params)
    end
  end

  def sync_receive(params)
    return if decimalize(params[:amount], small_decimals: params[:small_decimals]).zero?

    if params[:currency].present?
      params[:to_amount] = params.delete(:amount)
      params[:to_currency] = params.delete(:currency)
    end

    params[:label] ||= @deposit_label

    sync_txn(params)
  end

  def sync_send(params)
    return if decimalize(params[:amount], small_decimals: params[:small_decimals]).zero?

    if params[:currency].present?
      params[:from_amount] = params.delete(:amount)
      params[:from_currency] = params.delete(:currency)
    end

    sync_txn(params)
  end

  def sync_trade(params)
    raise ArgumentError unless params.key?(:is_buy)

    quote = {
      amount: TxnHelper.normalize_amount(params.delete(:quote_amount), small_decimals: params[:small_decimals], no_zero: true),
      currency: params.delete(:quote_symbol)
    }
    base = {
      amount: TxnHelper.normalize_amount(params.delete(:base_amount), small_decimals: params[:small_decimals], no_zero: true),
      currency: params.delete(:base_symbol)
    }

    from, to = base, quote
    from, to = quote, base if params.delete(:is_buy)
    txhash = params.delete(:order_identifier) || params[:txhash]
    external_id = params.delete(:trade_identifier) || params[:external_id]

    sync_txn(params.merge(
      from_amount: from[:amount],
      from_currency: from[:currency],
      to_amount: to[:amount],
      to_currency: to[:currency],
      txhash: txhash,
      external_id: external_id,
    ))
  end

  def sync_txn(attrs)
    return if skip_txn?(TxnHelper.normalize_date(attrs[:date]), attrs.delete(:bypass_soft_start_date))

    attrs[:importer_tag] ||= @importer_tag
    allow_external_id = attrs.delete(:allow_external_id) || !disallow_external_id || true
    raise TxnError, "external_id not allowed" if !allow_external_id && attrs.key?(:external_id)

    ignore_duplicate_external_id = attrs.delete(:ignore_duplicate_external_id)
    check_duplicates = attrs.delete(:unique).presence
    txn = Txn.new(
      attrs,
      small_decimals: attrs.delete(:small_decimals),
      default_timezone: attrs.delete(:default_timezone),
      uniqueness_seed: (check_duplicates.is_a?(String) ? check_duplicates : nil),
    )

    # this ensures that any currency hashes are built by calling build_currency which allows us
    # to find all occurances easily and update the format when needed
    %i[from_currency to_currency fee_currency net_worth_currency fee_worth_currency].each do |name|
      raise TxnError, "#{name} is not a valid currency - ensure it was built with build_currency!" unless valid_currency?(attrs[name])
    end

    raise TxnError, txn unless txn.valid?

    if txn.external_id
      external_id_hash = [txn.external_id, txn.from_currency || txn.to_currency]
      # its possible for users to create 2 separate orders which have the same id when self-trading
      # (one sell and other buy). in such cases the order id is different but trade ids are the same
      # this was detected on both binance and fmfw
      external_id_hash << (txn.trade? ? txn.txhash : nil)

      if duplicate?(external_id_hash.map(&:to_s).join('_'), txn.type)
        # external_id duplicates should not exist and indicate the id is shared between
        # multiple txns in which case it shouldnt be used as an external id. we throw
        # an error to ensure this is looked into by devs, if its expected behaviour
        # then add the ignore flag
        if ENV['RACK_ENV'] == 'test' && !ignore_duplicate_external_id
          same_txn = pending_txns.find { _1.external_id == txn.external_id && _1.external_data == txn.external_data }
          raise TxnError, "duplicate external_id detected - #{txn.external_id}" unless same_txn
        end

        return
      end
    end

    return if check_duplicates && duplicate?(txn.unique_hash, 'duplicates')

    add_txn(txn)
    txn
  end

  def commit!
    raise "not implemented"
  end

  def find_pending_txn(q)
    pending_txns.reverse_each.find { |txn| matched?(txn, q) }
  end

  protected

  def valid_currency?(curr)
    case curr
    when Symbol, String, NilClass, Integer
      true
    when Hash
      # this is set by build_currency and should be removed here, it is to force
      # devs to call build_currency instead of creating hashes manually
      curr.delete(:valid) || false
    when Array
      curr.all? { |c| valid_currency?(c) }
    else
      false
    end
  end

  def skip_txn?(date, bypass_soft_start_date)
    return true if hard_start_date && hard_start_date > date
    return true if soft_start_date && soft_start_date > date && !bypass_soft_start_date
    false
  end

  def decimalize(amount, decimals = 0)
    TxnHelper.normalize_amount(amount, **(decimals.is_a?(Hash) ? decimals : { decimals: decimals }))
  end

  def add_txn(txn)
    pending_txns << txn
  end

  def duplicate?(hash, group = nil)
    @uniq_hashes ||= {}
    @uniq_hashes[group] ||= Set.new
    return true if @uniq_hashes[group].include? hash
    @uniq_hashes[group] << hash
    false
  end

  def matched?(record, attrs)
    attrs.all? do |k, v|
      val = record.send k
      if v.is_a?(Array)
        v.include?(val)
      elsif v.is_a?(Range)
        val.in?(v)
      else
        val == v
      end
    end
  end

  def publish(routing_key, message, opts = {})
    # publish
  end
end
