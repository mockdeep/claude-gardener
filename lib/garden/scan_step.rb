# frozen_string_literal: true

module Garden
  # The first part of a garden run for one project: tidy up state, then scan
  # if the saved findings are out of date.
  class ScanStep
    FINISHED_PR_STATES = %w[MERGED CLOSED].freeze

    def initialize(project, store: StateStore.new(project.name), repo: Repo.new(project.path),
                   scanner: Scanner.new(project), github: GitHub.new,
                   worktree: File.join(Paths.worktrees_dir, project.name, "scan"))
      @store = store
      @repo = repo
      @scanner = scanner
      @github = github
      @worktree = worktree
    end

    # Returns :scanned, or :fresh when the saved findings were recent enough.
    def call(force: false, now: Time.now)
      tidy(now)
      return :fresh unless force || @store.read.scan_stale?(now)

      @repo.fetch
      @repo.sync_worktree(@worktree, @repo.default_ref)
      # Scanning takes minutes, so do it outside the lock.
      findings = @scanner.scan(@worktree, @store.read)
      @store.update { |state| state.record_scan(findings, now: now) }
      :scanned
    end

    private

    def tidy(now)
      @store.update do |state|
        state.prune(now)
        state.findings.each do |f|
          next unless f.status == "approved" && f.pr_url

          state.remove(f.id) if FINISHED_PR_STATES.include?(@github.pr_state(f.pr_url))
        end
      end
    end
  end
end
