# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::ScanPlanner do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:issue_manager) { instance_double(ClaudeGardener::IssueManager) }
  let(:config) do
    ClaudeGardener::Config.new(
      "version" => 2,
      "categories" => %w[test_coverage security_fixes]
    )
  end

  subject(:planner) { described_class.new }

  before do
    allow(ClaudeGardener::Config).to receive(:load).and_return(config)
    allow(ClaudeGardener::GithubClient).to receive(:new).and_return(github)
    allow(ClaudeGardener::IssueManager).to receive(:new).with(github: github).and_return(issue_manager)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CONFIG_PATH", "claude-gardener.yml").and_return("claude-gardener.yml")
    allow(ENV).to receive(:fetch).with("GITHUB_WORKSPACE", anything).and_return("/workspace")
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)
  end

  describe "#run" do
    it "creates a plan issue when none exists" do
      allow(issue_manager).to receive(:find_plan_issue).and_return(nil)
      allow(issue_manager).to receive(:create_plan_issue)
        .with(categories: %w[test_coverage security_fixes])
        .and_return(double(number: 10))

      expect { planner.run }.to output(/Created scan plan issue #10/).to_stdout
    end

    it "skips when a plan issue already exists" do
      allow(issue_manager).to receive(:find_plan_issue).and_return(double(number: 5))

      expect { planner.run }.to output(/Plan issue already exists/).to_stdout
    end
  end
end
