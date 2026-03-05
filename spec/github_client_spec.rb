# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::GithubClient do
  let(:token) { "test_token" }
  let(:repository) { "owner/repo" }
  let(:client) { instance_double(Octokit::Client) }

  subject { described_class.new(token: token, repository: repository) }

  before do
    allow(Octokit::Client).to receive(:new).with(access_token: token).and_return(client)
    allow(client).to receive(:auto_paginate=).with(false)
  end

  describe "#initialize" do
    it "initializes with provided token and repository" do
      expect(Octokit::Client).to have_received(:new).with(access_token: token)
      expect(client).to have_received(:auto_paginate=).with(false)
      expect(subject.repository).to eq(repository)
    end

    context "when token is not provided" do
      it "uses GITHUB_TOKEN environment variable" do
        ENV["GITHUB_TOKEN"] = "env_token"
        described_class.new(repository: repository)

        expect(Octokit::Client).to have_received(:new).with(access_token: "env_token")
      ensure
        ENV.delete("GITHUB_TOKEN")
      end
    end

    context "when repository is not provided" do
      it "uses GITHUB_REPOSITORY environment variable" do
        ENV["GITHUB_REPOSITORY"] = "env/repo"
        client_instance = described_class.new(token: token)

        expect(client_instance.repository).to eq("env/repo")
      ensure
        ENV.delete("GITHUB_REPOSITORY")
      end
    end
  end

  describe "#pull_requests" do
    let(:pr1) { double("PR1", labels: [double(name: "bug"), double(name: "urgent")]) }
    let(:pr2) { double("PR2", labels: [double(name: "feature")]) }
    let(:pr3) { double("PR3", labels: [double(name: "bug")]) }
    let(:all_prs) { [pr1, pr2, pr3] }

    before do
      allow(client).to receive(:pull_requests).and_return(all_prs)
    end

    it "returns all pull requests by default" do
      result = subject.pull_requests

      expect(client).to have_received(:pull_requests).with(repository, state: "open")
      expect(result).to eq(all_prs)
    end

    it "filters by state" do
      subject.pull_requests(state: "closed")

      expect(client).to have_received(:pull_requests).with(repository, state: "closed")
    end

    it "filters by single label" do
      result = subject.pull_requests(labels: ["bug"])

      expect(result).to eq([pr1, pr3])
    end

    it "filters by multiple labels" do
      result = subject.pull_requests(labels: ["bug", "urgent"])

      expect(result).to eq([pr1])
    end

    it "returns empty array when no PRs match labels" do
      result = subject.pull_requests(labels: ["nonexistent"])

      expect(result).to eq([])
    end
  end

  describe "#pull_request" do
    let(:pr) { double("PR") }

    it "returns specific pull request" do
      allow(client).to receive(:pull_request).with(repository, 123).and_return(pr)

      result = subject.pull_request(123)

      expect(result).to eq(pr)
    end
  end

  describe "#pull_request_files" do
    let(:files) { [double("File1"), double("File2")] }

    it "returns files for pull request" do
      allow(client).to receive(:pull_request_files).with(repository, 123).and_return(files)

      result = subject.pull_request_files(123)

      expect(result).to eq(files)
    end
  end

  describe "#review_comments" do
    let(:comments) { [double("Comment1"), double("Comment2")] }

    it "returns review comments for pull request" do
      allow(client).to receive(:pull_request_comments).with(repository, 123).and_return(comments)

      result = subject.review_comments(123)

      expect(result).to eq(comments)
    end
  end

  describe "#issue_comments" do
    let(:comments) { [double("Comment1"), double("Comment2")] }

    it "returns issue comments for pull request" do
      allow(client).to receive(:issue_comments).with(repository, 123).and_return(comments)

      result = subject.issue_comments(123)

      expect(result).to eq(comments)
    end
  end

  describe "#create_pull_request" do
    let(:pr) { double("PR") }
    let(:params) { { base: "main", head: "feature", title: "Test PR", body: "Test body" } }

    it "creates pull request" do
      allow(client).to receive(:create_pull_request).and_return(pr)

      result = subject.create_pull_request(**params)

      expect(client).to have_received(:create_pull_request)
        .with(repository, "main", "feature", "Test PR", "Test body")
      expect(result).to eq(pr)
    end
  end

  describe "#add_labels" do
    it "adds labels to pull request" do
      allow(client).to receive(:add_labels_to_an_issue)

      subject.add_labels(123, ["bug", "urgent"])

      expect(client).to have_received(:add_labels_to_an_issue)
        .with(repository, 123, ["bug", "urgent"])
    end
  end

  describe "#add_comment" do
    it "adds comment to pull request" do
      allow(client).to receive(:add_comment)

      subject.add_comment(123, "Test comment")

      expect(client).to have_received(:add_comment)
        .with(repository, 123, "Test comment")
    end
  end

  describe "#update_comment" do
    it "updates comment" do
      allow(client).to receive(:update_comment)

      subject.update_comment(456, "Updated comment")

      expect(client).to have_received(:update_comment)
        .with(repository, 456, "Updated comment")
    end
  end

  describe "#create_branch" do
    let(:ref_object) { double("RefObject", sha: "abc123") }
    let(:ref) { double("Ref", object: ref_object) }

    before do
      allow(subject).to receive(:default_branch).and_return("main")
      allow(client).to receive(:ref).with(repository, "heads/main").and_return(ref)
      allow(client).to receive(:create_ref)
    end

    it "creates branch from default branch" do
      subject.create_branch("feature-branch")

      expect(client).to have_received(:create_ref)
        .with(repository, "refs/heads/feature-branch", "abc123")
    end

    it "creates branch from specified branch" do
      allow(client).to receive(:ref).with(repository, "heads/develop").and_return(ref)

      subject.create_branch("feature-branch", from: "develop")

      expect(client).to have_received(:ref).with(repository, "heads/develop")
      expect(client).to have_received(:create_ref)
        .with(repository, "refs/heads/feature-branch", "abc123")
    end
  end

  describe "#delete_branch" do
    it "deletes branch" do
      allow(client).to receive(:delete_ref)

      subject.delete_branch("feature-branch")

      expect(client).to have_received(:delete_ref)
        .with(repository, "heads/feature-branch")
    end

    it "ignores error if branch doesn't exist" do
      allow(client).to receive(:delete_ref).and_raise(Octokit::UnprocessableEntity)

      expect { subject.delete_branch("nonexistent") }.not_to raise_error
    end
  end

  describe "#default_branch" do
    let(:repo) { double("Repository", default_branch: "main") }

    it "returns default branch" do
      allow(client).to receive(:repository).with(repository).and_return(repo)

      result = subject.default_branch

      expect(result).to eq("main")
    end

    it "caches the result" do
      allow(client).to receive(:repository).with(repository).and_return(repo)

      subject.default_branch
      subject.default_branch

      expect(client).to have_received(:repository).once
    end
  end

  describe "#ensure_label_exists" do
    it "returns existing label" do
      label = double("Label")
      allow(client).to receive(:label).with(repository, "test").and_return(label)

      result = subject.ensure_label_exists("test")

      expect(result).to eq(label)
      expect(client).not_to have_received(:add_label)
    end

    it "creates label if it doesn't exist" do
      label = double("Label")
      allow(client).to receive(:label).and_raise(Octokit::NotFound)
      allow(client).to receive(:add_label).and_return(label)

      result = subject.ensure_label_exists("test", color: "ff0000", description: "Test label")

      expect(client).to have_received(:add_label)
        .with(repository, "test", "ff0000", description: "Test label")
      expect(result).to eq(label)
    end

    it "uses default color when not specified" do
      allow(client).to receive(:label).and_raise(Octokit::NotFound)
      allow(client).to receive(:add_label)

      subject.ensure_label_exists("test")

      expect(client).to have_received(:add_label)
        .with(repository, "test", "0e8a16", description: nil)
    end
  end

  describe "#create_issue" do
    let(:issue) { double("Issue") }

    it "creates issue" do
      allow(client).to receive(:create_issue).and_return(issue)

      result = subject.create_issue(title: "Test Issue", body: "Test body", labels: ["bug"])

      expect(client).to have_received(:create_issue)
        .with(repository, "Test Issue", "Test body", labels: ["bug"])
      expect(result).to eq(issue)
    end
  end

  describe "#update_issue" do
    it "updates issue with all options" do
      allow(client).to receive(:update_issue)

      subject.update_issue(123, body: "New body", state: "closed", labels: ["fixed"])

      expect(client).to have_received(:update_issue)
        .with(repository, 123, { body: "New body", state: "closed", labels: ["fixed"] })
    end

    it "updates issue with partial options" do
      allow(client).to receive(:update_issue)

      subject.update_issue(123, body: "New body")

      expect(client).to have_received(:update_issue)
        .with(repository, 123, { body: "New body" })
    end
  end

  describe "#close_issue" do
    it "closes issue" do
      allow(client).to receive(:close_issue)

      subject.close_issue(123)

      expect(client).to have_received(:close_issue).with(repository, 123)
    end
  end

  describe "#list_issues" do
    let(:issues) { [double("Issue1"), double("Issue2")] }

    before do
      allow(client).to receive(:list_issues).and_return(issues)
    end

    it "lists issues with default options" do
      result = subject.list_issues

      expect(client).to have_received(:list_issues).with(repository, state: "open")
      expect(result).to eq(issues)
    end

    it "lists issues with state filter" do
      subject.list_issues(state: "closed")

      expect(client).to have_received(:list_issues).with(repository, state: "closed")
    end

    it "lists issues with label filter" do
      subject.list_issues(labels: ["bug", "urgent"])

      expect(client).to have_received(:list_issues)
        .with(repository, state: "open", labels: "bug,urgent")
    end
  end

  describe "#issue" do
    let(:issue) { double("Issue") }

    it "returns specific issue" do
      allow(client).to receive(:issue).with(repository, 123).and_return(issue)

      result = subject.issue(123)

      expect(result).to eq(issue)
    end
  end
end