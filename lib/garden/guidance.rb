# frozen_string_literal: true

module Garden
  # General lessons from past reviews: every .md file in the guidance folder.
  class Guidance
    def initialize(dir = Paths.guidance_dir)
      @dir = dir
    end

    # A prompt section, or nil when there's no guidance yet.
    def section
      files = Dir[File.join(@dir, "*.md")]
      return if files.empty?

      parts = files.map { |f| "### #{File.basename(f, '.md')}\n\n#{File.read(f).strip}\n" }
      "## Guidance\n\nFollow this guidance from past reviews.\n\n#{parts.join("\n")}"
    end
  end
end
