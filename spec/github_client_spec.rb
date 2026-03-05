# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::GithubClient do
  let(:token) { "test-token" }
  let(:repository) { "owner/repo" }

  subject(:client) { described_class.new(token: token, repository: repository) }

  before do
    stub_const("ENV", ENV.to_hash.merge(
      "GITHUB_TOKEN" => "env-token",
      "GITHUB_REPOSITORY" => "env/repo"
    ))
  end

  describe "#initialize" do
    it "uses provided token and repository" do
      client = described_class.new(token: token, repository: repository)
      expect(client.repository).to eq(repository)
    end

    it "falls back to environment variables" do
      client = described_class.new
      expect(client.repository).to eq("env/repo")
    end

    context "when environment variables are missing" do
      before do
        stub_const("ENV", {})
      end

      it "raises KeyError for missing GITHUB_TOKEN" do
        expect { described_class.new }.to raise_error(KeyError, /GITHUB_TOKEN/)
      end

      it "raises KeyError for missing GITHUB_REPOSITORY" do
        expect { described_class.new(token: "token") }.to raise_error(KeyError, /GITHUB_REPOSITORY/)
      end
    end
  end

  describe "#pull_requests" do
    it "returns all open pull requests by default" do
      prs = [{ number: 1, title: "PR 1" }, { number: 2, title: "PR 2" }]
      stub_github_api("/repos/owner/repo/pulls?state=open", response: prs)

      result = client.pull_requests

      expect(result.length).to eq(2)
      expect(result.first[:number]).to eq(1)
    end

    it "filters pull requests by state" do
      prs = [{ number: 1, title: "Closed PR" }]
      stub_github_api("/repos/owner/repo/pulls?state=closed", response: prs)

      result = client.pull_requests(state: "closed")

      expect(result.length).to eq(1)
    end

    it "filters pull requests by labels" do
      prs = [
        { 
          number: 1, 
          title: "PR 1", 
          labels: [{ name: "bug" }, { name: "urgent" }] 
        },
        { 
          number: 2, 
          title: "PR 2", 
          labels: [{ name: "feature" }] 
        }
      ]
      stub_github_api("/repos/owner/repo/pulls?state=open", response: prs)

      result = client.pull_requests(labels: ["bug"])

      expect(result.length).to eq(1)
      expect(result.first[:number]).to eq(1)
    end

    it "handles API errors gracefully" do
      stub_github_api("/repos/owner/repo/pulls?state=open", response: { message: "Not Found" }, status: 404)

      expect { client.pull_requests }.to raise_error(Octokit::NotFound)
    end
  end

  describe "#pull_request" do
    it "returns a specific pull request" do
      pr = { number: 123, title: "Test PR", state: "open" }
      stub_github_api("/repos/owner/repo/pulls/123", response: pr)

      result = client.pull_request(123)

      expect(result[:number]).to eq(123)
      expect(result[:title]).to eq("Test PR")
    end

    it "handles non-existent pull request" do
      stub_github_api("/repos/owner/repo/pulls/999", response: { message: "Not Found" }, status: 404)

      expect { client.pull_request(999) }.to raise_error(Octokit::NotFound)
    end
  end

  describe "#pull_request_files" do
    it "returns files changed in a pull request" do
      files = [
        { filename: "lib/test.rb", status: "modified" },
        { filename: "spec/test_spec.rb", status: "added" }
      ]
      stub_github_api("/repos/owner/repo/pulls/123/files", response: files)

      result = client.pull_request_files(123)

      expect(result.length).to eq(2)
      expect(result.first[:filename]).to eq("lib/test.rb")
    end
  end

  describe "#create_pull_request" do
    it "creates a new pull request" do
      pr = { number: 456, title: "New PR", state: "open" }
      stub_github_api("/repos/owner/repo/pulls", 
                      response: pr, 
                      method: :post)

      result = client.create_pull_request(
        base: "main", 
        head: "feature-branch", 
        title: "New Feature", 
        body: "Description"
      )

      expect(result[:number]).to eq(456)
    end

    it "handles creation errors" do
      error_response = { 
        message: "Validation Failed",
        errors: [{ message: "No commits between main and feature-branch" }]
      }
      stub_github_api("/repos/owner/repo/pulls", 
                      response: error_response, 
                      method: :post,
                      status: 422)

      expect { 
        client.create_pull_request(
          base: "main", 
          head: "feature-branch", 
          title: "Empty PR", 
          body: "No changes"
        )
      }.to raise_error(Octokit::UnprocessableEntity)
    end
  end

  describe "#add_labels" do
    it "adds labels to an issue" do
      stub_github_api("/repos/owner/repo/issues/123/labels", 
                      response: [], 
                      method: :post)

      expect { client.add_labels(123, ["bug", "urgent"]) }.not_to raise_error
    end
  end

  describe "#create_branch" do
    it "creates a branch from the default branch" do
      repo = { default_branch: "main" }
      ref = { object: { sha: "abc123" } }
      
      stub_github_api("/repos/owner/repo", response: repo)
      stub_github_api("/repos/owner/repo/git/refs/heads/main", response: ref)
      stub_github_api("/repos/owner/repo/git/refs", 
                      response: { ref: "refs/heads/feature" }, 
                      method: :post)

      result = client.create_branch("feature")

      expect(result[:ref]).to eq("refs/heads/feature")
    end

    it "creates a branch from a specified base" do
      ref = { object: { sha: "def456" } }
      
      stub_github_api("/repos/owner/repo/git/refs/heads/develop", response: ref)
      stub_github_api("/repos/owner/repo/git/refs", 
                      response: { ref: "refs/heads/feature" }, 
                      method: :post)

      result = client.create_branch("feature", from: "develop")

      expect(result[:ref]).to eq("refs/heads/feature")
    end

    it "handles errors when base branch doesn't exist" do
      stub_github_api("/repos/owner/repo/git/refs/heads/nonexistent", 
                      response: { message: "Not Found" }, 
                      status: 404)

      expect { 
        client.create_branch("feature", from: "nonexistent") 
      }.to raise_error(Octokit::NotFound)
    end

    it "handles errors when branch already exists" do
      ref = { object: { sha: "abc123" } }
      error_response = { 
        message: "Reference already exists",
        documentation_url: "https://docs.github.com/rest/reference/git#create-a-reference"
      }
      
      stub_github_api("/repos/owner/repo/git/refs/heads/main", response: ref)
      stub_github_api("/repos/owner/repo/git/refs", 
                      response: error_response,
                      method: :post, 
                      status: 422)

      expect { 
        client.create_branch("existing-branch") 
      }.to raise_error(Octokit::UnprocessableEntity)
    end
  end

  describe "#delete_branch" do
    it "deletes an existing branch" do
      stub_github_api("/repos/owner/repo/git/refs/heads/feature", 
                      response: {},
                      method: :delete,
                      status: 204)

      expect { client.delete_branch("feature") }.not_to raise_error
    end

    it "ignores UnprocessableEntity errors (branch doesn't exist)" do
      stub_github_api("/repos/owner/repo/git/refs/heads/nonexistent", 
                      response: { message: "Reference does not exist" },
                      method: :delete,
                      status: 422)

      expect { client.delete_branch("nonexistent") }.not_to raise_error
    end

    it "propagates other errors" do
      stub_github_api("/repos/owner/repo/git/refs/heads/protected", 
                      response: { message: "Forbidden" },
                      method: :delete,
                      status: 403)

      expect { 
        client.delete_branch("protected") 
      }.to raise_error(Octokit::Forbidden)
    end
  end

  describe "#default_branch" do
    it "returns and caches the default branch" do
      repo = { default_branch: "main" }
      stub_github_api("/repos/owner/repo", response: repo)

      # Call twice to test caching
      expect(client.default_branch).to eq("main")
      expect(client.default_branch).to eq("main")
    end

    it "handles repository access errors" do
      stub_github_api("/repos/owner/repo", 
                      response: { message: "Not Found" }, 
                      status: 404)

      expect { client.default_branch }.to raise_error(Octokit::NotFound)
    end
  end

  describe "#ensure_label_exists" do
    it "does nothing when label already exists" do
      label = { name: "bug", color: "d73a4a" }
      stub_github_api("/repos/owner/repo/labels/bug", response: label)

      expect { client.ensure_label_exists("bug") }.not_to raise_error
    end

    it "creates label when it doesn't exist" do
      stub_github_api("/repos/owner/repo/labels/new-label", 
                      response: { message: "Not Found" }, 
                      status: 404)
      stub_github_api("/repos/owner/repo/labels", 
                      response: { name: "new-label", color: "0e8a16" },
                      method: :post)

      expect { 
        client.ensure_label_exists("new-label", color: "0e8a16", description: "New label") 
      }.not_to raise_error
    end

    it "handles label creation errors" do
      stub_github_api("/repos/owner/repo/labels/invalid", 
                      response: { message: "Not Found" }, 
                      status: 404)
      stub_github_api("/repos/owner/repo/labels", 
                      response: { message: "Validation Failed" },
                      method: :post,
                      status: 422)

      expect { 
        client.ensure_label_exists("invalid") 
      }.to raise_error(Octokit::UnprocessableEntity)
    end
  end

  describe "#create_issue" do
    it "creates a new issue" do
      issue = { number: 789, title: "Bug Report", state: "open" }
      stub_github_api("/repos/owner/repo/issues", 
                      response: issue, 
                      method: :post)

      result = client.create_issue(
        title: "Bug Report",
        body: "Description",
        labels: ["bug"]
      )

      expect(result[:number]).to eq(789)
    end
  end

  describe "#update_issue" do
    it "updates issue with provided fields" do
      issue = { number: 789, title: "Updated", state: "closed" }
      stub_github_api("/repos/owner/repo/issues/789", 
                      response: issue, 
                      method: :patch)

      result = client.update_issue(789, body: "New body", state: "closed")

      expect(result[:state]).to eq("closed")
    end
  end

  describe "#list_issues" do
    it "lists open issues by default" do
      issues = [{ number: 1 }, { number: 2 }]
      stub_github_api("/repos/owner/repo/issues?state=open", response: issues)

      result = client.list_issues

      expect(result.length).to eq(2)
    end

    it "filters by labels" do
      issues = [{ number: 1 }]
      stub_github_api("/repos/owner/repo/issues?state=open&labels=bug%2Curgent", response: issues)

      result = client.list_issues(labels: ["bug", "urgent"])

      expect(result.length).to eq(1)
    end
  end

  describe "#issue" do
    it "returns a specific issue" do
      issue = { number: 123, title: "Test Issue" }
      stub_github_api("/repos/owner/repo/issues/123", response: issue)

      result = client.issue(123)

      expect(result[:number]).to eq(123)
      expect(result[:title]).to eq("Test Issue")
    end
  end

  describe "#review_comments" do
    it "returns review comments for a pull request" do
      comments = [
        { id: 1, body: "Good change!", user: { login: "reviewer" } },
        { id: 2, body: "Needs work", user: { login: "reviewer2" } }
      ]
      stub_github_api("/repos/owner/repo/pulls/123/comments", response: comments)

      result = client.review_comments(123)

      expect(result.length).to eq(2)
      expect(result.first[:body]).to eq("Good change!")
    end
  end

  describe "#issue_comments" do
    it "returns issue comments for a pull request" do
      comments = [{ id: 1, body: "General comment" }]
      stub_github_api("/repos/owner/repo/issues/123/comments", response: comments)

      result = client.issue_comments(123)

      expect(result.length).to eq(1)
      expect(result.first[:body]).to eq("General comment")
    end
  end

  describe "#add_comment" do
    it "adds a comment to an issue" do
      comment = { id: 456, body: "New comment" }
      stub_github_api("/repos/owner/repo/issues/123/comments", 
                      response: comment, 
                      method: :post)

      result = client.add_comment(123, "New comment")

      expect(result[:id]).to eq(456)
    end
  end

  describe "#update_comment" do
    it "updates an existing comment" do
      comment = { id: 456, body: "Updated comment" }
      stub_github_api("/repos/owner/repo/issues/comments/456", 
                      response: comment, 
                      method: :patch)

      result = client.update_comment(456, "Updated comment")

      expect(result[:body]).to eq("Updated comment")
    end
  end

  describe "#close_issue" do
    it "closes an issue" do
      issue = { number: 123, state: "closed" }
      stub_github_api("/repos/owner/repo/issues/123", 
                      response: issue, 
                      method: :patch)

      result = client.close_issue(123)

      expect(result[:state]).to eq("closed")
    end
  end

  describe "authentication errors" do
    it "handles unauthorized access" do
      stub_github_api("/repos/owner/repo/pulls?state=open", 
                      response: { message: "Bad credentials" }, 
                      status: 401)

      expect { client.pull_requests }.to raise_error(Octokit::Unauthorized)
    end

    it "handles forbidden access" do
      stub_github_api("/repos/owner/repo/pulls?state=open", 
                      response: { message: "Forbidden" }, 
                      status: 403)

      expect { client.pull_requests }.to raise_error(Octokit::Forbidden)
    end
  end

  describe "rate limiting" do
    it "handles rate limit exceeded" do
      stub_github_api("/repos/owner/repo/pulls?state=open", 
                      response: { message: "API rate limit exceeded" }, 
                      status: 403)

      expect { client.pull_requests }.to raise_error(Octokit::Forbidden)
    end
  end

  describe "network errors" do
    it "handles timeout errors" do
      stub_request(:get, "https://api.github.com/repos/owner/repo/pulls?state=open")
        .to_timeout

      expect { client.pull_requests }.to raise_error(Faraday::TimeoutError)
    end

    it "handles connection errors" do
      stub_request(:get, "https://api.github.com/repos/owner/repo/pulls?state=open")
        .to_raise(Faraday::ConnectionFailed)

      expect { client.pull_requests }.to raise_error(Faraday::ConnectionFailed)
    end
  end
end