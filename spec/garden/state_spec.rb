# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::State do
  let(:now) { Time.utc(2026, 11, 6, 12) }
  let(:day) { 24 * 60 * 60 }

  def finding(status, **attrs)
    Garden::Finding.build(title: "Issue #{status}").with(status: status, **attrs)
  end

  describe "#scan_stale?" do
    it "is stale when never scanned" do
      expect(described_class.new).to be_scan_stale(now)
    end

    it "is fresh within a week" do
      expect(described_class.new(scanned_at: now - (6 * day))).not_to be_scan_stale(now)
    end

    it "is stale after a week" do
      expect(described_class.new(scanned_at: now - (8 * day))).to be_scan_stale(now)
    end
  end

  describe "#record_scan" do
    it "replaces open findings and keeps everything else" do
      kept = (Garden::Finding::STATUSES - ["open"]).map { |s| finding(s) }
      state = described_class.new(findings: [finding("open"), *kept])
      fresh = Garden::Finding.build(title: "New")

      state.record_scan([fresh], now: now)

      expect(state.findings).to eq(kept + [fresh])
      expect(state.scanned_at).to eq(now)
    end
  end

  it "groups findings for the review queue and in-progress list" do
    pending = finding("pending_review")
    failed = finding("failed")
    approved = finding("approved")
    state = described_class.new(findings: [finding("open"), pending, failed, approved, finding("rejected")])

    expect(state.review_queue).to eq([pending, failed])
    expect(state.in_progress).to include(pending, failed, approved)
  end

  it "rejects a finding with a reason and time" do
    open = finding("open")
    state = described_class.new(findings: [open])

    state.reject(open.id, reason: "Too broad", now: now)

    expect(state.find(open.id)).to have_attributes(status: "rejected", reason: "Too broad", rejected_at: now)
  end

  it "raises for an unknown id" do
    expect { described_class.new.find("nope") }.to raise_error(Garden::Error, /No finding/)
  end

  it "removes a finding" do
    open = finding("open")
    state = described_class.new(findings: [open])

    state.remove(open.id)

    expect(state.findings).to be_empty
  end

  it "prunes rejections older than a week" do
    old = finding("rejected", rejected_at: now - (8 * day))
    recent = finding("rejected", rejected_at: now - (2 * day))
    state = described_class.new(findings: [old, recent])

    state.prune(now)

    expect(state.findings).to eq([recent])
  end
end

RSpec.describe Garden::Finding do
  it "starts open with a short id" do
    finding = described_class.build(title: "XSS", files: ["a.rb"])

    expect(finding).to have_attributes(status: "open", files: ["a.rb"])
    expect(finding.id).to match(/\A\h{6}\z/)
  end

  it "rejects unknown statuses" do
    finding = described_class.build(title: "XSS")

    expect { finding.with(status: "done") }.to raise_error(Garden::Error, /Unknown finding status/)
  end
end

RSpec.describe Garden::StateStore do
  include_context "garden sandbox"

  subject(:store) { described_class.new("my-app") }

  it "returns empty state when there's no file" do
    expect(store.read.findings).to eq([])
  end

  it "saves changes made in update" do
    finding = Garden::Finding.build(title: "XSS", details: "Unescaped output", files: ["a.rb"])
    now = Time.utc(2026, 11, 6)

    store.update do |state|
      state.record_scan([finding], now: now)
      state.reject(finding.id, reason: "Not real", now: now)
    end

    state = described_class.new("my-app").read
    expect(state.scanned_at).to eq(now)
    expect(state.findings).to eq([finding.with(status: "rejected", reason: "Not real", rejected_at: now)])
  end

  it "returns the block's result" do
    expect(store.update { 42 }).to eq(42)
  end

  it "leaves no temp files behind" do
    store.update { |state| state.record_scan([]) }

    expect(Dir.children(File.dirname(store.path))).to contain_exactly("my-app.yml", "my-app.yml.lock")
  end

  it "doesn't save when the block raises" do
    store.update { |state| state.record_scan([Garden::Finding.build(title: "A")]) }

    expect do
      store.update do |state|
        state.record_scan([])
        raise "boom"
      end
    end.to raise_error("boom")
    expect(store.read.findings.size).to eq(1)
  end

  it "reads hand-written timestamps without quotes" do
    FileUtils.mkdir_p(File.dirname(store.path))
    File.write(store.path, <<~YAML)
      scanned_at: 2026-11-06T20:00:00Z
      findings:
        - id: abc123
          title: XSS
          status: rejected
          rejected_at: 2026-11-05T10:00:00Z
    YAML

    state = store.read
    expect(state.scanned_at).to eq(Time.utc(2026, 11, 6, 20))
    expect(state.findings.first.rejected_at).to eq(Time.utc(2026, 11, 5, 10))
  end
end
