# frozen_string_literal: true

module ClaudeGardener
  class PrManager
    LABEL_COLORS = {
      "claude-gardener" => "1d76db",
      "claude-gardener:test_coverage" => "0e8a16",
      "claude-gardener:security_fixes" => "d93f0b",
      "claude-gardener:linter_fixes" => "fbca04",
      "claude-gardener:code_improvements" => "c5def5",
      "needs-human" => "e99695"
    }.freeze

    LABEL_DESCRIPTIONS = {
      "claude-gardener" => "PR created by Claude Gardener",
      "needs-human" => "Gardener PR that needs human intervention"
    }.freeze

    def initialize(github:, config:)
      @github = github
      @config = config
    end

    def open_gardener_prs
      @github.pull_requests(state: "open", labels: [@config.labels.base])
    end

    def open_prs_for_category(category)
      labels = @config.labels.for_category(category)
      @github.pull_requests(state: "open", labels: labels)
    end

    def create_pr(branch:, category:, title:, body:)
      ensure_labels_exist(category)

      full_body = build_pr_body(body, category)

      pr = @github.create_pull_request(
        base: @github.default_branch,
        head: branch,
        title: "[Gardener] #{title}",
        body: full_body
      )

      labels = @config.labels.for_category(category)
      @github.add_labels(pr.number, labels)

      pr
    end

    def add_label(pr_number, label)
      ensure_label_exists(label)
      @github.add_labels(pr_number, [label])
    end

    def add_comment(pr_number, body)
      @github.add_comment(pr_number, body)
    end

    def update_metadata(pr_number, tracker)
      pr = @github.pull_request(pr_number)
      existing_body = pr.body

      new_body = tracker.update_metadata_in_body(existing_body)

      # Note: Octokit doesn't have update_pull_request, use the API directly
      # For now, we'll add a comment instead
      add_comment(pr_number, "Iteration #{tracker.iterations} completed.")
    end

    private

    def ensure_labels_exist(category)
      labels = @config.labels.for_category(category)
      labels.each { |label| ensure_label_exists(label) }
    end

    def ensure_label_exists(label)
      color = LABEL_COLORS[label] || "ededed"
      description = LABEL_DESCRIPTIONS[label]
      @github.ensure_label_exists(label, color: color, description: description)
    end

    def build_pr_body(body, category)
      metadata = build_metadata(category)

      <<~BODY
        #{body}

        ---

        #{metadata}

        🤖 *This PR was created by [Claude Gardener](https://github.com/mockdeep/claude-gardener)*
      BODY
    end

    def build_metadata(category)
      <<~METADATA
        <!-- gardener-metadata
        iteration: 1
        category: #{category}
        started: #{Time.now.utc.iso8601}
        -->
      METADATA
    end
  end
end
