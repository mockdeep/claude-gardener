#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "github_client"
require_relative "output_writer"

module ClaudeGardener
  class ReviewHandler
    include OutputWriter

    BASE_LABEL = "claude-gardener"

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

      comments = @github.review_comments(@pr_number)
      if comments.empty?
        puts "No review comments on PR ##{@pr_number}. Skipping."
        write_output("skipped", "true")
        return
      end

      prompt = build_review_prompt(pr, comments)

      write_output("skipped", "false")
      write_output("prompt", prompt)
      write_output("branch", pr.head.ref)
      write_output("category", extract_category(pr.body))
    end

    private

    def build_review_prompt(pr, comments)
      comment_text = comments.map do |c|
        "**#{c.path}:#{c.line || "general"}** - #{c.body}"
      end.join("\n\n")

      <<~PROMPT
        You are addressing review comments on a pull request.

        ## PR Title
        #{pr.title}

        ## Review Comments

        #{comment_text}

        ## Instructions

        1. Read and understand each review comment
        2. Make the requested changes
        3. If a comment asks a question, make a best judgment on the fix
        4. Keep changes focused on what reviewers asked for
        5. Do not make additional unrelated changes
      PROMPT
    end

    def extract_category(body)
      match = body&.match(/category:\s*(\w+)/)
      match ? match[1] : "unknown"
    end
  end
end

ClaudeGardener::ReviewHandler.run if __FILE__ == $PROGRAM_NAME
