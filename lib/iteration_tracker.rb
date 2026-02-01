# frozen_string_literal: true

module ClaudeGardener
  class IterationTracker
    METADATA_PATTERN = /<!--\s*gardener-metadata\n(.+?)\n-->/m

    attr_reader :iterations, :category, :started

    def initialize(pr)
      @pr = pr
      parse_metadata(pr.body)
    end

    def increment
      @iterations += 1
    end

    def update_metadata_in_body(body)
      new_metadata = build_metadata

      if body =~ METADATA_PATTERN
        body.gsub(METADATA_PATTERN, new_metadata)
      else
        "#{body}\n\n#{new_metadata}"
      end
    end

    private

    def parse_metadata(body)
      match = body&.match(METADATA_PATTERN)

      if match
        metadata_content = match[1]
        data = parse_yaml_like(metadata_content)

        @iterations = data["iteration"]&.to_i || 1
        @category = data["category"]
        @started = data["started"]
      else
        @iterations = 1
        @category = nil
        @started = Time.now.utc.iso8601
      end
    end

    def parse_yaml_like(content)
      data = {}
      content.each_line do |line|
        if line =~ /^(\w+):\s*(.+)$/
          data[::Regexp.last_match(1)] = ::Regexp.last_match(2).strip
        end
      end
      data
    end

    def build_metadata
      <<~METADATA
        <!-- gardener-metadata
        iteration: #{@iterations}
        category: #{@category}
        started: #{@started}
        -->
      METADATA
    end
  end
end
