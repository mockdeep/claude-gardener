# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::LockChecker do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }
  let(:config) do
    ClaudeGardener::Config.new(
      "labels" => { "base" => "claude-gardener" }
    )
  end

  subject(:checker) { described_class.new(github: github, config: config) }

  describe "#locked_files" do
    it "returns files from all open gardener PRs" do
      pr1 = double(number: 1, labels: [double(name: "claude-gardener")])
      pr2 = double(number: 2, labels: [double(name: "claude-gardener")])

      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: ["claude-gardener"])
        .and_return([pr1, pr2])

      allow(github).to receive(:pull_request_files)
        .with(1)
        .and_return([double(filename: "file1.rb"), double(filename: "file2.rb")])
      allow(github).to receive(:pull_request_files)
        .with(2)
        .and_return([double(filename: "file3.rb")])

      locked = checker.locked_files

      expect(locked).to contain_exactly("file1.rb", "file2.rb", "file3.rb")
    end

    it "returns empty set when no gardener PRs exist" do
      allow(github).to receive(:pull_requests)
        .with(state: "open", labels: ["claude-gardener"])
        .and_return([])

      locked = checker.locked_files

      expect(locked).to be_empty
    end
  end

  describe "#file_locked?" do
    it "returns true for locked files" do
      pr = double(number: 1, labels: [double(name: "claude-gardener")])
      allow(github).to receive(:pull_requests).and_return([pr])
      allow(github).to receive(:pull_request_files)
        .with(1)
        .and_return([double(filename: "locked.rb")])

      expect(checker.file_locked?("locked.rb")).to be true
    end

    it "returns false for unlocked files" do
      allow(github).to receive(:pull_requests).and_return([])

      expect(checker.file_locked?("unlocked.rb")).to be false
    end
  end

  describe "#any_locked?" do
    it "returns true if any file is locked" do
      pr = double(number: 1, labels: [double(name: "claude-gardener")])
      allow(github).to receive(:pull_requests).and_return([pr])
      allow(github).to receive(:pull_request_files)
        .with(1)
        .and_return([double(filename: "locked.rb")])

      expect(checker.any_locked?(%w[unlocked.rb locked.rb])).to be true
    end

    it "returns false if no files are locked" do
      allow(github).to receive(:pull_requests).and_return([])

      expect(checker.any_locked?(%w[file1.rb file2.rb])).to be false
    end
  end
end
