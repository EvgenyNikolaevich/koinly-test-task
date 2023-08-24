class CsvImportStarted
  MIN_ROWS_TO_REPORT_ETA = 1_000

  include CsvProcessor

  def process(payload)
    response = handle_payload(payload)
  end

  private

  def handle_payload(payload)
    wallet = payload['wallet'].symbolize_keys
    csv_import = payload['csv_import'].symbolize_keys
    file_url = csv_import[:file_url]
    max_rows_limit = csv_import[:max_rows_limit]
    options = csv_import[:options].symbolize_keys
    mapping_id = options.delete(:mapping_id)

    adapter = CsvAdapter.new(
      request_id: payload['id'],
      wallet_id: wallet[:id],
      start_date: options[:start_date],
      deposit_label: options[:deposit_label],
      csv_import_id: csv_import[:id],
    )

    begin
      file, file_name, initial_rows, total_rows, file_col_sep, file_row_sep = prepare_and_set_file(file_url)
      adapter.set_initial_rows(initial_rows)
    rescue StandardError => e
      logger.log_error(e)
      return adapter.commit! CsvAdapter::PROCESSING_FAILED, error: 'Error while processing'
    end

    if max_rows_limit && max_rows_limit.to_i < total_rows
      return adapter.commit! CsvAdapter::FAILED, error: "file has too many rows #{total_rows} (max: #{max_rows_limit})"
    end

    mappers = potential_mappers(wallet[:wallet_service_tag], initial_rows, file_name)
    if mappers.blank?
      return adapter.commit! CsvAdapter::UNKNOWN_CSV
    end

    # multiple ids can have the same score
    best_id, best_score = mappers.first
    best_mappers = mappers.select { |_, v| v == best_score }
    if best_mappers.count > 1
      if best_mappers.key?(mapping_id)
        best_id = mapping_id
      else
        return adapter.commit! CsvAdapter::ENTER_MAPPING_ID, mappers: best_mappers.keys
      end
    end


    adapter.set_mapping_id(best_id)

    mapper_klass = all_mappers[best_id].constantize

    mapper = mapper_klass.new(
      adapter,
      best_id,
      deposit_label: options[:deposit_label],
      timezone: options[:timezone],
      currency_id: options[:currency_id],
      wallet_service_tag: wallet[:wallet_service_tag]
    )

    required_options = mapper.mapping[:required_options]&.map(&:to_sym) || []
    if (required_options - options.keys).any?
      return adapter.commit! CsvAdapter::ENTER_REQUIRED_OPTIONS, required_options: required_options
    end

    return adapter.commit! CsvAdapter::FAILED, error: mapper.mapping[:error] if mapper.mapping[:error].present?

    mapper.import_and_commit!(file, file_name, file_col_sep, file_row_sep)
  end

  private

  # returns hash of mapping id to mapping class
  #   "etoro-txns" => EtoroMapper
  def all_mappers
    @all_mappings ||= begin
      mappings = {}
      Module.constants
        .select{ |x| x.to_s.end_with?('Mapper') }
        .map(&:to_s)
        .sort
        .map(&:constantize)
        .select{ |x| x < BaseMapper && x != BaseMapper }
        .each do |klass|
          klass.mappings.each do |mapping|
            if mappings[mapping[:id]]
              raise "duplicate mapping id found: #{mapping[:id]}"
            else
              mappings[mapping[:id]] = klass.to_s
            end
          end
        end
      raise "no mappers found!" if mappings.blank?
      mappings
    end
  end

  # returns hash of mapping ids and their scores with highest scores on top
  #   "etoro-txns" => 2
  #   "blitz-txns" => 1
  def potential_mappers(wallet_tag, initial_rows, file_name)
    all_mappers.inject({}) do |memo, (mapping_id, klass)|
      klass = klass.constantize
      mapping = klass.mappings.find { |x| x[:id] == mapping_id }
      score = klass.confidence_score(initial_rows, file_name, mapping, wallet_tag) || 0
      memo[mapping_id] = score unless score.zero?
      memo
    end.sort_by{ |_, v| -v }.to_h
  end
end
