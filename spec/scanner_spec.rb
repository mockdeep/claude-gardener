# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::Scanner do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:issue_manager) { instance_double(ClaudeGardener::IssueManager) }
  let(:config) do
    ClaudeGardener::Config.new(
      "version" => 2,
      "categories" => %w[test_coverage],
      "excluded_paths" => ["vendor/**"]
    )
  end

  subject(:scanner) { described_class.new }

  before do
    allow(ClaudeGardener::Config).to receive(:load).and_return(config)
    allow(ClaudeGardener::GithubClient).to receive(:new).and_return(github)
    allow(ClaudeGardener::IssueManager).to receive(:new).with(github: github).and_return(issue_manager)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CONFIG_PATH", "claude-gardener.yml").and_return("config.yml")
    allow(ENV).to receive(:fetch).with("GITHUB_WORKSPACE", anything).and_return("/workspace")
    allow(ENV).to receive(:fetch).with("CATEGORY").and_return("test_coverage")
    allow(ENV).to receive(:fetch).with("PLAN_ISSUE", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)
  end

  describe "#run" do
    it "outputs the scan prompt and category" do
      output = capture_stdout { scanner.run }

      expect(output).to include("prompt=")
      expect(output).to include("category=test_coverage")
    end

    it "includes excluded paths in the prompt" do
      output = capture_stdout { scanner.run }

      expect(output).to include("vendor/**")
    end
  end

  describe "#post_scan" do
    let(:claude_output) do
      <<~MD
        - [ ] Add tests for UserController
        - [ ] Add tests for OrderService
      MD
    end

    before do
      allow(ENV).to receive(:fetch).with("CLAUDE_OUTPUT", "").and_return(claude_output)
    end

    it "creates an aggregate issue from Claude's output" do
      allow(issue_manager).to receive(:find_aggregate_issues)
        .with(category: "test_coverage")
        .and_return([])
      allow(issue_manager).to receive(:create_aggregate_issue)
        .with(
          category: "test_coverage",
          items: ["Add tests for UserController", "Add tests for OrderService"]
        )
        .and_return(double(number: 20))

      output = capture_stdout { scanner.post_scan }

      expect(output).to include("Created aggregate issue #20 with 2 items")
    end

    it "closes old aggregate issues" do
      old_issue = double(number: 10)
      allow(issue_manager).to receive(:find_aggregate_issues)
        .with(category: "test_coverage")
        .and_return([old_issue])
      allow(issue_manager).to receive(:create_aggregate_issue)
        .and_return(double(number: 20))
      allow(issue_manager).to receive(:close_aggregate_issue)

      capture_stdout { scanner.post_scan }

      expect(issue_manager).to have_received(:close_aggregate_issue).with(10, replaced_by: 20)
    end

    it "checks off the plan issue item when plan_issue is set" do
      allow(ENV).to receive(:fetch).with("PLAN_ISSUE", nil).and_return("5")
      # Re-create scanner to pick up new env
      scanner_with_plan = described_class.new

      allow(issue_manager).to receive(:find_aggregate_issues).and_return([])
      allow(issue_manager).to receive(:create_aggregate_issue).and_return(double(number: 20))
      allow(issue_manager).to receive(:get_issue_body).with(5).and_return(
        "- [ ] test_coverage\n- [ ] security_fixes\n"
      )
      allow(issue_manager).to receive(:update_issue_body)

      capture_stdout { scanner_with_plan.post_scan }

      expect(issue_manager).to have_received(:update_issue_body).with(
        5,
        a_string_including("- [x] test_coverage")
      )
    end

    it "aborts when Claude output is empty" do
      allow(ENV).to receive(:fetch).with("CLAUDE_OUTPUT", "").and_return("")

      expect { scanner.post_scan }.to raise_error(SystemExit)
        .and output(/No scan output/).to_stderr
    end

    it "skips when no checklist items found" do
      allow(ENV).to receive(:fetch).with("CLAUDE_OUTPUT", "").and_return("Just some text")

      output = capture_stdout { scanner.post_scan }

      expect(output).to include("No checklist items found")
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
