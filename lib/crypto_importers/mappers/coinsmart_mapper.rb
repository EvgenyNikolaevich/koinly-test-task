class CoinsmartMapper < BaseMapper
  tag Tag::COINSMART
  mappings [
    {
      id: 'coinsmart-transactions',
      required_headers: %w[Transaction\ Type Reference\ Type Product Balance Time\ Stamp],
      optional_headers: %w[Debit Debits Credit Credits],
      header_mappings: {
        date: 'Time Stamp',
        from_amount: %w[Debit Debits],
        to_amount: %w[Credit Credits]
      },
      group: {
        by_hash: ->(_mapped, row) { row['Time Stamp'] },
        eligible: ->(_mapped, row) { row['Transaction Type'].match?(/trade|fee/i) },
      }
    }
  ]

  def parse_row(mapped_row, raw_row, options)
    currency, ref_type = raw_row.values_at('Product', 'Reference Type')
    from_amount = from_amount(raw_row)
    to_amount   = to_amount(raw_row)

    if ref_type.match?(/deposit/i)
      mapped_row[:to_currency] = currency
    elsif ref_type.match?(/withdraw/i)
      mapped_row[:from_currency] = currency
    elsif ref_type.match?(/fee/i)
      mapped_row[:fee_currency] = currency
      mapped_row[:fee_amount] = from_amount || to_amount
    else
      mapped_row.merge!(from_currency: currency) if from_amount
      mapped_row.merge!(to_currency: currency) if to_amount
    end

    mapped_row
  end

  def from_amount(row)
    row.select { |header| header.match?(/debit/i) }
       .values
       .first
  end

  def to_amount(row)
    row.select { |header| header.match?(/credit/i) }
       .values
       .first
  end
end
