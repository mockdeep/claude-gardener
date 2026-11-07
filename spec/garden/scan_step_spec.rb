# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::ScanStep do
  include_context "garden sandbox"

  let(:now) { Time.utc(2026, 11, 6, 12) }
  let(:day) { 24 * 60 * 60 }
  let(:project) do
    Garden::Registry::Project.new(name: "my-app", path: "/code/my-app", fix_limit: 2,
                                  model: nil, audit_commands: [])
  end
  let(:store) { Garden::StateStore.new("my-app") }
  let(:repo) { instance_double(Garden::Repo, fetch: nil, default_ref: "origin/main", sync_worktree: nil) }
  let(:scanner) { instance_double(Garden::Scanner) }
  let(:github) { instance_double(Garden::GitHub) }
  let(:new_finding) { Garden::Finding.build(title: "New") }

  subject(:step) do
    described_class.new(project, store: store, repo: repo, scanner: scanner, github: github,
                                 worktree: "/wt/scan")
  end

  before { allow(scanner).to receive(:scan).and_return([new_finding]) }

  def save(scanned_at:, findings: [])
    store.update { |s| s.record_scan(findings, now: scanned_at) }
  end

  it "scans when there's no saved scan" do
    expect(step.call(now: now)).to eq(:scanned)

    expect(repo).to have_received(:fetch)
    expect(repo).to have_received(:sync_worktree).with("/wt/scan", "origin/main")
    expect(scanner).to have_received(:scan).with("/wt/scan", kind_of(Garden::State))
    expect(store.read).to have_attributes(scanned_at: now, findings: [new_finding])
  end

  it "uses saved findings from the last week" do
    save(scanned_at: now - (2 * day))

    expect(step.call(now: now)).to eq(:fresh)
    expect(scanner).not_to have_received(:scan)
  end

  it "rescans after a week" do
    save(scanned_at: now - (8 * day))

    expect(step.call(now: now)).to eq(:scanned)
  end

  it "rescans a recent scan when forced" do
    save(scanned_at: now - day)

    expect(step.call(force: true, now: now)).to eq(:scanned)
  end

  it "removes approved findings whose PR has merged or closed" do
    merged = Garden::Finding.build(title: "M").with(status: "approved", pr_url: "https://gh/pr/1")
    closed = Garden::Finding.build(title: "C").with(status: "approved", pr_url: "https://gh/pr/2")
    open = Garden::Finding.build(title: "O").with(status: "approved", pr_url: "https://gh/pr/3")
    unknown = Garden::Finding.build(title: "U").with(status: "approved", pr_url: "https://gh/pr/4")
    allow(github).to receive(:pr_state).and_return("MERGED", "CLOSED", "OPEN", nil)
    save(scanned_at: now, findings: [merged, closed, open, unknown])

    step.call(now: now)

    expect(store.read.findings).to eq([open, unknown])
  end

  it "drops week-old rejections" do
    old = Garden::Finding.build(title: "Old").with(status: "rejected", rejected_at: now - (8 * day))
    save(scanned_at: now, findings: [old])

    step.call(now: now)

    expect(store.read.findings).to be_empty
  end

  it "keeps the old findings when the scan fails" do
    kept = Garden::Finding.build(title: "Kept")
    save(scanned_at: now - (8 * day), findings: [kept])
    allow(scanner).to receive(:scan).and_raise(Garden::Error, "Claude failed")

    expect { step.call(now: now) }.to raise_error(Garden::Error, "Claude failed")
    expect(store.read.findings).to eq([kept])
  end
end
