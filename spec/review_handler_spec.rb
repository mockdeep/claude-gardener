# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::ReviewHandler do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }

  subject(:handler) { described_class.new }

  before do
    allow(ClaudeGardener::GithubClient).to receive(:new).and_return(github)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PR_NUMBER").and_return("42")
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)
  end

  describe "#run" do
    it "builds a review prompt from comments" do
      pr = double(
        title: "[Gardener] Test coverage improvements",
        body: "category: test_coverage",
        labels: [double(name: "claude-gardener")],
        head: double(ref: "gardener/test_coverage/20240101")
      )
      comments = [
        double(path: "lib/user.rb", line: 10, body: "This should handle nil")
      ]

      allow(github).to receive(:pull_request).with(42).and_return(pr)
      allow(github).to receive(:review_comments).with(42).and_return(comments)

      output = capture_stdout { handler.run }

      expect(output).to include("skipped=false")
      expect(output).to include("This should handle nil")
      expect(output).to include("category=test_coverage")
    end

    it "skips non-gardener PRs" do
      pr = double(labels: [double(name: "bug")])
      allow(github).to receive(:pull_request).with(42).and_return(pr)

      output = capture_stdout { handler.run }

      expect(output).to include("skipped=true")
    end

    it "skips when no review comments" do
      pr = double(
        labels: [double(name: "claude-gardener")],
        body: "category: test_coverage"
      )
      allow(github).to receive(:pull_request).with(42).and_return(pr)
      allow(github).to receive(:review_comments).with(42).and_return([])

      output = capture_stdout { handler.run }

      expect(output).to include("skipped=true")
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
