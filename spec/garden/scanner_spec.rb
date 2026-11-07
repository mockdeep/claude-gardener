# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::Scanner do
  include_context "garden sandbox"

  let(:project) do
    Garden::Registry::Project.new(name: "my-app", path: "/code/my-app", fix_limit: 2,
                                  model: "opus", audit_commands: ["composer audit"])
  end
  let(:claude) { instance_double(Garden::Claude) }
  let(:guidance_dir) { File.join(sandbox, "guidance") }

  subject(:scanner) { described_class.new(project, claude: claude, guidance_dir: guidance_dir) }

  def finding(status, title, **attrs)
    Garden::Finding.build(title: title, files: ["app/x.rb"]).with(status: status, **attrs)
  end

  describe "#prompt" do
    it "starts with the security scan prompt" do
      expect(scanner.prompt(Garden::State.new)).to start_with("# Security scan")
    end

    it "includes each guidance file" do
      FileUtils.mkdir_p(guidance_dir)
      File.write(File.join(guidance_dir, "fixes.md"), "Fix the root cause.")

      expect(scanner.prompt(Garden::State.new)).to include("### fixes\n\nFix the root cause.")
    end

    it "leaves out empty sections" do
      prompt = scanner.prompt(Garden::State.new)

      expect(prompt).not_to include("## Guidance")
      expect(prompt).not_to include("## Already known")
    end

    it "lists in-progress and rejected findings so they aren't reported again" do
      state = Garden::State.new(findings: [
                                  finding("open", "Open one"),
                                  finding("pending_review", "Being fixed"),
                                  finding("rejected", "Turned down", reason: "Not reachable")
                                ])

      prompt = scanner.prompt(state)

      expect(prompt).to include("- (in progress) Being fixed (app/x.rb).")
      expect(prompt).to include("- (rejected) Turned down (app/x.rb). Reason: Not reachable")
      expect(prompt).not_to include("Open one")
    end
  end

  it "allows the built-in and extra audit commands, bare or with arguments" do
    expect(scanner.allowed_tools).to include("Bash(npm audit)", "Bash(npm audit *)",
                                             "Bash(composer audit)", "Bash(composer audit *)")
  end

  it "turns Claude's answer into open findings" do
    allow(claude).to receive(:structured).and_return(
      "findings" => [
        { "title" => "XSS in search", "details" => "Unescaped", "files" => ["a.rb"], "severity" => "high" }
      ]
    )

    findings = scanner.scan("/tmp/scan", Garden::State.new)

    expect(findings.size).to eq(1)
    expect(findings.first).to have_attributes(title: "XSS in search", details: "Unescaped",
                                              files: ["a.rb"], severity: "high", status: "open")
    expect(claude).to have_received(:structured).with(
      hash_including(dir: "/tmp/scan", model: "opus", tools: described_class::TOOLS,
                     schema: described_class::SCHEMA)
    )
  end

  it "keeps at most 10 findings" do
    many = Array.new(12) { |i| { "title" => "T#{i}", "details" => "", "files" => [], "severity" => "low" } }
    allow(claude).to receive(:structured).and_return("findings" => many)

    expect(scanner.scan("/tmp/scan", Garden::State.new).size).to eq(10)
  end
end
