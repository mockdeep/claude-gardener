# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::ReviewContext do
  include_context "garden sandbox"

  let(:project_path) { make_git_repo("my-app") }
  let(:project) do
    Garden::Registry::Project.new(name: "my-app", path: project_path, test_commands: ["bin/test"])
  end
  let(:finding) do
    Garden::Finding.build(title: "XSS in search", details: "Unescaped output", files: ["app.rb"],
                          severity: "high")
                   .with(id: "abc123", status: "pending_review", branch: "garden/security/abc123-xss",
                         note: "Escaped the output.")
  end

  subject(:context) { described_class.new(project, finding, default_ref: "origin/main") }

  it "writes the context file in the finding's review folder" do
    path = context.write

    expect(path).to eq(File.join(Garden::Paths.reviews_dir, "abc123", "context.md"))
    expect(context.summary_path).to eq(File.join(Garden::Paths.reviews_dir, "abc123", "summary.md"))
    expect(File.read(path)).to eq(context.render)
  end

  it "includes the finding, the note and what to compare against" do
    text = context.render

    expect(text).to start_with("# Garden review: XSS in search\n")
    expect(text).to include(
      "- Status: pending_review", "- Severity: high", "- Branch: garden/security/abc123-xss",
      "- Compare against: origin/main (`git diff origin/main...HEAD`)", "- Files: app.rb",
      "## The issue\n\nUnescaped output", "## Note from the fix\n\nEscaped the output."
    )
  end

  it "says where tests, the summary and guidance go" do
    FileUtils.mkdir_p(Garden::Paths.guidance_dir)
    File.write(File.join(Garden::Paths.guidance_dir, "fixes.md"), "x")

    text = context.render

    expect(text).to include(
      "- Test commands: `bin/test`",
      "- Summary file: `#{context.summary_path}`",
      "(topic files: fixes.md)",
      "`#{described_class.guidance_worktree(project)}`, on branch `garden/guidance`",
      "- Repo-specific guidance file: `CLAUDE.md`"
    )
  end

  it "points repo-specific guidance at AGENTS.md when the repo has one" do
    File.write(File.join(project_path, "AGENTS.md"), "")

    expect(context.render).to include("- Repo-specific guidance file: `AGENTS.md`")
  end

  it "includes the end of the test log" do
    log = File.join(sandbox, "abc123.log")
    File.write(log, (1..100).map { |i| "line #{i}\n" }.join)

    text = described_class.new(project, finding.with(log: log), default_ref: "main").render

    expect(text).to include("## Test log\n\n(last 80 of 100 lines)", "line 21\n", "line 100\n```")
    expect(text).not_to include("line 20\n")
  end

  it "leaves out empty sections" do
    text = described_class.new(project, finding.with(note: nil), default_ref: "main").render

    expect(text).not_to include("## Note from the fix", "## Test log")
  end

  it "removes an old summary so a stale one isn't read" do
    FileUtils.mkdir_p(context.dir)
    File.write(context.summary_path, "old")

    context.write

    expect(File).not_to exist(context.summary_path)
  end

  it "lists the folders the session needs" do
    expect(context.extra_dirs).to eq([Garden::Paths.guidance_dir, described_class.guidance_worktree(project),
                                      context.dir])
  end
end
