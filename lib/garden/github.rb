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
  end
end
