# frozen_string_literal: true

module ClaudeGardener
  class IssueManager
    PLAN_LABEL = "claude-gardener:plan"
    SCAN_LABEL_PREFIX = "claude-gardener:scan"

    def initialize(github:)
      @github = github
    end

    def find_plan_issue
      issues = @github.list_issues(state: "open", labels: [PLAN_LABEL])
      issues.first
    end

    def create_plan_issue(categories:)
      checklist = categories.map { |c| "- [ ] #{c}" }.join("\n")
      body = <<~MD
        ## Gardener Scan Plan

        The following categories will be scanned for work items:

        #{checklist}

        ---
        *Managed by [Claude Gardener](https://github.com/mockdeep/claude-gardener)*
      MD

      @github.create_issue(
        title: "[Gardener] Scan Plan",
        body: body,
        labels: [PLAN_LABEL]
      )
    end

    def find_aggregate_issues(category: nil)
      label = category ? "#{SCAN_LABEL_PREFIX}:#{category}" : SCAN_LABEL_PREFIX
      @github.list_issues(state: "open", labels: [label])
    end

    def create_aggregate_issue(category:, items:)
      label = "#{SCAN_LABEL_PREFIX}:#{category}"
      checklist = items.map { |item| "- [ ] #{item}" }.join("\n")
      body = <<~MD
        ## #{category.tr("_", " ").capitalize} - Work Items

        #{checklist}

        ---
        <!-- gardener-metadata
        category: #{category}
        created: #{Time.now.utc.iso8601}
        -->
        *Managed by [Claude Gardener](https://github.com/mockdeep/claude-gardener)*
      MD

      @github.create_issue(
        title: "[Gardener] #{category.tr("_", " ").capitalize} scan results",
        body: body,
        labels: [label]
      )
    end

    def close_aggregate_issue(number, replaced_by: nil)
      comment = if replaced_by
        "Closing: replaced by ##{replaced_by}"
      else
        "Closing: all items completed or superseded."
      end
      @github.add_comment(number, comment)
      @github.close_issue(number)
    end

    def update_issue_body(number, body)
      @github.update_issue(number, body: body)
    end

    def get_issue_body(number)
      issue = @github.issue(number)
      issue.body
    end

    def add_comment(number, body)
      @github.add_comment(number, body)
    end
  end
end
