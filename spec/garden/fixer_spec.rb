# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::Fixer do
  include_context "garden sandbox"

  # Stands in for Claude: each turn is a block run in the worktree that
  # returns the structured output.
  let(:claude) do
    Class.new do
      attr_reader :calls

      def initialize = (@calls = [])
      def turns(*blocks) = (@turns = blocks)

      def run(**opts)
        @calls << opts
        turn = @turns.shift or raise "Claude was called more times than expected"
        Garden::Claude::Response.new(data: turn.call(opts[:dir]), session_id: "session-1")
      end
    end.new
  end

  let(:repo_path) do
    path = make_git_repo("my-app")
    git(path, "checkout", "-q", "-b", "main")
    File.write(File.join(path, "app.rb"), "puts params\n")
    File.write(File.join(path, ".gitignore"), ".env\n")
    git(path, "add", ".")
    git(path, "commit", "-q", "-m", "Start")
    File.write(File.join(path, ".env"), "SECRET=1\n")
    path
  end

  let(:settings) { { test_commands: ["test -f fixed.txt"] } }
  let(:project) { Garden::Registry::Project.new(name: "my-app", path: repo_path, **settings) }
  let(:repo) { Garden::Repo.new(repo_path) }
  let(:guidance) { Garden::Guidance.new(File.join(sandbox, "guidance")) }
  let(:fixer) do
    described_class.new(project, repo: repo, claude: claude, guidance: guidance,
                                 logs_dir: File.join(sandbox, "logs"))
  end
  let(:finding) do
    f = Garden::Finding.build(title: "XSS in search", details: "Unescaped output", files: ["app.rb"],
                              severity: "high")
    f.with(status: "fixing", branch: described_class.branch_name(f),
           worktree: File.join(sandbox, "worktrees", "my-app", "fix"))
  end

  def git(dir, *args)
    Garden::Shell.run!("git", "-C", dir, *args).out
  end

  def fixed(message = "Escape search output")
    lambda do |dir|
      File.write(File.join(dir, "fixed.txt"), "yes")
      { "outcome" => "fixed", "summary" => "Escaped it.", "commit_message" => message }
    end
  end

  def answer(outcome, summary)
    ->(_dir) { { "outcome" => outcome, "summary" => summary, "commit_message" => "" } }
  end

  it "names branches after the finding" do
    f = Garden::Finding.build(title: "SQL injection in `User.search` (admin!)").with(id: "a1b2c3")

    expect(described_class.branch_name(f)).to eq("garden/security/a1b2c3-sql-injection-in-user-search-admin")
  end

  it "fixes, tests and commits on the finding's branch" do
    claude.turns(fixed)

    outcome = fixer.call(finding, "main")

    expect(outcome).to eq(described_class::Outcome.new(status: "pending_review", note: "Escaped it.", log: nil))
    expect(git(repo_path, "log", "-1", "--format=%s", finding.branch).strip).to eq("Escape search output")
    expect(git(repo_path, "show", "--name-only", "--format=", finding.branch).split).to eq(["fixed.txt"])
  end

  it "runs Claude in the worktree with edit permissions and the test commands allowed" do
    claude.turns(fixed)

    fixer.call(finding, "main")

    call = claude.calls.first
    expect(call).to include(dir: finding.worktree, permission_mode: "acceptEdits", persist: true,
                            timeout: 1800, tools: described_class::TOOLS)
    expect(call[:allowed_tools]).to include("Bash(test -f fixed.txt)", "Bash(git diff *)")
    expect(call[:prompt]).to include("**XSS in search** (severity: high)", "- `test -f fixed.txt`")
  end

  it "links worktree files without committing them" do
    settings[:worktree_files] = [".env"]
    settings[:test_commands] = ["test -f fixed.txt", "grep -q SECRET .env"]
    claude.turns(fixed)

    expect(fixer.call(finding, "main").status).to eq("pending_review")
    expect(File.symlink?(File.join(finding.worktree, ".env"))).to be(true)
    expect(git(repo_path, "show", "--name-only", "--format=", finding.branch).split).to eq(["fixed.txt"])
  end

  it "doesn't commit linked files even when they aren't ignored" do
    File.write(File.join(repo_path, "local.yml"), "x")
    settings[:worktree_files] = ["local.yml"]
    claude.turns(fixed)

    fixer.call(finding, "main")

    expect(git(repo_path, "show", "--name-only", "--format=", finding.branch).split).to eq(["fixed.txt"])
  end

  it "runs setup commands before Claude" do
    settings[:setup_commands] = ["touch setup-ran"]
    File.write(File.join(repo_path, ".gitignore"), ".env\nsetup-ran\n")
    git(repo_path, "commit", "-q", "-am", "Ignore setup file")
    claude.turns(lambda { |dir|
      raise "setup didn't run first" unless File.exist?(File.join(dir, "setup-ran"))

      fixed.call(dir)
    })

    expect(fixer.call(finding, "main").status).to eq("pending_review")
  end

  it "raises when a setup command fails" do
    settings[:setup_commands] = ["echo broken; exit 1"]

    expect { fixer.call(finding, "main") }.to raise_error(Garden::Error, /Setup command `echo broken; exit 1` failed:\nbroken/)
  end

  it "raises when setup changes files that would end up in the commit" do
    settings[:setup_commands] = ["echo changed >> app.rb"]

    expect { fixer.call(finding, "main") }.to raise_error(Garden::Error, /Setup commands changed files/)
  end

  it "retries once with the test output when tests fail" do
    claude.turns(answer("fixed", "First try."), fixed)

    expect(fixer.call(finding, "main").status).to eq("pending_review")
    retry_call = claude.calls.last
    expect(retry_call[:resume]).to eq("session-1")
    expect(retry_call[:prompt]).to include("$ test -f fixed.txt")
  end

  it "fails with a saved log when tests still fail after the retry" do
    claude.turns(answer("fixed", "First try."), answer("fixed", "Second try."))

    outcome = fixer.call(finding, "main")

    expect(outcome.status).to eq("failed")
    expect(outcome.note).to include("Tests still fail after one retry", "Second try.")
    expect(File.read(outcome.log)).to include("$ test -f fixed.txt")
  end

  it "fails with Claude's explanation when it isn't a real issue" do
    claude.turns(answer("not_an_issue", "Output is escaped by the template."))

    outcome = fixer.call(finding, "main")

    expect(outcome).to have_attributes(status: "failed", log: nil)
    expect(outcome.note).to eq("Claude thinks this isn't a real issue: Output is escaped by the template.")
  end

  it "fails when Claude gives up" do
    claude.turns(answer("failed", "Needs a design decision."))

    expect(fixer.call(finding, "main").note).to eq("Claude couldn't fix this: Needs a design decision.")
  end

  it "fails when Claude says it fixed it but changed nothing" do
    settings[:test_commands] = []
    claude.turns(answer("fixed", "Done."))

    expect(fixer.call(finding, "main").note).to start_with("Claude said it fixed this but changed nothing")
  end

  describe "#prompt" do
    it "includes the commit template when git has one" do
      template = File.join(sandbox, "gitmessage")
      File.write(template, "# Subject\n**What**\n")
      git(repo_path, "config", "commit.template", template)

      expect(fixer.prompt(finding)).to include("Follow this template", "# Subject\n**What**")
    end

    it "says when there are no test commands" do
      settings[:test_commands] = []

      expect(fixer.prompt(finding)).to include("No test commands are set up")
    end
  end
end
