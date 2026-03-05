#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "config"
require_relative "github_client"
require_relative "issue_manager"
require_relative "output_writer"

module ClaudeGardener
  class ScanPlanner
    include OutputWriter

    def self.run
      new.run
    end

    def initialize
      config_path = ENV.fetch("CONFIG_PATH", "claude-gardener.yml")
      workspace = ENV.fetch("GITHUB_WORKSPACE", Dir.pwd)
      full_config_path = File.join(workspace, config_path)

      @config = Config.load(full_config_path)
      @github = GithubClient.new
      @issue_manager = IssueManager.new(github: @github)
    end

    def run
      existing = @issue_manager.find_plan_issue
      if existing
        puts "Closing existing plan issue ##{existing.number}"
        @issue_manager.close_aggregate_issue(existing.number)
      end

      categories = @config.enabled_categories
      issue = @issue_manager.create_plan_issue(categories: categories)

      puts "Created scan plan issue ##{issue.number} with #{categories.length} categories"
      write_output("skipped", "false")
      write_output("plan_issue", issue.number.to_s)
      write_output("categories", JSON.generate(categories))
    end
  end
end

ClaudeGardener::ScanPlanner.run if __FILE__ == $PROGRAM_NAME
