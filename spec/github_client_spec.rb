# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::GithubClient do
  let(:token) { "gh_token_123" }
  let(:repository) { "owner/repo" }
  let(:octokit_client) { instance_double(Octokit::Client) }

  before do
    allow(Octokit::Client).to receive(:new).and_return(octokit_client)
    allow(octokit_client).to receive(:auto_paginate=)
  end

  subject(:client) { described_class.new(token: token, repository: repository) }

  describe "#initialize" do
    it "initializes with provided token and repository" do
      expect(Octokit::Client).to have_received(:new).with(access_token: token)
      expect(octokit_client).to have_received(:auto_paginate=).with(false)
      expect(client.repository).to eq(repository)
    end

    it "uses environment variables when token not provided" do
      allow(ENV).to receive(:fetch).with("GITHUB_TOKEN").and_return("env_token")
      allow(ENV).to receive(:fetch).with("GITHUB_REPOSITORY").and_return("env/repo")

      client = described_class.new
      
      expect(Octokit::Client).to have_received(:new).with(access_token: "env_token")
      expect(client.repository).to eq("env/repo")
    end

    it "raises error when environment variables are missing" do
      allow(ENV).to receive(:fetch).with("GITHUB_TOKEN").and_raise(KeyError)

      expect { described_class.new }.to raise_error(KeyError)
    end
  end

  describe "#pull_requests" do
    let(:pr1) { double(labels: [double(name: "bug"), double(name: "priority-high")]) }
    let(:pr2) { double(labels: [double(name: "feature")]) }
    let(:prs) { [pr1, pr2] }

    before do
      allow(octokit_client).to receive(:pull_requests).and_return(prs)
    end

    it "returns all PRs when no labels filter" do
      result = client.pull_requests

      expect(octokit_client).to have_received(:pull_requests).with(repository, state: "open")
      expect(result).to eq(prs)
    end

    it "filters PRs by single label" do
      result = client.pull_requests(labels: ["bug"])

      expect(result).to eq([pr1])
    end

    it "filters PRs by multiple labels (all must match)" do
      result = client.pull_requests(labels: ["bug", "priority-high"])

      expect(result).to eq([pr1])
    end

    it "returns empty when no PRs match labels" do
      result = client.pull_requests(labels: ["nonexistent"])

      expect(result).to eq([])
    end

    it "supports different states" do
      client.pull_requests(state: "closed")

      expect(octokit_client).to have_received(:pull_requests).with(repository, state: "closed")
    end
  end

  describe "#pull_request" do
    it "returns specific pull request" do
      pr = double
      allow(octokit_client).to receive(:pull_request).with(repository, 123).and_return(pr)

      result = client.pull_request(123)

      expect(result).to eq(pr)
    end
  end

  describe "#pull_request_files" do
    it "returns files for pull request" do
      files = [double, double]
      allow(octokit_client).to receive(:pull_request_files).with(repository, 123).and_return(files)

      result = client.pull_request_files(123)

      expect(result).to eq(files)
    end
  end

  describe "#review_comments" do
    it "returns review comments for pull request" do
      comments = [double, double]
      allow(octokit_client).to receive(:pull_request_comments).with(repository, 123).and_return(comments)

      result = client.review_comments(123)

      expect(result).to eq(comments)
    end
  end

  describe "#issue_comments" do
    it "returns issue comments for pull request" do
      comments = [double, double]
      allow(octokit_client).to receive(:issue_comments).with(repository, 123).and_return(comments)

      result = client.issue_comments(123)

      expect(result).to eq(comments)
    end
  end

  describe "#create_pull_request" do
    it "creates pull request with given parameters" do
      pr = double
      allow(octokit_client).to receive(:create_pull_request).and_return(pr)

      result = client.create_pull_request(
        base: "main",
        head: "feature-branch",
        title: "Add feature",
        body: "Description"
      )

      expect(octokit_client).to have_received(:create_pull_request).with(
        repository, "main", "feature-branch", "Add feature", "Description"
      )
      expect(result).to eq(pr)
    end
  end

  describe "#add_labels" do
    it "adds labels to pull request" do
      allow(octokit_client).to receive(:add_labels_to_an_issue)

      client.add_labels(123, ["bug", "enhancement"])

      expect(octokit_client).to have_received(:add_labels_to_an_issue).with(
        repository, 123, ["bug", "enhancement"]
      )
    end
  end

  describe "#add_comment" do
    it "adds comment to pull request" do
      allow(octokit_client).to receive(:add_comment)

      client.add_comment(123, "Great work!")

      expect(octokit_client).to have_received(:add_comment).with(repository, 123, "Great work!")
    end
  end

  describe "#update_comment" do
    it "updates existing comment" do
      allow(octokit_client).to receive(:update_comment)

      client.update_comment(456, "Updated comment")

      expect(octokit_client).to have_received(:update_comment).with(repository, 456, "Updated comment")
    end
  end

  describe "#create_branch" do
    let(:ref) { double(object: double(sha: "abc123")) }

    before do
      allow(client).to receive(:default_branch).and_return("main")
      allow(octokit_client).to receive(:ref).and_return(ref)
      allow(octokit_client).to receive(:create_ref)
    end

    it "creates branch from default branch when no 'from' specified" do
      client.create_branch("new-feature")

      expect(octokit_client).to have_received(:ref).with(repository, "heads/main")
      expect(octokit_client).to have_received(:create_ref).with(repository, "refs/heads/new-feature", "abc123")
    end

    it "creates branch from specified branch" do
      client.create_branch("new-feature", from: "develop")

      expect(octokit_client).to have_received(:ref).with(repository, "heads/develop")
      expect(octokit_client).to have_received(:create_ref).with(repository, "refs/heads/new-feature", "abc123")
    end
  end

  describe "#delete_branch" do
    it "deletes branch successfully" do
      allow(octokit_client).to receive(:delete_ref)

      client.delete_branch("old-feature")

      expect(octokit_client).to have_received(:delete_ref).with(repository, "heads/old-feature")
    end

    it "ignores error when branch doesn't exist" do
      allow(octokit_client).to receive(:delete_ref).and_raise(Octokit::UnprocessableEntity)

      expect { client.delete_branch("nonexistent") }.not_to raise_error
    end
  end

  describe "#default_branch" do
    it "returns default branch and caches result" do
      repo = double(default_branch: "main")
      allow(octokit_client).to receive(:repository).with(repository).and_return(repo)

      result1 = client.default_branch
      result2 = client.default_branch

      expect(result1).to eq("main")
      expect(result2).to eq("main")
      expect(octokit_client).to have_received(:repository).once
    end
  end

  describe "#ensure_label_exists" do
    it "returns existing label" do
      label = double
      allow(octokit_client).to receive(:label).with(repository, "bug").and_return(label)

      result = client.ensure_label_exists("bug")

      expect(result).to eq(label)
      expect(octokit_client).not_to have_received(:add_label)
    end

    it "creates label when it doesn't exist" do
      label = double
      allow(octokit_client).to receive(:label).and_raise(Octokit::NotFound)
      allow(octokit_client).to receive(:add_label).and_return(label)

      result = client.ensure_label_exists("new-label", color: "ff0000", description: "New label")

      expect(octokit_client).to have_received(:add_label).with(
        repository, "new-label", "ff0000", description: "New label"
      )
      expect(result).to eq(label)
    end

    it "uses default color when not specified" do
      allow(octokit_client).to receive(:label).and_raise(Octokit::NotFound)
      allow(octokit_client).to receive(:add_label)

      client.ensure_label_exists("default-color")

      expect(octokit_client).to have_received(:add_label).with(
        repository, "default-color", "0e8a16", description: nil
      )
    end
  end

  describe "#create_issue" do
    it "creates issue with given parameters" do
      issue = double
      allow(octokit_client).to receive(:create_issue).and_return(issue)

      result = client.create_issue(
        title: "Bug report",
        body: "Description",
        labels: ["bug", "priority-high"]
      )

      expect(octokit_client).to have_received(:create_issue).with(
        repository, "Bug report", "Description", labels: ["bug", "priority-high"]
      )
      expect(result).to eq(issue)
    end

    it "creates issue with empty labels by default" do
      issue = double
      allow(octokit_client).to receive(:create_issue).and_return(issue)

      client.create_issue(title: "Simple issue", body: "Description")

      expect(octokit_client).to have_received(:create_issue).with(
        repository, "Simple issue", "Description", labels: []
      )
    end
  end

  describe "#update_issue" do
    before do
      allow(octokit_client).to receive(:update_issue)
    end

    it "updates only specified fields" do
      client.update_issue(123, body: "New body")

      expect(octokit_client).to have_received(:update_issue).with(repository, 123, { body: "New body" })
    end

    it "updates multiple fields" do
      client.update_issue(123, body: "New body", state: "closed", labels: ["resolved"])

      expect(octokit_client).to have_received(:update_issue).with(
        repository, 123, { body: "New body", state: "closed", labels: ["resolved"] }
      )
    end

    it "sends empty options when no fields specified" do
      client.update_issue(123)

      expect(octokit_client).to have_received(:update_issue).with(repository, 123, {})
    end
  end

  describe "#close_issue" do
    it "closes issue" do
      allow(octokit_client).to receive(:close_issue)

      client.close_issue(123)

      expect(octokit_client).to have_received(:close_issue).with(repository, 123)
    end
  end

  describe "#list_issues" do
    let(:issues) { [double, double] }

    before do
      allow(octokit_client).to receive(:list_issues).and_return(issues)
    end

    it "lists issues with default state" do
      result = client.list_issues

      expect(octokit_client).to have_received(:list_issues).with(repository, state: "open")
      expect(result).to eq(issues)
    end

    it "lists issues with specified state" do
      client.list_issues(state: "closed")

      expect(octokit_client).to have_received(:list_issues).with(repository, state: "closed")
    end

    it "lists issues with labels filter" do
      client.list_issues(labels: ["bug", "priority-high"])

      expect(octokit_client).to have_received(:list_issues).with(
        repository, state: "open", labels: "bug,priority-high"
      )
    end

    it "lists issues with both state and labels" do
      client.list_issues(state: "all", labels: ["enhancement"])

      expect(octokit_client).to have_received(:list_issues).with(
        repository, state: "all", labels: "enhancement"
      )
    end
  end

  describe "#issue" do
    it "returns specific issue" do
      issue = double
      allow(octokit_client).to receive(:issue).with(repository, 123).and_return(issue)

      result = client.issue(123)

      expect(result).to eq(issue)
    end
  end

  describe "error handling" do
    it "propagates Octokit errors for pull_request" do
      allow(octokit_client).to receive(:pull_request).and_raise(Octokit::NotFound)

      expect { client.pull_request(999) }.to raise_error(Octokit::NotFound)
    end

    it "propagates Octokit errors for create_pull_request" do
      allow(octokit_client).to receive(:create_pull_request).and_raise(Octokit::UnprocessableEntity)

      expect {
        client.create_pull_request(base: "main", head: "invalid", title: "Test", body: "Test")
      }.to raise_error(Octokit::UnprocessableEntity)
    end

    it "propagates Octokit errors for branch operations" do
      allow(octokit_client).to receive(:ref).and_raise(Octokit::NotFound)

      expect { client.create_branch("new-branch") }.to raise_error(Octokit::NotFound)
    end

    it "propagates Octokit errors for issue operations" do
      allow(octokit_client).to receive(:create_issue).and_raise(Octokit::Unauthorized)

      expect {
        client.create_issue(title: "Test", body: "Test")
      }.to raise_error(Octokit::Unauthorized)
    end
  end
end