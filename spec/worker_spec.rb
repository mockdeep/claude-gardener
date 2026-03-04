# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::Worker do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:issue_manager) { instance_double(ClaudeGardener::IssueManager) }
  let(:config) do
    ClaudeGardener::Config.new(
      "version" => 2,
      "categories" => %w[test_coverage],
      "excluded_paths" => ["vendor/**"]
    )
  end

  let(:task_json) do
    '{"issue":10,"index":0,"category":"test_coverage","text":"Add tests for UserController"}'
  end

  subject(:worker) { described_class.new }

  before do
    allow(ClaudeGardener::Config).to receive(:load).and_return(config)
    allow(ClaudeGardener::GithubClient).to receive(:new).and_return(github)
    allow(ClaudeGardener::IssueManager).to receive(:new).with(github: github).and_return(issue_manager)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CONFIG_PATH", "claude-gardener.yml").and_return("config.yml")
    allow(ENV).to receive(:fetch).with("GITHUB_WORKSPACE", anything).and_return("/workspace")
    allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("TASK").and_return(task_json)
  end

  describe "#run" do
    it "outputs a work prompt when task is available" do
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(
        "- [ ] Add tests for UserController\n"
      )

      output = capture_stdout { worker.run }

      expect(output).to include("skipped=false")
      expect(output).to include("category=test_coverage")
      expect(output).to include("Add tests for UserController")
    end

    it "skips when task is already claimed" do
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(
        "- [ ] Add tests for UserController (claimed by PR #42)\n"
      )

      output = capture_stdout { worker.run }

      expect(output).to include("skipped=true")
    end

    it "skips when task is already completed" do
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(
        "- [x] Add tests for UserController\n"
      )

      output = capture_stdout { worker.run }

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
