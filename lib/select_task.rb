#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "config"
require_relative "github_client"
require_relative "task_selector"
require_relative "pr_manager"
require_relative "lock_checker"

module ClaudeGardener
  class SelectTask
    def self.run
      new.run
    end

    def initialize
      config_path = ENV.fetch("CONFIG_PATH", "claude-gardener.yml")
      # Config is in the user's repo, not the action directory
      workspace = ENV.fetch("GITHUB_WORKSPACE", Dir.pwd)
      full_config_path = File.join(workspace, config_path)

      @config = Config.load(full_config_path)
      @category = ENV.fetch("CATEGORY", "auto")
      @github = GithubClient.new
      @pr_manager = PrManager.new(github: @github, config: @config)
      @lock_checker = LockChecker.new(github: @github, config: @config)
      @task_selector = TaskSelector.new(
        config: @config,
        pr_manager: @pr_manager,
        lock_checker: @lock_checker
      )
    end

    def run
      if at_worker_capacity?
        puts "At worker capacity (#{@config.workers.max_concurrent} concurrent PRs). Skipping."
        output_skipped
        return
      end

      task = select_task
      unless task
        puts "No tasks available. All categories at max PRs or no work to do."
        output_skipped
        return
      end

      puts "Selected task: #{task.category}"
      output_task(task)
    end

    private

    def select_task
      if @category == "auto"
        @task_selector.select_next_task
      else
        @task_selector.select_task_for_category(@category)
      end
    end

    def at_worker_capacity?
      open_prs = @pr_manager.open_gardener_prs
      open_prs.count >= @config.workers.max_concurrent
    end

    def output_skipped
      write_output("skipped", "true")
    end

    def output_task(task)
      write_output("skipped", "false")
      write_output("category", task.category)
      write_output("base_label", @config.labels.base)

      # Build the full prompt with constraints
      full_prompt = build_full_prompt(task)
      write_output("prompt", full_prompt)
    end

    def build_full_prompt(task)
      locked_files_list = task.locked_files.to_a
      locked_section = if locked_files_list.any?
        "\n\n## Locked Files (do not modify)\n\n" +
          locked_files_list.map { |f| "- #{f}" }.join("\n")
      else
        ""
      end

      <<~PROMPT
        #{task.prompt}

        ## Important Guidelines

        - Maximum #{@config.guardrails.max_files_per_pr} files per PR
        - #{@config.guardrails.require_tests? ? "Include or update tests for your changes" : "Tests are optional"}
        - Keep changes focused and minimal
        - Follow existing code conventions
        - Read CLAUDE.md if present for project-specific guidelines
        #{locked_section}

        ## Excluded Paths

        Do not modify files matching these patterns:
        #{@config.excluded_paths.map { |p| "- #{p}" }.join("\n")}

        After making changes, provide a brief summary of what you changed.
      PROMPT
    end

    def write_output(name, value)
      output_file = ENV.fetch("GITHUB_OUTPUT", nil)
      if output_file
        # Handle multiline values
        if value.include?("\n")
          delimiter = "EOF_#{rand(1000000)}"
          File.open(output_file, "a") do |f|
            f.puts "#{name}<<#{delimiter}"
            f.puts value
            f.puts delimiter
          end
        else
          File.open(output_file, "a") { |f| f.puts "#{name}=#{value}" }
        end
      else
        puts "#{name}=#{value}"
      end
    end
  end
end

ClaudeGardener::SelectTask.run if __FILE__ == $PROGRAM_NAME
