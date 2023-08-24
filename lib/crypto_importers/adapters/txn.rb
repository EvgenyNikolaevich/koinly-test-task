class Txn
  include ActiveModel::Model
  include ActiveModel::Validations
  include ActiveModel::Validations::Callbacks
  include ActiveModel::Serialization

  TYPES = [
    TRADE = 'trade',
    TRANSFER = 'transfer',
    DEPOSIT = 'deposit',
    WITHDRAWAL = 'withdrawal',
  ].freeze

  LABELS = [
    REALIZED_GAIN = 'realized_gain',
    AIRDROP = 'airdrop',
    FORK = 'fork',
    MINING = 'mining',
    REWARD = 'staking',
    LOAN_INTEREST = 'loan_interest',
    OTHER_INCOME = 'other_income',
    GIFT = 'gift',
    LOST = 'lost',
    DONATION = 'donation',
    COST = 'cost',
    INTEREST_PAYMENT = 'margin_interest_fee',
    MARGIN_TRADE_FEE = 'margin_trade_fee',
    MARGIN_FEE_REFUND = 'margin_fee_refund',
    FROM_POOL = 'from_pool',
    TO_POOL = 'to_pool',
    LIQUIDITY_IN = 'liquidity_in',
    LIQUIDITY_OUT = 'liquidity_out',
  ].freeze

  INCOME_LABELS = [AIRDROP, FORK, MINING, REWARD, LOAN_INTEREST, OTHER_INCOME].freeze
  EXPENSE_LABELS = [COST, MARGIN_TRADE_FEE, INTEREST_PAYMENT].freeze
  SPECIAL_LABELS = [GIFT, LOST, DONATION].freeze

  DEPOSIT_LABELS = [REALIZED_GAIN, MARGIN_FEE_REFUND] + INCOME_LABELS
  WITHDRAWAL_LABELS = [REALIZED_GAIN] + EXPENSE_LABELS + SPECIAL_LABELS
  TRADE_LABELS = [LIQUIDITY_IN, LIQUIDITY_OUT]
  TRANSFER_LABELS = [FROM_POOL, TO_POOL]

  ALL_ATTRIBUTES = [
    :date, :description,
    :label, :type,
    :from_amount, :from_currency,
    :to_amount, :to_currency,
    :from_wallet, :to_wallet,
    :fee_amount, :fee_currency,
    :net_worth_amount, :net_worth_currency,
    :fee_worth_amount, :fee_worth_currency,
    :txhash, :txsrc, :txdest,
    :contract_address, :method_hash, :method_name,
    :external_id, :external_data,
    :importer_tag,
    :margin,
    :group_name,
    :synced,
    :unique_hash,
  ].freeze

  attr_accessor *ALL_ATTRIBUTES

  validates_inclusion_of :type, in: TYPES
  validates_presence_of :date
  validates_presence_of :from_currency, if: :should_validate_from
  validates_presence_of :to_currency, if: :should_validate_to
  validates_presence_of :fee_currency, if: :should_validate_fee
  validates :from_amount, numericality: { greater_than: 0 }, if: :should_validate_from
  validates :to_amount, numericality: { greater_than: 0 }, if: :should_validate_to
  validates_numericality_of :fee_amount, if: :should_validate_fee
  validate :ensure_valid_transfer, if: :transfer?
  validate :ensure_from_and_to_not_same, if: :trade?
  validate :ensure_amounts_are_within_bounds
  validate :ensure_date_is_valid
  validate :ensure_label_is_valid

  def initialize(params, small_decimals: nil, default_timezone: nil, uniqueness_seed: nil)
    super(params)

    self.synced = !!params[:synced]
    self.margin = !!params[:margin]
    self.description = params[:description].to_s.presence
    self.label = params[:label].to_s.presence
    self.group_name = params[:group_name].to_s.presence

    self.date = TxnHelper.normalize_date(params[:date], default_timezone)
    self.from_amount = TxnHelper.normalize_amount(params[:from_amount], small_decimals: small_decimals).abs
    self.to_amount = TxnHelper.normalize_amount(params[:to_amount], small_decimals: small_decimals).abs
    self.fee_amount = TxnHelper.normalize_amount(params[:fee_amount], small_decimals: small_decimals).abs
    self.fee_currency = nil if fee_amount <= 0

    self.net_worth_amount = TxnHelper.normalize_amount(params[:net_worth_amount]).abs
    self.net_worth_currency = nil unless params[:net_worth_amount]
    self.net_worth_amount = self.net_worth_currency = nil if net_worth_amount.blank?

    self.fee_worth_amount = TxnHelper.normalize_amount(params[:fee_worth_amount]).abs
    self.fee_worth_currency = nil unless params[:fee_worth_amount]
    self.fee_worth_amount = self.fee_worth_currency = nil if fee_worth_amount.blank?

    self.txsrc = params[:txsrc].to_s.presence
    self.txdest = params[:txdest].to_s.presence
    self.txhash = params[:txhash].to_s.presence
    self.txhash = nil if txhash.to_s.strip.size <= 2 # 0, 0x
    self.contract_address = params[:contract_address].to_s.presence
    self.method_hash = params[:method_hash].to_s.presence
    self.method_name = params[:method_name].to_s.presence
    self.external_id = params[:external_id].to_s.presence

    self.type =
      if to_currency && from_currency
        if to_currency == from_currency
          TRANSFER
        else
          TRADE
        end
      elsif to_currency
        DEPOSIT
      elsif from_currency
        WITHDRAWAL
      end

    self.unique_hash = uniq_attributes_hash_v1(uniqueness_seed.presence)
  end

  # This is required by ActiveModel::Serialization.
  def attributes
    ALL_ATTRIBUTES.map { |attr| [attr.to_s, nil] }.to_h # value is set to nil as per docs
  end

  def transfer?
    type == TRANSFER
  end

  def deposit?
    type == DEPOSIT
  end

  def withdrawal?
    type == WITHDRAWAL
  end

  def trade?
    type == TRADE
  end

  def fee?
    fee_currency.present? && fee_amount > 0
  end

  def prettify
    from = "#{from_amount} #{from_currency.to_s}" if from_currency
    to = "#{to_amount} #{to_currency.to_s}" if to_currency
    if from && to
      result = from + ' -> ' + to
    elsif from
      result = "Withdraw " + from
    else
      result = "Deposit " + to
    end

    extra_info = []
    extra_info << "fee: #{fee_amount} #{fee_currency.to_s}" if fee_currency
    extra_info << "net worth: #{net_worth_amount} #{net_worth_currency.to_s}" if net_worth_currency
    extra_info << "fee worth: #{fee_worth_amount} #{fee_worth_currency.to_s}" if fee_worth_currency
    extra_info << "label: #{label}" if label
    extra_info << "desc: #{description}" if description.present?
    extra_info << "txhash: #{txhash}" if txhash.present?
    extra_info << "txsrc: #{txsrc}" if txsrc.present?
    extra_info << "txdest: #{txdest}" if txdest.present?
    extra_info << "contract: #{contract_address}" if contract_address.present?
    extra_info << "method: #{method_name || method_hash}" if (method_name || method_hash).present?
    extra_info << "importer_tag: #{importer_tag}" if importer_tag.present?
    extra_info << "margin trade!" if margin

    date.to_s + " | " + result + (extra_info.any? ? " (" + extra_info.join(', ') + ")" : "")
  end

  private

  def should_validate_from
    trade? || transfer? || withdrawal?
  end

  def should_validate_to
    trade? || transfer? || deposit?
  end

  def should_validate_fee
    fee_currency.present?
  end

  def ensure_label_is_valid
    labels = DEPOSIT_LABELS if deposit?
    labels = WITHDRAWAL_LABELS if withdrawal?
    labels = TRADE_LABELS if trade?
    labels = TRANSFER_LABELS if transfer?

    if label && labels && !labels.include?(label)
      errors.add(:from_amount, 'invalid label')
    end
  end

  def ensure_valid_transfer
    if to_amount > from_amount + 0.0000_0001
      # sometimes from_amount might have more than 8 decimals while the receiving wallet rounds
      # it to 8 so it looks like you received more than you sent. The TransferMatcher can
      # still match such txns so need to prevent any validation errors due to this here
      errors.add(:to_amount, "must be less than From_amount")
    elsif from_currency != to_currency
      errors.add(:from_currency, "must be same as To currency")
    end
  end

  def ensure_from_and_to_not_same
    if from_currency == to_currency
      self.errors.add(:from_currency, 'should not be same as To currency')
    end
  end

  def ensure_amounts_are_within_bounds
    if from_amount && from_amount.to_d.abs > 10**15
      errors.add(:from_amount, 'must be less than 10^15')
    elsif to_amount && to_amount.to_d.abs > 10**15
      errors.add(:to_amount, 'must be less than 10^15')
    elsif fee_amount && fee_amount.to_d.abs > 10**15
      errors.add(:fee_amount, 'must be less than 10^15')
    end
  end

  def ensure_date_is_valid
    if date.nil?
      errors.add(:date, 'is invalid')
    elsif date > 1.year.from_now || date.year < 2009
      errors.add(:date, 'is out of bounds/invalid')
    end
  end

  def uniq_attributes_hash_v1(uniqueness_seed)
    uniq_attrs = []

    # fees are sometimes imported incorrectly so we dont include these in the hash to make it a bit more resilient
    %i[date type from_amount to_amount].each do |k|
      uniq_attrs << [k, send(k)]
    end

    %i[from_currency to_currency].each do |k|
      currency = send(k)
      if currency.is_a?(Hash) || currency.is_a?(Array)
        hash = currency.is_a?(Array) ? currency[0] : currency
        sliced = hash[:address].present? ? hash.slice(:address, :nft_token) : hash[:symbol]
        uniq_attrs << [k, sliced]
      else
        uniq_attrs << [k, currency]
      end
    end

    %i[from_wallet to_wallet].each do |k|
      wallet = send(k)
      uniq_attrs << [k, wallet.is_a?(Hash) ? wallet[:wallet_service_tag] : wallet]
    end

    uniq_attrs << [:txhash, TxnHelper.normalize_hash(txhash)]
    uniq_attrs << [:external_id, external_id]
    uniq_attrs << [:uniqueness_seed, uniqueness_seed]

    uniq_attrs.reject! { |arr| arr[1].blank? }

    "v1:#{Digest::MD5.hexdigest(uniq_attrs.to_json.downcase)}"
  end
end
