class CsvAdapter < BaseAdapter
  STATES = [
    PROCESSING_FAILED = "processing_failed",
    FAILED = "failed",
    ENTER_MAPPING_ID = "enter_mapping_id",
    ENTER_REQUIRED_OPTIONS = "enter_required_options",
    UNKNOWN_CSV = "unknown_csv",
    COMPLETED = "completed"
  ]

  attr_reader :initialized_at, :pending_txns, :csv_import_id

  def initialize(options)
    super
    @csv_import_id = options[:csv_import_id]
  end

  def set_initial_rows(initial_rows)
    @initial_rows = initial_rows
  end

  def set_mapping_id(mapping_id)
    @mapping_id = mapping_id
  end

  def commit!(state, error: nil, required_options: nil, mappers: nil, results: nil, exception: nil)
    payload = {
      'id' => request_id,
      'csv_import_id' => csv_import_id,
      'started_at' => initialized_at,
      'finished_at' => Time.now,
      'initial_rows' => @initial_rows,
      'state' => state,
      'txns' => pending_txns.map(&:serializable_hash),
      'error' => error,
      'required_options' => required_options,
      'potential_mappers' => mappers,
      'mapping_id' => @mapping_id,
      'results' => results,
      'exception' => exception,
    }
    publish('job.finished.csv_import', payload, content_type: 'application/json+br')

    pending_txns.clear

    payload
  end
end
