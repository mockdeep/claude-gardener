# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe ClaudeGardener::CreatePR do
  let(:env_vars) do
    {
      "CATEGORY" => "test_coverage",
      "BASE_LABEL" => "claude-gardener",
      "GITHUB_REPOSITORY" => "owner/repo",
      "AMEND" => "false",
      "AGGREGATE_ISSUE" => "123",
      "ITEM_TEXT" => "Add tests for feature X"
    }
  end

  before do
    env_vars.each { |key, value| allow(ENV).to receive(:fetch).with(key, anything).and_return(value) }
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)
  end

  describe "#initialize" do
    it "reads environment variables correctly" do
      create_pr = described_class.new

      expect(create_pr.instance_variable_get(:@category)).to eq("test_coverage")
      expect(create_pr.instance_variable_get(:@base_label)).to eq("claude-gardener")
      expect(create_pr.instance_variable_get(:@repository)).to eq("owner/repo")
      expect(create_pr.instance_variable_get(:@amend)).to be false
      expect(create_pr.instance_variable_get(:@aggregate_issue)).to eq("123")
      expect(create_pr.instance_variable_get(:@item_text)).to eq("Add tests for feature X")
    end

    it "handles default values for optional environment variables" do
      allow(ENV).to receive(:fetch).with("BASE_LABEL", "claude-gardener").and_return("claude-gardener")
      allow(ENV).to receive(:fetch).with("AMEND", "false").and_return("false")
      allow(ENV).to receive(:fetch).with("AGGREGATE_ISSUE", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("ITEM_TEXT", nil).and_return(nil)

      create_pr = described_class.new

      expect(create_pr.instance_variable_get(:@base_label)).to eq("claude-gardener")
      expect(create_pr.instance_variable_get(:@amend)).to be false
      expect(create_pr.instance_variable_get(:@aggregate_issue)).to be_nil
      expect(create_pr.instance_variable_get(:@item_text)).to be_nil
    end

    it "sets amend to true when AMEND is 'true'" do
      allow(ENV).to receive(:fetch).with("AMEND", "false").and_return("true")

      create_pr = described_class.new

      expect(create_pr.instance_variable_get(:@amend)).to be true
    end
  end

  describe "#run" do
    let(:create_pr) { described_class.new }

    context "when there are no changes" do
      before do
        allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["", ""])
      end

      it "skips PR creation and outputs empty values" do
        expect(create_pr).to receive(:write_output).with("pr_number", "")
        expect(create_pr).to receive(:write_output).with("pr_url", "")
        expect { create_pr.run }.to output(/No changes were made by Claude/).to_stdout
      end
    end

    context "when there are changes and amend is false" do
      before do
        allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["M file.rb\n", ""])
        allow(create_pr).to receive(:create_branch).and_return("gardener/test_coverage/20240101-120000")
        allow(create_pr).to receive(:commit_changes)
        allow(create_pr).to receive(:push_branch)
        allow(create_pr).to receive(:create_pull_request).and_return([42, "https://github.com/owner/repo/pull/42"])
        allow(create_pr).to receive(:add_labels)
        allow(create_pr).to receive(:write_output)
      end

      it "creates a new branch, commits, pushes, and creates a PR" do
        expect(create_pr).to receive(:create_branch).and_return("gardener/test_coverage/20240101-120000")
        expect(create_pr).to receive(:commit_changes)
        expect(create_pr).to receive(:push_branch).with("gardener/test_coverage/20240101-120000")
        expect(create_pr).to receive(:create_pull_request).with("gardener/test_coverage/20240101-120000")
        expect(create_pr).to receive(:add_labels).with(42)
        expect(create_pr).to receive(:write_output).with("pr_number", "42")
        expect(create_pr).to receive(:write_output).with("pr_url", "https://github.com/owner/repo/pull/42")

        expect { create_pr.run }.to output(/Created PR #42/).to_stdout
      end
    end

    context "when amend is true" do
      before do
        allow(ENV).to receive(:fetch).with("AMEND", "false").and_return("true")
        allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["M file.rb\n", ""])
        allow(create_pr).to receive(:amend_and_push)
      end

      let(:create_pr) { described_class.new }

      it "amends the existing commit instead of creating a new PR" do
        expect(create_pr).to receive(:amend_and_push)
        expect(create_pr).not_to receive(:create_branch)
        expect(create_pr).not_to receive(:create_pull_request)

        create_pr.run
      end
    end
  end

  describe "#create_branch" do
    let(:create_pr) { described_class.new }

    it "creates a branch with timestamp and sets git identity" do
      allow(Time).to receive(:now).and_return(Time.parse("2024-01-01 12:00:00 UTC"))
      expect(create_pr).to receive(:system).with("git", "config", "user.name", "Claude Gardener")
      expect(create_pr).to receive(:system).with("git", "config", "user.email", "claude-gardener[bot]@users.noreply.github.com")
      expect(create_pr).to receive(:system).with("git", "checkout", "-b", "gardener/test_coverage/20240101-120000")

      branch_name = create_pr.send(:create_branch)

      expect(branch_name).to eq("gardener/test_coverage/20240101-120000")
    end
  end

  describe "#commit_changes" do
    let(:create_pr) { described_class.new }

    it "stages all files and commits with proper message" do
      expect(create_pr).to receive(:exclude_output_files)
      expect(create_pr).to receive(:system).with("git", "add", "-A")
      expect(create_pr).to receive(:system).with("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")
      expect(create_pr).to receive(:system).with("git", "commit", "-m", match(/\[gardener\] Test coverage improvements/))

      create_pr.send(:commit_changes)
    end

    it "generates a proper commit message" do
      allow(create_pr).to receive(:exclude_output_files)
      allow(create_pr).to receive(:system)

      expect(create_pr).to receive(:system) do |*args|
        if args[0..2] == ["git", "commit", "-m"]
          message = args[3]
          expect(message).to include("[gardener] Test coverage improvements")
          expect(message).to include("Automated improvements by Claude Gardener")
          expect(message).to include("Category: test_coverage")
        end
      end

      create_pr.send(:commit_changes)
    end
  end

  describe "#amend_and_push" do
    let(:create_pr) { described_class.new }

    it "amends the commit and force pushes" do
      expect(create_pr).to receive(:exclude_output_files)
      expect(create_pr).to receive(:system).with("git", "add", "-A")
      expect(create_pr).to receive(:system).with("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")
      expect(create_pr).to receive(:system).with("git", "commit", "--amend", "--no-edit")
      expect(create_pr).to receive(:system).with("git", "push", "--force-with-lease")

      expect { create_pr.send(:amend_and_push) }.to output(/Amended commit and force-pushed/).to_stdout
    end
  end

  describe "#exclude_output_files" do
    let(:create_pr) { described_class.new }

    it "checks out output files if they exist" do
      allow(File).to receive(:exist?).with("output.txt").and_return(true)
      allow(File).to receive(:exist?).with("claude-output.txt").and_return(false)

      expect(create_pr).to receive(:system).with("git", "checkout", "--", "output.txt")
      expect(create_pr).not_to receive(:system).with("git", "checkout", "--", "claude-output.txt")

      create_pr.send(:exclude_output_files)
    end

    it "does not check out files that don't exist" do
      allow(File).to receive(:exist?).and_return(false)

      expect(create_pr).not_to receive(:system)

      create_pr.send(:exclude_output_files)
    end
  end

  describe "#push_branch" do
    let(:create_pr) { described_class.new }

    it "pushes the branch with upstream tracking" do
      expect(create_pr).to receive(:system).with("git", "push", "-u", "origin", "test-branch")

      create_pr.send(:push_branch, "test-branch")
    end
  end

  describe "#create_pull_request" do
    let(:create_pr) { described_class.new }

    it "creates a PR and returns number and URL" do
      pr_url = "https://github.com/owner/repo/pull/42"
      allow(Open3).to receive(:capture2).with("gh", "pr", "create", "--title", "[Gardener] Test coverage improvements", "--body", anything, "--head", "test-branch").and_return([pr_url, ""])

      pr_number, returned_url = create_pr.send(:create_pull_request, "test-branch")

      expect(pr_number).to eq(42)
      expect(returned_url).to eq(pr_url)
    end

    it "uses the correct title format" do
      pr_url = "https://github.com/owner/repo/pull/42"
      expect(Open3).to receive(:capture2).with("gh", "pr", "create", "--title", "[Gardener] Test coverage improvements", "--body", anything, "--head", "test-branch").and_return([pr_url, ""])

      create_pr.send(:create_pull_request, "test-branch")
    end
  end

  describe "#build_pr_body" do
    let(:create_pr) { described_class.new }

    it "includes category, issue reference, and task reference" do
      allow(Time).to receive(:now).and_return(Time.parse("2024-01-01 12:00:00 UTC"))

      body = create_pr.send(:build_pr_body)

      expect(body).to include("**Category:** test_coverage")
      expect(body).to include("**Source issue:** #123")
      expect(body).to include("**Task:** Add tests for feature X")
      expect(body).to include("category: test_coverage")
      expect(body).to include("aggregate_issue: 123")
      expect(body).to include("started: 2024-01-01T12:00:00Z")
    end

    it "handles missing aggregate issue and item text" do
      allow(ENV).to receive(:fetch).with("AGGREGATE_ISSUE", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("ITEM_TEXT", nil).and_return(nil)
      create_pr_no_refs = described_class.new
      allow(Time).to receive(:now).and_return(Time.parse("2024-01-01 12:00:00 UTC"))

      body = create_pr_no_refs.send(:build_pr_body)

      expect(body).to include("**Category:** test_coverage")
      expect(body).not_to include("**Source issue:**")
      expect(body).not_to include("**Task:**")
      expect(body).to include("aggregate_issue: none")
    end
  end

  describe "#add_labels" do
    let(:create_pr) { described_class.new }

    it "creates and adds labels to the PR" do
      expect(create_pr).to receive(:system).with("gh", "label", "create", "claude-gardener", "--force", "--color", "1d76db")
      expect(create_pr).to receive(:system).with("gh", "label", "create", "claude-gardener:test_coverage", "--force", "--color", "0e8a16")
      expect(create_pr).to receive(:system).with("gh", "pr", "edit", "42", "--add-label", "claude-gardener,claude-gardener:test_coverage")

      create_pr.send(:add_labels, 42)
    end
  end

  describe "#label_color" do
    let(:create_pr) { described_class.new }

    it "returns correct colors for known labels" do
      expect(create_pr.send(:label_color, "claude-gardener")).to eq("1d76db")
      expect(create_pr.send(:label_color, "claude-gardener:test_coverage")).to eq("0e8a16")
      expect(create_pr.send(:label_color, "claude-gardener:security_fixes")).to eq("d93f0b")
      expect(create_pr.send(:label_color, "claude-gardener:linter_fixes")).to eq("fbca04")
      expect(create_pr.send(:label_color, "claude-gardener:code_improvements")).to eq("c5def5")
    end

    it "returns default color for unknown labels" do
      expect(create_pr.send(:label_color, "unknown-label")).to eq("ededed")
    end
  end

  describe ".run" do
    it "creates a new instance and calls run" do
      instance = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(instance)
      expect(instance).to receive(:run)

      described_class.run
    end
  end

  describe "integration with OutputWriter" do
    let(:create_pr) { described_class.new }

    it "includes OutputWriter module" do
      expect(create_pr).to respond_to(:write_output)
    end
  end

  describe "error handling for git operations" do
    let(:create_pr) { described_class.new }

    context "when git status fails" do
      it "allows the error to propagate" do
        allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_raise(StandardError.new("git not found"))

        expect { create_pr.run }.to raise_error(StandardError, "git not found")
      end
    end

    context "when system commands fail" do
      before do
        allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["M file.rb\n", ""])
      end

      it "continues execution even if git config fails" do
        allow(create_pr).to receive(:system).with("git", "config", anything, anything).and_return(false)
        allow(create_pr).to receive(:system).with("git", "checkout", "-b", anything).and_return(true)

        expect { create_pr.send(:create_branch) }.not_to raise_error
      end
    end
  end
end