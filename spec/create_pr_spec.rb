# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::CreatePR do
  let(:category) { "test_coverage" }
  let(:base_label) { "claude-gardener" }
  let(:repository) { "owner/repo" }
  let(:amend) { "false" }
  let(:aggregate_issue) { nil }
  let(:item_text) { nil }

  let(:env_vars) do
    {
      "CATEGORY" => category,
      "BASE_LABEL" => base_label,
      "GITHUB_REPOSITORY" => repository,
      "AMEND" => amend,
      "AGGREGATE_ISSUE" => aggregate_issue,
      "ITEM_TEXT" => item_text
    }
  end

  before do
    env_vars.each { |key, value| ENV[key] = value }
    allow(described_class).to receive(:system).and_return(true)
    allow(Open3).to receive(:capture2).and_return(["", ""])
    allow(File).to receive(:exist?).and_return(false)
  end

  after do
    env_vars.each_key { |key| ENV.delete(key) }
  end

  describe ".run" do
    it "creates a new instance and calls run" do
      instance = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:run)

      described_class.run

      expect(described_class).to have_received(:new)
      expect(instance).to have_received(:run)
    end
  end

  describe "#initialize" do
    context "with all environment variables" do
      let(:aggregate_issue) { "123" }
      let(:item_text) { "Add more tests" }

      it "sets instance variables from environment" do
        instance = described_class.new

        expect(instance.instance_variable_get(:@category)).to eq(category)
        expect(instance.instance_variable_get(:@base_label)).to eq(base_label)
        expect(instance.instance_variable_get(:@repository)).to eq(repository)
        expect(instance.instance_variable_get(:@amend)).to be(false)
        expect(instance.instance_variable_get(:@aggregate_issue)).to eq(aggregate_issue)
        expect(instance.instance_variable_get(:@item_text)).to eq(item_text)
      end
    end

    context "without optional environment variables" do
      it "uses defaults" do
        instance = described_class.new

        expect(instance.instance_variable_get(:@base_label)).to eq("claude-gardener")
        expect(instance.instance_variable_get(:@amend)).to be(false)
        expect(instance.instance_variable_get(:@aggregate_issue)).to be_nil
        expect(instance.instance_variable_get(:@item_text)).to be_nil
      end
    end

    context "with amend=true" do
      let(:amend) { "true" }

      it "sets amend to true" do
        instance = described_class.new

        expect(instance.instance_variable_get(:@amend)).to be(true)
      end
    end

    it "raises error when CATEGORY is missing" do
      ENV.delete("CATEGORY")

      expect { described_class.new }.to raise_error(KeyError)
    end

    it "raises error when GITHUB_REPOSITORY is missing" do
      ENV.delete("GITHUB_REPOSITORY")

      expect { described_class.new }.to raise_error(KeyError)
    end
  end

  describe "#run" do
    let(:instance) { described_class.new }

    context "when there are no changes" do
      before do
        allow(Open3).to receive(:capture2)
          .with("git", "status", "--porcelain")
          .and_return(["", ""])
        allow(instance).to receive(:write_output)
        allow(instance).to receive(:puts)
      end

      it "skips PR creation and outputs empty values" do
        instance.run

        expect(instance).to have_received(:write_output).with("pr_number", "")
        expect(instance).to have_received(:write_output).with("pr_url", "")
        expect(instance).to have_received(:puts).with("No changes were made by Claude. Skipping PR creation.")
      end
    end

    context "when there are changes and amend=false" do
      let(:branch_name) { "gardener/test_coverage/20240305-143000" }
      let(:pr_number) { 42 }
      let(:pr_url) { "https://github.com/owner/repo/pull/42" }

      before do
        allow(Open3).to receive(:capture2)
          .with("git", "status", "--porcelain")
          .and_return(["M file.rb\n", ""])
        
        allow(instance).to receive(:create_branch).and_return(branch_name)
        allow(instance).to receive(:commit_changes)
        allow(instance).to receive(:push_branch)
        allow(instance).to receive(:create_pull_request).and_return([pr_number, pr_url])
        allow(instance).to receive(:add_labels)
        allow(instance).to receive(:write_output)
        allow(instance).to receive(:puts)
      end

      it "creates branch, commits, pushes, and creates PR" do
        instance.run

        expect(instance).to have_received(:create_branch)
        expect(instance).to have_received(:commit_changes)
        expect(instance).to have_received(:push_branch).with(branch_name)
        expect(instance).to have_received(:create_pull_request).with(branch_name)
        expect(instance).to have_received(:add_labels).with(pr_number)
      end

      it "outputs PR information" do
        instance.run

        expect(instance).to have_received(:write_output).with("pr_number", "42")
        expect(instance).to have_received(:write_output).with("pr_url", pr_url)
        expect(instance).to have_received(:puts).with("Created PR #42: #{pr_url}")
      end
    end

    context "when there are changes and amend=true" do
      let(:amend) { "true" }

      before do
        allow(Open3).to receive(:capture2)
          .with("git", "status", "--porcelain")
          .and_return(["M file.rb\n", ""])
        
        allow(instance).to receive(:amend_and_push)
      end

      it "amends and pushes instead of creating new PR" do
        instance.run

        expect(instance).to have_received(:amend_and_push)
      end
    end
  end

  describe "#create_branch" do
    let(:instance) { described_class.new }
    let(:timestamp) { "20240305-143000" }

    before do
      allow(Time).to receive(:now).and_return(Time.new(2024, 3, 5, 14, 30, 0))
    end

    it "creates a timestamped branch" do
      branch_name = instance.send(:create_branch)

      expect(described_class).to have_received(:system)
        .with("git", "config", "user.name", "Claude Gardener")
      expect(described_class).to have_received(:system)
        .with("git", "config", "user.email", "claude-gardener[bot]@users.noreply.github.com")
      expect(described_class).to have_received(:system)
        .with("git", "checkout", "-b", "gardener/test_coverage/#{timestamp}")
      expect(branch_name).to eq("gardener/test_coverage/#{timestamp}")
    end
  end

  describe "#commit_changes" do
    let(:instance) { described_class.new }

    before do
      allow(instance).to receive(:exclude_output_files)
    end

    it "excludes output files, adds all files, and commits with message" do
      instance.send(:commit_changes)

      expect(instance).to have_received(:exclude_output_files)
      expect(described_class).to have_received(:system).with("git", "add", "-A")
      expect(described_class).to have_received(:system)
        .with("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")

      expected_message = <<~MSG
        [gardener] Test coverage improvements

        Automated improvements by Claude Gardener.

        Category: test_coverage
      MSG

      expect(described_class).to have_received(:system)
        .with("git", "commit", "-m", expected_message)
    end
  end

  describe "#amend_and_push" do
    let(:instance) { described_class.new }

    before do
      allow(instance).to receive(:exclude_output_files)
      allow(instance).to receive(:puts)
    end

    it "excludes output files, adds all files, amends commit and force pushes" do
      instance.send(:amend_and_push)

      expect(instance).to have_received(:exclude_output_files)
      expect(described_class).to have_received(:system).with("git", "add", "-A")
      expect(described_class).to have_received(:system)
        .with("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")
      expect(described_class).to have_received(:system)
        .with("git", "commit", "--amend", "--no-edit")
      expect(described_class).to have_received(:system)
        .with("git", "push", "--force-with-lease")
      expect(instance).to have_received(:puts).with("Amended commit and force-pushed.")
    end
  end

  describe "#exclude_output_files" do
    let(:instance) { described_class.new }

    context "when output files exist" do
      before do
        allow(File).to receive(:exist?).with("output.txt").and_return(true)
        allow(File).to receive(:exist?).with("claude-output.txt").and_return(true)
      end

      it "checks out the output files" do
        instance.send(:exclude_output_files)

        expect(described_class).to have_received(:system)
          .with("git", "checkout", "--", "output.txt")
        expect(described_class).to have_received(:system)
          .with("git", "checkout", "--", "claude-output.txt")
      end
    end

    context "when output files don't exist" do
      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      it "doesn't attempt to check out files" do
        instance.send(:exclude_output_files)

        expect(described_class).not_to have_received(:system)
          .with("git", "checkout", "--", "output.txt")
        expect(described_class).not_to have_received(:system)
          .with("git", "checkout", "--", "claude-output.txt")
      end
    end
  end

  describe "#push_branch" do
    let(:instance) { described_class.new }
    let(:branch_name) { "gardener/test_coverage/20240305-143000" }

    it "pushes the branch with upstream tracking" do
      instance.send(:push_branch, branch_name)

      expect(described_class).to have_received(:system)
        .with("git", "push", "-u", "origin", branch_name)
    end
  end

  describe "#create_pull_request" do
    let(:instance) { described_class.new }
    let(:branch_name) { "gardener/test_coverage/20240305-143000" }
    let(:pr_url) { "https://github.com/owner/repo/pull/42" }

    before do
      allow(Open3).to receive(:capture2)
        .with("gh", "pr", "create", "--title", anything, "--body", anything, "--head", branch_name)
        .and_return([pr_url, ""])
      allow(instance).to receive(:build_pr_body).and_return("PR body content")
    end

    it "creates PR with correct title and returns PR number and URL" do
      pr_number, returned_url = instance.send(:create_pull_request, branch_name)

      expect(Open3).to have_received(:capture2).with(
        "gh", "pr", "create",
        "--title", "[Gardener] Test coverage improvements",
        "--body", "PR body content",
        "--head", branch_name
      )
      expect(pr_number).to eq(42)
      expect(returned_url).to eq(pr_url)
    end
  end

  describe "#build_pr_body" do
    let(:instance) { described_class.new }

    context "without aggregate issue or item text" do
      before do
        allow(Time).to receive(:now).and_return(Time.new(2024, 3, 5, 14, 30, 0, 0))
      end

      it "builds basic PR body" do
        body = instance.send(:build_pr_body)

        expect(body).to include("## Summary")
        expect(body).to include("**Category:** test_coverage")
        expect(body).to include("category: test_coverage")
        expect(body).to include("aggregate_issue: none")
        expect(body).to include("started: 2024-03-05T14:30:00Z")
        expect(body).to include("Claude Gardener")
      end
    end

    context "with aggregate issue and item text" do
      let(:aggregate_issue) { "123" }
      let(:item_text) { "Add more unit tests" }

      it "includes issue and task references" do
        body = instance.send(:build_pr_body)

        expect(body).to include("**Source issue:** #123")
        expect(body).to include("**Task:** Add more unit tests")
        expect(body).to include("aggregate_issue: 123")
      end
    end
  end

  describe "#add_labels" do
    let(:instance) { described_class.new }
    let(:pr_number) { 42 }

    it "creates labels and adds them to PR" do
      instance.send(:add_labels, pr_number)

      expect(described_class).to have_received(:system).with(
        "gh", "label", "create", "claude-gardener", "--force", "--color", "1d76db"
      )
      expect(described_class).to have_received(:system).with(
        "gh", "label", "create", "claude-gardener:test_coverage", "--force", "--color", "0e8a16"
      )
      expect(described_class).to have_received(:system).with(
        "gh", "pr", "edit", "42", "--add-label", "claude-gardener,claude-gardener:test_coverage"
      )
    end
  end

  describe "#label_color" do
    let(:instance) { described_class.new }

    it "returns predefined colors for known labels" do
      expect(instance.send(:label_color, "claude-gardener")).to eq("1d76db")
      expect(instance.send(:label_color, "claude-gardener:test_coverage")).to eq("0e8a16")
      expect(instance.send(:label_color, "claude-gardener:security_fixes")).to eq("d93f0b")
      expect(instance.send(:label_color, "claude-gardener:linter_fixes")).to eq("fbca04")
      expect(instance.send(:label_color, "claude-gardener:code_improvements")).to eq("c5def5")
    end

    it "returns default color for unknown labels" do
      expect(instance.send(:label_color, "unknown-label")).to eq("ededed")
    end
  end
end