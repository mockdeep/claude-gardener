#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require_relative "github_client"
require_relative "output_writer"

module ClaudeGardener
  class BuildHandler
    include OutputWriter

    BASE_LABEL = "claude-gardener"
    MAX_FIX_ATTEMPTS = 3

    def self.run
      new.run
    end

    def initialize
      @github = GithubClient.new
      @pr_number = ENV.fetch("PR_NUMBER").to_i
    end

    def run
      pr = @github.pull_request(@pr_number)
      pr_labels = pr.labels.map(&:name)

      unless pr_labels.include?(BASE_LABEL)
        puts "PR ##{@pr_number} is not a gardener PR. Skipping."
        write_output("skipped", "true")
        return
      end

      attempt = current_fix_attempt(pr.body)
      if attempt >= MAX_FIX_ATTEMPTS
        puts "PR ##{@pr_number} has exceeded #{MAX_FIX_ATTEMPTS} fix attempts. Skipping."
        @github.add_comment(@pr_number, "Build fix attempts exhausted (#{MAX_FIX_ATTEMPTS}/#{MAX_FIX_ATTEMPTS}). Needs human intervention.")
        write_output("skipped", "true")
        return
      end

      failure_log = ENV.fetch("FAILURE_LOG", "Build failed. Check the Actions tab for details.")
      prompt = build_fix_prompt(pr, failure_log, attempt + 1)

      write_output("skipped", "false")
      write_output("prompt", prompt)
      write_output("branch", pr.head.ref)
      write_output("category", extract_category(pr.body))
      write_output("fix_attempt", (attempt + 1).to_s)
    end

    private

    def build_fix_prompt(pr, failure_log, attempt)
      <<~PROMPT
        You are fixing a build failure on a pull request (attempt #{attempt}/#{MAX_FIX_ATTEMPTS}).

        ## PR Title
        #{pr.title}

        ## Build Failure

        ```
        #{failure_log}
        ```

        ## Instructions

        1. Analyze the build failure output
        2. Identify the root cause
        3. Make the minimal fix needed
        4. Run tests locally to verify if possible
        5. Do not make unrelated changes
      PROMPT
    end

    def current_fix_attempt(body)
      match = body&.match(/fix_attempts:\s*(\d+)/)
      match ? match[1].to_i : 0
    end

    def extract_category(body)
      match = body&.match(/category:\s*(\w+)/)
      match ? match[1] : "unknown"
    end
  end
end

ClaudeGardener::BuildHandler.run if __FILE__ == $PROGRAM_NAME
