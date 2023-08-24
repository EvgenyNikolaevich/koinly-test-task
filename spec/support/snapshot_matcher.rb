RSpec::Matchers.define :match_snapshot do |filename|
  match do |data|
    data = JSON.parse(data.to_json) # this normalizes it
    path = filename.start_with?('/') ? filename : "#{Dir.pwd}/spec/fixtures/snapshots/#{filename}.json"
    unless File.exist?(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(data))
      puts "Generated snapshot file: #{path}"
    end

    @actual = data
    @expected = JSON.parse(File.read(path))

    if @actual != @expected && ENV['OVERRIDE']
      File.write(path, JSON.pretty_generate(data))
      puts "Overrided: #{path}"
      return true
    end

    @actual == @expected
  end

  failure_message do |actual|
    message = "expected that #{@actual.to_s} to match snapshot #{filename}.json"
    if @actual.is_a?(Array) && @expected.is_a?(Array)
      if @actual.count != @expected.count
        message += "\nDiff: #{@actual.count} rows vs #{@expected.count} expected rows"
      else
        @actual.each.with_index do |line, idx|
          other_line = @expected[idx]
          if line.is_a?(Array) && other_line.is_a?(Array)
            if line.join(', ') != other_line.join(', ')
              message += "\nDiff on line #{idx}: \n\t  #{line.join(', ')}\n\t  #{other_line.join(', ')} \t-> expected"
            end
          else
            diff = differ.diff(line, other_line)
            if diff.present?
              message += "\nDiff on line #{idx}: " + diff
            end
          end
        end
      end
    else
      message += "\nDiff:" + differ.diff(@actual, @expected)
    end
    message
  end

  def differ
    RSpec::Support::Differ.new(
      :object_preparer => lambda { |object| RSpec::Matchers::Composable.surface_descriptions_in(object) },
      :color => RSpec::Matchers.configuration.color?
    )
  end
end
