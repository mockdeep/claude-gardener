# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::CreatePR do
  let(:category) { "test_coverage" }
  let(:repository) { "owner/repo" }
  let(:base_label) { "claude-gardener" }
  let(:env_vars) do
    {
      "CATEGORY" => category,
      "GITHUB_REPOSITORY" => repository,
      "BASE_LABEL" => base_label,
      "AMEND" => "false",
      "AGGREGATE_ISSUE" => nil,
      "ITEM_TEXT" => nil,
      "PR_ASSIGNEES" => "",
      "PR_REVIEWERS" => ""
    }
  end

  subject(:create_pr) { described_class.new }

  before do
    env_vars.each { |key, value| allow(ENV).to receive(:fetch).with(key, any_args).and_return(value) }
    allow(ENV).to receive(:fetch).with("AMEND", "false").and_return("false")
    allow(ENV).to receive(:fetch).with("BASE_LABEL", "claude-gardener").and_return(base_label)
    allow(ENV).to receive(:fetch).with("AGGREGATE_ISSUE", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("ITEM_TEXT", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("PR_ASSIGNEES", "").and_return("")
    allow(ENV).to receive(:fetch).with("PR_REVIEWERS", "").and_return("")
  end

  describe "#run" do
    context "when there are no changes" do
      it "skips PR creation and sets empty outputs" do
        allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["", ""])
        expect(create_pr).to receive(:write_output).with("pr_number", "")
        expect(create_pr).to receive(:write_output).with("pr_url", "")

        expect { create_pr.run }.to output("No changes were made by Claude. Skipping PR creation.\n").to_stdout
      end
    end

    context "when there are changes" do
      before do
        allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["modified: file.rb\n", ""])
      end

      context "when amend is false" do
        it "creates a new branch, commits, pushes, and creates PR" do
          branch_name = "gardener/test_coverage/20241201-120000"
          pr_number = 123
          pr_url = "https://github.com/owner/repo/pull/123"

          allow(Time).to receive(:now).and_return(Time.new(2024, 12, 1, 12, 0, 0))
          allow(create_pr).to receive(:system).and_return(true)
          allow(Open3).to receive(:capture2).and_return([pr_url, ""])
          allow(create_pr).to receive(:write_output)

          expect(create_pr).to receive(:system).with("git", "config", "user.name", "Claude Gardener")
          expect(create_pr).to receive(:system).with("git", "config", "user.email", "claude-gardener[bot]@users.noreply.github.com")
          expect(create_pr).to receive(:system).with("git", "checkout", "-b", branch_name)
          expect(create_pr).to receive(:system).with("git", "add", "-A")
          expect(create_pr).to receive(:system).with("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")
          expect(create_pr).to receive(:system).with("git", "commit", "-m", include("[gardener] Test coverage improvements"))
          expect(create_pr).to receive(:system).with("git", "push", "-u", "origin", branch_name)

          expect(Open3).to receive(:capture2).with(
            "gh", "pr", "create", 
            "--title", "[Gardener] Test coverage improvements",
            "--body", include("Category: test_coverage"),
            "--head", branch_name
          ).and_return([pr_url, ""])

          expect(create_pr).to receive(:write_output).with("pr_number", "123")
          expect(create_pr).to receive(:write_output).with("pr_url", pr_url)

          expect { create_pr.run }.to output("Created PR #123: #{pr_url}\n").to_stdout
        end
      end

      context "when amend is true" do
        before do
          allow(ENV).to receive(:fetch).with("AMEND", "false").and_return("true")
        end

        it "amends the existing commit and force pushes" do
          allow(create_pr).to receive(:system).and_return(true)
          allow(File).to receive(:exist?).and_return(false)

          expect(create_pr).to receive(:system).with("git", "add", "-A")
          expect(create_pr).to receive(:system).with("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")
          expect(create_pr).to receive(:system).with("git", "commit", "--amend", "--no-edit")
          expect(create_pr).to receive(:system).with("git", "push", "--force-with-lease")

          expect { create_pr.run }.to output("Amended commit and force-pushed.\n").to_stdout
        end
      end
    end
  end

  describe "#create_branch" do
    it "creates a timestamped branch and sets git identity" do
      allow(Time).to receive(:now).and_return(Time.new(2024, 12, 1, 12, 0, 0))
      allow(create_pr).to receive(:system).and_return(true)

      branch_name = create_pr.send(:create_branch)

      expect(branch_name).to eq("gardener/test_coverage/20241201-120000")
      expect(create_pr).to have_received(:system).with("git", "config", "user.name", "Claude Gardener")
      expect(create_pr).to have_received(:system).with("git", "config", "user.email", "claude-gardener[bot]@users.noreply.github.com")
      expect(create_pr).to have_received(:system).with("git", "checkout", "-b", "gardener/test_coverage/20241201-120000")
    end
  end

  describe "#commit_changes" do
    it "stages files, excludes output files, and commits" do
      allow(create_pr).to receive(:system).and_return(true)
      allow(File).to receive(:exist?).and_return(false)

      create_pr.send(:commit_changes)

      expect(create_pr).to have_received(:system).with("git", "add", "-A")
      expect(create_pr).to have_received(:system).with("git", "reset", "HEAD", "--", "output.txt", "claude-output.txt", "*.log")
      expect(create_pr).to have_received(:system).with("git", "commit", "-m", include("[gardener] Test coverage improvements"))
    end
  end

  describe "#exclude_output_files" do
    context "when output files exist" do
      it "reverts output files from working directory" do
        allow(File).to receive(:exist?).with("output.txt").and_return(true)
        allow(File).to receive(:exist?).with("claude-output.txt").and_return(true)
        allow(create_pr).to receive(:system).and_return(true)

        create_pr.send(:exclude_output_files)

        expect(create_pr).to have_received(:system).with("git", "checkout", "--", "output.txt")
        expect(create_pr).to have_received(:system).with("git", "checkout", "--", "claude-output.txt")
      end
    end

    context "when output files don't exist" do
      it "does not attempt to revert non-existent files" do
        allow(File).to receive(:exist?).and_return(false)
        allow(create_pr).to receive(:system).and_return(true)

        create_pr.send(:exclude_output_files)

        expect(create_pr).not_to have_received(:system).with("git", "checkout", "--", "output.txt")
        expect(create_pr).not_to have_received(:system).with("git", "checkout", "--", "claude-output.txt")
      end
    end
  end

  describe "#push_branch" do
    it "pushes the branch with upstream tracking" do
      branch_name = "gardener/test_coverage/20241201-120000"
      allow(create_pr).to receive(:system).and_return(true)

      create_pr.send(:push_branch, branch_name)

      expect(create_pr).to have_received(:system).with("git", "push", "-u", "origin", branch_name)
    end
  end

  describe "#create_pull_request" do
    let(:branch_name) { "gardener/test_coverage/20241201-120000" }
    let(:pr_url) { "https://github.com/owner/repo/pull/123" }

    it "creates PR with basic configuration" do
      allow(Open3).to receive(:capture2).and_return([pr_url, ""])

      pr_number, returned_url = create_pr.send(:create_pull_request, branch_name)

      expect(Open3).to have_received(:capture2).with(
        "gh", "pr", "create",
        "--title", "[Gardener] Test coverage improvements",
        "--body", include("Category: test_coverage"),
        "--head", branch_name
      )
      expect(pr_number).to eq(123)
      expect(returned_url).to eq(pr_url)
    end

    context "with assignees and reviewers" do
      before do
        allow(ENV).to receive(:fetch).with("PR_ASSIGNEES", "").and_return("user1,user2")
        allow(ENV).to receive(:fetch).with("PR_REVIEWERS", "").and_return("reviewer1")
      end

      it "includes assignees and reviewers in PR creation" do
        allow(Open3).to receive(:capture2).and_return([pr_url, ""])

        create_pr.send(:create_pull_request, branch_name)

        expect(Open3).to have_received(:capture2).with(
          "gh", "pr", "create",
          "--title", "[Gardener] Test coverage improvements",
          "--body", include("Category: test_coverage"),
          "--head", branch_name,
          "--assignee", "user1",
          "--assignee", "user2",
          "--reviewer", "reviewer1"
        )
      end
    end
  end

  describe "#build_pr_body" do
    it "builds basic PR body" do
      body = create_pr.send(:build_pr_body)

      expect(body).to include("## Summary")
      expect(body).to include("**Category:** test_coverage")
      expect(body).to include("gardener-metadata")
      expect(body).to include("iteration: 1")
      expect(body).to include("category: test_coverage")
      expect(body).to include("aggregate_issue: none")
      expect(body).to include("Claude Gardener")
    end

    context "with aggregate issue and item text" do
      before do
        allow(ENV).to receive(:fetch).with("AGGREGATE_ISSUE", nil).and_return("456")
        allow(ENV).to receive(:fetch).with("ITEM_TEXT", nil).and_return("Add missing unit tests")
      end

      it "includes issue reference and task description" do
        body = create_pr.send(:build_pr_body)

        expect(body).to include("**Source issue:** #456")
        expect(body).to include("**Task:** Add missing unit tests")
        expect(body).to include("aggregate_issue: 456")
      end
    end
  end

  describe "#add_labels" do
    let(:pr_number) { 123 }

    it "creates labels and adds them to PR" do
      allow(create_pr).to receive(:system).and_return(true)

      create_pr.send(:add_labels, pr_number)

      expect(create_pr).to have_received(:system).with("gh", "label", "create", "claude-gardener", "--force", "--color", "1d76db")
      expect(create_pr).to have_received(:system).with("gh", "label", "create", "claude-gardener:test_coverage", "--force", "--color", "0e8a16")
      expect(create_pr).to have_received(:system).with("gh", "pr", "edit", "123", "--add-label", "claude-gardener,claude-gardener:test_coverage")
    end
  end

  describe "#label_color" do
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

  describe "error handling" do
    before do
      allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["modified: file.rb\n", ""])
    end

    context "when git operations fail" do
      it "handles git checkout failure gracefully" do
        allow(create_pr).to receive(:system).with("git", "checkout", "-b", anything).and_return(false)
        allow(create_pr).to receive(:system).and_call_original

        expect { create_pr.run }.not_to raise_error
      end

      it "handles git commit failure gracefully" do
        allow(create_pr).to receive(:system).with("git", "commit", "-m", anything).and_return(false)
        allow(create_pr).to receive(:system).and_call_original

        expect { create_pr.run }.not_to raise_error
      end

      it "handles git push failure gracefully" do
        allow(create_pr).to receive(:system).with("git", "push", "-u", "origin", anything).and_return(false)
        allow(create_pr).to receive(:system).and_call_original

        expect { create_pr.run }.not_to raise_error
      end
    end

    context "when PR creation fails" do
      it "handles gh pr create failure" do
        allow(Open3).to receive(:capture2).with("gh", "pr", "create", *anything).and_raise(StandardError, "API error")
        allow(create_pr).to receive(:system).and_return(true)

        expect { create_pr.run }.to raise_error(StandardError, "API error")
      end
    end

    context "when label creation fails" do
      it "handles gh label create failure gracefully" do
        allow(create_pr).to receive(:system).with("gh", "label", "create", anything, anything, anything, anything).and_return(false)
        allow(create_pr).to receive(:system).and_call_original
        allow(Open3).to receive(:capture2).and_return(["https://github.com/owner/repo/pull/123", ""])

        expect { create_pr.run }.not_to raise_error
      end
    end
  end
end