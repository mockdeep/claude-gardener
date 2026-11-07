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
