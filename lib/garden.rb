# frozen_string_literal: true

module Garden
  class Error < StandardError; end
end

require_relative "garden/version"
require_relative "garden/paths"
require_relative "garden/registry"
require_relative "garden/finding"
require_relative "garden/state"
require_relative "garden/shell"
require_relative "garden/repo"
require_relative "garden/claude"
require_relative "garden/github"
require_relative "garden/guidance"
require_relative "garden/scanner"
require_relative "garden/scan_step"
require_relative "garden/test_commands"
require_relative "garden/fixer"
require_relative "garden/fix_step"
require_relative "garden/review_context"
require_relative "garden/setup"
require_relative "garden/cli"
