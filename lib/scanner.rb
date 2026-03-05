#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "config"
require_relative "github_client"
require_relative "issue_manager"
require_relative "checklist_parser"
require_relative "output_writer"

module ClaudeGardener
  class Scanner
    include OutputWriter

    def self.run
      new.run
    end

    def self.post_scan
      new.post_scan
    end

    def initialize
      config_path = ENV.fetch("CONFIG_PATH", "claude-gardener.yml")
      workspace = ENV.fetch("GITHUB_WORKSPACE", Dir.pwd)
      full_config_path = File.join(workspace, config_path)

      @config = Config.load(full_config_path)
      @category = ENV.fetch("CATEGORY")
      @plan_issue = ENV.fetch("PLAN_ISSUE", nil)
      @github = GithubClient.new
      @issue_manager = IssueManager.new(github: @github)
    end

    def run
      prompt = load_scan_prompt
      excluded = @config.excluded_paths.map { |p| "- #{p}" }.join("\n")

      full_prompt = <<~PROMPT
        #{prompt}

        ## Excluded Paths

        Do not analyze files matching these patterns:
        #{excluded}
      PROMPT

      write_output("prompt", full_prompt)
      write_output("category", @category)
    end

    def post_scan
      claude_output = ENV.fetch("CLAUDE_OUTPUT", "")

      if claude_output.strip.empty?
        puts "No scan output from Claude. Skipping."
        write_output("skipped", "true")
        return
      end

      items = ChecklistParser.parse(claude_output)
      if items.empty?
        puts "No checklist items found in scan output. Skipping."
        write_output("skipped", "true")
        return
      end

      item_texts = items.map(&:text)

      # Close old aggregate issues for this category
      old_issues = @issue_manager.find_aggregate_issues(category: @category)

      # Create new aggregate issue
      new_issue = @issue_manager.create_aggregate_issue(
        category: @category,
        items: item_texts
      )

      old_issues.each do |old|
        @issue_manager.close_aggregate_issue(old.number, replaced_by: new_issue.number)
      end

      # Check off the plan issue item if provided
      check_off_plan_item if @plan_issue

      puts "Created aggregate issue ##{new_issue.number} with #{item_texts.length} items"
      write_output("skipped", "false")
      write_output("aggregate_issue", new_issue.number.to_s)
    end

    private

    def load_scan_prompt
      prompt_file = File.join(__dir__, "prompts", "scan", "#{@category}.md")

      if File.exist?(prompt_file)
        File.read(prompt_file)
      else
        <<~PROMPT
          Scan this codebase for improvements in the area of: #{@category}

          Output a markdown checklist of specific, actionable work items.
          Each item should be completable in a single PR.
          Do not include more than 10 items.
        PROMPT
      end
    end

    def check_off_plan_item
      body = @issue_manager.get_issue_body(@plan_issue.to_i)
      items = ChecklistParser.parse(body)
      item = items.find { |i| i.text.strip == @category }
      return unless item

      updated = ChecklistParser.check_item(body, line_index: item.index)
      @issue_manager.update_issue_body(@plan_issue.to_i, updated)
    end
  end
end

ClaudeGardener::Scanner.run if __FILE__ == $PROGRAM_NAME
