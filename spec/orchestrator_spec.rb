# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::Orchestrator do
  let(:config) do
    ClaudeGardener::Config.new(
      "workers" => { "max_concurrent" => 2 },
      "priorities" => [
        { "category" => "test_coverage", "max_prs" => 3, "enabled" => true }
      ],
      "guardrails" => { "max_iterations_per_pr" => 3 },
      "labels" => { "base" => "claude-gardener" }
    )
  end

  let(:github) { instance_double(ClaudeGardener::GithubClient, repository: "owner/repo") }
  let(:pr_manager) { instance_double(ClaudeGardener::PrManager) }
  let(:lock_checker) { instance_double(ClaudeGardener::LockChecker, locked_files: Set.new) }
  let(:claude) { instance_double(ClaudeGardener::ClaudeRunner) }

  before do
    allow(ClaudeGardener::GithubClient).to receive(:new).and_return(github)
    allow(ClaudeGardener::PrManager).to receive(:new).and_return(pr_manager)
    allow(ClaudeGardener::LockChecker).to receive(:new).and_return(lock_checker)
    allow(ClaudeGardener::ClaudeRunner).to receive(:new).and_return(claude)
  end

  describe "#run with workflow_dispatch" do
    subject(:orchestrator) do
      described_class.new(
        config: config,
        event_type: "workflow_dispatch",
        event_data: {},
        category: "auto"
      )
    end

    it "exits when at worker capacity" do
      allow(pr_manager).to receive(:open_gardener_prs).and_return([double, double])

      expect { orchestrator.run }.to output(/At worker capacity/).to_stdout
    end

    it "exits when no tasks available" do
      allow(pr_manager).to receive(:open_gardener_prs).and_return([])
      allow(pr_manager).to receive(:open_prs_for_category).and_return([double, double, double])

      expect { orchestrator.run }.to output(/No tasks available/).to_stdout
    end

    it "creates a PR when task is available" do
      allow(pr_manager).to receive(:open_gardener_prs).and_return([])
      allow(pr_manager).to receive(:open_prs_for_category).and_return([])
      allow(github).to receive(:create_branch)

      result = ClaudeGardener::ClaudeRunner::Result.new(
        success: true,
        pr_title: "Add tests for User model",
        pr_body: "Added comprehensive tests."
      )
      allow(claude).to receive(:run).and_return(result)

      created_pr = double(number: 42, html_url: "https://github.com/owner/repo/pull/42")
      allow(pr_manager).to receive(:create_pr).and_return(created_pr)

      expect { orchestrator.run }.to output(/Created PR #42/).to_stdout
    end

    it "deletes branch when Claude fails" do
      allow(pr_manager).to receive(:open_gardener_prs).and_return([])
      allow(pr_manager).to receive(:open_prs_for_category).and_return([])
      allow(github).to receive(:create_branch)

      result = ClaudeGardener::ClaudeRunner::Result.new(
        success: false,
        error: "No changes were made"
      )
      allow(claude).to receive(:run).and_return(result)
      allow(github).to receive(:delete_branch)

      expect(github).to receive(:delete_branch)

      orchestrator.run
    end
  end

  describe "#run with pull_request_review" do
    let(:event_data) do
      {
        "pull_request" => {
          "number" => 123,
          "labels" => [{ "name" => "claude-gardener" }]
        },
        "review" => { "state" => "changes_requested" }
      }
    end

    subject(:orchestrator) do
      described_class.new(
        config: config,
        event_type: "pull_request_review",
        event_data: event_data,
        category: "auto"
      )
    end

    it "addresses feedback on gardener PRs" do
      pr = double(
        labels: [double(name: "claude-gardener")],
        body: "<!-- gardener-metadata\niteration: 1\ncategory: test_coverage\nstarted: 2026-01-01T00:00:00Z\n-->",
        head: double(ref: "gardener/test_coverage/123")
      )
      allow(github).to receive(:pull_request).with(123).and_return(pr)
      allow(github).to receive(:review_comments).and_return([])
      allow(github).to receive(:issue_comments).and_return([])

      result = ClaudeGardener::ClaudeRunner::Result.new(success: true)
      allow(claude).to receive(:address_feedback).and_return(result)
      allow(pr_manager).to receive(:update_metadata)

      expect(claude).to receive(:address_feedback)

      orchestrator.run
    end

    it "adds needs-human label when max iterations reached" do
      pr = double(
        labels: [double(name: "claude-gardener")],
        body: "<!-- gardener-metadata\niteration: 3\ncategory: test_coverage\nstarted: 2026-01-01T00:00:00Z\n-->"
      )
      allow(github).to receive(:pull_request).with(123).and_return(pr)
      allow(pr_manager).to receive(:add_label)
      allow(pr_manager).to receive(:add_comment)

      expect(pr_manager).to receive(:add_label).with(123, "needs-human")

      orchestrator.run
    end
  end

  describe "#run with push" do
    it "skips non-gardener pushes" do
      orchestrator = described_class.new(
        config: config,
        event_type: "push",
        event_data: { "head_commit" => { "message" => "Regular commit" } },
        category: "auto"
      )

      expect { orchestrator.run }.to output(/not from a gardener PR/).to_stdout
    end

    it "starts new task after gardener merge" do
      orchestrator = described_class.new(
        config: config,
        event_type: "push",
        event_data: { "head_commit" => { "message" => "[gardener] Add tests" } },
        category: "auto"
      )

      allow(pr_manager).to receive(:open_gardener_prs).and_return([double, double])

      expect { orchestrator.run }.to output(/Gardener PR merged/).to_stdout
    end
  end
end
