#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

require_relative "orchestrator"
require_relative "config"

module ClaudeGardener
  class Error < StandardError; end

  class << self
    def run(event_type:, config_path:, category: "auto")
      config = Config.load(config_path)
      event_data = load_event_data

      orchestrator = Orchestrator.new(
        config: config,
        event_type: event_type,
        event_data: event_data,
        category: category
      )

      orchestrator.run
    end

    private

    def load_event_data
      event_path = ENV.fetch("GITHUB_EVENT_PATH", nil)
      return {} unless event_path && File.exist?(event_path)

      JSON.parse(File.read(event_path))
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  event_type = ARGV[0] || "workflow_dispatch"
  config_path = ARGV[1] || "claude-gardener.yml"
  category = ARGV[2] || "auto"

  ClaudeGardener.run(
    event_type: event_type,
    config_path: config_path,
    category: category
  )
end
