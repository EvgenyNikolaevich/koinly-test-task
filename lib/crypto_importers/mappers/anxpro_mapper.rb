class AnxproMapper < BaseMapper
  tag Tag::ANXPRO
  mappings [
    {
      id: 'anxpro-transactions',
      required_headers: ["Processed Date Time","Method","Amount","Currency","Status","Fee","Additional Information"]
    },
    # new way:
    # {
    #       id: 'anxpro-transactions',
    #       required_headers: ["Processed Date Time","Method","Amount","Currency","Status","Fee","Additional Information"],
    #       header_mappings: {
    #         date: 'Processed Date Time',
    #         amount: 'Amount',
    #         currency: 'Currency',
    #       },
    #       group: {
    #         by_hash: ->(mapped, row) { row['Processed Date Time'] },
    #         eligible: ->(mapped, row) { row['Method'] == 'Order Fill' },
    #       }
    #     }
  ]

  def fetch_rows(header, spreadsheet)
    rows = super
    trades = {}
    new_rows = rows.map do |row|
      mapped_row = {
        date: row['Processed Date Time'],
        external_data: row,
      }

      mapped_row.merge!(to_amount: row['Amount'], to_currency: row['Currency']) if row['Amount'].clean_d > 0
      mapped_row.merge!(from_amount: row['Amount'], from_currency: row['Currency']) if row['Amount'].clean_d < 0

      case row['Method']
      when 'Order Fill'
        trades[mapped_row[:date]] ||= {}
        trades[mapped_row[:date]].merge!(mapped_row)
        mapped_row = nil
      else
        mapped_row.merge!(currency: row['Currency'], amount: row['Amount'])
      end

      mapped_row
    end.compact

    new_rows + trades.values
  end

  def parse_row(mapped_row, raw_row, _)
    raw_row
  end
end
