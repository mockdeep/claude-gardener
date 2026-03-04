# frozen_string_literal: true

require_relative "checklist_parser"
require_relative "issue_manager"

module ClaudeGardener
  class TaskClaimer
    def initialize(issue_manager:)
      @issue_manager = issue_manager
    end

    def claim_next(pr_number:, aggregate_issues:)
      aggregate_issues.each do |issue|
        body = @issue_manager.get_issue_body(issue.number)
        unclaimed = ChecklistParser.unclaimed_items(body)
        next if unclaimed.empty?

        item = unclaimed.first
        result = claim_item(
          issue_number: issue.number,
          item: item,
          pr_number: pr_number
        )
        return result if result
      end

      nil
    end

    def claim_item(issue_number:, item:, pr_number:)
      body = @issue_manager.get_issue_body(issue_number)

      # Re-check the item is still unclaimed (race condition guard)
      current_items = ChecklistParser.parse(body)
      current = current_items.find { |i| i.index == item.index }
      return nil if current.nil? || current.checked || current.claimed_by

      updated = ChecklistParser.claim_item(body, line_index: item.index, pr_number: pr_number)
      @issue_manager.update_issue_body(issue_number, updated)

      ClaimedTask.new(
        issue_number: issue_number,
        item_index: item.index,
        text: item.text
      )
    end

    def complete_item(issue_number:, item_index:, note: nil)
      body = @issue_manager.get_issue_body(issue_number)
      updated = ChecklistParser.check_item(body, line_index: item_index, note: note)
      @issue_manager.update_issue_body(issue_number, updated)
    end
  end

  ClaimedTask = Struct.new(:issue_number, :item_index, :text, keyword_init: true)
end
