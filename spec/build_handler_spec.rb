# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::BuildHandler do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }

  subject(:handler) { described_class.new }

  before do
    allow(ClaudeGardener::GithubClient).to receive(:new).and_return(github)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PR_NUMBER").and_return("42")
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("FAILURE_LOG", anything).and_return("Error: test failed")
  end

  describe "#run" do
    it "builds a fix prompt for build failures" do
      pr = double(
        title: "[Gardener] Test coverage improvements",
        body: "category: test_coverage\nfix_attempts: 0",
        labels: [double(name: "claude-gardener")],
        head: double(ref: "gardener/test_coverage/20240101")
      )
      allow(github).to receive(:pull_request).with(42).and_return(pr)

      output = capture_stdout { handler.run }

      expect(output).to include("skipped=false")
      expect(output).to include("Error: test failed")
      expect(output).to include("fix_attempt=1")
    end

    it "skips non-gardener PRs" do
      pr = double(labels: [double(name: "bug")])
      allow(github).to receive(:pull_request).with(42).and_return(pr)

      output = capture_stdout { handler.run }

      expect(output).to include("skipped=true")
    end

    it "skips when max fix attempts exceeded" do
      pr = double(
        body: "category: test_coverage\nfix_attempts: 3",
        labels: [double(name: "claude-gardener")]
      )
      allow(github).to receive(:pull_request).with(42).and_return(pr)
      allow(github).to receive(:add_comment)

      output = capture_stdout { handler.run }

      expect(output).to include("skipped=true")
      expect(github).to have_received(:add_comment).with(
        42,
        a_string_including("exhausted")
      )
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
