# frozen_string_literal: true

require "stringio"
require_relative "support"

RSpec.describe Garden::CLI do
  include_context "garden sandbox"

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def garden(*args)
    described_class.new(args, out: out, err: err).run
  end

  it "adds a project" do
    path = make_git_repo("my-app")

    expect(garden("add", path)).to eq(0)
    expect(out.string).to include("Added my-app (#{path})")
  end

  it "adds a project under a custom name" do
    expect(garden("add", make_git_repo("my-app"), "--name", "app")).to eq(0)
    expect(out.string).to include("Added app")
  end

  it "says when a project is already registered" do
    path = make_git_repo("my-app")
    garden("add", path)

    expect(garden("add", path)).to eq(0)
    expect(out.string).to include("my-app is already registered")
  end

  it "reports errors without a stack trace" do
    expect(garden("add", File.join(sandbox, "missing"))).to eq(1)
    expect(err.string).to start_with("garden: No such directory")
  end

  it "reports unknown options" do
    expect(garden("add", "--bogus")).to eq(1)
    expect(err.string).to include("invalid option: --bogus")
  end

  describe "scan" do
    let(:step) { instance_double(Garden::ScanStep) }

    before { allow(Garden::ScanStep).to receive(:new).and_return(step) }

    def save_findings(name, findings, scanned_at: Time.now)
      Garden::StateStore.new(name).update { |s| s.record_scan(findings, now: scanned_at) }
    end

    it "says when no projects are registered" do
      expect(garden("scan")).to eq(0)
      expect(out.string).to include("No projects registered")
    end

    it "prints open findings, most severe first" do
      garden("add", make_git_repo("my-app"))
      save_findings("my-app", [
                      Garden::Finding.build(title: "Weak", severity: "low"),
                      Garden::Finding.build(title: "XSS", files: ["a.rb"], severity: "high"),
                      Garden::Finding.build(title: "Busy").with(status: "pending_review")
                    ])
      allow(step).to receive(:call).and_return(:scanned)

      expect(garden("scan", "my-app")).to eq(0)
      expect(out.string).to include("== my-app\n  [high] XSS (a.rb)\n  [low] Weak\n  ...plus 1 already in progress")
    end

    it "says when it used saved findings" do
      garden("add", make_git_repo("my-app"))
      save_findings("my-app", [], scanned_at: Time.new(2026, 11, 5, 12))
      allow(step).to receive(:call).with(force: false).and_return(:fresh)

      garden("scan")

      expect(out.string).to include("Using findings from 2026-11-05 (--force to rescan)")
      expect(out.string).to include("No open findings.")
    end

    it "passes --force through" do
      garden("add", make_git_repo("my-app"))
      allow(step).to receive(:call).and_return(:scanned)

      garden("scan", "--force")

      expect(step).to have_received(:call).with(force: true)
    end

    it "carries on after a failed project and exits with 1" do
      garden("add", make_git_repo("a"))
      garden("add", make_git_repo("b"))
      allow(step).to receive(:call).and_raise(Garden::Error, "Claude failed: boom")

      expect(garden("scan")).to eq(1)
      expect(err.string).to include("a: Claude failed: boom", "b: Claude failed: boom")
    end
  end

  it "runs setup" do
    expect(garden("setup")).to eq(0)
    expect(out.string).to include("Linked garden-review")
  end

  it "shows help" do
    expect(garden("help")).to eq(0)
    expect(out.string).to include("Usage: garden")
  end

  it "rejects unknown commands" do
    expect(garden("bogus")).to eq(1)
    expect(err.string).to include("unknown command 'bogus'")
  end
end
