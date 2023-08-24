require "base64"

# REMEMBER TO ADD DERIVED CLASS TO CSV_IMPORT!!!
class BaseMapper
  FILE_ROW_IDX_KEY = "File Row #".freeze
  CANCELED_REGEX = /fail|error|invalid|cancel/i
  attr_accessor :current_user, :current_wallet, :adapter, :options, :mapping, :results

  delegate :sync_txn, to: :adapter

  # acts as both setter and getter
  # tag is used for symbol aliases and may be omitted
  def self.tag(tag = nil)
    tag ? (@tag = tag) : @tag
  end

  # acts as both setter and getter
  def self.mappings(mappings = nil)
    mappings ? (@mappings = mappings) : @mappings
  end

  def initialize(adapter, mapping_id, **options)
    @options = options
    @mapping = self.class.mappings.find { |x| x[:id] == mapping_id }
    @results = {
      total_count: 0,
      skipped_count: 0,
      duplicate_count: 0,
      error_count: 0,
      success_count: 0,
      bad_rows: [],
      errors: Hash.new(0),
      skipped: Hash.new(0),
    }
    @adapter = adapter
  end

  # must return the header row index
  # use this to find the header row if it is preceded by other header lines
  def self.header_row(rows, mapping)
    empty_rows = 0
    empty_rows += 1 while empty_rows < rows.count && rows[empty_rows].select(&:present?).count <= 1
    empty_rows = 0 if empty_rows == rows.count

    if mapping[:header_row].is_a?(Integer)
      empty_rows + mapping[:header_row]
    elsif mapping[:header_row].is_a?(Proc)
      empty_rows + mapping[:header_row].call(rows)
    else
      empty_rows
    end
  end

  def self.confidence_score(rows, file_name, mapping, wallet_tag)
    return 0 if rows.empty?
    header_row = rows[header_row(rows, mapping)]
    return 0 if header_row.nil? || header_row.empty?

    # headers must match
    # some column headers can be nil when empty (for xlsx), contain invalid chars or quotes - we strip all that
    header_row = header_row.map { |k| TxnHelper.printable_string(k, mapping[:downcase_headers]) || '' }
    return 0 unless (mapping[:required_headers] - header_row).none?

    mapping_tag = mapping[:importer_tag] || tag
    return 0 if mapping.dig(:options, :tag_required) && wallet_tag != mapping_tag

    # the file name checks are optional as a file may have been renamed to sth else
    if file_name.present?
      file_name = file_name.downcase.strip
      name_in = mapping.dig(:options, :file_name_in)&.any? { |name| file_name.include?(name.downcase) }
      return 0 if mapping.dig(:options, :file_name_not_in)&.any? { |name| file_name.include?(name.downcase) }
    end

    score = 10
    score += 10 if name_in
    score += mapping[:required_headers].size # the more columns the better the match
    score += 100 if wallet_tag && mapping_tag && mapping_tag == wallet_tag # top priority to tags
    score
  end

  def import_and_commit!(file, file_name, col_sep = ",", row_sep = "auto")
    doc_options = {
      csv_options: { col_sep: (col_sep || ','), row_sep: (row_sep || 'auto'), quote_char: "\"" },
      extension: file_name.split('.').last,
    }

    begin
      spreadsheet = Roo::Spreadsheet.open(file, doc_options.dup)
      spreadsheet.last_row
    rescue CSV::MalformedCSVError => e
      doc_options[:csv_options][:quote_char] = "\x00"
      spreadsheet = Roo::Spreadsheet.open(file, doc_options.dup)
    end

    header = fetch_header(spreadsheet)
    rows = fetch_rows(header, spreadsheet)

    raise TxnError, "file has too many rows #{rows.count}" if rows.count > 100_000

    mapped = rows.flat_map.with_index do |raw_row, idx|
      results[:total_count] += 1

      mapped_row = apply_mapping(mapping, raw_row, options.merge(file_name: file_name, idx: idx))

      # NOTE: mapped row can also be an array of mapped items
      mapped_row = parse_row(mapped_row, raw_row, options.merge(file_name: file_name, idx: idx)) if mapped_row && !mapped_row.is_a?(String)

      if mapped_row.nil? || mapped_row.is_a?(String)
        row_skipped(mapped_row)
        nil
      elsif mapped_row.is_a?(Hash) && mapped_row.key?(:error)
        row_failed(raw_row, idx, mapped_row[:error])
        nil
      else
        mapped_row = create_swap_txns(mapped_row, raw_row, idx) if mapping[:is_swap_service]

        # this can create multiple rows
        mapped_row = [mapped_row].flatten.map { |x| handle_deposits_and_withdrawals(x, raw_row) }

        [mapped_row].flatten.map do |mapped_row|
          finalize_fields(mapped_row, raw_row, idx)
          error = nil
          error = "cant exchange between same currency" if (mapped_row[:from_currency] == mapped_row[:to_currency] && !mapped_row[:to_wallet])
          error = "both sent currency (from) and received currency (to) are blank" if !mapped_row[:from_currency] && !mapped_row[:to_currency]
          error = "date is invalid" unless mapped_row[:date]
          if error
            row_failed(raw_row, idx, error)
            nil
          else
            mapped_row
          end
        end
      end
    rescue => e
      if e.is_a?(TxnError)
        row_failed(raw_row, idx, e.message)
      else
        log_error(e, raw_row.merge(mapping: mapping[:id]))
        row_failed(raw_row, idx, "unable to parse row")
      end
      nil
    end.compact

    if mapping[:determine_date_format]
      american_default = mapping[:determine_date_format] != :not_american
      @date_format = TxnHelper.determine_date_format(mapped.sample(100).map { |row| row[:date] }, american_default) rescue nil
      mapped.select! do |row|
        row[:date] = TxnHelper.convert_date_with_fmt(row[:date], @date_format) rescue nil
        if row[:date].nil?
          row_failed(row, nil, 'cant determine date')
          nil
        else
          row
        end
      end
    end

    if mapping[:group]
      mapped = apply_grouping(mapped, mapping[:group])
    end

    mapped.each do |mapped_row|
      mapped_row[:date] = TxnHelper.normalize_date(mapped_row[:date], mapped_row[:default_timezone])
      if mapped_row.key?(:date_adjust)
        date_adjust = mapped_row.delete(:date_adjust)
        mapped_row[:date] += date_adjust if date_adjust
      end
      if mapped_row[:from_currency] && mapped_row[:to_currency]
        if mapped_row[:from_currency] == mapped_row[:to_currency] && mapped_row[:from_wallet] != mapped_row[:to_wallet]
          sync_txn(mapped_row)
        else
          warn_if_bad_trade(mapped_row)
          sync_txn(mapped_row)
        end
      elsif mapped_row[:from_currency]
        sync_txn(mapped_row)
      elsif mapped_row[:to_currency]
        sync_txn(mapped_row)
      end

      results[:success_count] += 1
    rescue => e
      log_error(e, mapped_row.merge(mapping: mapping[:id]))
      row_failed(mapped_row, nil, "internal error while adding row")
      raise
    end

    adapter.commit!(CsvAdapter::COMPLETED, results: results)

    [results, nil]
  rescue => e
    log_error(e, mapping: mapping[:id])
    message = Base64.encode64(e.message.first(200))
    row_failed({ code: message }, 0, "failed to import file - contact support")
    adapter.commit!(CsvAdapter::FAILED, error: "Error: #{message}", results: results)

    [results, e, message]
  end

  def fetch_header(spreadsheet)
    rows = spreadsheet.each.to_a
    rows[self.class.header_row(rows, mapping)].map { |k| TxnHelper.printable_string(k, mapping[:downcase_headers]) || '' }
  end

  # override in derived classes if needed
  # Note: if you are converting the rows in then then override the parse_row method to return raw_row instead of mapped_row!
  def fetch_rows(header, spreadsheet)
    rows = spreadsheet.each.to_a
    convert_array_to_row(header, rows[((self.class.header_row(rows, mapping)) + 1)..-1])
  end

  def convert_array_to_row(header, rows)
    rows.map do |row|
      # we convert all row values to string because xlsx files can map them to their actual types ex. DateTime, Integer etc
      HashWithIndifferentAccess[transpose_row(header, row.map { |r| r.to_s.blank? ? nil : r.to_s })] unless row.all?(&:blank?)
    end.compact
  end

  # override in derived classes if needed
  def parse_row(mapped_row, raw_row, options)
    mapped_row
  end

  def transpose_row(header, row)
    transposed = [header, row].transpose
    hash = {}
    transposed.each do |(k, v)|
      v&.gsub!(/^"|"$/, "")
      # this handles duplicate header columns
      if hash.key?(k)
        if hash[k].is_a?(Array)
          hash[k] << v
        else
          hash[k] = [hash[k], v]
        end
      else
        hash[k] = v
      end
    end
    hash
  end

  def apply_mapping(mapping, row, opt)
    mapped_row = {}
    (mapping[:header_mappings] || {}).each do |k, v|
      v = v.detect { |x| row[x].present? } if v.is_a?(Array) # we allow multiple fallback values
      mapped_row[k] = row[v].to_s.strip
      mapped_row[k] = nil if mapped_row[k].blank?
    end
    mapped_row.merge!(mapping[:row_defaults]) if mapping[:row_defaults].present?
    mapped_row.symbolize_keys!
    instance_exec(mapped_row, row, opt, &mapping[:process]) if mapping.key?(:process)
    return (mapped_row[:skip] == true ? nil : mapped_row[:skip]) if mapped_row[:skip]
    mapped_row
  end

  def handle_deposits_and_withdrawals(row, raw_row)
    if row[:amount].present? && row[:currency].present?
      if row[:amount].clean_d > 0
        row[:to_currency] = row.delete(:currency)
        row[:to_amount] = row.delete(:amount)
      else
        row[:from_currency] = row.delete(:currency)
        row[:from_amount] = row.delete(:amount)
      end
    end

    # handle deposit or withdrawal fees
    unless row[:fee_amount].clean_d.zero?
      create_separate_fee_txn = false

      # add to existing txn if possible
      if row[:from_currency].present? && row[:to_currency].blank?
        if row[:fee_currency].blank? || row[:fee_currency] == row[:from_currency]
          row[:from_amount] = row[:from_amount].clean_d.abs + row[:fee_amount].clean_d.abs
          row.delete(:fee_currency)
        else
          create_separate_fee_txn = true
        end
      elsif row[:from_currency].blank? && row[:to_currency].present?
        # for deposits we will always create a separate txn for the fee so user can see it on his report
        row[:fee_currency] = row[:to_currency] if row[:fee_currency].blank?
        create_separate_fee_txn = true
      end

      # create new txn for the fee
      if create_separate_fee_txn && row[:fee_currency].present?
        fee = row.merge(
          from_amount: row[:fee_amount],
          from_currency: row[:fee_currency],
          to_amount: nil,
          to_currency: nil,
          fee_amount: nil,
          fee_currency: nil,
          label: Txn::COST,
          description: 'Fee',
          txhash: nil
        )

        if row[:external_id].present?
          fee[:external_id] = row[:external_id].to_s + '_fee'
        elsif row[:txhash].present?
          fee[:external_id] = row[:txhash].to_s + '_fee'
        end

        row[:fee_amount] = row[:fee_currency] = nil

        return [row, fee]
      end
    end

    row
  end

  def finalize_fields(row, raw_row, idx)
    row.each { |k, v| row[k] = (k == :description ? TxnHelper.clean_string(v) : TxnHelper.printable_string(v)) }
    row.each { |k, v| row[k] = nil if row[k].blank? }

    if [:pair, :type, :amount].all? { |k| row[k].present? } && (row[:unit_price].present? || row[:total_price].present?)
      base, quote = TxnHelper.split_pair(row[:pair], mapping[:known_quotes] || known_quotes)
      params = TxnHelper.convert_trade_params(row.merge(base: base, quote: quote))
      params.delete(:fee_currency) if row[:fee_currency].present?
      row.merge!(params)
      row.except!(:pair, :type, :amount, :unit_price, :total_price)
    end

    if row[:from_currency] && !row[:to_currency]
      row[:label] ||= options[:withdrawal_label]
    elsif !row[:from_currency] && row[:to_currency]
      row[:label] ||= options[:deposit_label]
    end

    # if both from and to currencies are present then we assume its a trade and if any of the amounts are 0 we change
    # them to the lowest possible value - this prevents trades from being added as deposits/withdrawals
    row[:from_amount] = TxnHelper.normalize_amount(row[:from_amount], no_zero: !!row[:to_currency]) if row[:from_currency]
    row[:to_amount] = TxnHelper.normalize_amount(row[:to_amount], no_zero: !!row[:from_currency]) if row[:to_currency]
    row[:fee_amount] = TxnHelper.normalize_amount(row[:fee_amount]) if row[:fee_currency]

    row.delete(:fee_currency) if row[:fee_amount].to_d.zero?
    row.delete(:net_worth_currency) if row[:net_worth_amount].to_d.zero?
    row.delete(:fee_worth_currency) if row[:fee_worth_amount].to_d.zero?

    # some exchanges have _OLD in the symbol so we remove that, note that currency may also be a Currency object
    # BTC_OLD, BTC_OLD2
    row[:from_currency] = row[:from_currency].split('_').first if row[:from_currency].respond_to?(:include?) && row[:from_currency].include?('_OLD')
    row[:to_currency] = row[:to_currency].split('_').first if row[:to_currency].respond_to?(:include?) && row[:to_currency].include?('_OLD')
    row[:fee_currency] = row[:fee_currency].split('_').first if row[:fee_currency].respond_to?(:include?) && row[:fee_currency].include?('_OLD')

    row[:default_timezone] = options[:timezone] if options[:timezone].present?

    # we need an importer_tag to ensure symbol aliases continue working
    row[:importer_tag] ||= mapping[:importer_tag] || self.class.tag || row[:wallet] || options[:wallet_service_tag]

    # mappers that parse the whole file must set external_data themselves so we add file index to it
    external_data = row[:external_data] || raw_row
    external_data.merge!(FILE_ROW_IDX_KEY => idx)
    row[:external_data] = raw_row unless raw_row.nil? || row == raw_row
    row
  end

  def warn_if_bad_trade(row)
    return unless ENV['RACK_ENV'] == 'test'
    return unless row[:from_currency].present? && row[:to_currency].present?

    trade_text = "#{row[:from_amount]} #{row[:from_currency]} -> #{row[:to_amount]} #{row[:to_currency]} (#{row[:date]}) #{mapping[:id]}"

    # ensure fee is not higher than the traded amounts
    if row[:fee_amount].present? && row[:fee_currency].present? && row[:fee_amount] > 0.0001
      if row[:fee_currency] == row[:from_currency] && row[:fee_amount] > row[:from_amount] && row[:from_amount] > 0.0001
        warn("very high fee of #{row[:fee_amount]} #{row[:fee_currency]} on trade: #{trade_text}")
      elsif row[:fee_currency] == row[:to_currency] && row[:fee_amount] > row[:to_amount] && row[:to_amount] > 0.0001
        warn("very high fee of #{row[:fee_amount]} #{row[:fee_currency]} on trade: #{trade_text}")
      end
    end

    @oldest_date ||= DateTime.parse("2015-01-01") # older trades (pre 2015) fluctuated too much veen with BTC ex. you could trade 20 AAA for 50 BTC
    # ensure BTC amount is always higher than the other traded amount
    if row[:from_currency] == 'BTC' && row[:from_amount] > row[:to_amount]
      warn("looks like a bad trade: #{trade_text}") unless TxnHelper.normalize_date(row[:date]) < @oldest_date
    elsif row[:to_currency] == 'BTC' && row[:from_amount] < row[:to_amount]
      warn("looks like a bad trade: #{trade_text}") unless TxnHelper.normalize_date(row[:date]) < @oldest_date
    end
  end

  def import_with_builder(builder_klass, row)
    builder = builder_klass.new(current_user, row[:wallet] || current_wallet, row, adapter)
    if builder.valid?
      if builder.create!
        results[:success_count] += 1
      else
        results[:duplicate_count] += 1
      end
    else
      row_failed(row, nil, builder.errors.full_messages.join('. '))
    end
  rescue TxnError => e
    row_failed(row, nil, e.txn&.errors&.full_messages&.join('. ') || e.message)
  end

  def row_failed(row, idx, message)
    raw = (row.dig(:external_data) || row).except(:wallet, :to_wallet)
    results[:error_count] += 1

    if results[:bad_rows].count <= 50
      results[:bad_rows] << { id: (idx || raw.dig(FILE_ROW_IDX_KEY)), row: raw, message: message }
    end

    results[:errors][message] += 1 unless results[:errors].keys.count > 50
  end

  def row_skipped(message)
    message ||= 'unnecessary row'
    results[:skipped_count] += 1
    results[:skipped][message] += 1 unless results[:skipped].keys.count > 50
  end

  # error can be an exception or a string
  # this method must return the logged error message
  def log_error(error, data = {})
    @logged_errors ||= []
    message = error.try(:message) || error
    unless @logged_errors.include?(message)
      if error.is_a?(Exception)
        Rollbar.error(error, data)
      else
        Rollbar.warning(error, data)
      end
      @logged_errors << message
    end
    message
  end

  # override this if the pair does not have a separator ex. BATUSD
  def known_quotes
    []
  end

  # this method can be used for exchanges like safello, btcx, changelly etc that
  # only handle conversions between coins but do not store any funds,
  # ex. user sends coins to changelly and changelly converts to chosen currency and
  # sends it to specified address
  def create_swap_txns(mapped_row, raw_row, idx)
    finalize_fields(mapped_row, raw_row, idx)
    date = mapped_row[:date]

    deposit = {
      date: date,
      date_adjust: mapped_row[:date_adjust],
      to_amount: mapped_row[:from_amount],
      to_currency: mapped_row[:from_currency],
    }

    withdrawal = {
      date: date,
      date_adjust: mapped_row[:date_adjust],
      from_amount: mapped_row[:to_amount],
      from_currency: mapped_row[:to_currency],
      txhash: mapped_row.delete(:txhash),
      txdest: mapped_row.delete(:txdest),
    }

    [deposit, mapped_row, withdrawal]
  end

  # +14 USD
  # 14.25 USD
  # -15.22USD
  # 1e-5 USD
  # -55e5 usd
  def split_amount_curr(val)
    return unless val.present?
    match = val.squish.strip.match(/(-?\d+(?:(?:\.\d+)|(?:e-?\d+))?) ?([a-zA-Z]+)/)
    return unless match
    [match[1], match[2]]
  end

  # returns all grouped trades and all non-trades
  def apply_grouping(rows, params)
    groupable = rows
    if params[:eligible].is_a?(Proc)
      groupable = rows.select { |x| params[:eligible].call(x, x[:external_data]) }
    end

    return rows if groupable.blank?

    groupable.sort_by! { |x| x[:date] = TxnHelper.normalize_date(x[:date], x[:default_timezone]) }

    if params[:by_date]
      groups = group_by_date_intervals(groupable, params[:by_date])
      if params[:by_hash]
        groups = groups.flat_map { |group| group.group_by { |x| params[:by_hash].call(x, x[:external_data]) }.values }
      end
    elsif params[:by_hash]
      groups = groupable.group_by { |x| params[:by_hash].call(x, x[:external_data]) }.values
    else
      raise "must specify group identifier, either date or hash"
    end

    # return both ineligible and grouped txns
    (rows - groupable) + groups.map { |group| resolve_groups(group, params[:on_conflict]) }.flatten
  end

  def group_by_date_intervals(rows, interval)
    groups = []
    current_group = []
    current_group_date = rows[0][:date].to_i
    rows.each do |x|
      if (x[:date].to_i - current_group_date) <= interval
        current_group << x
      else
        groups << current_group
        current_group_date = x[:date].to_i
        current_group = [x]
      end
    end
    groups << current_group if current_group.any?
    groups
  end

  def resolve_groups(group, on_conflict)
    fee = group.select { |x| x[:label] == Txn::COST }
    from = group.select { |x| x[:from_currency].present? && x[:label] != Txn::COST }
    to = group.select { |x| x[:to_currency].present? }

    if (group[-1][:date].to_i - group[0][:date].to_i) > 2.days
      log_error("group dates are too far apart", mapping: mapping[:id], group: group.map { |x| x[:external_data] }.take(5))
      return
    end

    # ensure all same currency
    unless from.all? { |x| x[:from_currency] == from[0][:from_currency] } && to.all? { |x| x[:to_currency] == to[0][:to_currency] }
      if on_conflict
        return instance_exec(group, &on_conflict).map { |x| resolve_groups(x, nil) }
      else
        @conflicts ||= 0
        @conflicts += 1
        puts "got conflict in group trades: #{@conflicts}"
        return group # add all rows as separate txns
      end
    end

    if from.none? || to.none?
      return group
    end

    grouped_rows = []
    # dont add fee if there are multiple in different currencies
    unless fee.all? { |x| x[:from_currency] == fee[0][:from_currency] }
      grouped_rows.concat(fee)
      fee = []
    end

    net_worth = group.find { |x| x[:net_worth_amount].present? && x[:net_worth_currency].present? && x[:label] != Txn::COST }
    desc = group.select { |x| x[:description].present? && x[:label] != Txn::COST }.map { |x| x[:description] }.sort.first

    grouped_rows << {
      date: group.first[:date],
      date_adjust: group.first[:date_adjust],
      from_amount: from.sum { |x| x[:from_amount] },
      from_currency: from[0][:from_currency],
      to_amount: to.sum { |x| x[:to_amount] },
      to_currency: to[0][:to_currency],
      fee_amount: fee.sum { |x| x[:from_amount] },
      fee_currency: fee&.dig(0, :from_currency), # note: fee is withdrawal so using from_curr instead of fee_curr
      net_worth_amount: net_worth&.dig(:net_worth_amount),
      net_worth_currency: net_worth&.dig(:net_worth_currency),
      description: desc,
      txhash: (from + to + fee).map { |x| x[:txhash] }.first,
      external_id: (from + to + fee).map { |x| x[:external_id] }.first,
      external_data: { multi: group.map { |x| x[:external_data] }.sort_by(&:to_s).take(5), total: group.count },
      importer_tag: group[0][:importer_tag],
      margin: group.any? { |x| x[:margin] }
    }

    grouped_rows
  end
end
