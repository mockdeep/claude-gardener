# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::PrManager do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:config) { instance_double(ClaudeGardener::Config) }
  let(:labels) { instance_double(ClaudeGardener::Config::Labels) }

  subject(:pr_manager) { described_class.new(github: github, config: config) }

  before do
    allow(config).to receive(:labels).and_return(labels)
  end

  describe "#open_gardener_prs" do
    it "returns open PRs with base label" do
      prs = [double(number: 1), double(number: 2)]
      allow(labels).to receive(:base).and_return("claude-gardener")
      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: ["claude-gardener"])
        .and_return(prs)

      result = pr_manager.open_gardener_prs

      expect(result).to eq(prs)
    end
  end

  describe "#open_prs_for_category" do
    it "returns open PRs for a specific category" do
      prs = [double(number: 3)]
      category_labels = ["claude-gardener", "claude-gardener:test_coverage"]
      allow(labels).to receive(:for_category).with("test_coverage").and_return(category_labels)
      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: category_labels)
        .and_return(prs)

      result = pr_manager.open_prs_for_category("test_coverage")

      expect(result).to eq(prs)
    end
  end

  describe "#create_pr" do
    let(:branch) { "feature/add-tests" }
    let(:category) { "test_coverage" }
    let(:title) { "Add unit tests for UserController" }
    let(:body) { "Adds comprehensive tests covering edge cases" }
    let(:pr) { double(number: 123) }
    let(:category_labels) { ["claude-gardener", "claude-gardener:test_coverage"] }

    before do
      allow(labels).to receive(:for_category).with(category).and_return(category_labels)
      allow(github).to receive(:default_branch).and_return("main")
      allow(github).to receive(:ensure_label_exists)
      allow(github).to receive(:create_pull_request).and_return(pr)
      allow(github).to receive(:add_labels)
    end

    it "creates a PR with proper formatting and metadata" do
      time_now = Time.parse("2023-01-15 10:30:00 UTC")
      allow(Time).to receive(:now).and_return(time_now)

      result = pr_manager.create_pr(branch: branch, category: category, title: title, body: body)

      expect(github).to have_received(:create_pull_request).with(
        base: "main",
        head: branch,
        title: "[Gardener] Add unit tests for UserController",
        body: a_string_including(
          "Adds comprehensive tests covering edge cases",
          "<!-- gardener-metadata",
          "iteration: 1",
          "category: test_coverage",
          "started: 2023-01-15T10:30:00Z",
          "🤖 *This PR was created by [Claude Gardener]"
        )
      )
      expect(result).to eq(pr)
    end

    it "ensures labels exist before creating PR" do
      pr_manager.create_pr(branch: branch, category: category, title: title, body: body)

      category_labels.each do |label|
        expect(github).to have_received(:ensure_label_exists)
          .with(label, color: anything, description: anything)
      end
    end

    it "adds category labels to the PR" do
      pr_manager.create_pr(branch: branch, category: category, title: title, body: body)

      expect(github).to have_received(:add_labels).with(123, category_labels)
    end

    it "uses correct label colors and descriptions" do
      pr_manager.create_pr(branch: branch, category: category, title: title, body: body)

      expect(github).to have_received(:ensure_label_exists)
        .with("claude-gardener", color: "1d76db", description: "PR created by Claude Gardener")
      expect(github).to have_received(:ensure_label_exists)
        .with("claude-gardener:test_coverage", color: "0e8a16", description: nil)
    end

    context "with different categories" do
      it "uses correct colors for security_fixes" do
        allow(labels).to receive(:for_category).with("security_fixes")
          .and_return(["claude-gardener", "claude-gardener:security_fixes"])

        pr_manager.create_pr(branch: branch, category: "security_fixes", title: title, body: body)

        expect(github).to have_received(:ensure_label_exists)
          .with("claude-gardener:security_fixes", color: "d93f0b", description: nil)
      end

      it "uses correct colors for linter_fixes" do
        allow(labels).to receive(:for_category).with("linter_fixes")
          .and_return(["claude-gardener", "claude-gardener:linter_fixes"])

        pr_manager.create_pr(branch: branch, category: "linter_fixes", title: title, body: body)

        expect(github).to have_received(:ensure_label_exists)
          .with("claude-gardener:linter_fixes", color: "fbca04", description: nil)
      end

      it "uses correct colors for code_improvements" do
        allow(labels).to receive(:for_category).with("code_improvements")
          .and_return(["claude-gardener", "claude-gardener:code_improvements"])

        pr_manager.create_pr(branch: branch, category: "code_improvements", title: title, body: body)

        expect(github).to have_received(:ensure_label_exists)
          .with("claude-gardener:code_improvements", color: "c5def5", description: nil)
      end
    end
  end

  describe "#add_label" do
    let(:pr_number) { 456 }
    let(:label) { "needs-human" }

    before do
      allow(github).to receive(:ensure_label_exists)
      allow(github).to receive(:add_labels)
    end

    it "ensures label exists before adding" do
      pr_manager.add_label(pr_number, label)

      expect(github).to have_received(:ensure_label_exists)
        .with(label, color: "e99695", description: "Gardener PR that needs human intervention")
    end

    it "adds the label to the PR" do
      pr_manager.add_label(pr_number, label)

      expect(github).to have_received(:add_labels).with(pr_number, [label])
    end

    it "uses default color for unknown labels" do
      pr_manager.add_label(pr_number, "unknown-label")

      expect(github).to have_received(:ensure_label_exists)
        .with("unknown-label", color: "ededed", description: nil)
    end
  end

  describe "#add_comment" do
    it "adds a comment to the PR" do
      pr_number = 789
      comment_body = "Automated fix applied"
      allow(github).to receive(:add_comment)

      pr_manager.add_comment(pr_number, comment_body)

      expect(github).to have_received(:add_comment).with(pr_number, comment_body)
    end
  end

  describe "#update_metadata" do
    let(:pr_number) { 101 }
    let(:tracker) { instance_double("Tracker") }
    let(:existing_pr) { double(body: "Original PR body") }

    before do
      allow(github).to receive(:pull_request).with(pr_number).and_return(existing_pr)
      allow(tracker).to receive(:update_metadata_in_body).with("Original PR body")
        .and_return("Updated PR body")
      allow(tracker).to receive(:iterations).and_return(2)
      allow(github).to receive(:add_comment)
    end

    it "gets current PR body and updates metadata" do
      pr_manager.update_metadata(pr_number, tracker)

      expect(github).to have_received(:pull_request).with(pr_number)
      expect(tracker).to have_received(:update_metadata_in_body).with("Original PR body")
    end

    it "adds iteration comment" do
      pr_manager.update_metadata(pr_number, tracker)

      expect(github).to have_received(:add_comment).with(pr_number, "Iteration 2 completed.")
    end
  end

  describe "private methods" do
    describe "#build_pr_body" do
      it "combines body with metadata and footer" do
        time_now = Time.parse("2023-01-15 10:30:00 UTC")
        allow(Time).to receive(:now).and_return(time_now)

        body = "Test improvements"
        category = "test_coverage"

        result = pr_manager.send(:build_pr_body, body, category)

        expect(result).to include("Test improvements")
        expect(result).to include("---")
        expect(result).to include("<!-- gardener-metadata")
        expect(result).to include("iteration: 1")
        expect(result).to include("category: test_coverage")
        expect(result).to include("started: 2023-01-15T10:30:00Z")
        expect(result).to include("🤖 *This PR was created by [Claude Gardener]")
      end
    end

    describe "#build_metadata" do
      it "generates metadata comment block" do
        time_now = Time.parse("2023-01-15 10:30:00 UTC")
        allow(Time).to receive(:now).and_return(time_now)

        result = pr_manager.send(:build_metadata, "security_fixes")

        expect(result).to include("<!-- gardener-metadata")
        expect(result).to include("iteration: 1")
        expect(result).to include("category: security_fixes")
        expect(result).to include("started: 2023-01-15T10:30:00Z")
        expect(result).to include("-->")
      end
    end

    describe "#ensure_labels_exist" do
      it "ensures all category labels exist" do
        category_labels = ["claude-gardener", "claude-gardener:test_coverage"]
        allow(labels).to receive(:for_category).with("test_coverage").and_return(category_labels)
        allow(github).to receive(:ensure_label_exists)

        pr_manager.send(:ensure_labels_exist, "test_coverage")

        category_labels.each do |label|
          expect(github).to have_received(:ensure_label_exists)
            .with(label, color: anything, description: anything)
        end
      end
    end

    describe "#ensure_label_exists" do
      it "creates label with predefined color and description" do
        allow(github).to receive(:ensure_label_exists)

        pr_manager.send(:ensure_label_exists, "claude-gardener")

        expect(github).to have_received(:ensure_label_exists)
          .with("claude-gardener", color: "1d76db", description: "PR created by Claude Gardener")
      end

      it "creates label with default color when unknown" do
        allow(github).to receive(:ensure_label_exists)

        pr_manager.send(:ensure_label_exists, "custom-label")

        expect(github).to have_received(:ensure_label_exists)
          .with("custom-label", color: "ededed", description: nil)
      end
    end
  end
end