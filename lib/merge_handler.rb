#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require_relative "github_client"
require_relative "issue_manager"
require_relative "task_claimer"
require_relative "output_writer"

module ClaudeGardener
  class MergeHandler
    include OutputWriter

    BASE_LABEL = "claude-gardener"

    def self.run
      new.run
    end

    def initialize
      @github = GithubClient.new
      @issue_manager = IssueManager.new(github: @github)
      @claimer = TaskClaimer.new(issue_manager: @issue_manager)
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

      # Check off the completed item
      complete_linked_item(pr.body)

      # Check for conflicting PRs
      conflicting = find_conflicting_prs
      if conflicting.any?
        puts "Found #{conflicting.length} PRs with potential conflicts: #{conflicting.map(&:number).join(", ")}"
        write_output("conflicting_prs", conflicting.map(&:number).join(","))
      end

      write_output("skipped", "false")
    end

    private

    def complete_linked_item(body)
      aggregate_issue = extract_aggregate_issue(body)
      return unless aggregate_issue

      # Find the item that was claimed by this PR
      issue_body = @issue_manager.get_issue_body(aggregate_issue)
      items = ChecklistParser.parse(issue_body)
      item = items.find { |i| i.claimed_by == @pr_number }
      return unless item

      @claimer.complete_item(
        issue_number: aggregate_issue,
        item_index: item.index,
        note: "merged in PR ##{@pr_number}"
      )
      puts "Checked off item in issue ##{aggregate_issue}"

      # Close the aggregate issue if all items are complete
      updated_body = @issue_manager.get_issue_body(aggregate_issue)
      if ChecklistParser.parse(updated_body).all?(&:checked)
        @issue_manager.close_aggregate_issue(aggregate_issue)
        puts "All items complete. Closed issue ##{aggregate_issue}"
      end
    end

    def extract_aggregate_issue(body)
      match = body&.match(/aggregate_issue:\s*(\d+)/)
      match ? match[1].to_i : nil
    end

    def find_conflicting_prs
      open_prs = @github.pull_requests(state: "open", labels: [BASE_LABEL])

      open_prs.select do |pr|
        mergeable = pr.respond_to?(:mergeable) ? pr.mergeable : nil
        mergeable == false
      end
    end
  end
end

ClaudeGardener::MergeHandler.run if __FILE__ == $PROGRAM_NAME
