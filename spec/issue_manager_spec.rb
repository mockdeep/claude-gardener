# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::IssueManager do
  let(:github) { instance_double(ClaudeGardener::GithubClient) }

  subject(:manager) { described_class.new(github: github) }

  describe "#find_plan_issue" do
    it "returns the first open plan issue" do
      issue = double(number: 1)
      allow(github).to receive(:list_issues)
        .with(state: "open", labels: ["claude-gardener:plan"])
        .and_return([issue])

      expect(manager.find_plan_issue).to eq(issue)
    end

    it "returns nil when no plan issue exists" do
      allow(github).to receive(:list_issues)
        .with(state: "open", labels: ["claude-gardener:plan"])
        .and_return([])

      expect(manager.find_plan_issue).to be_nil
    end
  end

  describe "#create_plan_issue" do
    it "creates an issue with category checklist" do
      allow(github).to receive(:create_issue).and_return(double(number: 5))

      result = manager.create_plan_issue(categories: %w[test_coverage security_fixes])

      expect(github).to have_received(:create_issue).with(
        title: "[Gardener] Scan Plan",
        body: a_string_including("- [ ] test_coverage", "- [ ] security_fixes"),
        labels: ["claude-gardener:plan"]
      )
      expect(result.number).to eq(5)
    end
  end

  describe "#find_aggregate_issues" do
    it "finds issues for a specific category" do
      issues = [double(number: 10)]
      allow(github).to receive(:list_issues)
        .with(state: "open", labels: ["claude-gardener:scan:test_coverage"])
        .and_return(issues)

      expect(manager.find_aggregate_issues(category: "test_coverage")).to eq(issues)
    end

    it "finds all aggregate issues when no category given" do
      issues = [double(number: 10), double(number: 11)]
      allow(github).to receive(:list_issues)
        .with(state: "open", labels: ["claude-gardener:scan"])
        .and_return(issues)

      expect(manager.find_aggregate_issues).to eq(issues)
    end
  end

  describe "#create_aggregate_issue" do
    it "creates an issue with work item checklist" do
      allow(github).to receive(:create_issue).and_return(double(number: 15))

      result = manager.create_aggregate_issue(
        category: "test_coverage",
        items: ["Add tests for UserController", "Add tests for OrderService"]
      )

      expect(github).to have_received(:create_issue).with(
        title: "[Gardener] Test coverage scan results",
        body: a_string_including(
          "- [ ] Add tests for UserController",
          "- [ ] Add tests for OrderService"
        ),
        labels: ["claude-gardener:scan:test_coverage"]
      )
      expect(result.number).to eq(15)
    end
  end

  describe "#close_aggregate_issue" do
    it "closes with replacement link" do
      allow(github).to receive(:add_comment)
      allow(github).to receive(:close_issue)

      manager.close_aggregate_issue(10, replaced_by: 20)

      expect(github).to have_received(:add_comment).with(10, "Closing: replaced by #20")
      expect(github).to have_received(:close_issue).with(10)
    end

    it "closes without replacement" do
      allow(github).to receive(:add_comment)
      allow(github).to receive(:close_issue)

      manager.close_aggregate_issue(10)

      expect(github).to have_received(:add_comment).with(10, "Closing: all items completed or superseded.")
      expect(github).to have_received(:close_issue).with(10)
    end
  end

  describe "#update_issue_body" do
    it "updates the issue body" do
      allow(github).to receive(:update_issue)

      manager.update_issue_body(5, "new body")

      expect(github).to have_received(:update_issue).with(5, body: "new body")
    end
  end

  describe "#get_issue_body" do
    it "returns the issue body" do
      allow(github).to receive(:issue).with(5).and_return(double(body: "the body"))

      expect(manager.get_issue_body(5)).to eq("the body")
    end
  end

  describe "#add_comment" do
    it "adds a comment to the issue" do
      allow(github).to receive(:add_comment)

      manager.add_comment(5, "hello")

      expect(github).to have_received(:add_comment).with(5, "hello")
    end
  end
end
