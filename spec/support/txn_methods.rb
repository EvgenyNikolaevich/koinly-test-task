module TxnMethods
  def dump_txns(formatter)
    reset_dump_folder
    dump_txns_to_file(formatter.txns)
    dump_entries_to_file(formatter.entries)
    puts "Transactions are dumped to #{dump_folder}"
  end

  def dump_payload(file_name, payload)
    path = "./#{file_name}.json"
    File.write(path, JSON.pretty_generate(payload)) unless File.exist?(path)
    puts "Payload is dumped to #{path}"
  end

  def dump_folder
    base = "./dump"
    if ENV['DUMP'].present? && ENV['DUMP'].to_i.to_s != ENV['DUMP'] && !%w[true false].include?(ENV['DUMP'])
      base += "_#{ENV['DUMP']}"
    end
    base
  end

  def reset_dump_folder
    FileUtils.rm_rf(dump_folder)
    FileUtils.mkdir_p(dump_folder)
  end

  def dump_txns_to_file(txns)
    fields = %i[
      date type from_amount from_currency to_amount to_currency fee_amount fee_currency label
      net_worth_amount net_worth_currency fee_worth_amount fee_worth_currency description txhash txsrc txdest
      importer_tag is_margin
    ].freeze

    values = txns.sort_by(&:date).map do |txn|
      {
        date: txn.date,
        type: txn.type,
        from_amount: txn.from_amount.nonzero?,
        from_currency: txn.from_currency&.humanize,
        to_amount: txn.to_amount.nonzero?,
        to_currency: txn.to_currency&.humanize,
        fee_amount: txn.fee_amount.nonzero?,
        fee_currency: txn.fee_currency&.humanize,
        label: txn.label,
        net_worth_amount: txn.net_worth_amount.to_d.nonzero?,
        net_worth_currency: txn.net_worth_currency&.humanize,
        fee_worth_amount: txn.fee_worth_amount.to_d.nonzero?,
        fee_worth_currency: txn.fee_worth_currency&.humanize,
        description: txn.description,
        txhash: txn.txhash,
        txsrc: txn.txsrc,
        txdest: txn.txdest,
        importer_tag: txn.importer_tag,
        is_margin: txn.margin?,
      }
    end.map{ |x| x.values_at(*fields) }

    by_day = []
    txns.group_by{ |x| x.date.beginning_of_day.to_s }.each do |date, txns|
      by_day << ""
      by_day << date.to_datetime.strftime("%Y-%m-%d")
      txns.each do |txn|
        by_day << txn.prettify
      end
    end
    IO.write("#{dump_folder}/transactions.txt", by_day.join("\n"))
    IO.write("#{dump_folder}/transactions.csv", ([fields.join(',')] + values.map{ |x| x.join(",") }).join("\n"))
  end

  def dump_entries_to_file(entries)
    fields = %i[date amount balance fee external_id txhash]
    entries.group_by { _1[:ledger] }.each do |(symbol, values)|
      balance = 0
      values = values.sort_by { _1[:date] }.map { _1.merge(balance: (balance += _1[:amount])).values_at(*fields) }
      IO.write("#{dump_folder}/#{symbol.gsub(/[^\w]+/, '_')}.csv", ([fields.join(',')] + values.map{ |x| x.join(",") }).join("\n"))
    end
  end
end

RSpec.configure do |config|
  config.include TxnMethods
  config.extend TxnMethods
end
