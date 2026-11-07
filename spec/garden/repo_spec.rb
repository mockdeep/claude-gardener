# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::Repo do
  include_context "garden sandbox"

  def git(dir, *args)
    Garden::Shell.run!("git", "-C", dir, *args).out.strip
  end

  def commit(dir, file, content)
    File.write(File.join(dir, file), content)
    git(dir, "add", file)
    git(dir, "-c", "user.name=T", "-c", "user.email=t@example.com", "commit", "-q", "-m", "Add #{file}")
  end

  # A project cloned from an "origin" repo whose default branch is trunk.
  def cloned_project
    origin = File.join(sandbox, "origin")
    FileUtils.mkdir_p(origin)
    git(origin, "init", "-q", "-b", "trunk")
    commit(origin, "a.txt", "one")
    clone = File.join(sandbox, "clone")
    Garden::Shell.run!("git", "clone", "-q", origin, clone)
    [origin, clone]
  end

  it "finds the default branch from origin/HEAD" do
    _, clone = cloned_project

    expect(described_class.new(clone).default_ref).to eq("origin/trunk")
  end

  it "falls back to a local main branch when there's no remote" do
    path = File.join(sandbox, "local")
    FileUtils.mkdir_p(path)
    git(path, "init", "-q", "-b", "main")
    commit(path, "a.txt", "one")

    expect(described_class.new(path).default_ref).to eq("main")
  end

  it "raises when there's no default branch to use" do
    path = File.join(sandbox, "local")
    FileUtils.mkdir_p(path)
    git(path, "init", "-q", "-b", "odd")
    commit(path, "a.txt", "one")

    expect { described_class.new(path).default_ref }.to raise_error(Garden::Error, /default branch/)
  end

  it "fetches new commits from origin without touching local branches" do
    origin, clone = cloned_project
    local_head = git(clone, "rev-parse", "HEAD")
    commit(origin, "b.txt", "two")

    described_class.new(clone).fetch

    expect(git(clone, "rev-parse", "origin/trunk")).to eq(git(origin, "rev-parse", "HEAD"))
    expect(git(clone, "rev-parse", "HEAD")).to eq(local_head)
  end

  it "skips fetching when there's no origin" do
    path = make_git_repo("local")

    expect { described_class.new(path).fetch }.not_to raise_error
  end

  it "creates a worktree, then resets it to a clean copy of the ref" do
    origin, clone = cloned_project
    repo = described_class.new(clone)
    worktree = File.join(sandbox, "worktrees", "scan")

    repo.sync_worktree(worktree, "origin/trunk")
    expect(File.read(File.join(worktree, "a.txt"))).to eq("one")

    File.write(File.join(worktree, "a.txt"), "changed")
    File.write(File.join(worktree, "stray.txt"), "junk")
    commit(origin, "b.txt", "two")
    repo.fetch
    repo.sync_worktree(worktree, "origin/trunk")

    expect(File.read(File.join(worktree, "a.txt"))).to eq("one")
    expect(File).not_to exist(File.join(worktree, "stray.txt"))
    expect(File).to exist(File.join(worktree, "b.txt"))
  end

  describe "fix worktrees" do
    let(:path) do
      path = File.join(sandbox, "local")
      FileUtils.mkdir_p(path)
      git(path, "init", "-q", "-b", "main")
      commit(path, "a.txt", "one")
      path
    end
    let(:repo) { described_class.new(path) }
    let(:worktree) { File.join(sandbox, "worktrees", "fix") }

    it "creates a new branch in a new worktree" do
      repo.add_worktree(worktree, "garden/security/x", "main")

      expect(git(worktree, "branch", "--show-current")).to eq("garden/security/x")
    end

    it "reports changes, ignoring excluded paths" do
      repo.add_worktree(worktree, "garden/security/x", "main")
      expect(repo.changes?(worktree)).to be(false)

      File.write(File.join(worktree, "local.yml"), "x")
      expect(repo.changes?(worktree)).to be(true)
      expect(repo.changes?(worktree, exclude: ["local.yml"])).to be(false)
    end

    it "commits everything except excluded paths" do
      repo.add_worktree(worktree, "garden/security/x", "main")
      File.write(File.join(worktree, "a.txt"), "two")
      File.write(File.join(worktree, "local.yml"), "x")
      repo.commit_all(worktree, "Fix it\n\nBody", exclude: ["local.yml"])

      expect(git(worktree, "log", "-1", "--format=%B")).to eq("Fix it\n\nBody")
      expect(git(worktree, "show", "--name-only", "--format=")).to eq("a.txt")
      expect(git(worktree, "status", "--porcelain")).to eq("?? local.yml")
    end

    it "creates a guidance worktree, reusing the branch if it already exists" do
      repo.ensure_worktree(worktree, "garden/guidance", "main")
      expect(git(worktree, "branch", "--show-current")).to eq("garden/guidance")
      commit(worktree, "AGENTS.md", "lesson")

      git(path, "worktree", "remove", worktree)
      repo.ensure_worktree(worktree, "garden/guidance", "main")

      expect(File.read(File.join(worktree, "AGENTS.md"))).to eq("lesson")
    end

    it "leaves an existing worktree and its changes alone" do
      repo.ensure_worktree(worktree, "garden/guidance", "main")
      File.write(File.join(worktree, "AGENTS.md"), "draft")

      repo.ensure_worktree(worktree, "garden/guidance", "main")

      expect(File.read(File.join(worktree, "AGENTS.md"))).to eq("draft")
    end

    it "reads the commit template when one is set" do
      template = File.join(sandbox, "msg")
      File.write(template, "# Subject\n")
      git(path, "config", "commit.template", template)

      expect(repo.commit_template).to eq("# Subject\n")
    end

    it "returns nil when there's no commit template" do
      git(path, "config", "commit.template", File.join(sandbox, "missing"))

      expect(repo.commit_template).to be_nil
    end
  end

  it "recreates a worktree whose folder was deleted" do
    _, clone = cloned_project
    repo = described_class.new(clone)
    worktree = File.join(sandbox, "worktrees", "scan")
    repo.sync_worktree(worktree, "origin/trunk")

    FileUtils.rm_rf(worktree)
    repo.sync_worktree(worktree, "origin/trunk")

    expect(File).to exist(File.join(worktree, "a.txt"))
  end
end
