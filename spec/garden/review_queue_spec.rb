# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::ReviewQueue do
  include_context "garden sandbox"

  # Plays the user. Claude sessions run the given block in the worktree;
  # other programs (git commit) run for real, with GIT_EDITOR=true so the
  # message is kept as it is.
  let(:terminal) do
    Class.new do
      attr_reader :said, :runs, :choices_offered
      attr_accessor :claude, :answers, :next_answers

      def initialize
        @said = []
        @runs = []
        @choices_offered = []
        @answers = []
        @next_answers = []
      end

      def run(*cmd, chdir: nil)
        @runs << { cmd: cmd, chdir: chdir }
        return (claude&.call(chdir) || true) if cmd.first == "claude"

        system(*cmd, **(chdir ? { chdir: chdir } : {}))
      end

      def run!(*cmd, chdir: nil)
        run(*cmd, chdir: chdir) or raise Garden::Error, "#{cmd.join(' ')} failed"
      end

      def say(text) = @said << text

      def choose(_question, choices, default:)
        @choices_offered << { choices: choices.keys, default: default }
        answers.shift || default
      end

      def yes?(_question, default: true)
        next_answers.empty? ? default : next_answers.shift
      end
    end.new
  end

  let(:github) do
    Class.new do
      attr_reader :created
      attr_accessor :open_prs

      def initialize
        @created = []
        @open_prs = {}
      end

      def open_pr(_dir, branch) = open_prs[branch]

      def create_pr(dir, branch:, base:, fill: "--fill")
        @created << { dir: dir, branch: branch, base: base, fill: fill }
        "https://github.com/me/app/pull/#{@created.size}"
      end
    end.new
  end

  let(:origin) { File.join(sandbox, "origin.git") }
  let(:project_path) { File.join(sandbox, "projects", "my-app") }
  let(:project) { Garden::Registry::Project.new(name: "my-app", path: project_path, test_commands: []) }
  let(:registry) { instance_double(Garden::Registry, projects: [project]) }
  let(:store) { Garden::StateStore.new("my-app") }
  let(:repo) { Garden::Repo.new(project_path) }
  let(:fix_dir) { File.join(Garden::Paths.worktrees_dir, "my-app", "garden-security-abc123-xss") }
  let(:guidance_dir) { File.join(Garden::Paths.worktrees_dir, "my-app", "guidance") }
  let(:queue) { described_class.new(registry: registry, terminal: terminal, github: github) }

  def git(dir, *args)
    Garden::Shell.run!("git", "-C", dir, *args).out.strip
  end

  def commit(dir, file, content, message = "Change #{file}")
    File.write(File.join(dir, file), content)
    git(dir, "add", file)
    git(dir, "commit", "-q", "-m", message)
  end

  # A pending_review finding with one fix commit, like FixStep leaves it.
  def fixed_finding(id: "abc123", severity: "high", status: "pending_review", with_commit: true)
    branch = "garden/security/#{id}-xss"
    dir = File.join(Garden::Paths.worktrees_dir, "my-app", "garden-security-#{id}-xss")
    repo.add_worktree(dir, branch, "origin/main")
    commit(dir, "fix-#{id}.txt", "fixed", "Fix XSS #{id}") if with_commit
    Garden::Finding.build(title: "XSS #{id}", severity: severity)
                   .with(id: id, status: status, branch: branch, worktree: dir)
  end

  def save(*findings)
    store.update { |s| s.record_scan(findings) }
  end

  def write_summary(decision, reason)
    lambda do |_dir|
      path = File.join(Garden::Paths.reviews_dir, "abc123", "summary.md")
      File.write(path, "# XSS\n\n**Suggested decision:** #{decision}\n\n**Reason:** #{reason}\n\n## Discussion\n")
      true
    end
  end

  around do |example|
    ENV["GIT_EDITOR"] = "true"
    example.run
  ensure
    ENV.delete("GIT_EDITOR")
  end

  before do
    Garden::Shell.run!("git", "init", "-q", "--bare", "-b", "main", origin)
    seed = File.join(sandbox, "seed")
    Garden::Shell.run!("git", "clone", "-q", origin, seed)
    commit(seed, "app.rb", "puts 1\n", "Start")
    git(seed, "push", "-q", "origin", "HEAD:main")
    Garden::Shell.run!("git", "clone", "-q", origin, project_path)
  end

  it "says when there's nothing to review" do
    queue.call

    expect(terminal.said).to eq(["Nothing to review."])
  end

  it "orders the queue by severity across projects" do
    other = Garden::Registry::Project.new(name: "other", path: "/x")
    allow(registry).to receive(:projects).and_return([project, other])
    save(Garden::Finding.build(title: "Low").with(status: "failed", severity: "low"))
    Garden::StateStore.new("other").update do |s|
      s.record_scan([Garden::Finding.build(title: "High", severity: "high").with(status: "pending_review")])
    end

    expect(queue.queue.map { |_, f| f.title }).to eq(%w[High Low])
  end

  it "starts Claude in the fix worktree with the skill and the extra folders" do
    save(fixed_finding)

    queue.call

    claude = terminal.runs.find { |r| r[:cmd].first == "claude" }
    context = File.join(Garden::Paths.reviews_dir, "abc123", "context.md")
    expect(claude[:chdir]).to eq(fix_dir)
    expect(claude[:cmd]).to eq(["claude", "/garden-review #{context}", "--add-dir",
                                Garden::Paths.guidance_dir, guidance_dir, File.dirname(context)])
    expect(File).to exist(context)
    expect(git(guidance_dir, "branch", "--show-current")).to eq("garden/guidance")
  end

  describe "approve" do
    before do
      save(fixed_finding)
      terminal.claude = write_summary("approve", "Fix looks right.")
    end

    it "rebases, pushes, opens a PR and removes the worktree" do
      seed = File.join(sandbox, "seed")
      commit(seed, "newer.txt", "x", "Newer work on main")
      git(seed, "push", "-q", "origin", "HEAD:main")

      queue.call

      branch = "garden/security/abc123-xss"
      expect(terminal.choices_offered.last).to eq(choices: %w[approve reject retry skip], default: "approve")
      expect(git(origin, "log", "--format=%s", branch)).to eq("Fix XSS abc123\nNewer work on main\nStart")
      expect(github.created).to eq([{ dir: fix_dir, branch: branch, base: "main", fill: "--fill" }])
      expect(store.read.find("abc123")).to have_attributes(status: "approved",
                                                          pr_url: "https://github.com/me/app/pull/1")
      expect(File).not_to exist(fix_dir)
      expect(git(project_path, "branch", "--list", branch)).not_to be_empty
    end

    it "reuses an open PR for the branch" do
      github.open_prs["garden/security/abc123-xss"] = "https://github.com/me/app/pull/9"

      queue.call

      expect(github.created).to be_empty
      expect(store.read.find("abc123").pr_url).to eq("https://github.com/me/app/pull/9")
    end

    it "cancels on a rebase conflict and leaves the finding in the queue" do
      seed = File.join(sandbox, "seed")
      commit(seed, "fix-abc123.txt", "conflicting", "Same file on main")
      git(seed, "push", "-q", "origin", "HEAD:main")

      queue.call

      expect(terminal.said.join("\n")).to include("hit a conflict", "still in the queue")
      expect(store.read.find("abc123").status).to eq("pending_review")
      expect(File).not_to exist(File.join(git(fix_dir, "rev-parse", "--git-dir"), "rebase-merge"))
      expect(git(fix_dir, "log", "-1", "--format=%s")).to eq("Fix XSS abc123")
    end

    it "leaves the finding alone when the commit message edit is cancelled" do
      ENV["GIT_EDITOR"] = "false"

      queue.call

      expect(store.read.find("abc123").status).to eq("pending_review")
      expect(github.created).to be_empty
    end
  end

  it "rejects with the summary's reason and deletes the branch" do
    save(fixed_finding)
    terminal.claude = write_summary("reject", "Too broad;\nrewrites the whole module.")

    queue.call

    expect(store.read.find("abc123")).to have_attributes(status: "rejected",
                                                        reason: "Too broad; rewrites the whole module.")
    expect(File).not_to exist(fix_dir)
    expect(git(project_path, "branch", "--list", "garden/security/abc123-xss")).to be_empty
  end

  it "retries by deleting the branch and reopening the finding" do
    save(fixed_finding(status: "failed"))
    terminal.answers = ["retry"]

    queue.call

    expect(store.read.find("abc123")).to have_attributes(status: "open", branch: nil, worktree: nil)
    expect(git(project_path, "branch", "--list", "garden/security/abc123-xss")).to be_empty
  end

  it "doesn't offer approve when there's no commit, and defaults to skip without a summary" do
    save(fixed_finding(status: "failed", with_commit: false))

    queue.call

    expect(terminal.choices_offered.last).to eq(choices: %w[reject retry skip], default: "skip")
    expect(terminal.said).to include("No review summary was written.", "Skipped.")
    expect(store.read.find("abc123").status).to eq("failed")
  end

  it "recreates a fix worktree that has gone missing" do
    finding = fixed_finding
    repo.remove_worktree(finding.worktree)
    save(finding)

    queue.call

    expect(terminal.runs.find { |r| r[:cmd].first == "claude" }[:chdir]).to eq(fix_dir)
    expect(File).to exist(File.join(fix_dir, "fix-abc123.txt"))
  end

  it "stops when the user says not to go on" do
    save(fixed_finding(id: "abc123"), fixed_finding(id: "def456", severity: "low"))
    terminal.next_answers = [false]

    queue.call

    expect(terminal.runs.count { |r| r[:cmd].first == "claude" }).to eq(1)
  end

  describe "guidance" do
    before { save(fixed_finding) }

    it "commits, pushes and opens a PR for lessons saved during the session" do
      editor = File.join(sandbox, "editor")
      File.write(editor, "#!/bin/sh\necho 'Add lesson' > \"$1\"\n")
      File.chmod(0o755, editor)
      ENV["GIT_EDITOR"] = editor
      terminal.claude = lambda do |_dir|
        File.write(File.join(guidance_dir, "AGENTS.md"), "Prefer Open3 with argument lists.\n")
      end

      queue.call

      expect(git(origin, "show", "garden/guidance:AGENTS.md")).to eq("Prefer Open3 with argument lists.")
      expect(git(origin, "log", "-1", "--format=%s", "garden/guidance")).to eq("Add lesson")
      expect(github.created.last).to eq(dir: guidance_dir, branch: "garden/guidance", base: "main",
                                        fill: "--fill-first")
      expect(terminal.said).to include("Guidance PR: https://github.com/me/app/pull/1")
    end

    it "keeps the changes when the commit message edit is cancelled" do
      terminal.claude = ->(_dir) { File.write(File.join(guidance_dir, "AGENTS.md"), "lesson\n") }

      queue.call

      expect(terminal.said.last).to include("Couldn't save guidance", "still in #{guidance_dir}")
      expect(File.read(File.join(guidance_dir, "AGENTS.md"))).to eq("lesson\n")
      expect(github.created).to be_empty
    end

    it "does nothing when no lessons were saved" do
      queue.call

      expect(github.created).to be_empty
      expect(git(origin, "branch", "--list", "garden/guidance")).to be_empty
    end

    it "starts the guidance branch fresh once its PR is done" do
      repo.ensure_worktree(guidance_dir, "garden/guidance", "origin/main")
      commit(guidance_dir, "AGENTS.md", "old lesson")
      repo.push(guidance_dir, "garden/guidance")

      queue.call

      expect(File).not_to exist(File.join(guidance_dir, "AGENTS.md"))
    end

    it "keeps the guidance branch while its PR is open" do
      repo.ensure_worktree(guidance_dir, "garden/guidance", "origin/main")
      commit(guidance_dir, "AGENTS.md", "pending lesson")
      repo.push(guidance_dir, "garden/guidance")
      github.open_prs["garden/guidance"] = "https://github.com/me/app/pull/5"

      queue.call

      expect(File.read(File.join(guidance_dir, "AGENTS.md"))).to eq("pending lesson")
    end

    it "keeps unpushed guidance commits" do
      repo.ensure_worktree(guidance_dir, "garden/guidance", "origin/main")
      commit(guidance_dir, "AGENTS.md", "unpushed lesson")

      queue.call

      expect(File.read(File.join(guidance_dir, "AGENTS.md"))).to eq("unpushed lesson")
    end
  end
end
