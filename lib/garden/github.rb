# frozen_string_literal: true

module Garden
  # GitHub lookups through the `gh` command.
  class GitHub
    def initialize(shell: Shell)
      @shell = shell
    end

    # "OPEN", "MERGED" or "CLOSED", or nil if gh couldn't tell.
    def pr_state(url)
      result = @shell.run("gh", "pr", "view", url, "--json", "state", "--jq", ".state")
      result.success? ? result.out.strip : nil
    end

    # The URL of the open PR for branch in dir's repo, or nil.
    def open_pr(dir, branch)
      result = @shell.run("gh", "pr", "list", "--head", branch, "--state", "open",
                          "--json", "url", "--jq", ".[0].url", chdir: dir)
      url = result.out.strip
      url unless !result.success? || url.empty?
    end

    # Opens a ready-for-review PR for branch and returns its URL. fill is
    # "--fill" (title and body from the commit) or "--fill-first" (from the
    # first commit, for branches with several).
    def create_pr(dir, branch:, base:, fill: "--fill")
      result = @shell.run!("gh", "pr", "create", fill, "--head", branch, "--base", base, chdir: dir)
      result.out.lines.last.to_s.strip
    end
  end
end
