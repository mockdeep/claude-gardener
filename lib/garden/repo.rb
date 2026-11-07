# frozen_string_literal: true

require "fileutils"

module Garden
  # Git operations on a registered project.
  class Repo
    FALLBACK_REFS = %w[origin/main origin/master main master].freeze

    def initialize(path, shell: Shell)
      @path = path
      @shell = shell
    end

    # Updates origin/* refs. Never touches local branches.
    def fetch
      return unless remote?("origin")

      git!("fetch", "--quiet", "origin")
    end

    # The ref to scan and branch from, e.g. "origin/main".
    def default_ref
      head = git("symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
      return head.out.strip if head.success?

      FALLBACK_REFS.find { |ref| git("rev-parse", "--verify", "--quiet", "#{ref}^{commit}").success? } or
        raise Error, "Can't find a default branch in #{@path}"
    end

    # Makes dir a clean, detached worktree at ref, creating it if needed.
    # Ignored files (like node_modules) are left alone.
    def sync_worktree(dir, ref)
      git!("worktree", "prune")
      if File.directory?(dir)
        @shell.run!("git", "-C", dir, "checkout", "--quiet", "--force", "--detach", ref)
        @shell.run!("git", "-C", dir, "clean", "-fdq")
      else
        FileUtils.mkdir_p(File.dirname(dir))
        git!("worktree", "add", "--quiet", "--detach", dir, ref)
      end
    end

    # Creates a new branch at ref, checked out in a new worktree at dir.
    def add_worktree(dir, branch, ref)
      git!("worktree", "prune")
      FileUtils.mkdir_p(File.dirname(dir))
      git!("worktree", "add", "--quiet", "-b", branch, dir, ref)
    end

    # Makes sure branch is checked out in a worktree at dir, creating the
    # branch from ref if it doesn't exist yet. An existing worktree is left
    # as it is, changes and all.
    def ensure_worktree(dir, branch, ref)
      return if File.directory?(dir)

      git!("worktree", "prune")
      FileUtils.mkdir_p(File.dirname(dir))
      if git("rev-parse", "--verify", "--quiet", "refs/heads/#{branch}").success?
        git!("worktree", "add", "--quiet", dir, branch)
      else
        git!("worktree", "add", "--quiet", "-b", branch, dir, ref)
      end
    end

    # Rebases dir's branch onto ref. On a conflict, cancels the rebase and
    # raises, leaving the branch as it was.
    def rebase(dir, ref)
      result = @shell.run("git", "-C", dir, "rebase", "--quiet", ref)
      return if result.success?

      @shell.run("git", "-C", dir, "rebase", "--abort")
      raise Error, "Rebasing onto #{ref} hit a conflict, so it was cancelled. " \
                   "Resolve it in #{dir}, or reject or retry the finding."
    end

    # Pushes dir's branch to origin. Garden owns its branches, so it's safe
    # to overwrite one that was pushed before a rebase or amend.
    def push(dir, branch)
      @shell.run!("git", "-C", dir, "push", "--quiet", "--force-with-lease", "--set-upstream", "origin", branch)
    end

    # Whether dir's branch has commits that aren't in ref.
    def commits_since?(dir, ref)
      @shell.run!("git", "-C", dir, "rev-list", "--count", "#{ref}..HEAD").out.strip.to_i.positive?
    end

    # Whether dir's branch has commits that aren't on any remote branch.
    def unpushed_commits?(dir)
      !@shell.run!("git", "-C", dir, "rev-list", "HEAD", "--not", "--remotes").out.strip.empty?
    end

    # Moves dir's branch to ref, throwing away its commits and changes.
    def reset_to(dir, ref)
      @shell.run!("git", "-C", dir, "reset", "--quiet", "--hard", ref)
    end

    def remove_worktree(dir)
      git!("worktree", "remove", "--force", dir) if File.directory?(dir)
      git!("worktree", "prune")
    end

    def delete_branch(branch)
      return unless git("rev-parse", "--verify", "--quiet", "refs/heads/#{branch}").success?

      git!("branch", "--quiet", "-D", branch)
    end

    # Whether dir has uncommitted changes, ignoring the paths in exclude.
    def changes?(dir, exclude: [])
      !@shell.run!("git", "-C", dir, "status", "--porcelain", "--", *pathspec(dir, exclude)).out.strip.empty?
    end

    def stage_all(dir)
      @shell.run!("git", "-C", dir, "add", "--all")
    end

    # Commits everything in dir except the paths in exclude.
    def commit_all(dir, message, exclude: [])
      @shell.run!("git", "-C", dir, "add", "--all", "--", *pathspec(dir, exclude))
      @shell.run!("git", "-C", dir, "commit", "--quiet", "--file", "-", stdin: message)
    end

    # The text of git's commit.template, if one is set.
    def commit_template
      result = git("config", "--path", "commit.template")
      path = result.out.strip
      File.read(path) if result.success? && File.file?(path)
    end

    private

    # Everything, minus the excluded paths. Paths git already ignores are
    # skipped, since git refuses an exclude that names an ignored file.
    def pathspec(dir, exclude)
      exclude = exclude.reject { |path| @shell.run("git", "-C", dir, "check-ignore", "--quiet", path).success? }
      ["."] + exclude.map { |path| ":(exclude)#{path}" }
    end

    def remote?(name)
      git("remote").out.split.include?(name)
    end

    def git(*args) = @shell.run("git", "-C", @path, *args)
    def git!(*args) = @shell.run!("git", "-C", @path, *args)
  end
end
