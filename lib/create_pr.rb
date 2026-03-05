#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "time"
require_relative "output_writer"

module ClaudeGardener
  class CreatePR
    include OutputWriter

    def self.run
      new.run
    end

    def initialize
      @category = ENV.fetch("CATEGORY")
      @base_label = ENV.fetch("BASE_LABEL", "claude-gardener")
      @repository = ENV.fetch("GITHUB_REPOSITORY")
      @amend = ENV.fetch("AMEND", "false") == "true"
      @aggregate_issue = ENV.fetch("AGGREGATE_ISSUE", nil)
      @item_text = ENV.fetch("ITEM_TEXT", nil)
      @pr_assignees = ENV.fetch("PR_ASSIGNEES", "").split(",").map(&:strip).reject(&:empty?)
      @pr_reviewers = ENV.fetch("PR_REVIEWERS", "").split(",").map(&:strip).reject(&:empty?)
    end

    def run
      # Check if there are any changes
      changes, = Open3.capture2("git", "status", "--porcelain")
      if changes.strip.empty?
        puts "No changes were made by Claude. Skipping PR creation."
        write_output("pr_number", "")
        write_output("pr_url", "")
        return
      end

      if @amend
        amend_and_push
      else
        branch_name = create_branch
        commit_changes
        push_branch(branch_name)
        pr_number, pr_url = create_pull_request(branch_name)

        add_labels(pr_number)

        puts "Created PR ##{pr_number}: #{pr_url}"
        write_output("pr_number", pr_number.to_s)
        write_output("pr_url", pr_url)
      end
    end

    private

    def create_branch
      timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
      branch_name = "gardener/#{@category}/#{timestamp}"

      # Set git identity for commits
      system("git", "config", "user.name", "Claude Gardener")
      system("git", "config", "user.email", "claude-gardener[bot]@users.noreply.github.com")

      system("git", "checkout", "-b", branch_name)
      branch_name
    end

    def commit_changes
      exclude_output_files

      system("git", "add", "-A")

      # Unstage any remaining output files
      system("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")

      commit_message = <<~MSG
        [gardener] #{@category.tr("_", " ").capitalize} improvements

        Automated improvements by Claude Gardener.

        Category: #{@category}
      MSG

      system("git", "commit", "-m", commit_message)
    end

    def amend_and_push
      exclude_output_files

      system("git", "add", "-A")
      system("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")
      system("git", "commit", "--amend", "--no-edit")
      system("git", "push", "--force-with-lease")

      puts "Amended commit and force-pushed."
    end

    def exclude_output_files
      system("git", "checkout", "--", "output.txt") if File.exist?("output.txt")
      system("git", "checkout", "--", "claude-output.txt") if File.exist?("claude-output.txt")
    end

    def push_branch(branch_name)
      system("git", "push", "-u", "origin", branch_name)
    end

    def create_pull_request(branch_name)
      title = "[Gardener] #{@category.tr("_", " ").capitalize} improvements"

      body = build_pr_body

      args = ["gh", "pr", "create", "--title", title, "--body", body, "--head", branch_name]
      @pr_assignees.each { |user| args += ["--assignee", user] }
      @pr_reviewers.each { |user| args += ["--reviewer", user] }

      output, = Open3.capture2(*args)

      # Parse PR URL from output
      pr_url = output.strip
      pr_number = pr_url.split("/").last.to_i

      [pr_number, pr_url]
    end

    def build_pr_body
      issue_ref = if @aggregate_issue
        "\n**Source issue:** ##{@aggregate_issue}"
      else
        ""
      end

      task_ref = if @item_text
        "\n**Task:** #{@item_text}"
      else
        ""
      end

      <<~BODY
        ## Summary

        Automated improvements by Claude Gardener.

        **Category:** #{@category}#{issue_ref}#{task_ref}

        ---

        <!-- gardener-metadata
        iteration: 1
        category: #{@category}
        aggregate_issue: #{@aggregate_issue || "none"}
        started: #{Time.now.utc.iso8601}
        -->

        🤖 *This PR was created by [Claude Gardener](https://github.com/mockdeep/claude-gardener)*
      BODY
    end

    def add_labels(pr_number)
      labels = [@base_label, "#{@base_label}:#{@category}"]

      # Ensure labels exist
      labels.each do |label|
        system("gh", "label", "create", label, "--force", "--color", label_color(label))
      end

      # Add labels to PR
      system("gh", "pr", "edit", pr_number.to_s, "--add-label", labels.join(","))
    end

    def label_color(label)
      colors = {
        "claude-gardener" => "1d76db",
        "claude-gardener:test_coverage" => "0e8a16",
        "claude-gardener:security_fixes" => "d93f0b",
        "claude-gardener:linter_fixes" => "fbca04",
        "claude-gardener:code_improvements" => "c5def5"
      }
      colors[label] || "ededed"
    end
  end
end

ClaudeGardener::CreatePR.run if __FILE__ == $PROGRAM_NAME
