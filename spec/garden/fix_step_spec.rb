# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::FixStep do
  include_context "garden sandbox"

  let(:project) { Garden::Registry::Project.new(name: "my-app", path: "/code/my-app", fix_limit: 2) }
  let(:store) { Garden::StateStore.new("my-app") }
  let(:repo) { instance_double(Garden::Repo, fetch: nil, default_ref: "origin/main") }
  let(:fixer) { instance_double(Garden::Fixer) }
  let(:ready) { Garden::Fixer::Outcome.new(status: "pending_review", note: "Done", log: nil) }

  subject(:step) { described_class.new(project, store: store, repo: repo, fixer: fixer, worktrees_dir: "/wt") }

  def save(*findings)
    store.update { |s| s.record_scan(findings) }
  end

  it "fixes the most severe open findings, up to the limit" do
    low = Garden::Finding.build(title: "Low", severity: "low")
    high = Garden::Finding.build(title: "High", severity: "high")
    medium = Garden::Finding.build(title: "Medium", severity: "medium")
    save(low, high, medium)
    allow(fixer).to receive(:call).and_return(ready)

    done = step.call

    expect(done.map(&:title)).to eq(%w[High Medium])
    expect(store.read.find(low.id).status).to eq("open")
    expect(store.read.find(high.id)).to have_attributes(status: "pending_review", note: "Done")
  end

  it "gives each fix a branch and worktree before starting" do
    finding = Garden::Finding.build(title: "XSS").with(id: "abc123")
    save(finding)
    allow(fixer).to receive(:call) do |started, ref|
      expect(ref).to eq("origin/main")
      expect(started).to have_attributes(status: "fixing", branch: "garden/security/abc123-xss",
                                         worktree: "/wt/my-app/garden-security-abc123-xss")
      expect(store.read.find("abc123").status).to eq("fixing")
      ready
    end

    step.call

    expect(repo).to have_received(:fetch)
  end

  it "reports progress as each fix starts and ends" do
    save(Garden::Finding.build(title: "XSS"))
    allow(fixer).to receive(:call).and_return(ready)
    events = []

    step.call { |finding, outcome| events << [finding.status, outcome&.status] }

    expect(events).to eq([["fixing", nil], ["pending_review", "pending_review"]])
  end

  it "records a failure when a step raises, and carries on" do
    first = Garden::Finding.build(title: "First", severity: "high")
    second = Garden::Finding.build(title: "Second")
    save(first, second)
    allow(fixer).to receive(:call).and_raise(Garden::Error, "Setup command failed")
    allow(fixer).to receive(:call).with(having_attributes(id: second.id), anything).and_return(ready)

    step.call

    expect(store.read.find(first.id)).to have_attributes(status: "failed", note: "Setup command failed")
    expect(store.read.find(second.id).status).to eq("pending_review")
  end

  it "marks findings left in fixing by a crashed run as failed" do
    stuck = Garden::Finding.build(title: "Stuck").with(status: "fixing")
    save(stuck)

    expect(step.call).to eq([])
    expect(store.read.find(stuck.id)).to have_attributes(status: "failed", note: /stopped partway/)
  end
end
