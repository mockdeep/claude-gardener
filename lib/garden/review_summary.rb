# frozen_string_literal: true

module Garden
  # Reads the summary.md that the garden-review skill writes.
  class ReviewSummary
    DECISIONS = %w[approve reject retry skip].freeze

    attr_reader :decision, :reason, :text

    # A blank summary (decision nil) when the file is missing.
    def self.read(path)
      new(File.exist?(path) ? File.read(path) : nil)
    end

    def initialize(text)
      @text = text
      return unless text

      decision = text[/\*\*Suggested decision:\*\*\s*`?(\w+)/i, 1]&.downcase
      @decision = decision if DECISIONS.include?(decision)
      reason = text[/\*\*Reason:\*\*\s*(.+?)(?=\n\s*\n|\n#|\z)/m, 1]
      @reason = reason&.gsub(/\s+/, " ")&.strip
    end

    def present? = !text.nil?
  end
end
