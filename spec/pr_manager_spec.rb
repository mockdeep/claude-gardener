# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::PrManager do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:config) { instance_double(ClaudeGardener::Config) }
  let(:labels) { instance_double(ClaudeGardener::Config::Labels) }
  let(:pr_manager) { described_class.new(github: github, config: config) }

  before do
    allow(config).to receive(:labels).and_return(labels)
    allow(github).to receive(:default_branch).and_return("main")
  end

  describe "#create_pr" do
    let(:pr) { instance_double("PR", number: 123) }
    let(:category_labels) { %w[claude-gardener claude-gardener:test_coverage] }
    let(:branch) { "gardener/test-coverage-20240305" }
    let(:title) { "Add tests for user authentication" }
    let(:body) { "This PR adds comprehensive tests for the user authentication module." }

    before do
      allow(labels).to receive(:for_category).with("test_coverage").and_return(category_labels)
      allow(github).to receive(:ensure_label_exists)
      allow(github).to receive(:create_pull_request).and_return(pr)
      allow(github).to receive(:add_labels)
      allow(Time).to receive(:now).and_return(Time.parse("2024-03-05 10:00:00 UTC"))
    end

    it "creates a PR with proper title and body" do
      expected_body = <<~BODY
        #{body}

        ---

        <!-- gardener-metadata
        iteration: 1
        category: test_coverage
        started: 2024-03-05T10:00:00Z
        -->

        🤖 *This PR was created by [Claude Gardener](https://github.com/mockdeep/claude-gardener)*
      BODY

      expect(github).to receive(:create_pull_request).with(
        base: "main",
        head: branch,
        title: "[Gardener] #{title}",
        body: expected_body
      ).and_return(pr)

      result = pr_manager.create_pr(
        branch: branch,
        category: "test_coverage",
        title: title,
        body: body
      )

      expect(result).to eq(pr)
    end

    it "ensures labels exist before creating PR" do
      expect(github).to receive(:ensure_label_exists).with("claude-gardener", color: "1d76db", description: "PR created by Claude Gardener")
      expect(github).to receive(:ensure_label_exists).with("claude-gardener:test_coverage", color: "0e8a16", description: nil)

      pr_manager.create_pr(
        branch: branch,
        category: "test_coverage",
        title: title,
        body: body
      )
    end

    it "adds category labels to the PR" do
      expect(github).to receive(:add_labels).with(123, category_labels)

      pr_manager.create_pr(
        branch: branch,
        category: "test_coverage",
        title: title,
        body: body
      )
    end
  end

  describe "#add_comment" do
    let(:pr_number) { 42 }
    let(:comment_body) { "This is a test comment" }

    it "adds a comment to the specified PR" do
      expect(github).to receive(:add_comment).with(pr_number, comment_body)

      pr_manager.add_comment(pr_number, comment_body)
    end
  end

  describe "#update_metadata" do
    let(:pr_number) { 42 }
    let(:tracker) { instance_double("Tracker", iterations: 2) }
    let(:existing_pr) { instance_double("PR", body: "Original body") }
    let(:updated_body) { "Updated body with metadata" }

    before do
      allow(github).to receive(:pull_request).with(pr_number).and_return(existing_pr)
      allow(tracker).to receive(:update_metadata_in_body).with("Original body").and_return(updated_body)
      allow(github).to receive(:add_comment)
    end

    it "retrieves the PR and updates metadata" do
      expect(github).to receive(:pull_request).with(pr_number)
      expect(tracker).to receive(:update_metadata_in_body).with("Original body")

      pr_manager.update_metadata(pr_number, tracker)
    end

    it "adds a comment about the iteration" do
      expect(github).to receive(:add_comment).with(pr_number, "Iteration 2 completed.")

      pr_manager.update_metadata(pr_number, tracker)
    end
  end

  describe "#add_label" do
    let(:pr_number) { 42 }
    let(:label) { "needs-human" }

    before do
      allow(github).to receive(:ensure_label_exists)
      allow(github).to receive(:add_labels)
    end

    it "ensures the label exists before adding it" do
      expect(github).to receive(:ensure_label_exists).with(label, color: "e99695", description: "Gardener PR that needs human intervention")

      pr_manager.add_label(pr_number, label)
    end

    it "adds the label to the PR" do
      expect(github).to receive(:add_labels).with(pr_number, [label])

      pr_manager.add_label(pr_number, label)
    end

    context "when label is not in predefined colors" do
      let(:unknown_label) { "custom-label" }

      it "uses default color" do
        expect(github).to receive(:ensure_label_exists).with(unknown_label, color: "ededed", description: nil)

        pr_manager.add_label(pr_number, unknown_label)
      end
    end
  end

  describe "label management" do
    describe "LABEL_COLORS constant" do
      it "defines colors for all default labels" do
        expect(described_class::LABEL_COLORS).to include(
          "claude-gardener" => "1d76db",
          "claude-gardener:test_coverage" => "0e8a16",
          "claude-gardener:security_fixes" => "d93f0b",
          "claude-gardener:linter_fixes" => "fbca04",
          "claude-gardener:code_improvements" => "c5def5",
          "needs-human" => "e99695"
        )
      end
    end

    describe "LABEL_DESCRIPTIONS constant" do
      it "defines descriptions for base labels" do
        expect(described_class::LABEL_DESCRIPTIONS).to include(
          "claude-gardener" => "PR created by Claude Gardener",
          "needs-human" => "Gardener PR that needs human intervention"
        )
      end
    end

    describe "#ensure_labels_exist" do
      let(:category_labels) { %w[claude-gardener claude-gardener:security_fixes] }

      before do
        allow(labels).to receive(:for_category).with("security_fixes").and_return(category_labels)
        allow(github).to receive(:ensure_label_exists)
      end

      it "ensures all category labels exist" do
        expect(github).to receive(:ensure_label_exists).with("claude-gardener", color: "1d76db", description: "PR created by Claude Gardener")
        expect(github).to receive(:ensure_label_exists).with("claude-gardener:security_fixes", color: "d93f0b", description: nil)

        pr_manager.send(:ensure_labels_exist, "security_fixes")
      end
    end
  end

  describe "#open_gardener_prs" do
    let(:base_label) { "claude-gardener" }

    before do
      allow(labels).to receive(:base).and_return(base_label)
    end

    it "queries for open PRs with the base label" do
      expect(github).to receive(:pull_requests).with(state: "open", labels: [base_label])

      pr_manager.open_gardener_prs
    end
  end

  describe "#open_prs_for_category" do
    let(:category_labels) { %w[claude-gardener claude-gardener:linter_fixes] }

    before do
      allow(labels).to receive(:for_category).with("linter_fixes").and_return(category_labels)
    end

    it "queries for open PRs with category labels" do
      expect(github).to receive(:pull_requests).with(state: "open", labels: category_labels)

      pr_manager.open_prs_for_category("linter_fixes")
    end
  end
end