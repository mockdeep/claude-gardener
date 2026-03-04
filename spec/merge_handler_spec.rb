# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::MergeHandler do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:issue_manager) { instance_double(ClaudeGardener::IssueManager) }

  subject(:handler) { described_class.new }

  before do
    allow(ClaudeGardener::GithubClient).to receive(:new).and_return(github)
    allow(ClaudeGardener::IssueManager).to receive(:new).with(github: github).and_return(issue_manager)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PR_NUMBER").and_return("42")
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)
  end

  describe "#run" do
    it "checks off the completed item and looks for conflicts" do
      pr = double(
        body: "aggregate_issue: 10\ncategory: test_coverage",
        labels: [double(name: "claude-gardener")]
      )
      allow(github).to receive(:pull_request).with(42).and_return(pr)
      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: ["claude-gardener"])
        .and_return([])

      issue_body = "- [ ] Task A (claimed by PR #42)\n- [ ] Task B\n"
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(issue_body)
      allow(issue_manager).to receive(:update_issue_body)

      output = capture_stdout { handler.run }

      expect(output).to include("Checked off item in issue #10")
      expect(output).to include("skipped=false")
      expect(issue_manager).to have_received(:update_issue_body).with(
        10,
        a_string_including("- [x] Task A")
      )
    end

    it "skips non-gardener PRs" do
      pr = double(labels: [double(name: "bug")])
      allow(github).to receive(:pull_request).with(42).and_return(pr)

      output = capture_stdout { handler.run }

      expect(output).to include("skipped=true")
    end

    it "handles PRs without aggregate issue link" do
      pr = double(
        body: "category: test_coverage",
        labels: [double(name: "claude-gardener")]
      )
      allow(github).to receive(:pull_request).with(42).and_return(pr)
      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: ["claude-gardener"])
        .and_return([])

      output = capture_stdout { handler.run }

      expect(output).to include("skipped=false")
    end

    it "reports conflicting PRs" do
      pr = double(
        body: "category: test_coverage",
        labels: [double(name: "claude-gardener")]
      )
      conflicting_pr = double(number: 50, mergeable: false)
      allow(github).to receive(:pull_request).with(42).and_return(pr)
      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: ["claude-gardener"])
        .and_return([conflicting_pr])

      output = capture_stdout { handler.run }

      expect(output).to include("conflicting_prs=50")
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
