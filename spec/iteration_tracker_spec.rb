# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeGardener::IterationTracker do
  describe "#iterations" do
    it "parses iteration from PR body metadata" do
      pr = double(body: <<~BODY)
        Some PR description.

        <!-- gardener-metadata
        iteration: 3
        category: test_coverage
        started: 2026-01-15T10:00:00Z
        -->
      BODY

      tracker = described_class.new(pr)

      expect(tracker.iterations).to eq(3)
    end

    it "defaults to 1 when no metadata present" do
      pr = double(body: "Just a regular PR description.")

      tracker = described_class.new(pr)

      expect(tracker.iterations).to eq(1)
    end

    it "handles nil body" do
      pr = double(body: nil)

      tracker = described_class.new(pr)

      expect(tracker.iterations).to eq(1)
    end
  end

  describe "#category" do
    it "parses category from metadata" do
      pr = double(body: <<~BODY)
        <!-- gardener-metadata
        iteration: 1
        category: security_fixes
        started: 2026-01-15T10:00:00Z
        -->
      BODY

      tracker = described_class.new(pr)

      expect(tracker.category).to eq("security_fixes")
    end
  end

  describe "#increment" do
    it "increases iteration count" do
      pr = double(body: <<~BODY)
        <!-- gardener-metadata
        iteration: 2
        category: test_coverage
        started: 2026-01-15T10:00:00Z
        -->
      BODY

      tracker = described_class.new(pr)
      tracker.increment

      expect(tracker.iterations).to eq(3)
    end
  end

  describe "#update_metadata_in_body" do
    it "replaces existing metadata" do
      pr = double(body: <<~BODY)
        Description here.

        <!-- gardener-metadata
        iteration: 1
        category: test_coverage
        started: 2026-01-15T10:00:00Z
        -->
      BODY

      tracker = described_class.new(pr)
      tracker.increment
      tracker.increment

      new_body = tracker.update_metadata_in_body(pr.body)

      expect(new_body).to include("iteration: 3")
      expect(new_body).to include("Description here.")
    end

    it "adds metadata when not present" do
      pr = double(body: "Just a description.")
      tracker = described_class.new(pr)

      new_body = tracker.update_metadata_in_body(pr.body)

      expect(new_body).to include("<!-- gardener-metadata")
      expect(new_body).to include("iteration: 1")
    end
  end
end
