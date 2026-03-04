#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "config"
require_relative "github_client"
require_relative "issue_manager"
require_relative "pr_manager"
require_relative "checklist_parser"
require_relative "output_writer"

module ClaudeGardener
  class WorkSelector
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
      @pr_manager = PrManager.new(github: @github, config: @config)
    end

    def run
      open_prs = @pr_manager.open_gardener_prs.count
      available_slots = @config.max_concurrent - open_prs

      if available_slots <= 0
        puts "At capacity (#{open_prs}/#{@config.max_concurrent} PRs open). Skipping."
        write_output("skipped", "true")
        write_output("tasks", "[]")
        return
      end

      tasks = collect_tasks(available_slots)

      if tasks.empty?
        puts "No unclaimed work items found."
        write_output("skipped", "true")
        write_output("tasks", "[]")
        return
      end

      puts "Found #{tasks.length} tasks (#{available_slots} slots available)"
      write_output("skipped", "false")
      write_output("tasks", JSON.generate(tasks))
    end

    private

    def collect_tasks(max_tasks)
      tasks = []

      @config.enabled_categories.each do |category|
        break if tasks.length >= max_tasks

        issues = @issue_manager.find_aggregate_issues(category: category)
        issues.each do |issue|
          break if tasks.length >= max_tasks

          body = @issue_manager.get_issue_body(issue.number)
          unclaimed = ChecklistParser.unclaimed_items(body)

          unclaimed.each do |item|
            break if tasks.length >= max_tasks

            tasks << {
              "issue" => issue.number,
              "index" => item.index,
              "category" => category,
              "text" => item.text
            }
          end
        end
      end

      tasks
    end
  end
end

ClaudeGardener::WorkSelector.run if __FILE__ == $PROGRAM_NAME
