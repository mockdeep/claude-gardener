# frozen_string_literal: true

module Garden
  class Error < StandardError; end
end

require_relative "garden/version"
require_relative "garden/paths"
require_relative "garden/registry"
require_relative "garden/finding"
require_relative "garden/state"
require_relative "garden/setup"
require_relative "garden/cli"
