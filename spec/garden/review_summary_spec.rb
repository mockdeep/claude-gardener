# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::ReviewSummary do
  it "reads the suggested decision and reason" do
    summary = described_class.new(<<~MD)
      # XSS in search

      **Suggested decision:** reject

      **Reason:** The input is already escaped by the
      template, so this can't happen.

      ## Discussion

      - Looked at the template
    MD

    expect(summary.decision).to eq("reject")
    expect(summary.reason).to eq("The input is already escaped by the template, so this can't happen.")
  end

  it "accepts the decision in backticks or capitals" do
    expect(described_class.new("**Suggested decision:** `Approve`").decision).to eq("approve")
  end

  it "ignores a decision it doesn't know" do
    expect(described_class.new("**Suggested decision:** maybe").decision).to be_nil
  end

  it "is blank when the file is missing" do
    summary = described_class.read("/no/such/summary.md")

    expect(summary).not_to be_present
    expect(summary.decision).to be_nil
    expect(summary.reason).to be_nil
  end
end
