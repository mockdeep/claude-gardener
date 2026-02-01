#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

module ClaudeGardener
  class CreatePR
    def self.run
      new.run
    end

    def initialize
      @category = ENV.fetch("CATEGORY")
      @base_label = ENV.fetch("BASE_LABEL", "claude-gardener")
      @repository = ENV.fetch("GITHUB_REPOSITORY")
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

      branch_name = create_branch
      commit_changes(branch_name)
      push_branch(branch_name)
      pr_number, pr_url = create_pull_request(branch_name)

      add_labels(pr_number)

      puts "Created PR ##{pr_number}: #{pr_url}"
      write_output("pr_number", pr_number.to_s)
      write_output("pr_url", pr_url)
    end

    private

    def create_branch
      timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
      branch_name = "gardener/#{@category}/#{timestamp}"

      system("git", "checkout", "-b", branch_name)
      branch_name
    end

    def commit_changes(branch_name)
      system("git", "add", "-A")

      commit_message = <<~MSG
        [gardener] #{@category.tr("_", " ").capitalize} improvements

        Automated improvements by Claude Gardener.

        Category: #{@category}
      MSG

      system("git", "commit", "-m", commit_message)
    end

    def push_branch(branch_name)
      system("git", "push", "-u", "origin", branch_name)
    end

    def create_pull_request(branch_name)
      title = "[Gardener] #{@category.tr("_", " ").capitalize} improvements"

      body = <<~BODY
        ## Summary

        Automated improvements by Claude Gardener.

        **Category:** #{@category}

        ---

        <!-- gardener-metadata
        iteration: 1
        category: #{@category}
        started: #{Time.now.utc.iso8601}
        -->

        🤖 *This PR was created by [Claude Gardener](https://github.com/mockdeep/claude-gardener)*
      BODY

      output, = Open3.capture2(
        "gh", "pr", "create",
        "--title", title,
        "--body", body,
        "--head", branch_name
      )

      # Parse PR URL from output
      pr_url = output.strip
      pr_number = pr_url.split("/").last.to_i

      [pr_number, pr_url]
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

    def write_output(name, value)
      output_file = ENV.fetch("GITHUB_OUTPUT", nil)
      if output_file
        File.open(output_file, "a") { |f| f.puts "#{name}=#{value}" }
      else
        puts "#{name}=#{value}"
      end
    end
  end
end

ClaudeGardener::CreatePR.run if __FILE__ == $PROGRAM_NAME
