# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::TaskClaimer do
  let(:issue_manager) { instance_double(ClaudeGardener::IssueManager) }

  subject(:claimer) { described_class.new(issue_manager: issue_manager) }

  let(:issue_body) do
    <<~MD
      ## Test coverage - Work Items

      - [ ] Add tests for UserController
      - [x] Add tests for OrderService
      - [ ] Add tests for AuthHelper (claimed by PR #42)
      - [ ] Add tests for PaymentGateway
    MD
  end

  describe "#claim_next" do
    it "claims the first unclaimed item across aggregate issues" do
      issue = double(number: 10)
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(issue_body)
      allow(issue_manager).to receive(:update_issue_body)

      result = claimer.claim_next(pr_number: 50, aggregate_issues: [issue])

      expect(result).not_to be_nil
      expect(result.text).to eq("Add tests for UserController")
      expect(result.issue_number).to eq(10)
    end

    it "skips issues with no unclaimed items" do
      all_claimed = "- [x] Done\n- [ ] Claimed (claimed by PR #1)\n"
      available = "- [ ] Available item\n"

      issue1 = double(number: 10)
      issue2 = double(number: 11)
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(all_claimed)
      allow(issue_manager).to receive(:get_issue_body).with(11).and_return(available)
      allow(issue_manager).to receive(:update_issue_body)

      result = claimer.claim_next(pr_number: 50, aggregate_issues: [issue1, issue2])

      expect(result.issue_number).to eq(11)
      expect(result.text).to eq("Available item")
    end

    it "returns nil when no items available" do
      issue = double(number: 10)
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return("- [x] Done\n")

      result = claimer.claim_next(pr_number: 50, aggregate_issues: [issue])

      expect(result).to be_nil
    end
  end

  describe "#claim_item" do
    it "claims an item and updates the issue body" do
      item = ClaudeGardener::ChecklistParser::Item.new(
        text: "Add tests for UserController",
        checked: false,
        claimed_by: nil,
        index: 2
      )
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(issue_body)
      allow(issue_manager).to receive(:update_issue_body)

      result = claimer.claim_item(issue_number: 10, item: item, pr_number: 50)

      expect(result.text).to eq("Add tests for UserController")
      expect(issue_manager).to have_received(:update_issue_body).with(
        10,
        a_string_including("claimed by PR #50")
      )
    end

    it "returns nil if the item was already claimed (race condition)" do
      item = ClaudeGardener::ChecklistParser::Item.new(
        text: "Add tests for AuthHelper",
        checked: false,
        claimed_by: nil,
        index: 4
      )
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(issue_body)

      result = claimer.claim_item(issue_number: 10, item: item, pr_number: 50)

      expect(result).to be_nil
    end
  end

  describe "#complete_item" do
    it "checks off a completed item" do
      allow(issue_manager).to receive(:get_issue_body).with(10).and_return(issue_body)
      allow(issue_manager).to receive(:update_issue_body)

      claimer.complete_item(issue_number: 10, item_index: 2, note: "done in PR #50")

      expect(issue_manager).to have_received(:update_issue_body).with(
        10,
        a_string_including("- [x] Add tests for UserController (done in PR #50)")
      )
    end
  end
end
