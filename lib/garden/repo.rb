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

    # Whether dir has uncommitted changes, ignoring the paths in exclude.
    def changes?(dir, exclude: [])
      !@shell.run!("git", "-C", dir, "status", "--porcelain", "--", *pathspec(dir, exclude)).out.strip.empty?
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
