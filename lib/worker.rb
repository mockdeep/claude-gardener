#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "config"
require_relative "github_client"
require_relative "issue_manager"
require_relative "task_claimer"
require_relative "output_writer"

module ClaudeGardener
  class Worker
    include OutputWriter

    def self.run
      new.run
    end

    def initialize
      config_path = ENV.fetch("CONFIG_PATH", "claude-gardener.yml")
      workspace = ENV.fetch("GITHUB_WORKSPACE", Dir.pwd)
      full_config_path = File.join(workspace, config_path)

      @config = Config.load(full_config_path)
      @task_json = ENV.fetch("TASK")
      @github = GithubClient.new
      @issue_manager = IssueManager.new(github: @github)
      @claimer = TaskClaimer.new(issue_manager: @issue_manager)
    end

    def run
      task = JSON.parse(@task_json)
      issue_number = task["issue"]
      item_index = task["index"]
      category = task["category"]
      item_text = task["text"]

      # Attempt to claim
      item = ChecklistParser::Item.new(
        text: item_text,
        checked: false,
        claimed_by: nil,
        index: item_index
      )

      # We don't have a PR number yet - use a placeholder that will be updated
      # For now, claim with a temporary marker
      body = @issue_manager.get_issue_body(issue_number)
      current_items = ChecklistParser.parse(body)
      current = current_items.find { |i| i.index == item_index }

      if current.nil? || current.checked || current.claimed_by
        puts "Task already claimed or completed. Skipping."
        write_output("skipped", "true")
        return
      end

      prompt = build_work_prompt(category, item_text)

      write_output("skipped", "false")
      write_output("prompt", prompt)
      write_output("category", category)
      write_output("aggregate_issue", issue_number.to_s)
      write_output("item_index", item_index.to_s)
      write_output("item_text", item_text)
    end

    private

    def build_work_prompt(category, item_text)
      base_prompt = load_work_prompt(category)
      docs_context = load_docs_context

      <<~PROMPT
        #{base_prompt}

        ## Your Specific Task

        #{item_text}

        ## Important Guidelines

        - Keep changes focused and minimal
        - Follow existing code conventions
        - Read CLAUDE.md if present for project-specific guidelines
        #{docs_context}

        ## Excluded Paths

        Do not modify files matching these patterns:
        #{@config.excluded_paths.map { |p| "- #{p}" }.join("\n")}

        After making changes, provide a brief summary of what you changed.
      PROMPT
    end

    def load_work_prompt(category)
      prompt_file = File.join(__dir__, "prompts", "#{category}.md")

      if File.exist?(prompt_file)
        File.read(prompt_file)
      else
        "You are improving the codebase in the area of: #{category}"
      end
    end

    def load_docs_context
      docs_dir = File.join(ENV.fetch("GITHUB_WORKSPACE", Dir.pwd), "docs")
      return "" unless Dir.exist?(docs_dir)

      docs = Dir.glob(File.join(docs_dir, "**/*.md")).first(5)
      return "" if docs.empty?

      context = "\n## Project Documentation\n\nRelevant docs found in `docs/`:\n"
      docs.each do |doc|
        relative = doc.sub("#{ENV.fetch("GITHUB_WORKSPACE", Dir.pwd)}/", "")
        context += "- `#{relative}`\n"
      end
      context + "\nRead these if they're relevant to your task."
    end
  end
end

ClaudeGardener::Worker.run if __FILE__ == $PROGRAM_NAME
