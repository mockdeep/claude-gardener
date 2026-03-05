# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::PrManager do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:config) { instance_double(ClaudeGardener::Config) }
  let(:labels_config) { instance_double(ClaudeGardener::Config::Labels) }

  subject(:pr_manager) { described_class.new(github: github, config: config) }

  before do
    allow(config).to receive(:labels).and_return(labels_config)
    allow(labels_config).to receive(:base).and_return("claude-gardener")
  end

  describe "#open_gardener_prs" do
    it "returns open PRs with base label" do
      expected_prs = [double(number: 1), double(number: 2)]
      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: ["claude-gardener"])
        .and_return(expected_prs)

      result = pr_manager.open_gardener_prs

      expect(result).to eq(expected_prs)
    end
  end

  describe "#open_prs_for_category" do
    it "returns open PRs with category labels" do
      expected_prs = [double(number: 3)]
      allow(labels_config).to receive(:for_category)
        .with("test_coverage")
        .and_return(["claude-gardener", "claude-gardener:test_coverage"])
      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: ["claude-gardener", "claude-gardener:test_coverage"])
        .and_return(expected_prs)

      result = pr_manager.open_prs_for_category("test_coverage")

      expect(result).to eq(expected_prs)
    end
  end

  describe "#create_pr" do
    let(:pr_data) do
      {
        branch: "feature/test-improvements",
        category: "test_coverage",
        title: "Add tests for UserService",
        body: "This PR adds comprehensive tests for UserService methods."
      }
    end
    let(:created_pr) { double(number: 42) }

    before do
      allow(labels_config).to receive(:for_category)
        .with("test_coverage")
        .and_return(["claude-gardener", "claude-gardener:test_coverage"])
      allow(github).to receive(:default_branch).and_return("main")
      allow(github).to receive(:ensure_label_exists)
      allow(github).to receive(:create_pull_request).and_return(created_pr)
      allow(github).to receive(:add_labels)
      allow(Time).to receive(:now).and_return(Time.utc(2023, 1, 15, 10, 30, 0))
    end

    it "ensures labels exist, creates PR with formatted body, and adds labels" do
      result = pr_manager.create_pr(**pr_data)

      expect(github).to have_received(:ensure_label_exists)
        .with("claude-gardener", color: "1d76db", description: "PR created by Claude Gardener")
      expect(github).to have_received(:ensure_label_exists)
        .with("claude-gardener:test_coverage", color: "0e8a16", description: nil)

      expect(github).to have_received(:create_pull_request).with(
        base: "main",
        head: "feature/test-improvements",
        title: "[Gardener] Add tests for UserService",
        body: a_string_including(
          "This PR adds comprehensive tests for UserService methods.",
          "<!-- gardener-metadata",
          "iteration: 1",
          "category: test_coverage",
          "started: 2023-01-15T10:30:00Z",
          "🤖 *This PR was created by [Claude Gardener]"
        )
      )

      expect(github).to have_received(:add_labels)
        .with(42, ["claude-gardener", "claude-gardener:test_coverage"])

      expect(result).to eq(created_pr)
    end
  end

  describe "#add_label" do
    it "ensures label exists and adds it to PR" do
      allow(github).to receive(:ensure_label_exists)
      allow(github).to receive(:add_labels)

      pr_manager.add_label(123, "needs-human")

      expect(github).to have_received(:ensure_label_exists)
        .with("needs-human", color: "e99695", description: "Gardener PR that needs human intervention")
      expect(github).to have_received(:add_labels).with(123, ["needs-human"])
    end

    it "uses default color for unknown labels" do
      allow(github).to receive(:ensure_label_exists)
      allow(github).to receive(:add_labels)

      pr_manager.add_label(123, "custom-label")

      expect(github).to have_received(:ensure_label_exists)
        .with("custom-label", color: "ededed", description: nil)
    end
  end

  describe "#add_comment" do
    it "adds comment to PR" do
      allow(github).to receive(:add_comment)

      pr_manager.add_comment(456, "This needs review")

      expect(github).to have_received(:add_comment).with(456, "This needs review")
    end
  end

  describe "#update_metadata" do
    let(:tracker) { double(iterations: 2) }
    let(:existing_pr) { double(body: "Original body content") }

    before do
      allow(github).to receive(:pull_request).with(789).and_return(existing_pr)
      allow(github).to receive(:add_comment)
      allow(tracker).to receive(:update_metadata_in_body)
        .with("Original body content")
        .and_return("Updated body with new metadata")
    end

    it "retrieves PR, updates metadata, and adds iteration comment" do
      pr_manager.update_metadata(789, tracker)

      expect(github).to have_received(:pull_request).with(789)
      expect(tracker).to have_received(:update_metadata_in_body).with("Original body content")
      expect(github).to have_received(:add_comment).with(789, "Iteration 2 completed.")
    end
  end

  describe "label constants" do
    it "defines correct label colors" do
      expect(described_class::LABEL_COLORS).to include(
        "claude-gardener" => "1d76db",
        "claude-gardener:test_coverage" => "0e8a16",
        "claude-gardener:security_fixes" => "d93f0b",
        "claude-gardener:linter_fixes" => "fbca04",
        "claude-gardener:code_improvements" => "c5def5",
        "needs-human" => "e99695"
      )
    end

    it "defines correct label descriptions" do
      expect(described_class::LABEL_DESCRIPTIONS).to include(
        "claude-gardener" => "PR created by Claude Gardener",
        "needs-human" => "Gardener PR that needs human intervention"
      )
    end
  end

  describe "private methods" do
    describe "#build_pr_body" do
      before do
        allow(Time).to receive(:now).and_return(Time.utc(2023, 6, 1, 14, 0, 0))
      end

      it "formats PR body with metadata and signature" do
        body = pr_manager.send(:build_pr_body, "Original content", "security_fixes")

        expect(body).to include("Original content")
        expect(body).to include("---")
        expect(body).to include("<!-- gardener-metadata")
        expect(body).to include("iteration: 1")
        expect(body).to include("category: security_fixes")
        expect(body).to include("started: 2023-06-01T14:00:00Z")
        expect(body).to include("🤖 *This PR was created by [Claude Gardener]")
      end
    end

    describe "#build_metadata" do
      before do
        allow(Time).to receive(:now).and_return(Time.utc(2023, 12, 25, 9, 15, 30))
      end

      it "generates correct metadata block" do
        metadata = pr_manager.send(:build_metadata, "linter_fixes")

        expect(metadata).to eq(<<~METADATA)
          <!-- gardener-metadata
          iteration: 1
          category: linter_fixes
          started: 2023-12-25T09:15:30Z
          -->
        METADATA
      end
    end

    describe "#ensure_labels_exist" do
      before do
        allow(labels_config).to receive(:for_category)
          .with("code_improvements")
          .and_return(["claude-gardener", "claude-gardener:code_improvements"])
        allow(github).to receive(:ensure_label_exists)
      end

      it "ensures all category labels exist" do
        pr_manager.send(:ensure_labels_exist, "code_improvements")

        expect(github).to have_received(:ensure_label_exists)
          .with("claude-gardener", color: "1d76db", description: "PR created by Claude Gardener")
        expect(github).to have_received(:ensure_label_exists)
          .with("claude-gardener:code_improvements", color: "c5def5", description: nil)
      end
    end
  end
end