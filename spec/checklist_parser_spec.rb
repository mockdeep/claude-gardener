# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::ChecklistParser do
  let(:body) do
    <<~MD
      ## Tasks

      - [ ] Add tests for UserController
      - [x] Fix login bug
      - [ ] Refactor database queries (claimed by PR #42)
      - [ ] Update README
    MD
  end

  describe ".parse" do
    it "parses all checklist items" do
      items = described_class.parse(body)

      expect(items.length).to eq(4)
    end

    it "identifies unchecked items" do
      items = described_class.parse(body)

      expect(items[0].checked).to be false
      expect(items[0].text).to eq("Add tests for UserController")
    end

    it "identifies checked items" do
      items = described_class.parse(body)

      expect(items[1].checked).to be true
      expect(items[1].text).to eq("Fix login bug")
    end

    it "extracts claim information" do
      items = described_class.parse(body)

      expect(items[2].claimed_by).to eq(42)
      expect(items[2].text).to eq("Refactor database queries")
    end

    it "returns empty array for nil body" do
      expect(described_class.parse(nil)).to eq([])
    end

    it "returns empty array for body without checklists" do
      expect(described_class.parse("Just some text")).to eq([])
    end

    it "tracks line index" do
      items = described_class.parse(body)

      expect(items[0].index).to eq(2)
      expect(items[1].index).to eq(3)
    end
  end

  describe ".unclaimed_items" do
    it "returns only unchecked, unclaimed items" do
      items = described_class.unclaimed_items(body)

      expect(items.map(&:text)).to eq([
        "Add tests for UserController",
        "Update README"
      ])
    end
  end

  describe ".check_item" do
    it "checks off an item" do
      result = described_class.check_item(body, line_index: 2)

      expect(result).to include("- [x] Add tests for UserController")
    end

    it "adds a note when provided" do
      result = described_class.check_item(body, line_index: 2, note: "done in PR #50")

      expect(result).to include("- [x] Add tests for UserController (done in PR #50)")
    end

    it "returns body unchanged for non-checklist lines" do
      result = described_class.check_item(body, line_index: 0)

      expect(result).to eq(body)
    end
  end

  describe ".claim_item" do
    it "adds claim note to an item" do
      result = described_class.claim_item(body, line_index: 2, pr_number: 99)

      expect(result).to include("- [ ] Add tests for UserController (claimed by PR #99)")
    end
  end

  describe ".add_item" do
    it "appends a new unchecked item" do
      result = described_class.add_item(body, "New task")

      expect(result).to end_with("- [ ] New task\n")
    end
  end
end
