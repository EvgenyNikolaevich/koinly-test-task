NilClass.class_eval do
  # this method only comes with bigdecimal 2.0.0 but this version of bigd has
  # deprecated BigDecimal.new which causes other gems to break...
  def to_d
    BigDecimal(0)
  end

  def clean_d(comma_as_decimal = false)
    to_d
  end

  def to_boolean
    false
  end
end

Float.class_eval do
  def clean_d(comma_as_decimal = false)
    to_d
  end

  def to_boolean
    self != 0
  end

  # to keep behaviour before fixing bug in BigDecimal gem
  # https://github.com/ruby/bigdecimal/issues/185#issuecomment-817761008
  def to_d(precision = Float::DIG)
    BigDecimal(self, precision)
  end
end

Integer.class_eval do
  def clean_d(comma_as_decimal = false)
    to_d
  end

  def to_boolean
    self != 0
  end
end

BigDecimal.class_eval do
  def clean_d(comma_as_decimal = false)
    to_d
  end

  def to_boolean
    self != 0
  end
end

class TrueClass
  def to_boolean
    true
  end

  def to_i
    1
  end
end

class FalseClass
  def to_boolean
    false
  end

  def to_i
    0
  end
end

String.class_eval do
  def clean_d(comma_as_decimal = false)
    return to_d if blank?
    cleaned = self.dup
    cleaned.gsub!('−', '-') if self[0].ord == 8722 # replaces the ascii minus sign with actual minus sign
    cleaned.gsub!(',', '.') if !cleaned.include?('.') && comma_as_decimal
    cleaned.sub!('.', '') while cleaned.count('.') > 1 # 7.456.12345687
    cleaned.gsub!(/\.$/, '') # if it ends with a dot ex. 5.
    # -$1,012.13
    # -55e5
    # 1e-5 USD
    # 89.612179480 Interzone
    cleaned.gsub!(/([A-Za-z ][A-Za-z ]+)/, '') # replace 'e' or 'E' if they occur in a sequence of at least 2 letters
    cleaned.gsub!(/[^-0-9.eE]/, '') # replace anything thats not the characters in the square brackets
    return 0.to_d if cleaned.downcase.count('e') > 1 # multiple scientific notations means sth is wrong (maybe not an integer)
    return 0.to_d if cleaned.match(/e([0-9]+)/i).to_a.second.to_i > 100 # very high scientific notations can cause oom
    cleaned.to_d
  end

  def to_boolean
    !%w[0 f false off].include?(downcase)
  end
end
