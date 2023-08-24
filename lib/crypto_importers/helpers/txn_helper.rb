class TxnHelper
  BAD_DATE_FORMAT = /^\d{2}:\d{2}\.\d$/.freeze # 42:01.6 (happens probably because of Excel formatting)
  FIATS = %w[AED ARS AUD BGN BRL CAD CHF CLP CNY COP CZK DKK DZD EGP
    EUR GBP HKD HRK HUF IDR ILS INR ISK JPY KES KHR KRW LAK
    LKR MAD MMK MXN MYR NGN NOK NZD PHP PKR PLN QAR RON RUB
    RUB SEK SGD THB TWD UAH UYU USD VEF XAG XAU XPL XPT ZAR].freeze

  # a buy of 10 on BTC/USD means we are buying 10 BTC for X USD (from USD to BTC)
  # a sell of 10 BTC/USD means we are selling 10 BTC for X USD (from BTC to USD)
  # @params: pair, side, amount, unit_price or total_price
  def self.convert_trade_params(params)
    base_symbol = params[:base]
    quote_symbol = params[:quote]
    side = params[:type]
    amount = params[:amount]
    unit_price = params[:unit_price]
    total_price = params[:total_price]

    base_amount = amount
    quote_amount = total_price.present? ? total_price : amount.clean_d * unit_price.clean_d
    is_buy =
      case side
      when /buy|bought|bid/i
        true
      when /sell|sold|ask/i
        false
      else
        raise sTxnError, "Unknown side value: #{side}"
      end

    amounts_params = {
      from_amount: (is_buy ? quote_amount : base_amount),
      from_currency: (is_buy ? quote_symbol : base_symbol),
      to_amount: (is_buy ? base_amount : quote_amount),
      to_currency: (is_buy ? base_symbol : quote_symbol)
    }

    fee_currency = detect_fee_currency(**amounts_params.merge(fee_amount: params[:fee_amount]))
    fee_currency ||= (is_buy ? base_symbol : quote_symbol)

    amounts_params.merge(fee_currency: fee_currency)
  end

  def self.normalize_amount(amount, decimals: nil, no_zero: false, small_decimals: false)
    amount = amount.clean_d
    amount /= 10**decimals.to_i.clamp(0, 100) if decimals
    amount = amount.round(small_decimals ? 18 : 10)
    return (small_decimals ? 0.0000_0000_0000_0000_01 : 0.0000_0000_01) if amount.zero? && no_zero
    amount
  end

  def self.normalize_date(date, tz = nil)
    return unless date
    # 1577559733.5118
    # 1577559733511
    # 1577559733
    if date.to_s.to_d.to_s.gsub(/\.0$/, '') == date.to_s.gsub(/\.0$/, '') # remove trailing .0
      int = date.to_i
      if int > 1000.years.from_now.to_i # millisecond detection
        Time.at(int / 1000).utc
      else
        Time.at(int).utc
      end
    else
      to_time(date, tz)&.utc
    end
  rescue ArgumentError
    nil
  end

  def self.to_time(date, zone = nil)
    parts = Date._parse(date.to_s.squish, false)
    used_keys = %i(year mon mday hour min sec sec_fraction offset)
    return if (parts.keys & used_keys).empty?

    now = Time.now
    # We need to take in account hours for timezone offset because there might be edge cases.
    # Day when switching back from DST (Daylight Saving Time) should be treated as (ST) Standard time but if do not count hours in will treated as DST,
    # because clocks are changed and 03:00 (according to TZInfo lib).
    date_only = Time.new(
      parts.fetch(:year, now.year),
      parts.fetch(:mon, now.month),
      parts.fetch(:mday, now.day),
      parts.fetch(:hour, 0),
      )
    time = Time.new(
      parts.fetch(:year, now.year),
      parts.fetch(:mon, now.month),
      parts.fetch(:mday, now.day),
      parts.fetch(:hour, 0),
      parts.fetch(:min, 0),
      parts.fetch(:sec, 0),
      zone ? TZInfo::Timezone.get(zone).period_for_local(date_only) { |x| x[0] }.utc_total_offset : parts.fetch(:offset, 0),
      )

    time.to_time
  end

  def self.clean_string(s)
    return s unless s.is_a?(String)
    s.squish.gsub(/^"+|"+$/, '')
  end

  def self.printable_string(s, downcase = false)
    return s unless s.is_a?(String)
    name = clean_string(s).chars.each_with_object("") do |char, str|
      str << char if char.ascii_only? and char.ord.between?(32, 126)
    end
    name.downcase! if downcase
    name
  end

    # use this on a range of dates to figure out which column contains
  # the month and date ex. MM/DD/YY or DD/MM/YY. It can also return the
  # time format if time is present.
  # It does not return timezone information.
  # example dates:
  # 10-16-2019 11:34 PM
  # 11/30/2019 10:25:00
  # 03/12/2019 13:13:15
  # 18/11/2019 14:04
  # 30/09/2019
  # DD-MM-YY ex 10-12-14 (default)
  # MM-DD-YY ex 12-10-14
  # YY-MM-DD ex 14-12-10
  # it will return an array of formats
  # the second parameter determines how we handle inconclusive dates formatted as d/m/yyyy and m/d/yyyy
  # american style uses the latter format, note that this is only used if the date is slash separated
  def self.determine_date_format(dates, american = true)
    return if dates.empty?

    # 2015-09-30T18:57:52+00:00
    # 2019-04-03D06:28:09.536383000
    # 25 Jan 2020 14:06:41
    all_good = dates.all? do |x|
      date = x.to_datetime rescue nil
      date && date < 1.year.from_now && date.year >= 2010
    end

    # ruby formats slash separated dates as d/m/yyyy but american dates (slash separated)
    # are usually in m/d/yyyy
    return if all_good && (dates[0].count('/') == 0 || !american)

    splitters = /[-\/.]/
    # some dates have a comma between date and time ex. bitmex
    # 11/30/2019, 11:25PM
    dates = dates.map { |x| x.to_s.gsub(/,/, ' ').squish }.reject do |x|
      x.blank? ||
        !x.match(/[0-9]/) ||
        !x.match(splitters) ||
        x.scan(/[0-9]+/).map(&:to_i).sort[-1]&.>(10000) ||
        x.match?(BAD_DATE_FORMAT)
    end

    return if dates.empty?

    first_date = dates.first
    first_time = first_date.split(' ')[1..-1].join(' ')
    time_format = ""
    time_format = "%H:%M" if first_time.include?(':')
    time_format += ':%S' if first_time.match(/\d+:\d+:\d+/)
    time_format += ' %z' if first_time.match(/[+-]\d+:?\d*$/) # +0900, +09:00
    time_format += ' %P' if first_time.include?('AM') || first_time.include?('PM')

    # [XX-YY-ZZZZ HH:mm:ss, AA-BB-CCCC HH:mm:ss] becomes [[XX, AA], [YY, BB], [ZZZZ, CCCC]]
    date_grid = begin
      dates.map { |x| x&.split(' ')&.first&.split(splitters).map(&:to_i) }.compact.transpose
    rescue IndexError
    end

    raise TxnError, "bad date #{first_date}" if Array(date_grid).count <= 2

    # the year can be in the first or last column only
    year_cols = []
    year_cols << 0 if date_grid[0].all? { |x| x >= 2010 }
    year_cols << 2 if date_grid[2].all? { |x| x >= 2010 }
    if year_cols.empty?
      max_year = Time.now.year % 100 # so we can match partial years ex. 19 for 2019
      year_cols << 0 if date_grid[0].all? { |x| (x > 12 && x <= max_year) }
      year_cols << 2 if date_grid[2].all? { |x| (x > 12 && x <= max_year) }
    end

    # month can be in first and second column only
    month_cols = []
    month_cols << 0 if date_grid[0].all? { |x| x > 0 && x <= 12 }
    month_cols << 1 if date_grid[1].all? { |x| x > 0 && x <= 12 }

    # date can be in any column
    day_col = nil
    date_grid.each do |col|
      # max_year is only set if year is double digited ex. 19 instead of 2019
      # in such cases we want a date column that is higher than current years digit
      if col.any? { |x| x > (max_year || 12) && x <= 31 }
        day_col = col
        break
      end
    end

    year_cols -= [day_col] if day_col
    month_cols -= [day_col] if day_col

    # month and year can never clash. only date/month or date/year can have clashes
    # so its possible either the year_col or the month_col will be an array
    # ex year clash: 19/12/19 (year could be first or last, day_col will be nil)
    # ex month clash: 12/12/13 (month could be first or second, day_col will be nil)
    year_col = year_cols.first if year_cols.count == 1
    month_col = month_cols.first if month_cols.count == 1

    first_date = first_date.split(' ').first
    sep = %w[- / .].detect { |x| first_date.include?(x) }

    # only one of these can have clashes
    if year_cols.count > 1
      year_col = 2
    elsif month_cols.count > 1
      if sep == '/' # this separator is common in US dates: m/d/y, other countries use dash or dot as separator
        month_col = american ? 0 : 1
      else
        month_col = 1
      end
    end

    raise TxnError, "weird date #{first_date}" unless month_col && year_col

    # possible formats:
    # yy/mm/dd
    # dd/mm/yy
    # mm/dd/yy
    if year_col == 0
      # can only be yy/mm/dd
      day_col = 2
      month_col = 1
    elsif month_col == 0
      # can only be mm/dd/yy
      day_col = 1
      year_col = 2
    else
      day_col = ([0, 1, 2] - [month_col, year_col]).first
    end

    hash = {}
    hash[day_col] = '%d'
    hash[month_col] = '%m'
    hash[year_col] = max_year ? '%y' : '%Y'
    date_format = hash[0] + sep + hash[1] + sep + hash[2]
    [date_format, time_format].join(' ').strip
  end

  # use this in conjunction with determine_date_format, it cleans the
  # date in the same way as determine_date_format
  def self.convert_date_with_fmt(date, format)
    return date unless date.is_a?(String)
    date = date.squish

     # need raise an error because strings like 16:20.5 can be incorrectly parsed into time
    raise TxnError, "bad date #{date}" if date.match?(BAD_DATE_FORMAT)

    format ? DateTime.strptime(date.gsub(/[T,]/, ' ').squish, format) : DateTime.parse(date)
  end

  def self.split_pair(pair, known_quotes = [])
    pair = pair.upcase.squish

    split = pair.scan(/[a-zA-Z0-9$+]+/) # splits on non-alpha chars ex: BTC-ETH, BTC/ETH, BTC_ETH, BTC ETH, E$P_USDT
    if split.length > 2
      split.reject! { |x| x.start_with?('OLD') } # VEN_OLD/BTC
    elsif split.length == 1 && known_quotes.present?
      known_quotes = known_quotes.sort_by(&:length)

      # this allows matching BATUSD to BAT and USD when both TUSD and USD are in knowns
      known_quotes.reverse! if pair.length > 6

      quote = known_quotes.find { |x| pair.end_with?(x) }
      base = known_quotes.find { |x| pair.start_with?(x) }
      if quote
        split = [pair[0...(-quote.length)], quote]
      elsif base
        split = [base, pair[base.length..-1]]
      elsif pair.length == 6
        split = [pair.first(3), pair.last(3)]
      elsif pair.length == 8
        split = [pair.first(4), pair.last(4)]
      end
    end

    if split.length != 2
      raise TxnError.new("invalid market pair - #{pair}")
    end

    split
  end

  def self.detect_fee_currency(from_amount:, from_currency:, to_amount:, to_currency:, fee_amount:)
    return if [from_amount, to_amount, fee_amount].any? { |amount| amount.clean_d.zero? }

    fee_ratios = [
      { currency: from_currency, ratio: (fee_amount.clean_d / from_amount.clean_d).abs },
      { currency: to_currency, ratio: (fee_amount.clean_d / to_amount.clean_d).abs }
    ]
    # fee should be between 0.01% to 5%
    fee_ratios.select! { |entry| (0.0001..0.05).include?(entry[:ratio]) }
    # select smaller ratio, if the other ratio is bigger than 1%
    big_ratio_present = fee_ratios.any? { |entry| entry[:ratio] > 0.01 }
    fee_ratios.select! { |entry| (0.0001..0.005).include?(entry[:ratio]) } if fee_ratios.size > 1 && big_ratio_present
    # select precise enough ratio
    # e.g. 0.0019999998 or 0.005 ratio is more likely to be fee percent, than 0.00368219283
    fee_ratios.select! { |entry| entry[:ratio].round(4) == entry[:ratio].round(7) } if fee_ratios.size > 1

    fee_ratios[0][:currency] if fee_ratios.size == 1
  end

  # different exchanges store the hash in different formats ex. coinbase
  # doesnt store the 0x part of addresses.
  def self.normalize_hash(txhash)
    return if txhash.blank? || txhash.to_s == '0'
    txhash.to_s.strip.downcase.delete_prefix '0x'
  end
end
