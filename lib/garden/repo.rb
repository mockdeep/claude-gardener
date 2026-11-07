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

    private

    def remote?(name)
      git("remote").out.split.include?(name)
    end

    def git(*args) = @shell.run("git", "-C", @path, *args)
    def git!(*args) = @shell.run!("git", "-C", @path, *args)
  end
end
