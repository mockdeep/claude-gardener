# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::WorkSelector do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:issue_manager) { instance_double(ClaudeGardener::IssueManager) }
  let(:pr_manager) { instance_double(ClaudeGardener::PrManager) }
  let(:config) do
    ClaudeGardener::Config.new(
      "version" => 2,
      "max_concurrent" => 3,
      "categories" => %w[test_coverage security_fixes]
    )
  end

  subject(:selector) { described_class.new }

  before do
    allow(ClaudeGardener::Config).to receive(:load).and_return(config)
    allow(ClaudeGardener::GithubClient).to receive(:new).and_return(github)
    allow(ClaudeGardener::IssueManager).to receive(:new).with(github: github).and_return(issue_manager)
    allow(ClaudeGardener::PrManager).to receive(:new).with(github: github, config: config).and_return(pr_manager)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CONFIG_PATH", "claude-gardener.yml").and_return("config.yml")
    allow(ENV).to receive(:fetch).with("GITHUB_WORKSPACE", anything).and_return("/workspace")
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)
  end

  describe "#run" do
    it "collects unclaimed tasks up to available slots" do
      allow(pr_manager).to receive(:open_gardener_prs).and_return([double])
      # 1 open PR, max 3 = 2 slots available

      issue = double(number: 10)
      allow(issue_manager).to receive(:find_aggregate_issues)
        .with(category: "test_coverage")
        .and_return([issue])
      allow(issue_manager).to receive(:find_aggregate_issues)
        .with(category: "security_fixes")
        .and_return([])
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(
        "- [ ] Task 1\n- [ ] Task 2\n- [ ] Task 3\n"
      )

      output = capture_stdout { selector.run }

      expect(output).to include("Found 2 tasks")
      expect(output).to include('"issue":10')
    end

    it "skips when at capacity" do
      allow(pr_manager).to receive(:open_gardener_prs).and_return([double, double, double])

      output = capture_stdout { selector.run }

      expect(output).to include("At capacity")
      expect(output).to include("skipped=true")
    end

    it "skips when no unclaimed items" do
      allow(pr_manager).to receive(:open_gardener_prs).and_return([])
      allow(issue_manager).to receive(:find_aggregate_issues).and_return([])

      output = capture_stdout { selector.run }

      expect(output).to include("No unclaimed work items")
    end
  end

  private

  def capture_stdout(&block)
    output = StringIO.new
    $stdout = output
    block.call
    output.string
  ensure
    $stdout = STDOUT
  end
end
